/**
 * libwimg WASM loader and typed TypeScript wrappers.
 */

// --- DevTools instrumentation ---
// Uses dynamic import so devtools module is only loaded when active.
// In prod without ?devtools, devtoolsEnabled is never set and the check is a cheap boolean read.
import { devtoolsEnabled } from "./devtools.svelte";

function timed<T>(name: string, fn: () => T): T {
  if (!devtoolsEnabled) return fn();
  const start = performance.now();
  const result = fn();
  const duration = performance.now() - start;
  import("./devtools.svelte").then((m) => m.devtoolsStore.logWasmCall(name, duration));
  return result;
}

async function timedAsync<T>(name: string, fn: () => Promise<T>): Promise<T> {
  if (!devtoolsEnabled) return fn();
  const start = performance.now();
  const result = await fn();
  const duration = performance.now() - start;
  import("./devtools.svelte").then((m) => m.devtoolsStore.logWasmCall(name, duration));
  return result;
}

function logAction(action: string, details: string): void {
  if (!devtoolsEnabled) return;
  import("./devtools.svelte").then((m) => m.devtoolsStore.logAction(action, details));
}

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

export interface Snapshot {
  id: string;
  date: string;
  net_worth: number;
  income: number;
  expenses: number;
  tx_count: number;
  by_category: CategoryBreakdown[];
}

export interface ParseResult {
  format: string;
  total_rows: number;
  transactions: Transaction[];
}

export interface SyncRow {
  table: string;
  id: string;
  data: Record<string, unknown>;
  updated_at: number;
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
  wimg_detect_recurring: () => number;
  wimg_get_recurring: () => number;
  wimg_take_snapshot: (year: number, month: number) => number;
  wimg_get_snapshots: () => number;
  wimg_export_csv: () => number;
  wimg_export_db: () => number;
  wimg_undo: () => number;
  wimg_redo: () => number;
  wimg_get_changes: (since_ts: bigint) => number;
  wimg_apply_changes: (data: number, len: number) => number;
  wimg_derive_key: (sync_key: number, sync_key_len: number) => number;
  wimg_encrypt_field: (pt: number, pt_len: number, key: number, nonce: number) => number;
  wimg_decrypt_field: (ct: number, ct_len: number, key: number) => number;
  wimg_query: (sql: number, len: number) => number;
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

// --- Mutation callback for real-time sync ---
let onMutate: (() => void) | null = null;
export function setOnMutate(cb: (() => void) | null): void {
  onMutate = cb;
}

// --- Internal helpers ---

function generateUUID(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

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

async function opfsSaveInner(): Promise<void> {
  if (!wasm) return;

  const ptr = wasm.wimg_db_ptr();
  const size = wasm.wimg_db_size();
  if (ptr === 0 || size === 0) return;

  const mem = new Uint8Array(wasm.memory.buffer);
  const dbBytes = mem.slice(ptr, ptr + size);

  try {
    const root = await navigator.storage.getDirectory();
    const fileHandle = await root.getFileHandle(OPFS_DB_NAME, { create: true });

    // Safari < 17.2 doesn't support createWritable on main thread
    if (typeof fileHandle.createWritable === "function") {
      const writable = await fileHandle.createWritable();
      await writable.write(dbBytes);
      await writable.close();
    } else {
      // Fallback: write via Blob + Worker for older Safari
      const workerCode = `
        onmessage = async (e) => {
          const root = await navigator.storage.getDirectory();
          const fh = await root.getFileHandle(e.data.name, { create: true });
          const ah = await fh.createSyncAccessHandle();
          ah.truncate(0);
          ah.write(e.data.bytes);
          ah.flush();
          ah.close();
          postMessage("done");
        };
      `;
      const workerBlob = new Blob([workerCode], { type: "text/javascript" });
      const worker = new Worker(URL.createObjectURL(workerBlob));
      await new Promise<void>((resolve, reject) => {
        worker.onmessage = () => {
          worker.terminate();
          resolve();
        };
        worker.onerror = (err) => {
          worker.terminate();
          reject(err);
        };
        worker.postMessage({ name: OPFS_DB_NAME, bytes: dbBytes }, [dbBytes.buffer]);
      });
    }
    console.log(`[wimg] OPFS: saved ${size} bytes`);
  } catch (e) {
    console.error("[wimg] OPFS save failed:", e);
  }
}

async function opfsSave(): Promise<void> {
  return timedAsync("opfsSave", opfsSaveInner);
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
      js_time_ms: () => BigInt(Date.now()),
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
  return timed("parseCsv", () => {
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
  });
}

export async function importCsv(csvContent: ArrayBuffer): Promise<ImportResult> {
  return timedAsync("importCsv", async () => {
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
      onMutate?.();
    }

    logAction(
      "importCsv",
      `${importResult.imported} imported, ${importResult.skipped_duplicates} dupes, ${importResult.format}`,
    );
    return importResult;
  });
}

export function getTransactions(): Transaction[] {
  return timed("getTransactions", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_transactions();
    if (ptr === 0) {
      const err = getLastError("getTransactions failed");
      console.error("[wimg]", err);
      if (err.includes("buffer too small")) {
        throw new Error(
          "Zu viele Transaktionen zum Anzeigen. Daten sind gespeichert, aber der Anzeigepuffer ist voll.",
        );
      }
      return [];
    }

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as Transaction[];
  });
}

