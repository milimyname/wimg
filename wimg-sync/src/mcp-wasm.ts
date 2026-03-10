/**
 * libwimg WASM loader for Cloudflare Workers.
 * Adapted from wimg-mcp/src/wasm.ts — no filesystem, uses bundled WASM module.
 */

// Cloudflare bundles .wasm files as WebAssembly.Module via [[rules]]
// Uses compact build (smaller memory buffers) to fit CF Workers 128MB limit
import wasmModule from "../libwimg-compact.wasm";

// --- Types ---

export interface Transaction {
  id: string;
  date: string;
  description: string;
  amount: number;
  currency: string;
  category: number;
  account: string;
  excluded: number;
}

export interface Account {
  id: string;
  name: string;
  bank: string;
  color: string;
}

export interface MonthlySummary {
  year: number;
  month: number;
  income: number;
  expenses: number;
  available: number;
  tx_count: number;
  by_category: CategoryBreakdown[];
}

export interface CategoryBreakdown {
  id: number;
  name: string;
  amount: number;
  count: number;
}

export interface Debt {
  id: string;
  name: string;
  total: number;
  paid: number;
  monthly: number;
}

export interface CategoryInfo {
  id: number;
  name: string;
  color: string;
  icon: string;
}

export interface RecurringPattern {
  id: string;
  merchant: string;
  amount: number;
  interval: string;
  category: number;
  last_seen: string;
  next_due: string | null;
  active: number;
  prev_amount: number | null;
  price_change: number | null;
}

export interface SyncRow {
  table: string;
  id: string;
  data: Record<string, unknown> | string;
  updated_at: number;
}

interface UndoResult {
  action: string;
  detail: string;
}

interface WasmExports {
  memory: WebAssembly.Memory;
  wimg_init: (path: number) => number;
  wimg_close: () => void;
  wimg_free: (ptr: number, len: number) => void;
  wimg_alloc: (size: number) => number;
  wimg_get_error: () => number;

  // Read
  wimg_get_transactions: () => number;
  wimg_get_transactions_filtered: (acct: number, acct_len: number) => number;
  wimg_get_summary: (year: number, month: number) => number;
  wimg_get_summary_filtered: (
    year: number,
    month: number,
    acct: number,
    acct_len: number,
  ) => number;
  wimg_get_debts: () => number;
  wimg_get_accounts: () => number;
  wimg_get_categories: () => number;
  wimg_get_recurring: () => number;
  wimg_detect_recurring: () => number;
  wimg_auto_categorize: () => number;

  // Write
  wimg_set_category: (id: number, id_len: number, category: number) => number;
  wimg_set_excluded: (id: number, id_len: number, excluded: number) => number;
  wimg_add_debt: (data: number, len: number) => number;
  wimg_mark_debt_paid: (id: number, id_len: number, amount_cents: bigint) => number;
  wimg_add_account: (data: number, len: number) => number;
  wimg_update_account: (data: number, len: number) => number;
  wimg_undo: () => number;
  wimg_redo: () => number;

  // Sync
  wimg_get_changes: (since_ts: bigint) => number;
  wimg_apply_changes: (data: number, len: number) => number;

  // Encryption
  wimg_derive_key: (sync_key: number, sync_key_len: number) => number;
  wimg_encrypt_field: (pt: number, pt_len: number, key: number, nonce: number) => number;
  wimg_decrypt_field: (ct: number, ct_len: number, key: number) => number;
}

// --- WasmInstance: encapsulates one WASM instance ---

export class WasmInstance {
  private wasm: WasmExports;
  categories: Record<number, CategoryInfo> = {};

  private constructor(wasm: WasmExports) {
    this.wasm = wasm;
  }

  static async create(): Promise<WasmInstance> {
    let resultExports: WasmExports;

    const importObject: Record<string, Record<string, unknown>> = {
      env: {
        js_console_log: (ptr: number, len: number) => {
          try {
            const mem = new Uint8Array(resultExports.memory.buffer);
            const msg = new TextDecoder().decode(mem.slice(ptr, ptr + len));
            console.log("[wimg-wasm]", msg);
          } catch {
            // ignore
          }
        },
        js_time_ms: () => BigInt(Date.now()),
      },
    };

    // Fill in missing imports with stubs
    const neededImports = WebAssembly.Module.imports(wasmModule);
    for (const imp of neededImports) {
      if (!importObject[imp.module]) importObject[imp.module] = {};
      if (!(imp.name in importObject[imp.module])) {
        if (imp.kind === "function") {
          importObject[imp.module][imp.name] = () => 0;
        }
      }
    }

    const instance = await WebAssembly.instantiate(wasmModule, importObject as WebAssembly.Imports);
    resultExports = instance.exports as unknown as WasmExports;

    const w = new WasmInstance(resultExports);

    // Init database
    const pathPtr = w.writeString("/mcp.db");
    const rc = resultExports.wimg_init(pathPtr);
    if (rc !== 0) {
      throw new Error(w.getLastError("Failed to initialize wimg database"));
    }

    // Load categories
    const catPtr = resultExports.wimg_get_categories();
    if (catPtr !== 0) {
      const catJson = w.readLengthPrefixedString(catPtr);
      resultExports.wimg_free(catPtr, 0);
      const catArray = JSON.parse(catJson) as CategoryInfo[];
      for (const cat of catArray) {
        w.categories[cat.id] = cat;
      }
    }

    return w;
  }

