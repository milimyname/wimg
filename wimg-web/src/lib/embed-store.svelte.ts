/**
 * Global embed worker store — survives page navigation.
 * Manages the embed worker lifecycle, tracks progress, and notifies via toast on completion.
 */
import { getDbBytes, reloadDb } from "./wasm";
import { toastStore } from "./toast.svelte";

type EmbedState = "idle" | "init" | "model" | "embed" | "categorize";

let state = $state<EmbedState>("idle");
let progress = $state({ current: 0, total: 0 });
let error = $state("");
let worker: Worker | null = null;

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

  start() {
    if (worker) return; // Already running

    state = "init";
    progress = { current: 0, total: 0 };
    error = "";

    const dbBytes = getDbBytes();

    worker = new Worker(new URL("./embed.worker.ts", import.meta.url), { type: "module" });

    worker.onmessage = async (e: MessageEvent) => {
      const msg = e.data;

      if (msg.type === "progress") {
        state = msg.step as EmbedState;
      } else if (msg.type === "embed-progress") {
        state = "embed";
        progress = { current: msg.current, total: msg.total };
      } else if (msg.type === "done") {
        const updatedDb = new Uint8Array(msg.dbBytes as ArrayBuffer);
        await reloadDb(updatedDb);

        const parts: string[] = [];
        if (msg.embedded > 0) parts.push(`${msg.embedded} eingebettet`);
        if (msg.categorized > 0) parts.push(`${msg.categorized} kategorisiert`);
        toastStore.show(
          parts.length > 0 ? `Smart Categorize: ${parts.join(", ")}` : "Embedding abgeschlossen",
        );

        // Dispatch event so pages can refresh
        window.dispatchEvent(new CustomEvent("wimg:embed-done"));

        cleanup();
      } else if (msg.type === "error") {
        error = msg.message;
        toastStore.show(`Embedding-Fehler: ${msg.message}`);
        cleanup();
      }
    };

    worker.onerror = () => {
      error = "Worker-Fehler";
      toastStore.show("Embedding-Worker fehlgeschlagen");
      cleanup();
    };

    worker.postMessage({ type: "embed", dbBytes: dbBytes.buffer }, [dbBytes.buffer]);
  },
};

function cleanup() {
  worker?.terminate();
  worker = null;
  state = "idle";
  progress = { current: 0, total: 0 };
}
