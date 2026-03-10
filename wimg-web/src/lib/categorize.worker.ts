/**
 * Web Worker for post-import categorization.
 *
 * Loads its own WASM instance so heavy operations (rule engine, recurring
 * detection) run off the main thread. Receives the current DB state via
 * Transferable ArrayBuffer, categorizes, and sends back the modified DB.
 */
export {};

interface WorkerWasm {
  memory: WebAssembly.Memory;
  wimg_init: (path: number) => number;
  wimg_close: () => void;
  wimg_alloc: (size: number) => number;
  wimg_db_load: (data: number, size: number) => number;
  wimg_db_ptr: () => number;
  wimg_db_size: () => number;
  wimg_auto_categorize: () => number;
  wimg_detect_recurring: () => number;
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
          console.log("[wimg-worker]", new TextDecoder().decode(mem.slice(ptr, ptr + len)));
        } catch {
          /* ignore */
        }
      },
      js_time_ms: () => BigInt(Date.now()),
      js_embed_progress: () => {},
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

self.onmessage = async (e: MessageEvent) => {
  if (e.data.type !== "categorize") return;

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

    // Detect recurring patterns
    self.postMessage({ type: "progress", step: "recurring" });
    wasm!.wimg_detect_recurring();

    // Auto-categorize via rule engine
    self.postMessage({ type: "progress", step: "rules" });
    const ruleCount = wasm!.wimg_auto_categorize();

    // Extract modified DB
    const dbPtr = wasm!.wimg_db_ptr();
    const dbSize = wasm!.wimg_db_size();
    const resultDb = new Uint8Array(wasm!.memory.buffer).slice(dbPtr, dbPtr + dbSize);

    wasm!.wimg_close();

    // Send back (Transferable for zero-copy)
    self.postMessage(
      { type: "done", dbBytes: resultDb.buffer, ruleCount },
      { transfer: [resultDb.buffer] },
    );
  } catch (err) {
    self.postMessage({
      type: "error",
      message: err instanceof Error ? err.message : String(err),
    });
  }
};