  // --- Internal helpers ---

  private readLengthPrefixedString(ptr: number): string {
    const mem = new Uint8Array(this.wasm.memory.buffer);
    const len = mem[ptr] | (mem[ptr + 1] << 8) | (mem[ptr + 2] << 16) | (mem[ptr + 3] << 24);
    return new TextDecoder().decode(mem.slice(ptr + 4, ptr + 4 + len));
  }

  private getLastError(fallback: string): string {
    try {
      const ptr = this.wasm.wimg_get_error();
      if (ptr !== 0) return this.readLengthPrefixedString(ptr);
    } catch {
      // ignore
    }
    return fallback;
  }

  private writeString(s: string): number {
    const encoded = new TextEncoder().encode(s + "\0");
    const ptr = this.wasm.wimg_alloc(encoded.length);
    if (ptr === 0) throw new Error("WASM allocation failed");
    const mem = new Uint8Array(this.wasm.memory.buffer);
    mem.set(encoded, ptr);
    return ptr;
  }

  private writeBytes(data: Uint8Array): number {
    const ptr = this.wasm.wimg_alloc(data.length);
    if (ptr === 0) throw new Error("WASM allocation failed");
    const mem = new Uint8Array(this.wasm.memory.buffer);
    mem.set(data, ptr);
    return ptr;
  }

  // --- Read API ---

  getTransactions(): Transaction[] {
    const ptr = this.wasm.wimg_get_transactions();
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as Transaction[];
  }

  getTransactionsFiltered(account?: string | null): Transaction[] {
    if (!account) return this.getTransactions();
    const acctEncoded = new TextEncoder().encode(account);
    const acctPtr = this.writeBytes(acctEncoded);
    const ptr = this.wasm.wimg_get_transactions_filtered(acctPtr, acctEncoded.length);
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as Transaction[];
  }

  getSummary(year: number, month: number): MonthlySummary {
    const ptr = this.wasm.wimg_get_summary(year, month);
    if (ptr === 0) {
      return { year, month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [] };
    }
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as MonthlySummary;
  }

  getSummaryFiltered(year: number, month: number, account?: string | null): MonthlySummary {
    if (!account) return this.getSummary(year, month);
    const acctEncoded = new TextEncoder().encode(account);
    const acctPtr = this.writeBytes(acctEncoded);
    const ptr = this.wasm.wimg_get_summary_filtered(year, month, acctPtr, acctEncoded.length);
    if (ptr === 0) {
      return { year, month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [] };
    }
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as MonthlySummary;
  }

  getDebts(): Debt[] {
    const ptr = this.wasm.wimg_get_debts();
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as Debt[];
  }

  getAccounts(): Account[] {
    const ptr = this.wasm.wimg_get_accounts();
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as Account[];
  }

  detectRecurring(): number {
    return this.wasm.wimg_detect_recurring();
  }

  getRecurring(): RecurringPattern[] {
    const ptr = this.wasm.wimg_get_recurring();
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as RecurringPattern[];
  }

  // --- Write API ---

  setCategory(id: string, category: number): void {
    const idPtr = this.writeString(id);
    const rc = this.wasm.wimg_set_category(idPtr, id.length, category);
    if (rc !== 0) throw new Error(this.getLastError("Failed to set category"));
  }

  setExcluded(id: string, excluded: boolean): void {
    const idPtr = this.writeString(id);
    const rc = this.wasm.wimg_set_excluded(idPtr, id.length, excluded ? 1 : 0);
    if (rc !== 0) throw new Error(this.getLastError("Failed to set excluded"));
  }

  addDebt(name: string, total: number, monthly?: number): string {
    const id = crypto.randomUUID().replace(/-/g, "").slice(0, 32);
    const json = JSON.stringify({ id, name, total, monthly: monthly ?? 0 });
    const encoded = new TextEncoder().encode(json);
    const ptr = this.writeBytes(encoded);
    const rc = this.wasm.wimg_add_debt(ptr, encoded.length);
    if (rc !== 0) throw new Error(this.getLastError("Failed to add debt"));
    return id;
  }