export async function setCategory(id: string, category: number): Promise<void> {
  return timedAsync("setCategory", async () => {
    ensureInit();

    const idPtr = writeString(id);
    const rc = wasm!.wimg_set_category(idPtr, id.length, category);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to set category"));
    }

    await opfsSave();
    onMutate?.();
    logAction("setCategory", `${id.slice(0, 8)}... → cat ${category}`);
  });
}

export async function setExcluded(id: string, excluded: boolean): Promise<void> {
  return timedAsync("setExcluded", async () => {
    ensureInit();

    const idPtr = writeString(id);
    const rc = wasm!.wimg_set_excluded(idPtr, id.length, excluded ? 1 : 0);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to set excluded"));
    }

    await opfsSave();
    onMutate?.();
    logAction("setExcluded", `${id.slice(0, 8)}... → ${excluded ? "excluded" : "included"}`);
  });
}

export function getSummary(year: number, month: number): MonthlySummary {
  return timed("getSummary", () => {
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
  });
}

export function getDebts(): Debt[] {
  return timed("getDebts", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_debts();
    if (ptr === 0) return [];

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as Debt[];
  });
}

export async function addDebt(name: string, total: number, monthly: number): Promise<void> {
  return timedAsync("addDebt", async () => {
    ensureInit();

    const id = generateUUID().replace(/-/g, "").slice(0, 32);
    const json = JSON.stringify({ id, name, total, monthly });
    const encoded = new TextEncoder().encode(json);
    const ptr = writeBytes(encoded);

    const rc = wasm!.wimg_add_debt(ptr, encoded.length);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to add debt"));
    }

    await opfsSave();
    onMutate?.();
    logAction("addDebt", `"${name}" ${(total / 100).toFixed(2)}€`);
  });
}

export async function markDebtPaid(id: string, amountCents: number): Promise<void> {
  return timedAsync("markDebtPaid", async () => {
    ensureInit();

    const idPtr = writeString(id);
    const rc = wasm!.wimg_mark_debt_paid(idPtr, id.length, BigInt(amountCents));
    if (rc !== 0) {
      throw new Error(getLastError("Failed to mark debt paid"));
    }

    await opfsSave();
    onMutate?.();
    logAction("markDebtPaid", `${id.slice(0, 8)}... +${(amountCents / 100).toFixed(2)}€`);
  });
}

export async function deleteDebt(id: string): Promise<void> {
  return timedAsync("deleteDebt", async () => {
    ensureInit();

    const idPtr = writeString(id);
    const rc = wasm!.wimg_delete_debt(idPtr, id.length);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to delete debt"));
    }

    await opfsSave();
    onMutate?.();
    logAction("deleteDebt", `${id.slice(0, 8)}...`);
  });
}

export async function undo(): Promise<UndoResult | null> {
  return timedAsync("undo", async () => {
    ensureInit();

    const ptr = wasm!.wimg_undo();
    if (ptr === 0) return null;

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    await opfsSave();
    onMutate?.();
    const undoResult = JSON.parse(json) as UndoResult;
    logAction("undo", `${undoResult.op} ${undoResult.table}.${undoResult.row_id.slice(0, 8)}...`);
    return undoResult;
  });
}

export async function redo(): Promise<UndoResult | null> {
  return timedAsync("redo", async () => {
    ensureInit();

    const ptr = wasm!.wimg_redo();
    if (ptr === 0) return null;

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    await opfsSave();
    onMutate?.();
    const redoResult = JSON.parse(json) as UndoResult;
    logAction("redo", `${redoResult.op} ${redoResult.table}.${redoResult.row_id.slice(0, 8)}...`);
    return redoResult;
  });
}

