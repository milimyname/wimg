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

export const CATEGORIES: Record<number, { name: string; color: string }> = {
  0: { name: "Uncategorized", color: "#dfe6e9" },
  1: { name: "Groceries", color: "#4ecdc4" },
  2: { name: "Dining", color: "#ff6b6b" },
  3: { name: "Transport", color: "#45b7d1" },
  4: { name: "Housing", color: "#96ceb4" },
  5: { name: "Utilities", color: "#a8d8ea" },
  6: { name: "Entertainment", color: "#dda0dd" },
  7: { name: "Shopping", color: "#f7dc6f" },
  8: { name: "Health", color: "#ff9ff3" },
  9: { name: "Insurance", color: "#c8d6e5" },
  10: { name: "Income", color: "#2dc653" },
  11: { name: "Transfer", color: "#b8b8b8" },
  12: { name: "Cash", color: "#ffd93d" },
  13: { name: "Subscriptions", color: "#6c5ce7" },
  14: { name: "Travel", color: "#fd79a8" },
  15: { name: "Education", color: "#74b9ff" },
  255: { name: "Other", color: "#dfe6e9" },
};

interface WasmExports {
  memory: WebAssembly.Memory;
  wimg_init: (path: number) => number;
  wimg_import_csv: (data: number, len: number) => number;
  wimg_get_transactions: () => number;
  wimg_set_category: (id: number, id_len: number, category: number) => number;
  wimg_get_summary: (year: number, month: number) => number;
  wimg_get_debts: () => number;
  wimg_add_debt: (data: number, len: number) => number;
  wimg_mark_debt_paid: (
    id: number,
    id_len: number,
    amount_cents: bigint,
  ) => number;
  wimg_delete_debt: (id: number, id_len: number) => number;
  wimg_auto_categorize: () => number;
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
  const len =
    mem[ptr] | (mem[ptr + 1] << 8) | (mem[ptr + 2] << 16) | (mem[ptr + 3] << 24);
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
          console.warn(
            `[wimg] unimplemented import: ${imp.module}.${imp.name}`,
            args,
          );
          return 0;
        };
      }
    }
  }

  const result = await WebAssembly.instantiate(
    compiled,
    importObject as WebAssembly.Imports,
  );
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

export async function setCategory(
  id: string,
  category: number,
): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_set_category(idPtr, id.length, category);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to set category"));
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

export async function addDebt(
  name: string,
  total: number,
  monthly: number,
): Promise<void> {
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

export async function markDebtPaid(
  id: string,
  amountCents: number,
): Promise<void> {
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

export function close(): void {
  if (!wasm) return;
  wasm.wimg_close();
}
