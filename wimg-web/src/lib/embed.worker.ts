/**
 * Inference-only web worker for embedding transactions.
 *
 * Loads its own WASM instance + embedding model. Receives transaction
 * descriptions, computes embedding vectors, returns raw bytes.
 * No DB operations — main thread stores embeddings in the live DB.
 */
export {};

const MODEL_OPFS_FILE = "e5-small-q8-v7.gguf";

interface WorkerWasm {
  memory: WebAssembly.Memory;
  wimg_alloc: (size: number) => number;
  wimg_alloc_model: (size: number) => number;
  wimg_load_model: (data: number, len: number) => number;
  wimg_embed_text: (text: number, len: number) => number;
  wimg_free: (ptr: number, len: number) => void;
}

let wasm: WorkerWasm | null = null;

function readLengthPrefixedString(ptr: number): string {
  const mem = new Uint8Array(wasm!.memory.buffer);
  const len = mem[ptr] | (mem[ptr + 1] << 8) | (mem[ptr + 2] << 16) | (mem[ptr + 3] << 24);
  return new TextDecoder().decode(mem.slice(ptr + 4, ptr + 4 + len));
}

function writeBytes(data: Uint8Array): number {
  const ptr = wasm!.wimg_alloc(data.length);
  if (ptr === 0) throw new Error("WASM alloc failed");
  new Uint8Array(wasm!.memory.buffer).set(data, ptr);
  return ptr;
}

async function init(): Promise<void> {
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
      js_embed_progress: () => {},
    },
  };

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

  // Load model from OPFS
  const root = await navigator.storage.getDirectory();
  const fileHandle = await root.getFileHandle(MODEL_OPFS_FILE);
  const file = await fileHandle.getFile();
  if (file.size === 0) throw new Error("Model file empty in OPFS");

  const modelBytes = new Uint8Array(await file.arrayBuffer());
  const modelPtr = wasm.wimg_alloc_model(modelBytes.length);
  if (modelPtr === 0) throw new Error("WASM allocation failed for model");

  new Uint8Array(wasm.memory.buffer).set(modelBytes, modelPtr);

  const rc = wasm.wimg_load_model(modelPtr, modelBytes.length);
  if (rc !== 0) throw new Error("Failed to load embedding model");
}

function embedText(text: string): Uint8Array {
  const prefixed = "passage: " + text;
  const encoded = new TextEncoder().encode(prefixed);
  const ptr = writeBytes(encoded);

  const resultPtr = wasm!.wimg_embed_text(ptr, encoded.length);
  if (resultPtr === 0) throw new Error("embed_text failed");

  const json = readLengthPrefixedString(resultPtr);
  wasm!.wimg_free(resultPtr, 0);

  const floats = JSON.parse(json) as number[];
  const f32 = new Float32Array(floats);
  return new Uint8Array(f32.buffer);
}

self.addEventListener("message", async (e: MessageEvent) => {
  const { type } = e.data;

  if (type === "init") {
    try {
      await init();
      // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
      self.postMessage({ type: "ready" });
    } catch (err) {
      // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
      self.postMessage({
        type: "error",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  } else if (type === "batch") {
    try {
      const items = e.data.items as Array<{ id: string; text: string }>;
      const results: Array<{ id: string; embedding: ArrayBuffer }> = [];
      const transfers: ArrayBuffer[] = [];

      for (const item of items) {
        const bytes = embedText(item.text);
        const buf = bytes.buffer as ArrayBuffer;
        results.push({ id: item.id, embedding: buf });
        transfers.push(buf);
      }

      // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
      self.postMessage({ type: "batch-done", results }, { transfer: transfers });
    } catch (err) {
      // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
      self.postMessage({
        type: "error",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
});