  markDebtPaid(id: string, amountCents: number): void {
    const idPtr = this.writeString(id);
    const rc = this.wasm.wimg_mark_debt_paid(idPtr, id.length, BigInt(amountCents));
    if (rc !== 0) throw new Error(this.getLastError("Failed to mark debt paid"));
  }

  addAccount(id: string, name: string, color?: string): void {
    const json = JSON.stringify({ id, name, color: color ?? "#6B7280" });
    const encoded = new TextEncoder().encode(json);
    const ptr = this.writeBytes(encoded);
    const rc = this.wasm.wimg_add_account(ptr, encoded.length);
    if (rc !== 0) throw new Error(this.getLastError("Failed to add account"));
  }

  updateAccount(id: string, name: string, color?: string): void {
    const json = JSON.stringify({ id, name, color: color ?? "#6B7280" });
    const encoded = new TextEncoder().encode(json);
    const ptr = this.writeBytes(encoded);
    const rc = this.wasm.wimg_update_account(ptr, encoded.length);
    if (rc !== 0) throw new Error(this.getLastError("Failed to update account"));
  }

  undo(): UndoResult | null {
    const ptr = this.wasm.wimg_undo();
    if (ptr === 0) return null;
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as UndoResult;
  }

  redo(): UndoResult | null {
    const ptr = this.wasm.wimg_redo();
    if (ptr === 0) return null;
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    return JSON.parse(json) as UndoResult;
  }

  // --- Sync API ---

  getChanges(sinceTs: number): SyncRow[] {
    const ptr = this.wasm.wimg_get_changes(BigInt(sinceTs));
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    const result = JSON.parse(json) as { rows: SyncRow[] };
    return result.rows;
  }

  applyChanges(rows: SyncRow[]): number {
    const json = JSON.stringify({ rows });
    const encoded = new TextEncoder().encode(json);
    const ptr = this.writeBytes(encoded);
    const rc = this.wasm.wimg_apply_changes(ptr, encoded.length);
    if (rc < 0) throw new Error(this.getLastError("Failed to apply sync changes"));
    return rc;
  }

  // --- Encryption API ---

  deriveEncryptionKey(syncKey: string): Uint8Array {
    const encoded = new TextEncoder().encode(syncKey);
    const ptr = this.writeBytes(encoded);
    const resultPtr = this.wasm.wimg_derive_key(ptr, encoded.length);
    if (resultPtr === 0) throw new Error(this.getLastError("Failed to derive encryption key"));
    const mem = new Uint8Array(this.wasm.memory.buffer);
    const len =
      mem[resultPtr] |
      (mem[resultPtr + 1] << 8) |
      (mem[resultPtr + 2] << 16) |
      (mem[resultPtr + 3] << 24);
    const key = new Uint8Array(len);
    key.set(mem.slice(resultPtr + 4, resultPtr + 4 + len));
    this.wasm.wimg_free(resultPtr, 0);
    return key;
  }

  encryptField(plaintext: string, key: Uint8Array): string {
    const ptEncoded = new TextEncoder().encode(plaintext);
    const ptPtr = this.writeBytes(ptEncoded);
    const keyPtr = this.writeBytes(key);
    const nonce = crypto.getRandomValues(new Uint8Array(24));
    const noncePtr = this.writeBytes(nonce);
    const resultPtr = this.wasm.wimg_encrypt_field(ptPtr, ptEncoded.length, keyPtr, noncePtr);
    if (resultPtr === 0) throw new Error(this.getLastError("Encryption failed"));
    const result = this.readLengthPrefixedString(resultPtr);
    this.wasm.wimg_free(resultPtr, 0);
    return result;
  }

  decryptField(ciphertext: string, key: Uint8Array): string {
    const ctEncoded = new TextEncoder().encode(ciphertext);
    const ctPtr = this.writeBytes(ctEncoded);
    const keyPtr = this.writeBytes(key);
    const resultPtr = this.wasm.wimg_decrypt_field(ctPtr, ctEncoded.length, keyPtr);
    if (resultPtr === 0) throw new Error(this.getLastError("Decryption failed"));
    const result = this.readLengthPrefixedString(resultPtr);
    this.wasm.wimg_free(resultPtr, 0);
    return result;
  }

  decryptRows(rows: SyncRow[], key: Uint8Array): SyncRow[] {
    return rows.map((row) => {
      if (typeof row.data === "string") {
        const plaintext = this.decryptField(row.data, key);
        return { ...row, data: JSON.parse(plaintext) as Record<string, unknown> };
      }
      return row;
    });
  }

  close(): void {
    this.wasm.wimg_close();
  }
}
