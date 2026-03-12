/**
 * Embed store — worker computes embeddings, main thread stores in live DB.
 *
 * Worker loads its own WASM + model for inference (no DB).
 * Main thread queries unembedded txns, sends descriptions to worker,
 * stores returned vectors in the live DB. Search works incrementally.
 */
import {
  embeddingStatus,
  isModelLoaded,
  loadEmbeddingModel,
  opfsSave,
  queryRaw,
  smartCategorize,
  storeEmbedding,
} from "./wasm";
import { toastStore } from "./toast.svelte";

type EmbedState = "idle" | "init" | "model" | "embed" | "categorize";

const BATCH_SIZE = 10;
const MODEL_VER = "e5-small-q8-v7";

/**
 * Strip Comdirect banking boilerplate from transaction descriptions before embedding.
 * Keeps only the meaningful semantic content (merchant name, purpose, location).
 *
 * Examples:
 *   "Auftraggeber: Netto Marken-Discount Buchungstext: Netto Marken-Discount, Wuppertal D E
 *    Karte Nr. 4871 78XX XXXX 2560 Kartenzahlung comdirect Visa-Debitkarte 2026-01-08 00:00:00
 *    Ref. AM2C28SW1RZ86DYW/64398"
 *     → "Netto Marken-Discount Netto Marken-Discount, Wuppertal"
 *
 *   "Auftraggeber: Manuel Alles Ref. D05C28SU3O3LB1E0/1"
 *     → "Manuel Alles"
 */
function cleanDescription(desc: string): string {
  return desc
    .replace(/^(Auftraggeber|Empf(?:ä|ae?)nger):\s*/i, "")
    .replace(/Kto\/IBAN:\s*\S+/g, "") // IBAN (no \b — name runs into "Kto/" without space)
    .replace(/BLZ\/BIC:\s*\S+/g, "") // BIC
    .replace(/\bBuchungstext:\s*/gi, " ") // replace with space to separate
    .replace(/\bKarte\s+Nr\.\s*[\dX\s]+/g, "") // card number
    .replace(/Kartenzahlung\s+\S+\s+Visa-Debitkarte\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/g, "")
    .replace(/\bRef\.\s*\S+/g, "") // reference number
    .replace(/\b\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}\b/g, "") // dates: 05.01.2026 19:05
    .replace(/\bEINZAHLAUTOMAT\s+\d+/g, "") // ATM IDs
    .replace(/\bKARTE\s+\d+/g, "") // KARTE 0
    .replace(/\s+D\s+E\b/g, "") // country code "D E"
    .replace(/\s+/g, " ")
    .trim();
}

let state = $state<EmbedState>("idle");
let progress = $state({ current: 0, total: 0 });
let error = $state("");
let worker: Worker | null = null;
let pendingReject: ((err: Error) => void) | null = null;

