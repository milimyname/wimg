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
    // File doesn't exist yet — first run
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

/**
 * Load and initialize the WASM module + SQLite database.
 * Restores from OPFS if a previous database exists.
 */
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

  // Satisfy any other imports dynamically
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

  // Restore DB from OPFS before opening
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

  // Initialize SQLite (opens the DB file in the VFS — already populated if restored)
  const pathPtr = writeString("/wimg.db");
  const rc = wasm.wimg_init(pathPtr);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to initialize wimg database"));
  }
}

/**
 * Import a CSV file into the database. Auto-saves to OPFS.
 */
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

  // Persist to OPFS after successful import
  if (importResult.imported > 0) {
    await opfsSave();
  }

  return importResult;
}

/**
 * Get all transactions from the database.
 */
export function getTransactions(): Transaction[] {
  ensureInit();

  const ptr = wasm!.wimg_get_transactions();
  if (ptr === 0) return [];

  const json = readLengthPrefixedString(ptr);
  wasm!.wimg_free(ptr, 0);

  return JSON.parse(json) as Transaction[];
}

/**
 * Set the category for a transaction. Auto-saves to OPFS.
 */
export async function setCategory(id: string, category: number): Promise<void> {
  ensureInit();

  const idPtr = writeString(id);
  const rc = wasm!.wimg_set_category(idPtr, id.length, category);
  if (rc !== 0) {
    throw new Error(getLastError("Failed to set category"));
  }

  // Persist category change
  await opfsSave();
}

/**
 * Close the database.
 */
export function close(): void {
  if (!wasm) return;
  wasm.wimg_close();
}
