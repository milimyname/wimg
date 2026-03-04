/**
 * libwimg WASM loader and typed TypeScript wrappers.
 */

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

export interface ImportResult {
  total_rows: number;
  imported: number;
  skipped_duplicates: number;
  errors: number;
  format: string;
  categorized: number;
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

export interface UndoResult {
  op: string;
  table: string;
  row_id: string;
  column?: string;
}

export interface CategoryInfo {
  id: number;
  name: string;
  color: string;
  icon: string;
}

export let CATEGORIES: Record<number, CategoryInfo> = {};

export interface ParseResult {
  format: string;
  total_rows: number;
  transactions: Transaction[];
}

interface WasmExports {
  memory: WebAssembly.Memory;
  wimg_init: (path: number) => number;
  wimg_import_csv: (data: number, len: number) => number;
  wimg_parse_csv: (data: number, len: number) => number;
  wimg_get_transactions: () => number;
  wimg_set_category: (id: number, id_len: number, category: number) => number;
  wimg_set_excluded: (id: number, id_len: number, excluded: number) => number;
  wimg_get_summary: (year: number, month: number) => number;
  wimg_get_debts: () => number;
  wimg_add_debt: (data: number, len: number) => number;
  wimg_mark_debt_paid: (id: number, id_len: number, amount_cents: bigint) => number;
  wimg_delete_debt: (id: number, id_len: number) => number;
  wimg_auto_categorize: () => number;
  wimg_get_accounts: () => number;
  wimg_add_account: (data: number, len: number) => number;
  wimg_update_account: (data: number, len: number) => number;
  wimg_delete_account: (id: number, id_len: number) => number;
  wimg_get_transactions_filtered: (acct: number, acct_len: number) => number;
  wimg_get_summary_filtered: (
    year: number,
    month: number,
    acct: number,
    acct_len: number,
  ) => number;
  wimg_get_categories: () => number;
  wimg_undo: () => number;
  wimg_redo: () => number;
  wimg_close: () => void;
  wimg_free: (ptr: number, len: number) => void;
  wimg_alloc: (size: number) => number;
  wimg_get_error: () => number;
  wimg_db_ptr: () => number;
  wimg_db_size: () => number;
  wimg_db_load: (data: number, size: number) => number;
}

let wasm: WasmExports | null = null;

const OPFS_DB_NAME = "wimg.db";

// --- Internal helpers ---

function readLengthPrefixedString(ptr: number): string {
  const mem = new Uint8Array(wasm!.memory.buffer);
  const len = mem[ptr] | (mem[ptr + 1] << 8) | (mem[ptr + 2] << 16) | (mem[ptr + 3] << 24);
  return new TextDecoder().decode(mem.slice(ptr + 4, ptr + 4 + len));
}

function getLastError(fallback: string): string {
  try {
    const ptr = wasm!.wimg_get_error();
    if (ptr !== 0) {
      return readLengthPrefixedString(ptr);
    }
  } catch {
    // ignore
  }
  return fallback;
}

function writeString(s: string): number {
  const encoded = new TextEncoder().encode(s + "\0");
  const ptr = wasm!.wimg_alloc(encoded.length);
  if (ptr === 0) throw new Error("WASM allocation failed");
  const mem = new Uint8Array(wasm!.memory.buffer);
  mem.set(encoded, ptr);
  return ptr;
}

function writeBytes(data: Uint8Array): number {
  const ptr = wasm!.wimg_alloc(data.length);
  if (ptr === 0) throw new Error("WASM allocation failed");
  const mem = new Uint8Array(wasm!.memory.buffer);
  mem.set(data, ptr);
  return ptr;
}

function ensureInit(): void {
  if (!wasm) throw new Error("WASM not initialized. Call init() first.");
}

// --- OPFS persistence ---

async function opfsLoad(): Promise<Uint8Array | null> {
  try {
    const root = await navigator.storage.getDirectory();
    const fileHandle = await root.getFileHandle(OPFS_DB_NAME);
    const file = await fileHandle.getFile();
    const buffer = await file.arrayBuffer();
    if (buffer.byteLength === 0) return null;
    console.log(`[wimg] OPFS: loaded ${buffer.byteLength} bytes`);
    return new Uint8Array(buffer);
  } catch {
    console.log("[wimg] OPFS: no existing database");
    return null;
  }
}

async function opfsSave(): Promise<void> {
  if (!wasm) return;

  const ptr = wasm.wimg_db_ptr();
  const size = wasm.wimg_db_size();
  if (ptr === 0 || size === 0) return;

  const mem = new Uint8Array(wasm.memory.buffer);
  const dbBytes = mem.slice(ptr, ptr + size);

  try {
    const root = await navigator.storage.getDirectory();
    const fileHandle = await root.getFileHandle(OPFS_DB_NAME, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(dbBytes);
    await writable.close();
    console.log(`[wimg] OPFS: saved ${size} bytes`);
  } catch (e) {
    console.error("[wimg] OPFS save failed:", e);
  }
}

// --- Public API ---

export async function init(): Promise<void> {
  if (wasm) return;

  const response = await fetch("/libwimg.wasm");
  const bytes = await response.arrayBuffer();
  const compiled = await WebAssembly.compile(bytes);

  const neededImports = WebAssembly.Module.imports(compiled);
  if (neededImports.length > 0) {
    console.log("[wimg] WASM imports required:", neededImports);
  }

  const importObject: Record<string, Record<string, unknown>> = {
    env: {
      js_console_log: (ptr: number, len: number) => {
        try {
          const mem = new Uint8Array(
            (result.exports as { memory: WebAssembly.Memory }).memory.buffer,
          );
          const msg = new TextDecoder().decode(mem.slice(ptr, ptr + len));
          console.log("[wimg]", msg);
        } catch {
          console.log("[wimg] (log failed, ptr=%d len=%d)", ptr, len);
        }
      },
    },
  };

  for (const imp of neededImports) {
    if (!importObject[imp.module]) importObject[imp.module] = {};
    if (!(imp.name in importObject[imp.module])) {
      if (imp.kind === "function") {
        importObject[imp.module][imp.name] = (...args: unknown[]) => {
          console.warn(`[wimg] unimplemented import: ${imp.module}.${imp.name}`, args);
          return 0;
        };
      }
    }
  }

  const result = await WebAssembly.instantiate(compiled, importObject as WebAssembly.Imports);
  wasm = result.exports as unknown as WasmExports;

  console.log(
    "[wimg] exports:",
    WebAssembly.Module.exports(compiled)
      .map((e) => e.name)
      .join(", "),
  );

  const saved = await opfsLoad();
  if (saved) {
    const loadPtr = wasm.wimg_alloc(saved.length);
    if (loadPtr !== 0) {
      const mem = new Uint8Array(wasm.memory.buffer);
      mem.set(saved, loadPtr);
      const rc = wasm.wimg_db_load(loadPtr, saved.length);
      if (rc !== 0) {
        console.warn("[wimg] failed to restore DB from OPFS");
      }
    }
  }

  const pathPtr = writeString("/wimg.db");
  const rc = wasm.wimg_init(pathPtr);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to initialize wimg database"));
  }

  // Load category metadata from WASM
  const catPtr = wasm.wimg_get_categories();
  if (catPtr !== 0) {
    const catJson = readLengthPrefixedString(catPtr);
    wasm.wimg_free(catPtr, 0);
    const catArray = JSON.parse(catJson) as CategoryInfo[];
    CATEGORIES = {};
    for (const cat of catArray) {
      CATEGORIES[cat.id] = cat;
    }
  }
}

export function parseCsv(csvContent: ArrayBuffer): ParseResult {
  ensureInit();

  const data = new Uint8Array(csvContent);
  const ptr = wasm!.wimg_alloc(data.length);
  if (ptr === 0) throw new Error("WASM allocation failed");

  const mem = new Uint8Array(wasm!.memory.buffer);
  mem.set(data, ptr);

  const resultPtr = wasm!.wimg_parse_csv(ptr, data.length);
  if (resultPtr === 0) {
    throw new Error(getLastError("CSV parsing failed"));
  }

  const json = readLengthPrefixedString(resultPtr);
  wasm!.wimg_free(resultPtr, 0);

  return JSON.parse(json) as ParseResult;
}

export async function importCsv(csvContent: ArrayBuffer): Promise<ImportResult> {
  ensureInit();

  const data = new Uint8Array(csvContent);
  const ptr = wasm!.wimg_alloc(data.length);
  if (ptr === 0) throw new Error("WASM allocation failed");

  const mem = new Uint8Array(wasm!.memory.buffer);
  mem.set(data, ptr);

  const resultPtr = wasm!.wimg_import_csv(ptr, data.length);
  if (resultPtr === 0) {
    throw new Error(getLastError("CSV import failed"));
  }

  const json = readLengthPrefixedString(resultPtr);
  wasm!.wimg_free(resultPtr, 0);

  const importResult = JSON.parse(json) as ImportResult;

  if (importResult.imported > 0) {
    await opfsSave();
  }

  return importResult;
}

export function getTransactions(): Transaction[] {
  ensureInit();

  const ptr = wasm!.wimg_get_transactions();
  if (ptr === 0) return [];

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as Transaction[];
}

export async function setCategory(id: string, category: number): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_set_category(idPtr, id.length, category);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to set category"));
  }

  await opfsSave();
}