export const embedStore = {
  get running() {
    return state !== "idle";
  },
  get state() {
    return state;
  },
  get progress() {
    return progress;
  },
  get error() {
    return error;
  },

  async start() {
    if (state !== "idle") return;

    error = "";

    // 1. Ensure model is downloaded + loaded on main thread (for semantic search)
    if (!isModelLoaded()) {
      state = "model";
      try {
        await loadEmbeddingModel();
      } catch (e) {
        error = e instanceof Error ? e.message : "Modell laden fehlgeschlagen";
        toastStore.show(`Embedding-Fehler: ${error}`);
        state = "idle";
        return;
      }
    }

    // 2. Check how many need embedding
    const status = embeddingStatus();
    if (status.unembedded === 0) {
      state = "idle";
      return;
    }

    // 3. Init inference worker
    state = "init";
    try {
      await initWorker();
    } catch (e) {
      error = e instanceof Error ? e.message : "Worker-Init fehlgeschlagen";
      toastStore.show(`Embedding-Fehler: ${error}`);
      cleanup();
      return;
    }

    // 4. Batch embed loop
    state = "embed";
    progress = { current: 0, total: status.unembedded };
    let embedded = 0;

    try {
      while (worker) {
        // Query unembedded (or outdated model_ver) from live DB
        const result = queryRaw(
          `SELECT id, description FROM transactions WHERE id NOT IN (SELECT tx_id FROM embeddings WHERE model_ver = '${MODEL_VER}') LIMIT ${BATCH_SIZE}`,
        );
        if (result.rows.length === 0) break;

        const items = result.rows.map((r) => ({
          id: r[0] as string,
          text: cleanDescription(r[1] as string),
        }));

        // Send to worker for embedding computation
        const embeddings = await embedBatchInWorker(items);

        // Store each embedding in the live DB
        for (const { id, embedding } of embeddings) {
          storeEmbedding(id, new Uint8Array(embedding));
        }

        embedded += embeddings.length;
        progress = { current: embedded, total: status.unembedded };
      }

      // Save all new embeddings to OPFS
      await opfsSave();

      // 5. Smart categorize
      state = "categorize";
      const categorized = smartCategorize();
      if (categorized > 0) await opfsSave();

      // 6. Toast + event
      const parts: string[] = [];
      if (embedded > 0) parts.push(`${embedded} eingebettet`);
      if (categorized > 0) parts.push(`${categorized} kategorisiert`);
      toastStore.show(
        parts.length > 0 ? `Smart Categorize: ${parts.join(", ")}` : "Embedding abgeschlossen",
      );

      window.dispatchEvent(new CustomEvent("wimg:embed-done"));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg !== "Aborted") {
        error = msg;
        toastStore.show(`Embedding-Fehler: ${error}`);
      }
      // Partial embeddings are already stored in live DB — save them
      if (embedded > 0) await opfsSave();
    } finally {
      cleanup();
    }
  },

  stop() {
    const reject = pendingReject;
    pendingReject = null;
    worker?.terminate();
    worker = null;
    state = "idle";
    progress = { current: 0, total: 0 };
    if (reject) reject(new Error("Aborted"));
  },
};

function initWorker(): Promise<void> {
  return new Promise((resolve, reject) => {
    worker = new Worker(new URL("./embed.worker.ts", import.meta.url), { type: "module" });

    const onMessage = (e: MessageEvent) => {
      worker?.removeEventListener("message", onMessage);
      worker?.removeEventListener("error", onError);
      if (e.data.type === "ready") resolve();
      else reject(new Error(e.data.message || "Worker init failed"));
    };

    const onError = () => {
      worker?.removeEventListener("message", onMessage);
      worker?.removeEventListener("error", onError);
      reject(new Error("Worker error during init"));
    };

    worker.addEventListener("message", onMessage);
    worker.addEventListener("error", onError);
    // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
    worker.postMessage({ type: "init" });
  });
}

function embedBatchInWorker(
  items: Array<{ id: string; text: string }>,
): Promise<Array<{ id: string; embedding: ArrayBuffer }>> {
  return new Promise((resolve, reject) => {
    if (!worker) return reject(new Error("Worker not initialized"));

    pendingReject = reject;

    const onMessage = (e: MessageEvent) => {
      worker?.removeEventListener("message", onMessage);
      worker?.removeEventListener("error", onError);
      pendingReject = null;
      if (e.data.type === "batch-done") resolve(e.data.results);
      else reject(new Error(e.data.message || "Batch embedding failed"));
    };

    const onError = () => {
      worker?.removeEventListener("message", onMessage);
      worker?.removeEventListener("error", onError);
      pendingReject = null;
      reject(new Error("Worker error during batch"));
    };

    worker.addEventListener("message", onMessage);
    worker.addEventListener("error", onError);
    // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker
    worker.postMessage({ type: "batch", items });
  });
}

function cleanup() {
  worker?.terminate();
  worker = null;
  pendingReject = null;
  state = "idle";
  progress = { current: 0, total: 0 };
}
