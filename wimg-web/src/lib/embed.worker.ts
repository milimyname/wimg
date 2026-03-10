/**
 * Web Worker for embedding transactions.
 *
 * Loads its own WASM instance + embedding model so heavy operations
 * (embed_transactions, smart_categorize) run off the main thread.
 * Receives current DB state via Transferable ArrayBuffer, processes,
 * and sends back the modified DB.
 */
export {};

const MODEL_OPFS_FILE = "e5-small-q8.gguf";

interface WorkerWasm {
  memory: WebAssembly.Memory;
  wimg_init: (path: number) => number;
  wimg_close: () => void;
  wimg_alloc: (size: number) => number;
  wimg_alloc_model: (size: number) => number;
  wimg_load_model: (data: number, len: number) => number;
  wimg_embed_transactions: () => number;
  wimg_smart_categorize: () => number;
  wimg_db_load: (data: number, size: number) => number;
  wimg_db_ptr: () => number;
  wimg_db_size: () => number;
}

let wasm: WorkerWasm | null = null;

function writeZeroTerminated(s: string): number {
  const encoded = new TextEncoder().encode(s + "\0");
  const ptr = wasm!.wimg_alloc(encoded.length);
  if (ptr === 0) throw new Error("WASM alloc failed");
  new Uint8Array(wasm!.memory.buffer).set(encoded, ptr);
  return ptr;
}

async function loadWasm(): Promise<void> {
  if (wasm) return;

  const response = await fetch("/libwimg.wasm");
  const bytes = await response.arrayBuffer();
  const compiled = await WebAssembly.compile(bytes);

  const importObject: Record<string, Record<string, unknown>> = {
    env: {
      js_console_log: (ptr: number, len: number) => {
        try {
          const mem = new Uint8Array(wasm!.memory.buffer);
          console.log("[embed-worker]", new TextDecoder().decode(mem.slice(ptr, ptr + len)));
        } catch {
          /* ignore */
        }
      },
      js_time_ms: () => BigInt(Date.now()),
      js_embed_progress: (current: number, total: number) => {
        self.postMessage({ type: "embed-progress", current, total });
      },
    },
  };

  // Fill any missing imports with stubs
  for (const imp of WebAssembly.Module.imports(compiled)) {
    if (!importObject[imp.module]) importObject[imp.module] = {};
    if (!(imp.name in importObject[imp.module])) {
      if (imp.kind === "function") {
        importObject[imp.module][imp.name] = () => 0;
      }
    }
  }

  const result = await WebAssembly.instantiate(compiled, importObject as WebAssembly.Imports);
  wasm = result.exports as unknown as WorkerWasm;
}

async function loadModel(): Promise<void> {
  const root = await navigator.storage.getDirectory();
  const fileHandle = await root.getFileHandle(MODEL_OPFS_FILE);
  const file = await fileHandle.getFile();
  if (file.size === 0) throw new Error("Model file empty in OPFS");

  const modelBytes = new Uint8Array(await file.arrayBuffer());
  const ptr = wasm!.wimg_alloc_model(modelBytes.length);
  if (ptr === 0) throw new Error("WASM allocation failed for model");

  const mem = new Uint8Array(wasm!.memory.buffer);
  mem.set(modelBytes, ptr);

  const rc = wasm!.wimg_load_model(ptr, modelBytes.length);
  if (rc !== 0) throw new Error("Failed to load embedding model");
}

self.onmessage = async (e: MessageEvent) => {
  if (e.data.type !== "embed") return;

  try {
    self.postMessage({ type: "progress", step: "init" });
    await loadWasm();

    // Load DB state from main thread
    const dbData = new Uint8Array(e.data.dbBytes as ArrayBuffer);
    const loadPtr = wasm!.wimg_alloc(dbData.length);
    if (loadPtr === 0) throw new Error("Alloc failed");
    new Uint8Array(wasm!.memory.buffer).set(dbData, loadPtr);
    wasm!.wimg_db_load(loadPtr, dbData.length);

    const pathPtr = writeZeroTerminated("/wimg.db");
    wasm!.wimg_init(pathPtr);

    // Load embedding model from cache
    self.postMessage({ type: "progress", step: "model" });
    await loadModel();

    // Embed transactions
    self.postMessage({ type: "progress", step: "embed" });
    const embedded = wasm!.wimg_embed_transactions();
    if (embedded < 0) throw new Error("Embedding failed");

    // Smart categorize
    self.postMessage({ type: "progress", step: "categorize" });
    const categorized = wasm!.wimg_smart_categorize();
    if (categorized < 0) throw new Error("Smart categorize failed");

    // Extract modified DB
    const dbPtr = wasm!.wimg_db_ptr();
    const dbSize = wasm!.wimg_db_size();
    const resultDb = new Uint8Array(wasm!.memory.buffer).slice(dbPtr, dbPtr + dbSize);

    wasm!.wimg_close();

    self.postMessage(
      { type: "done", dbBytes: resultDb.buffer, embedded, categorized },
      { transfer: [resultDb.buffer] },
    );
  } catch (err) {
    self.postMessage({
      type: "error",
      message: err instanceof Error ? err.message : String(err),
    });
  }
};