export async function setExcluded(id: string, excluded: boolean): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_set_excluded(idPtr, id.length, excluded ? 1 : 0);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to set excluded"));
  }

  await opfsSave();
}

export function getSummary(year: number, month: number): MonthlySummary {
  ensureInit();

  const ptr = wasm!.wimg_get_summary(year, month);
  if (ptr === 0) {
    return {
      year,
      month,
      income: 0,
      expenses: 0,
      available: 0,
      tx_count: 0,
      by_category: [],
    };
  }

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as MonthlySummary;
}

export function getDebts(): Debt[] {
  ensureInit();

  const ptr = wasm!.wimg_get_debts();
  if (ptr === 0) return [];

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as Debt[];
}

export async function addDebt(name: string, total: number, monthly: number): Promise<void> {
  ensureInit();

  const id = crypto.randomUUID().replace(/-/g, "").slice(0, 32);
  const json = JSON.stringify({ id, name, total, monthly });
  const encoded = new TextEncoder().encode(json);
  const ptr = writeBytes(encoded);

  const rc = wasm!.wimg_add_debt(ptr, encoded.length);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to add debt"));
  }

  await opfsSave();
}

export async function markDebtPaid(id: string, amountCents: number): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_mark_debt_paid(idPtr, id.length, BigInt(amountCents));
  if (rc !== 0) {
    throw new Error(getLastError("Failed to mark debt paid"));
  }

  await opfsSave();
}

