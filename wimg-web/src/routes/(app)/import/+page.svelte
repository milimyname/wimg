<script lang="ts">
  import {
    parseCsv,
    importCsv,
    setCategory,
    getTransactions,
    getDbBytes,
    reloadDb,
    embeddingStatus,
    loadEmbeddingModel,
    smartCategorize,
    CATEGORIES,
    type ImportResult,
    type ParseResult,
    type Transaction,
  } from "$lib/wasm";
  import { embedStore } from "$lib/embed-store.svelte";
  import { onMount, onDestroy } from "svelte";
  import { formatEur, formatDate } from "$lib/format";
  import { toastStore } from "$lib/toast.svelte";
  import { accountStore } from "$lib/account.svelte";
  import { dropStore } from "$lib/drop.svelte";
  import BottomSheet from "../../../components/BottomSheet.svelte";

  type ImportStage = "idle" | "preview" | "imported";

  let stage = $state<ImportStage>("idle");
  let dragging = $state(false);
  let importing = $state(false);
  let parsing = $state(false);
  let importError = $state<string | null>(null);
  let importResult = $state<ImportResult | null>(null);

  // Preview state
  let parseResult = $state<ParseResult | null>(null);
  let csvBuffer = $state<ArrayBuffer | null>(null);
  let showAllPreview = $state(false);

  // Multi-file queue
  let fileQueue = $state<File[]>([]);
  let queueIndex = $state(0);

  // Post-import preview
  let previewTransactions = $state<Transaction[]>([]);

  // Auto-categorize counts
  let ruleCategorizeCount = $state<number | null>(null);

  // Inline category assignment
  let editingTxn = $state<Transaction | null>(null);
  let showCategorySheet = $state(false);

  // Multi-select
  let selectedTxnIds = $state<Set<string>>(new Set());
  let selectionMode = $state(false);

  // Embedding model CTA
  let showEmbeddingsInfo = $state(false);
  let modelDownloading = $state(false);
  let downloadProgress = $state(0);
  let modelError = $state("");

  // Categorization worker toast
  type CatStep = "init" | "recurring" | "rules" | "done";
  let catStep = $state<CatStep | null>(null);
  let catExpanded = $state(false);
  let catWorker: Worker | null = null;

  const CAT_STEP_LABELS: Record<CatStep, string> = {
    init: "WASM wird geladen...",
    recurring: "Wiederkehrende erkennen...",
    rules: "Regel-Engine...",
    done: "Kategorisierung abgeschlossen",
  };

  let categorizedCount = $derived(
    previewTransactions.filter((t) => t.category !== 0).length,
  );
  let uncategorizedTxns = $derived(
    previewTransactions.filter((t) => t.category === 0),
  );
  let selectedCount = $derived(selectedTxnIds.size);

  let embedStatusTrigger = $state(0);
  let embeddingModelStatus = $derived.by(() => {
    // eslint-disable-next-line no-unused-expressions
    embedStatusTrigger; // reactive dependency — increment to re-compute
    try {
      return embeddingStatus();
    } catch {
      return null;
    }
  });
  let hasEmbeddingModel = $derived(embeddingModelStatus?.model_loaded ?? false);
  let unembeddedCount = $derived(embeddingModelStatus?.unembedded ?? 0);

  // Refresh status when embed worker finishes
  function onEmbedDone() {
    embedStatusTrigger++;
    previewTransactions = getTransactions();
  }
  onMount(() => {
    window.addEventListener("wimg:embed-done", onEmbedDone);
  });
  onDestroy(() => {
    window.removeEventListener("wimg:embed-done", onEmbedDone);
  });

  // Smart Categorize (post-import, on main thread)
  let smartCatResult = $state("");

  function handleSmartCategorize() {
    smartCatResult = "";
    try {
      const count = smartCategorize();
      if (count === -2) {
        smartCatResult = "hint";
      } else if (count > 0) {
        smartCatResult = `${count} kategorisiert`;
        previewTransactions = getTransactions();
      } else {
        smartCatResult = "Keine unkategorisierten gefunden";
      }
      setTimeout(() => {
        smartCatResult = "";
      }, 5000);
    } catch {
      smartCatResult = "Fehler";
    }
  }

  let previewSlice = $derived.by(() => {
    if (stage === "preview" && parseResult) {
      const txns = parseResult.transactions;
      return showAllPreview ? txns : txns.slice(0, 5);
    }
    return [];
  });

  let previewTotals = $derived.by(() => {
    if (!parseResult) return { income: 0, expenses: 0 };
    let income = 0;
    let expenses = 0;
    for (const txn of parseResult.transactions) {
      if (txn.amount >= 0) income += txn.amount;
      else expenses += txn.amount;
    }
    return { income, expenses };
  });

  // Cleanup worker on unmount
  $effect(() => {
    return () => {
      catWorker?.terminate();
      catWorker = null;
    };
  });

  function handleDragOver(e: DragEvent) {
    e.preventDefault();
    dragging = true;
  }

  function handleDragLeave() {
    dragging = false;
  }

  async function handleDrop(e: DragEvent) {
    e.preventDefault();
    dragging = false;
    const files = Array.from(e.dataTransfer?.files ?? []).filter((f) =>
      f.name.endsWith(".csv"),
    );
    if (files.length === 0) return;
    fileQueue = files;
    queueIndex = 0;
    await processFile(files[0]);
  }

  async function handleFileInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    if (files.length === 0) return;
    fileQueue = files;
    queueIndex = 0;
    await processFile(files[0]);
    input.value = "";
  }

  async function processFile(file: File) {
    try {
      importError = null;
      importResult = null;
      parseResult = null;
      ruleCategorizeCount = null;
      parsing = true;
      const buffer = await file.arrayBuffer();
      csvBuffer = buffer;
      parseResult = parseCsv(buffer);
      stage = "preview";
      showAllPreview = false;
    } catch (e) {
      importError = e instanceof Error ? e.message : "Parsing fehlgeschlagen";
      stage = "idle";
    } finally {
      parsing = false;
    }
  }

  async function confirmImport() {
    if (!csvBuffer) return;
    try {
      importError = null;
      importing = true;
      importResult = await importCsv(csvBuffer);
      csvBuffer = null;

      // Show imported state immediately — no heavy work on main thread
      showAllPreview = false;
      stage = "imported";
      importing = false;
      accountStore.reload();

      // Offload categorization to Web Worker
      runCategorizationWorker();
    } catch (e) {
      importError = e instanceof Error ? e.message : "Import fehlgeschlagen";
      importing = false;
    }
  }

  function runCategorizationWorker() {
    catExpanded = false;
    catStep = "init";

    // Snapshot current DB state for the worker
    const dbBytes = getDbBytes();

    const worker = new Worker(
      new URL("../../../lib/categorize.worker.ts", import.meta.url),
      { type: "module" },
    );
    catWorker = worker;

    worker.onmessage = async (e: MessageEvent) => {
      const msg = e.data;

      if (msg.type === "progress") {
        catStep = msg.step as CatStep;
      } else if (msg.type === "done") {
        // Reload DB with worker's categorized data
        const updatedDb = new Uint8Array(msg.dbBytes as ArrayBuffer);
        await reloadDb(updatedDb);

        ruleCategorizeCount = msg.ruleCount > 0 ? msg.ruleCount : null;
        previewTransactions = getTransactions();

        catStep = "done";
        worker.terminate();
        catWorker = null;

        setTimeout(() => {
          if (catStep === "done") catStep = null;
        }, 2500);
      } else if (msg.type === "error") {
        console.error("[categorize-worker]", msg.message);
        // Fallback: show transactions without categorization
        previewTransactions = getTransactions();
        catStep = null;
        worker.terminate();
        catWorker = null;
      }
    };

    worker.onerror = () => {
      previewTransactions = getTransactions();
      catStep = null;
      catWorker = null;
    };

    // Transfer DB bytes (zero-copy)
    worker.postMessage({ type: "categorize", dbBytes: dbBytes.buffer }, [
      dbBytes.buffer,
    ]);
  }

  function cancelPreview() {
    parseResult = null;
    csvBuffer = null;
    stage = "idle";
  }

  async function handleInlineCategory(catId: number) {
    if (!editingTxn) return;
    await setCategory(editingTxn.id, catId);
    previewTransactions = previewTransactions.map((t) =>
      t.id === editingTxn!.id ? { ...t, category: catId } : t,
    );
    showCategorySheet = false;
    editingTxn = null;
  }

  async function handleBatchCategory(catId: number) {
    const ids = [...selectedTxnIds];
    for (const id of ids) {
      await setCategory(id, catId);
    }
    previewTransactions = previewTransactions.map((t) =>
      selectedTxnIds.has(t.id) ? { ...t, category: catId } : t,
    );
    selectedTxnIds = new Set();
    selectionMode = false;
    showCategorySheet = false;
  }

  function toggleSelection(id: string) {
    const next = new Set(selectedTxnIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    selectedTxnIds = next;
  }

  function selectAll() {
    selectedTxnIds = new Set(uncategorizedTxns.map((t) => t.id));
  }

  function clearSelection() {
    selectedTxnIds = new Set();
    selectionMode = false;
  }

  async function handleDownloadModel() {
    modelDownloading = true;
    downloadProgress = 0;
    modelError = "";
    try {
      await loadEmbeddingModel((pct) => {
        downloadProgress = pct;
      });
      embedStatusTrigger++;
      showEmbeddingsInfo = false;
    } catch (e) {
      modelError = e instanceof Error ? e.message : "Download fehlgeschlagen";
    } finally {
      modelDownloading = false;
    }
  }

  function handleEmbedNow() {
    modelError = "";
    showEmbeddingsInfo = false;
    embedStore.start();
  }

  function formatLabel(format: string): string {
    const map: Record<string, string> = {
      comdirect: "Comdirect",
      trade_republic: "Trade Republic",
      scalable: "Scalable Capital",
      scalable_capital: "Scalable Capital",
    };
    return map[format] ?? format;
  }

  function accountForFormat(format: string): { name: string; color: string } {
    const map: Record<string, { name: string; color: string }> = {
      comdirect: { name: "Comdirect", color: "#f5a623" },
      trade_republic: { name: "Trade Republic", color: "#1a1a2e" },
      scalable_capital: { name: "Scalable Capital", color: "#6c5ce7" },
    };
    return map[format] ?? { name: "Unbekannt", color: "#1A1A1A" };
  }

  $effect(() => {
    const files = dropStore.files;
    if (files.length > 0) {
      dropStore.clear();
      fileQueue = files;
      queueIndex = 0;
      processFile(files[0]);
    }
  });

  async function loadNextFile() {
    queueIndex++;
    stage = "idle";
    importResult = null;
    parseResult = null;
    showAllPreview = false;
    ruleCategorizeCount = null;
    catStep = null;
    previewTransactions = [];
    await processFile(fileQueue[queueIndex]);
  }
</script>

<div class="flex items-center gap-3 mb-5">
  <a
    href="/more"
    class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
    aria-label="Zurück"
  >
    <svg
      class="w-5 h-5 text-(--color-text)"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M15 19l-7-7 7-7"
      />
    </svg>
  </a>
  <h2 class="text-xl font-display font-extrabold text-(--color-text)">
    CSV Import
  </h2>
</div>

{#if fileQueue.length > 1}
  <div
    class="flex items-center justify-center gap-2 mb-4 text-sm font-bold text-(--color-text-secondary)"
  >
    <span>Datei {queueIndex + 1} von {fileQueue.length}</span>
    <span class="text-xs">({fileQueue[queueIndex]?.name})</span>
  </div>
{/if}

<!-- Drop Zone (idle + preview stages) -->
{#if stage === "idle" || stage === "preview"}
  <div
    class="flex flex-col items-center gap-5 rounded-3xl border-2 border-dashed px-6 py-10 mb-5 transition-all cursor-pointer bg-white shadow-[var(--shadow-card)]"
    style="border-color: {dragging ? 'var(--color-text)' : '#e0dcd6'}"
    role="button"
    tabindex="0"
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
    onclick={() => document.getElementById("file-input")?.click()}
    onkeydown={(e) =>
      e.key === "Enter" && document.getElementById("file-input")?.click()}
  >
    <input
      id="file-input"
      type="file"
      accept=".csv"
      multiple
      class="hidden"
      onchange={handleFileInput}
    />

    {#if parsing}
      <div
        class="animate-spin w-10 h-10 border-4 border-(--color-text) border-t-transparent rounded-full"
      ></div>
      <p class="text-sm text-(--color-text-secondary) font-medium">
        Analysiere...
      </p>
    {:else}
      <div class="bg-gray-100 p-5 rounded-full mb-2">
        {#if dragging}
          <svg
            class="w-8 h-8 text-(--color-text)"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 4v16m8-8H4"
            />
          </svg>
        {:else}
          <svg
            class="w-8 h-8 text-(--color-text)"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
            />
          </svg>
        {/if}
      </div>
      <div class="text-center">
        <p class="text-xl font-display font-extrabold">CSV-Datei hochladen</p>
        <p
          class="text-sm text-(--color-text-secondary) mt-1.5 max-w-[240px] font-medium"
        >
          Ziehe deine Bankdatei hierhin oder tippe zum Durchsuchen
        </p>
      </div>
      <button
        class="px-8 py-3 rounded-full text-sm font-bold bg-(--color-text) text-white shadow-md cursor-pointer hover:opacity-90 transition-opacity"
        onclick={(e) => {
          e.stopPropagation();
          document.getElementById("file-input")?.click();
        }}
      >
        Datei auswählen
      </button>
    {/if}
  </div>
{/if}

<!-- Error -->
{#if importError}
  <div class="bg-red-50 rounded-3xl p-5 mb-4 text-red-700 text-sm font-medium">
    {importError}
  </div>
{/if}

<!-- CSV Preview (stage: preview) -->
{#if stage === "preview" && parseResult}
  <!-- Format Badge -->
  {#if parseResult.format && parseResult.format !== "unknown"}
    <div
      class="flex items-center justify-between gap-4 rounded-3xl bg-emerald-50 p-5 mb-3"
    >
      <div class="flex flex-col gap-1 flex-1">
        <div class="flex items-center gap-2">
          <svg
            class="w-5 h-5 text-emerald-600 shrink-0"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <p class="text-base font-bold text-emerald-800">
            {formatLabel(parseResult.format)} CSV erkannt
          </p>
        </div>
        <p class="text-xs text-emerald-600 pl-7">
          {parseResult.total_rows} Zeilen gelesen
        </p>
      </div>
      <div
        class="w-12 h-12 bg-white/50 rounded-full flex items-center justify-center"
      >
        <svg
          class="w-6 h-6 text-emerald-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
          />
        </svg>
      </div>
    </div>
  {/if}

  <!-- Target Account Badge -->
  {#if parseResult.format && parseResult.format !== "unknown"}
    {@const acct = accountForFormat(parseResult.format)}
    <div
      class="flex items-center gap-2.5 rounded-2xl bg-white p-4 shadow-[var(--shadow-card)] mb-3"
    >
      <div
        class="w-3 h-3 rounded-full shrink-0"
        style="background-color: {acct.color}"
      ></div>
      <p class="text-xs text-(--color-text-secondary)">
        <span class="font-bold text-(--color-text)">Zielkonto:</span>
        {acct.name}
      </p>
    </div>
  {/if}

  <!-- Summary Card -->
  <div class="bg-blue-50 rounded-3xl p-5 mb-4">
    <p class="text-sm font-bold text-blue-900">
      {parseResult.transactions.length} Buchungen gefunden
    </p>
    <div class="flex gap-4 mt-2">
      {#if previewTotals.income > 0}
        <p class="text-xs text-emerald-600 font-bold">
          +{formatEur(previewTotals.income)} Einnahmen
        </p>
      {/if}
      {#if previewTotals.expenses < 0}
        <p class="text-xs text-rose-500 font-bold">
          {formatEur(previewTotals.expenses)} Ausgaben
        </p>
      {/if}
    </div>
  </div>

  <!-- Preview Transaction List -->
  {#if parseResult.transactions.length > 0}
    <div class="flex items-center justify-between mb-3">
      <h3 class="text-lg font-display font-bold">Vorschau</h3>
      {#if parseResult.transactions.length > 5}
        <button
          class="text-xs font-bold cursor-pointer text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
          onclick={() => (showAllPreview = !showAllPreview)}
        >
          {showAllPreview
            ? "Weniger"
            : `Alle ${parseResult.transactions.length} anzeigen`}
        </button>
      {/if}
    </div>
    <div class="flex flex-col gap-3 mb-5">
      {#each previewSlice as txn}
        <div
          class="flex items-center justify-between p-4 bg-white rounded-3xl shadow-[var(--shadow-card)]"
        >
          <div class="flex items-center gap-3.5">
            <div
              class="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0"
              style="background-color: {CATEGORIES[txn.category]?.color ??
                '#dfe6e9'}15"
            >
              {CATEGORIES[txn.category]?.icon ?? "📦"}
            </div>
            <div class="min-w-0">
              <p class="text-sm font-bold truncate max-w-[180px]">
                {txn.description}
              </p>
              <p
                class="text-xs text-(--color-text-secondary) mt-0.5 font-medium"
              >
                {formatDate(txn.date)} &middot; {CATEGORIES[txn.category]
                  ?.name ?? "Sonstiges"}
              </p>
            </div>
          </div>
          <p
            class="text-sm font-extrabold tabular-nums shrink-0"
            class:text-rose-500={txn.amount < 0}
            class:text-emerald-600={txn.amount > 0}
          >
            {txn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(txn.amount))}
          </p>
        </div>
      {/each}
    </div>

    <!-- Action Buttons -->
    <div class="flex flex-col gap-3 mb-5">
      <button
        onclick={confirmImport}
        disabled={importing}
        class="w-full px-6 py-4 rounded-full text-base font-display font-extrabold bg-(--color-accent) text-(--color-text) cursor-pointer hover:bg-(--color-accent-hover) transition-colors disabled:opacity-50 shadow-[var(--shadow-soft)]"
      >
        {#if importing}
          <span class="flex items-center justify-center gap-2">
            <span
              class="animate-spin w-4 h-4 border-2 border-t-transparent rounded-full border-(--color-text) inline-block"
            ></span>
            Importiere...
          </span>
        {:else}
          {parseResult.transactions.length} Buchungen importieren
        {/if}
      </button>
      <button
        onclick={cancelPreview}
        disabled={importing}
        class="w-full px-6 py-3 rounded-full text-sm font-bold text-(--color-text-secondary) bg-gray-100 cursor-pointer hover:bg-gray-200 transition-colors disabled:opacity-50"
      >
        Abbrechen
      </button>
    </div>
    <p
      class="text-center text-(--color-text-secondary) text-[10px] uppercase tracking-widest font-bold mb-4"
    >
      Local-first &middot; Sicherer Import
    </p>
  {/if}
{/if}

<!-- Global embed progress (persists across navigation) -->
{#if embedStore.running}
  <div class="flex items-center gap-3.5 bg-indigo-50 rounded-2xl p-4 mb-3">
    <div
      class="w-10 h-10 rounded-xl bg-indigo-100 flex items-center justify-center shrink-0"
    >
      <span
        class="w-5 h-5 border-2 border-indigo-300 border-t-indigo-600 rounded-full animate-spin"
      ></span>
    </div>
    <div class="flex-1 min-w-0">
      <p class="text-sm font-bold text-indigo-900">Smart Categorize läuft...</p>
      <p class="text-xs text-indigo-700 mt-0.5">
        {#if embedStore.state === "categorize"}
          Kategorisiere...
        {:else if embedStore.progress.total > 0}
          {embedStore.progress.current} von {embedStore.progress.total} Buchungen
          eingebettet
        {:else}
          {embedStore.state === "model"
            ? "Modell wird geladen..."
            : "Initialisiere..."}
        {/if}
      </p>
      {#if embedStore.progress.total > 0 && embedStore.state !== "categorize"}
        <div class="w-full bg-indigo-200 rounded-full h-1.5 mt-2">
          <div
            class="bg-indigo-600 h-1.5 rounded-full transition-all duration-300"
            style="width: {Math.round(
              (embedStore.progress.current / embedStore.progress.total) * 100,
            )}%"
          ></div>
        </div>
      {/if}
    </div>
  </div>
{/if}

<!-- Post-Import Results (stage: imported) -->
{#if stage === "imported" && importResult}
  <!-- Detected Format Card -->
  {#if importResult.format && importResult.format !== "unknown"}
    <div
      class="flex items-center justify-between gap-4 rounded-3xl bg-white p-5 shadow-[var(--shadow-card)] mb-3"
    >
      <div class="flex flex-col gap-1 flex-1">
        <div class="flex items-center gap-2">
          <svg
            class="w-5 h-5 text-emerald-600 shrink-0"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <p class="text-base font-bold">
            {formatLabel(importResult.format)} CSV erkannt
          </p>
        </div>
        <p class="text-xs text-(--color-text-secondary) pl-7">
          Importiert nach <span class="font-bold text-(--color-text)"
            >{accountForFormat(importResult.format).name}</span
          >
        </p>
      </div>
    </div>
  {/if}

  <!-- Import Summary -->
  <div class="bg-emerald-50 rounded-3xl p-5 mb-3 flex gap-3">
    <svg
      class="w-5 h-5 text-emerald-600 shrink-0 mt-0.5"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M5 13l4 4L19 7"
      />
    </svg>
    <div>
      <p class="text-sm font-bold text-emerald-900">Import abgeschlossen</p>
      <p class="text-xs text-emerald-700 mt-1">
        {importResult.imported} Buchungen importiert
        {#if ruleCategorizeCount && ruleCategorizeCount > 0}
          &middot; {ruleCategorizeCount} Regel-kategorisiert
        {/if}
        {#if importResult.errors > 0}
          &middot; {importResult.errors} Fehler
        {/if}
      </p>
    </div>
  </div>

  <!-- Duplicate Warning -->
  {#if importResult.skipped_duplicates > 0}
    <div class="bg-amber-50 rounded-3xl p-5 mb-3 flex gap-3">
      <svg
        class="w-5 h-5 text-amber-600 shrink-0 mt-0.5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
        />
      </svg>
      <div>
        <p class="text-sm font-bold text-amber-900">Duplikat-Hinweis</p>
        <p class="text-xs text-amber-700 mt-1">
          {importResult.skipped_duplicates} Buchungen waren bereits vorhanden und
          wurden übersprungen.
        </p>
      </div>
    </div>
  {/if}

  <!-- Smart Categorize CTA -->
  {#if !embedStore.running && (!hasEmbeddingModel || unembeddedCount > 0)}
    <button
      onclick={() => {
        showEmbeddingsInfo = true;
      }}
      class="flex items-center gap-3.5 bg-indigo-50 rounded-2xl p-4 mb-3 w-full text-left hover:bg-indigo-100 transition-colors cursor-pointer"
    >
      <div
        class="w-10 h-10 rounded-xl bg-indigo-100 flex items-center justify-center shrink-0"
      >
        <svg
          class="w-5 h-5 text-indigo-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M13 10V3L4 14h7v7l9-11h-7z"
          />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        {#if hasEmbeddingModel}
          <p class="text-sm font-bold text-indigo-900">Smart Categorize</p>
          <p class="text-xs text-indigo-700 mt-0.5">
            {unembeddedCount} Buchungen noch nicht eingebettet
          </p>
        {:else}
          <p class="text-sm font-bold text-indigo-900">
            Smart Categorize aktivieren
          </p>
          <p class="text-xs text-indigo-700 mt-0.5">
            Lokales KI-Modell installieren, damit neue Buchungen automatisch
            kategorisiert werden.
          </p>
        {/if}
      </div>
      <svg
        class="w-4 h-4 text-indigo-400 shrink-0"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 5l7 7-7 7"
        />
      </svg>
    </button>
  {/if}

  <!-- Next file in queue / Import another -->
  {#if fileQueue.length > 1 && queueIndex < fileQueue.length - 1}
    <button
      onclick={loadNextFile}
      class="w-full mb-3 px-4 py-3 rounded-2xl text-sm font-bold text-white bg-(--color-text) cursor-pointer hover:opacity-90 transition-opacity"
    >
      Nächste Datei laden ({queueIndex + 2}/{fileQueue.length})
    </button>
  {/if}
  <button
    onclick={() => {
      stage = "idle";
      importResult = null;
      parseResult = null;
      previewTransactions = [];
      showAllPreview = false;
      fileQueue = [];
      queueIndex = 0;
    }}
    class="w-full mb-4 px-4 py-3 rounded-2xl text-sm font-bold text-(--color-text-secondary) bg-white shadow-[var(--shadow-card)] cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow"
  >
    Weitere Datei importieren
  </button>

  <!-- Categorization Progress -->
  {#if previewTransactions.length > 0}
    <div class="mb-4">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-lg font-display font-bold">Kategorisierung</h3>
        <span class="text-sm font-bold text-(--color-text-secondary)">
          {categorizedCount} von {previewTransactions.length}
        </span>
      </div>
      <!-- Progress bar -->
      <div class="w-full h-2.5 bg-gray-100 rounded-full overflow-hidden">
        <div
          class="h-full rounded-full transition-all duration-300"
          style="width: {(categorizedCount / previewTransactions.length) *
            100}%; background-color: {categorizedCount ===
          previewTransactions.length
            ? '#10b981'
            : '#34d399'}"
        ></div>
      </div>
    </div>

    {#if uncategorizedTxns.length > 0}
      <!-- Smart Categorize hint + button -->
      <div class="mb-4 px-4 text-center">
        {#if hasEmbeddingModel && unembeddedCount === 0 && categorizedCount > 0}
          <button
            onclick={handleSmartCategorize}
            class="text-xs font-bold px-4 py-2 rounded-full bg-indigo-100 text-indigo-700 hover:bg-indigo-200 transition-colors cursor-pointer mb-2"
          >
            Smart Kategorisieren
          </button>
          {#if smartCatResult === "hint"}
            <p class="text-xs text-amber-600 font-medium">
              Kategorisiere zuerst ein paar Buchungen manuell als Referenz.
            </p>
          {:else if smartCatResult}
            <p class="text-xs text-emerald-600 font-medium">{smartCatResult}</p>
          {/if}
        {:else if hasEmbeddingModel && unembeddedCount > 0}
          <p class="text-xs text-amber-600 font-medium mb-1">
            Zuerst einbetten, dann kann Smart Categorize automatisch
            kategorisieren.
          </p>
        {/if}
        <p class="text-xs text-(--color-text-secondary) font-medium">
          Kategorisiere einige Buchungen manuell — Smart Categorize lernt daraus
          und kategorisiert ähnliche automatisch.
        </p>
      </div>

      <!-- Selection mode toggle -->
      <div class="flex items-center gap-2 mb-3">
        <button
          onclick={() => {
            selectionMode = !selectionMode;
            if (!selectionMode) selectedTxnIds = new Set();
          }}
          class="text-xs font-bold px-3 py-1.5 rounded-full transition-colors cursor-pointer"
          class:bg-emerald-100={selectionMode}
          class:text-emerald-700={selectionMode}
          class:bg-gray-100={!selectionMode}
          class:text-gray-600={!selectionMode}
        >
          {selectionMode ? "Auswahl beenden" : "Mehrere auswählen"}
        </button>
        {#if selectionMode}
          <button
            onclick={selectAll}
            class="text-xs font-bold px-3 py-1.5 rounded-full bg-gray-100 text-gray-600 cursor-pointer hover:bg-gray-200 transition-colors"
          >
            Alle auswählen
          </button>
        {/if}
      </div>

      <!-- Uncategorized transactions list -->
      <div class="flex flex-col gap-3 mb-4">
        {#each uncategorizedTxns as txn}
          <button
            class="flex items-center justify-between p-4 bg-white rounded-3xl shadow-[var(--shadow-card)] cursor-pointer hover:shadow-[var(--shadow-soft)] transition-all text-left w-full"
            style={selectionMode && selectedTxnIds.has(txn.id)
              ? "box-shadow: 0 0 0 2px #10b981, var(--shadow-card)"
              : ""}
            onclick={() => {
              if (selectionMode) {
                toggleSelection(txn.id);
              } else {
                editingTxn = txn;
                showCategorySheet = true;
              }
            }}
          >
            <div class="flex items-center gap-3.5 min-w-0 flex-1">
              {#if selectionMode}
                <div
                  class="w-6 h-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors"
                  class:border-emerald-500={selectedTxnIds.has(txn.id)}
                  class:bg-emerald-500={selectedTxnIds.has(txn.id)}
                  class:border-gray-300={!selectedTxnIds.has(txn.id)}
                >
                  {#if selectedTxnIds.has(txn.id)}
                    <svg
                      class="w-3.5 h-3.5 text-white"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="3"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                  {/if}
                </div>
              {/if}
              <div
                class="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0 bg-gray-50"
              >
                📦
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-bold truncate max-w-[180px]">
                  {txn.description}
                </p>
                <p
                  class="text-xs text-(--color-text-secondary) mt-0.5 font-medium"
                >
                  {formatDate(txn.date)}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2.5 shrink-0">
              <p
                class="text-sm font-extrabold tabular-nums"
                class:text-rose-500={txn.amount < 0}
                class:text-emerald-600={txn.amount > 0}
              >
                {txn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(txn.amount))}
              </p>
              {#if !selectionMode}
                <span
                  class="text-[11px] font-bold text-(--color-text-secondary) bg-gray-100 px-2.5 py-1 rounded-full whitespace-nowrap"
                >
                  Kategorie
                </span>
              {/if}
            </div>
          </button>
        {/each}
      </div>

      <!-- Floating action bar for batch selection -->
      {#if selectedCount > 0}
        <div
          class="fixed bottom-20 left-1/2 -translate-x-1/2 z-30 flex items-center gap-3 bg-white rounded-2xl shadow-lg border border-gray-100 px-4 py-3 max-w-[calc(100%-2rem)]"
        >
          <span class="text-sm font-bold text-(--color-text) whitespace-nowrap"
            >{selectedCount} ausgewählt</span
          >
          <button
            onclick={() => {
              editingTxn = null;
              showCategorySheet = true;
            }}
            class="px-4 py-2 rounded-full bg-(--color-text) text-white text-xs font-bold cursor-pointer hover:opacity-90 transition-opacity whitespace-nowrap"
          >
            Kategorie zuweisen
          </button>
          <button
            onclick={clearSelection}
            class="text-xs font-bold text-(--color-text-secondary) cursor-pointer hover:text-(--color-text) transition-colors whitespace-nowrap"
          >
            Abbrechen
          </button>
        </div>
      {/if}
    {:else}
      <!-- All categorized -->
      <div class="bg-emerald-50 rounded-3xl p-5 mb-5 flex items-center gap-3">
        <span class="text-2xl">🎉</span>
        <div>
          <p class="text-sm font-bold text-emerald-900">
            Alle Buchungen kategorisiert
          </p>
          <p class="text-xs text-emerald-700 mt-0.5">
            Zukünftige Importe profitieren von diesen Zuordnungen.
          </p>
        </div>
      </div>
    {/if}
  {/if}
{/if}

<!-- Category Selection BottomSheet -->
{#if showCategorySheet}
  <BottomSheet
    open={showCategorySheet}
    onclose={() => {
      showCategorySheet = false;
      editingTxn = null;
    }}
    snaps={[0.55]}
  >
    {#snippet children({ handle, content })}
      <!-- Handle -->
      <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
        <div class="w-12 h-1.5 bg-gray-200 rounded-full"></div>
      </div>

      <!-- Content -->
      <div class="px-6" {@attach content}>
        <!-- Header: single vs batch -->
        <div class="flex flex-col items-center mb-6 mt-4">
          {#if selectionMode && selectedCount > 0}
            <div
              class="w-16 h-16 rounded-2xl bg-emerald-50 flex items-center justify-center mb-3"
            >
              <span class="text-2xl font-extrabold text-emerald-600"
                >{selectedCount}</span
              >
            </div>
            <h2
              class="text-lg font-display font-extrabold text-center leading-tight"
            >
              {selectedCount} Buchungen
            </h2>
            <p class="text-sm text-(--color-text-secondary) mt-1">
              Kategorie für alle zuweisen
            </p>
          {:else if editingTxn}
            <div
              class="w-16 h-16 rounded-2xl bg-gray-50 flex items-center justify-center mb-3 text-3xl"
            >
              📦
            </div>
            <h2
              class="text-lg font-display font-extrabold text-center leading-tight"
            >
              {editingTxn.description}
            </h2>
            <p
              class="text-base font-display font-extrabold mt-1"
              class:text-rose-500={editingTxn.amount < 0}
              class:text-emerald-600={editingTxn.amount > 0}
            >
              {editingTxn.amount < 0 ? "-" : "+"}{formatEur(
                Math.abs(editingTxn.amount),
              )}
            </p>
          {/if}
        </div>

        <!-- Category pills -->
        <div class="mb-4">
          <span
            class="text-(--color-text-secondary) font-bold text-xs uppercase tracking-wider"
          >
            Kategorie wählen
          </span>
          <div class="flex flex-wrap gap-2 mt-3">
            {#each Object.entries(CATEGORIES) as [catId, cat]}
              <button
                class="flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold transition-all cursor-pointer border"
                style="background-color: {cat.color}10; border-color: transparent"
                onclick={() => {
                  if (selectionMode && selectedCount > 0) {
                    handleBatchCategory(Number(catId));
                  } else {
                    handleInlineCategory(Number(catId));
                  }
                }}
              >
                <span
                  class="w-2 h-2 rounded-full shrink-0"
                  style="background-color: {cat.color}"
                ></span>
                {cat.name}
              </button>
            {/each}
          </div>
        </div>
      </div>
    {/snippet}
  </BottomSheet>
{/if}

<!-- Categorization Toast -->
{#if catStep}
  <button
    class="fixed bottom-20 left-1/2 -translate-x-1/2 z-30 rounded-2xl shadow-lg border border-gray-100 px-5 py-3.5 flex items-center gap-3 cursor-pointer transition-all max-w-[calc(100%-2rem)] bg-white"
    onclick={() => (catExpanded = !catExpanded)}
  >
    {#if catStep === "done"}
      <svg
        class="w-5 h-5 text-emerald-500 shrink-0"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M5 13l4 4L19 7"
        />
      </svg>
    {:else}
      <div
        class="w-5 h-5 border-2 border-(--color-text) border-t-transparent rounded-full animate-spin shrink-0"
      ></div>
    {/if}
    <div class="text-left min-w-0">
      <p class="text-sm font-bold truncate">{CAT_STEP_LABELS[catStep]}</p>
      {#if catExpanded}
        {#if catStep !== "done"}
          <p class="text-xs text-(--color-text-secondary) mt-1">
            Läuft im Hintergrund. Die Seite bleibt bedienbar.
          </p>
        {:else if ruleCategorizeCount}
          <p class="text-xs text-emerald-600 mt-1 font-bold">
            {ruleCategorizeCount} Buchungen per Regeln kategorisiert
          </p>
        {/if}
      {/if}
    </div>
    <svg
      class="w-4 h-4 text-(--color-text-secondary) shrink-0 transition-transform"
      class:rotate-180={catExpanded}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M19 9l-7 7-7-7"
      />
    </svg>
  </button>
{/if}

<!-- Smart Categorize Info BottomSheet -->
<BottomSheet
  open={showEmbeddingsInfo}
  onclose={() => {
    showEmbeddingsInfo = false;
  }}
  snaps={[0.62]}
>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6">
      <div class="flex items-center gap-3 mb-5">
        <div
          class="w-12 h-12 rounded-2xl bg-indigo-100 flex items-center justify-center shrink-0"
        >
          <svg
            class="w-6 h-6 text-indigo-600"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
        </div>
        <div>
          <h3 class="font-display font-extrabold text-lg text-(--color-text)">
            Smart Categorize
          </h3>
          <p class="text-sm text-(--color-text-secondary)">
            {hasEmbeddingModel
              ? "Buchungen einbetten & kategorisieren"
              : "Lokales KI-Modell installieren"}
          </p>
        </div>
      </div>

      {#if hasEmbeddingModel}
        <!-- Model loaded: show embed info -->
        <div class="space-y-3">
          <p class="text-sm text-(--color-text-secondary) leading-relaxed">
            Das KI-Modell analysiert deine Buchungstexte und erkennt Muster. Je
            mehr Buchungen du manuell kategorisierst, desto besser lernt das
            Modell.
          </p>

          <div class="bg-gray-50 rounded-2xl p-4 space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-sm text-(--color-text-secondary)"
                >Transaktionen</span
              >
              <span class="text-sm font-medium text-(--color-text)"
                >{embeddingModelStatus?.total_txs ?? 0}</span
              >
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-(--color-text-secondary)"
                >Eingebettet</span
              >
              <span class="text-sm font-medium text-(--color-text)"
                >{embeddingModelStatus?.embedded ?? 0}</span
              >
            </div>
            {#if unembeddedCount > 0}
              <div class="flex items-center justify-between">
                <span class="text-sm text-(--color-text-secondary)"
                  >Ausstehend</span
                >
                <span class="text-sm font-medium text-amber-600"
                  >{unembeddedCount}</span
                >
              </div>
            {/if}
          </div>

          <div class="bg-amber-50 rounded-2xl p-4 flex items-start gap-3">
            <svg
              class="w-5 h-5 text-amber-500 shrink-0 mt-0.5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M13 10V3L4 14h7v7l9-11h-7z"
              />
            </svg>
            <p class="text-xs text-amber-800 leading-relaxed">
              <span class="font-bold">Tipp:</span> Kategorisiere mindestens 20–30
              Buchungen verschiedener Kategorien für beste Ergebnisse.
            </p>
          </div>
        </div>
      {:else}
        <!-- Model not installed: show download info -->
        <div class="space-y-3">
          <div class="flex items-start gap-3">
            <div
              class="w-8 h-8 rounded-xl bg-indigo-50 flex items-center justify-center shrink-0 mt-0.5"
            >
              <svg
                class="w-4 h-4 text-indigo-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                />
              </svg>
            </div>
            <div>
              <p class="text-sm font-medium text-(--color-text)">
                Was wird heruntergeladen?
              </p>
              <p class="text-xs text-(--color-text-secondary)">
                Ein mehrsprachiges Embedding-Modell (multilingual-e5-small, ~125
                MB). Es wandelt Buchungstexte in Vektoren um, die Ähnlichkeiten
                erkennen — mit hervorragender Deutsch-Unterstützung.
              </p>
            </div>
          </div>

          <div class="flex items-start gap-3">
            <div
              class="w-8 h-8 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0 mt-0.5"
            >
              <svg
                class="w-4 h-4 text-emerald-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </div>
            <div>
              <p class="text-sm font-medium text-(--color-text)">
                Smarte Kategorisierung
              </p>
              <p class="text-xs text-(--color-text-secondary)">
                Neue Buchungen werden automatisch kategorisiert, basierend auf
                Ähnlichkeit mit bereits kategorisierten Buchungen.
              </p>
            </div>
          </div>

          <div class="flex items-start gap-3">
            <div
              class="w-8 h-8 rounded-xl bg-blue-50 flex items-center justify-center shrink-0 mt-0.5"
            >
              <svg
                class="w-4 h-4 text-blue-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                />
              </svg>
            </div>
            <div>
              <p class="text-sm font-medium text-(--color-text)">
                100% lokal & privat
              </p>
              <p class="text-xs text-(--color-text-secondary)">
                Läuft komplett im Browser (WASM). Keine Daten verlassen dein
                Gerät. Einmaliger Download, danach gecacht.
              </p>
            </div>
          </div>
        </div>
      {/if}

      {#if modelError}
        <div
          class="rounded-xl bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700 mt-4"
        >
          {modelError}
        </div>
      {/if}

      {#if embedStore.error}
        <div
          class="rounded-xl bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700 mt-4"
        >
          {embedStore.error}
        </div>
      {/if}

      {#if modelDownloading}
        <div class="mt-4">
          <div class="w-full bg-gray-100 rounded-full h-2.5">
            <div
              class="bg-indigo-600 h-2.5 rounded-full transition-all duration-300"
              style="width: {downloadProgress}%"
            ></div>
          </div>
          <p class="text-xs text-(--color-text-secondary) mt-2 text-center">
            {downloadProgress}% heruntergeladen...
          </p>
        </div>
      {/if}
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      {#if hasEmbeddingModel}
        <button
          onclick={handleEmbedNow}
          disabled={embedStore.running || unembeddedCount === 0}
          class="w-full py-3.5 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50 mb-2"
        >
          {#if embedStore.running}
            <span class="inline-flex items-center gap-2">
              <span
                class="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin"
              ></span>
              {#if embedStore.progress.total > 0}
                {embedStore.progress.current} / {embedStore.progress.total} eingebettet...
              {:else}
                Modell wird geladen...
              {/if}
            </span>
          {:else}
            Jetzt einbetten ({unembeddedCount} ausstehend)
          {/if}
        </button>
      {:else}
        <button
          onclick={handleDownloadModel}
          disabled={modelDownloading}
          class="w-full py-3.5 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50 mb-2"
        >
          {#if modelDownloading}
            <span class="inline-flex items-center gap-2">
              <span
                class="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin"
              ></span>
              Lade herunter...
            </span>
          {:else}
            Modell herunterladen (~125 MB)
          {/if}
        </button>
      {/if}
      <button
        onclick={() => {
          showEmbeddingsInfo = false;
        }}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
      >
        {hasEmbeddingModel ? "Schliessen" : "Abbrechen"}
      </button>
    </div>
  {/snippet}
</BottomSheet>

<!-- Supported Formats (show when idle) -->
{#if stage === "idle"}
  <div class="bg-white rounded-3xl shadow-[var(--shadow-card)] p-5">
    <h3 class="text-base font-display font-bold mb-4">Unterstützte Formate</h3>
    <div class="space-y-4">
      <div class="flex items-center gap-3.5">
        <div
          class="w-10 h-10 rounded-full bg-amber-50 flex items-center justify-center shrink-0"
        >
          <span class="text-amber-700 text-xs font-extrabold">CD</span>
        </div>
        <div>
          <p class="text-sm font-bold">Comdirect</p>
          <p class="text-xs text-(--color-text-secondary)">
            Semikolon, ISO-8859-1, dd.MM.yyyy
          </p>
        </div>
      </div>
      <div class="flex items-center gap-3.5">
        <div
          class="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center shrink-0"
        >
          <span class="text-gray-700 text-xs font-extrabold">TR</span>
        </div>
        <div>
          <p class="text-sm font-bold">Trade Republic</p>
          <p class="text-xs text-(--color-text-secondary)">
            Komma, UTF-8, YYYY-MM-DD
          </p>
        </div>
      </div>
      <div class="flex items-center gap-3.5">
        <div
          class="w-10 h-10 rounded-full bg-purple-50 flex items-center justify-center shrink-0"
        >
          <span class="text-purple-700 text-xs font-extrabold">SC</span>
        </div>
        <div>
          <p class="text-sm font-bold">Scalable Capital</p>
          <p class="text-xs text-(--color-text-secondary)">
            Semikolon, UTF-8, flexible Daten
          </p>
        </div>
      </div>
    </div>
    <p
      class="text-center text-[10px] text-(--color-text-secondary) mt-5 uppercase tracking-widest font-bold"
    >
      Local-first &middot; Sicherer Import
    </p>
  </div>
{/if}