export function autoCategorize(): number {
  return timed("autoCategorize", () => {
    ensureInit();
    return wasm!.wimg_auto_categorize();
  });
}

export function detectRecurring(): number {
  return timed("detectRecurring", () => {
    ensureInit();
    return wasm!.wimg_detect_recurring();
  });
}

export function getRecurring(): RecurringPattern[] {
  return timed("getRecurring", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_recurring();
    if (ptr === 0) return [];

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as RecurringPattern[];
  });
}

// --- Snapshots ---

export function takeSnapshot(year: number, month: number): void {
  timed("takeSnapshot", () => {
    ensureInit();
    const rc = wasm!.wimg_take_snapshot(year, month);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to take snapshot"));
    }
  });
}

export function getSnapshots(): Snapshot[] {
  return timed("getSnapshots", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_snapshots();
    if (ptr === 0) return [];

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as Snapshot[];
  });
}

// --- Export ---

export function exportCsv(): string {
  return timed("exportCsv", () => {
    ensureInit();

    const ptr = wasm!.wimg_export_csv();
    if (ptr === 0) throw new Error(getLastError("Failed to export CSV"));

    const csv = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return csv;
  });
}

export function exportDb(): string {
  return timed("exportDb", () => {
    ensureInit();

    const ptr = wasm!.wimg_export_db();
    if (ptr === 0) throw new Error(getLastError("Failed to export database"));

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return json;
  });
}

export function getAccounts(): Account[] {
  return timed("getAccounts", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_accounts();
    if (ptr === 0) return [];

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as Account[];
  });
}

export async function addAccount(id: string, name: string, color: string): Promise<void> {
  return timedAsync("addAccount", async () => {
    ensureInit();

    const json = JSON.stringify({ id, name, color });
    const encoded = new TextEncoder().encode(json);
    const ptr = writeBytes(encoded);

    const rc = wasm!.wimg_add_account(ptr, encoded.length);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to add account"));
    }

    await opfsSave();
    onMutate?.();
    logAction("addAccount", `"${name}" (${id})`);
  });
}

export async function updateAccount(id: string, name: string, color: string): Promise<void> {
  return timedAsync("updateAccount", async () => {
    ensureInit();

    const json = JSON.stringify({ id, name, color });
    const encoded = new TextEncoder().encode(json);
    const ptr = writeBytes(encoded);

    const rc = wasm!.wimg_update_account(ptr, encoded.length);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to update account"));
    }

    await opfsSave();
    onMutate?.();
    logAction("updateAccount", `"${name}" (${id})`);
  });
}

export async function deleteAccount(id: string): Promise<void> {
  return timedAsync("deleteAccount", async () => {
    ensureInit();

    const idPtr = writeString(id);
    const rc = wasm!.wimg_delete_account(idPtr, id.length);
    if (rc !== 0) {
      throw new Error(getLastError("Failed to delete account"));
    }

    await opfsSave();
    onMutate?.();
    logAction("deleteAccount", id);
  });
}

export function getTransactionsFiltered(account?: string | null): Transaction[] {
  return timed("getTransactionsFiltered", () => {
    ensureInit();

    if (!account) {
      return getTransactions();
    }

    const acctEncoded = new TextEncoder().encode(account);
    const acctPtr = writeBytes(acctEncoded);
    const ptr = wasm!.wimg_get_transactions_filtered(acctPtr, acctEncoded.length);
    if (ptr === 0) {
      const err = getLastError("getTransactionsFiltered failed");
      console.error("[wimg]", err);
      if (err.includes("buffer too small")) {
        throw new Error(
          "Zu viele Transaktionen zum Anzeigen. Daten sind gespeichert, aber der Anzeigepuffer ist voll.",
        );
      }
      return [];
    }

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    return JSON.parse(json) as Transaction[];
  });
}

export function getSummaryFiltered(
  year: number,
  month: number,
  account?: string | null,
): MonthlySummary {
  return timed("getSummaryFiltered", () => {
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
  });
}

export function getChanges(sinceTs: number): SyncRow[] {
  return timed("getChanges", () => {
    ensureInit();

    const ptr = wasm!.wimg_get_changes(BigInt(sinceTs));
    if (ptr === 0) return [];

    const json = readLengthPrefixedString(ptr);
    wasm!.wimg_free(ptr, 0);

    const result = JSON.parse(json) as { rows: SyncRow[] };
    return result.rows;
  });
}