export async function deleteDebt(id: string): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_delete_debt(idPtr, id.length);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to delete debt"));
  }

  await opfsSave();
}

export async function undo(): Promise<UndoResult | null> {
  ensureInit();

  const ptr = wasm!.wimg_undo();
  if (ptr === 0) return null;

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  await opfsSave();
  return JSON.parse(json) as UndoResult;
}

export async function redo(): Promise<UndoResult | null> {
  ensureInit();

  const ptr = wasm!.wimg_redo();
  if (ptr === 0) return null;

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  await opfsSave();
  return JSON.parse(json) as UndoResult;
}

export function autoCategorize(): number {
  ensureInit();
  return wasm!.wimg_auto_categorize();
}

export function getAccounts(): Account[] {
  ensureInit();

  const ptr = wasm!.wimg_get_accounts();
  if (ptr === 0) return [];

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as Account[];
}

export async function addAccount(id: string, name: string, color: string): Promise<void> {
  ensureInit();

  const json = JSON.stringify({ id, name, color });
  const encoded = new TextEncoder().encode(json);
  const ptr = writeBytes(encoded);

  const rc = wasm!.wimg_add_account(ptr, encoded.length);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to add account"));
  }

  await opfsSave();
}

export async function updateAccount(id: string, name: string, color: string): Promise<void> {
  ensureInit();

  const json = JSON.stringify({ id, name, color });
  const encoded = new TextEncoder().encode(json);
  const ptr = writeBytes(encoded);

  const rc = wasm!.wimg_update_account(ptr, encoded.length);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to update account"));
  }

  await opfsSave();
}

export async function deleteAccount(id: string): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_delete_account(idPtr, id.length);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to delete account"));
  }

  await opfsSave();
}

export function getTransactionsFiltered(account?: string | null): Transaction[] {
  ensureInit();

  if (!account) {
    return getTransactions();
  }

  const acctEncoded = new TextEncoder().encode(account);
  const acctPtr = writeBytes(acctEncoded);
  const ptr = wasm!.wimg_get_transactions_filtered(acctPtr, acctEncoded.length);
  if (ptr === 0) return [];

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as Transaction[];
}

export function getSummaryFiltered(
  year: number,
  month: number,
  account?: string | null,
): MonthlySummary {
  ensureInit();

  if (!account) {
    return getSummary(year, month);
  }

  const acctEncoded = new TextEncoder().encode(account);
  const acctPtr = writeBytes(acctEncoded);
  const ptr = wasm!.wimg_get_summary_filtered(year, month, acctPtr, acctEncoded.length);
  if (ptr === 0) {
    return {
      year,
      month,
      income: 0,
      expenses: 0,
      available: 0,
      tx_count: 0,
      by_category: [],
    };
  }

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as MonthlySummary;
}

export function close(): void {
  if (!wasm) return;
  wasm.wimg_close();
}