export function applyChanges(rows: SyncRow[]): number {
  return timed("applyChanges", () => {
    ensureInit();

    const json = JSON.stringify({ rows });
    const encoded = new TextEncoder().encode(json);
    const ptr = writeBytes(encoded);

    const rc = wasm!.wimg_apply_changes(ptr, encoded.length);
    if (rc < 0) {
      throw new Error(getLastError("Failed to apply sync changes"));
    }

    return rc;
  });
}

export function deriveEncryptionKey(syncKey: string): Uint8Array {
  ensureInit();

  const encoded = new TextEncoder().encode(syncKey);
  const ptr = writeBytes(encoded);
  const resultPtr = wasm!.wimg_derive_key(ptr, encoded.length);
  if (resultPtr === 0) {
    throw new Error(getLastError("Failed to derive encryption key"));
  }

  const mem = new Uint8Array(wasm!.memory.buffer);
  const len =
    mem[resultPtr] |
    (mem[resultPtr + 1] << 8) |
    (mem[resultPtr + 2] << 16) |
    (mem[resultPtr + 3] << 24);
  const key = new Uint8Array(len);
  key.set(mem.slice(resultPtr + 4, resultPtr + 4 + len));
  wasm!.wimg_free(resultPtr, 0);
  return key;
}

export function encryptField(plaintext: string, key: Uint8Array): string {
  ensureInit();

  const ptEncoded = new TextEncoder().encode(plaintext);
  const ptPtr = writeBytes(ptEncoded);
  const keyPtr = writeBytes(key);

  // Generate 24-byte random nonce
  const nonce = crypto.getRandomValues(new Uint8Array(24));
  const noncePtr = writeBytes(nonce);

  const resultPtr = wasm!.wimg_encrypt_field(ptPtr, ptEncoded.length, keyPtr, noncePtr);
  if (resultPtr === 0) {
    throw new Error(getLastError("Encryption failed"));
  }

  const result = readLengthPrefixedString(resultPtr);
  wasm!.wimg_free(resultPtr, 0);
  return result;
}

export function decryptField(ciphertext: string, key: Uint8Array): string {
  ensureInit();

  const ctEncoded = new TextEncoder().encode(ciphertext);
  const ctPtr = writeBytes(ctEncoded);
  const keyPtr = writeBytes(key);

  const resultPtr = wasm!.wimg_decrypt_field(ctPtr, ctEncoded.length, keyPtr);
  if (resultPtr === 0) {
    throw new Error(getLastError("Decryption failed"));
  }

  const result = readLengthPrefixedString(resultPtr);
  wasm!.wimg_free(resultPtr, 0);
  return result;
}

export function decryptRows(rows: SyncRow[], key: Uint8Array): SyncRow[] {
  return rows.map((row) => {
    if (typeof row.data === "string") {
      const plaintext = decryptField(row.data, key);
      return { ...row, data: JSON.parse(plaintext) as Record<string, unknown> };
    }
    return row;
  });
}

export { opfsSave };

export interface QueryResult {
  columns: string[];
  rows: (string | number | null)[][];
  count: number;
  truncated: boolean;
}

export function queryRaw(sql: string): QueryResult {
  return timed("queryRaw", () => {
    ensureInit();

    const encoded = new TextEncoder().encode(sql);
    const ptr = writeBytes(encoded);

    const resultPtr = wasm!.wimg_query(ptr, encoded.length);
    if (resultPtr === 0) {
      throw new Error(getLastError("SQL query failed"));
    }

    const json = readLengthPrefixedString(resultPtr);
    wasm!.wimg_free(resultPtr, 0);

    return JSON.parse(json) as QueryResult;
  });
}

export function close(): void {
  if (!wasm) return;
  wasm.wimg_close();
}

/** DevTools: expose WASM memory and db_size for the Memory tab */
export function getWasmMemoryBytes(): number {
  return wasm?.memory.buffer.byteLength ?? 0;
}

export function getWasmDbSize(): number {
  if (!wasm) return 0;
  return wasm.wimg_db_size();
}

/** Debug: WASM memory size in MB. Call from console: __wimgMemoryMB() */
if (typeof globalThis !== "undefined") {
  (globalThis as Record<string, unknown>).__wimgMemoryMB = () => {
    if (!wasm) return "WASM not loaded";
    const bytes = wasm.memory.buffer.byteLength;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  };
}
