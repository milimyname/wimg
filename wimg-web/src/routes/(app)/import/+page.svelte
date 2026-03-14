<script lang="ts">
  import {
    parseCsv,
    importCsv,
    setCategory,
    getTransactions,
    detectRecurring,
    CATEGORIES,
    type ImportResult,
    type ParseResult,
    type Transaction,
  } from "$lib/wasm";
  import { formatEur, formatDate } from "$lib/format";
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

  // Inline category assignment
  let editingTxn = $state<Transaction | null>(null);
  let showCategorySheet = $state(false);

  // Multi-select
  let selectedTxnIds = $state<Set<string>>(new Set());
  let selectionMode = $state(false);

  let categorizedCount = $derived(
    previewTransactions.filter((t) => t.category !== 0).length,
  );
  let uncategorizedTxns = $derived(
    previewTransactions.filter((t) => t.category === 0),
  );
  let selectedCount = $derived(selectedTxnIds.size);

  let previewSlice = $derived.by(() => {
    if (stage === "preview" && parseResult) {
      const txns = parseResult.transactions;
      return showAllPreview ? txns : txns.slice(0, 3);
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

      showAllPreview = false;
      stage = "imported";
      importing = false;
      accountStore.reload();
      previewTransactions = getTransactions();
      // Auto-detect recurring patterns after import
      detectRecurring();
    } catch (e) {
      importError = e instanceof Error ? e.message : "Import fehlgeschlagen";
      importing = false;
    }
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
      await setCategory(id, catId); // eslint-disable-line no-await-in-loop -- WASM calls must be sequential
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
    previewTransactions = [];
    await processFile(fileQueue[queueIndex]);
  }
</script>

<!-- Header -->
<div class="flex items-center gap-3 mb-6">
  <a
    href="/more"
    class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
    aria-label="Zurück"
  >
    <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
  </a>
  <h2 class="text-2xl font-display font-extrabold text-(--color-text) flex-1">CSV Import</h2>
  {#if fileQueue.length > 1}
    <span class="text-xs font-bold text-(--color-text-secondary) bg-white px-3 py-1.5 rounded-full shadow-sm">
      {queueIndex + 1}/{fileQueue.length}
    </span>
  {/if}
</div>

<!-- Error -->
{#if importError}
  <div class="bg-red-50 rounded-2xl p-4 mb-4 flex gap-3 border border-red-100">
    <svg class="w-5 h-5 text-red-500 shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    <p class="text-sm text-red-700 font-medium">{importError}</p>
  </div>
{/if}

<!-- ═══════════════════ IDLE STAGE ═══════════════════ -->
{#if stage === "idle"}
  <!-- Drop Zone -->
  <div
    class="flex flex-col items-center gap-5 rounded-3xl border-2 border-dashed px-6 py-12 mb-6 transition-all cursor-pointer bg-white"
    style="border-color: {dragging ? 'var(--color-text)' : '#e0dcd6'}; {dragging ? 'background-color: #faf8f5' : ''}"
    role="button"
    tabindex="0"
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
    onclick={() => document.getElementById("file-input")?.click()}
    onkeydown={(e) => e.key === "Enter" && document.getElementById("file-input")?.click()}
  >
    <input id="file-input" type="file" accept=".csv" multiple class="hidden" onchange={handleFileInput} />

    {#if parsing}
      <div class="animate-spin w-10 h-10 border-4 border-(--color-text) border-t-transparent rounded-full"></div>
      <p class="text-sm text-(--color-text-secondary) font-medium">Analysiere...</p>
    {:else}
      <div class="bg-gray-100 p-5 rounded-full">
        {#if dragging}
          <svg class="w-8 h-8 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
        {:else}
          <svg class="w-8 h-8 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
          </svg>
        {/if}
      </div>
      <div class="text-center">
        <p class="text-xl font-display font-extrabold text-(--color-text)">CSV hochladen</p>
        <p class="text-sm text-(--color-text-secondary) mt-1.5 max-w-[240px] font-medium">
          Ziehe deine Bankdatei hierhin oder tippe zum Durchsuchen
        </p>
      </div>
      <button
        class="px-8 py-3.5 rounded-full text-sm font-bold bg-(--color-text) text-white cursor-pointer hover:opacity-90 transition-opacity"
        onclick={(e) => { e.stopPropagation(); document.getElementById("file-input")?.click(); }}
      >
        Datei auswählen
      </button>
    {/if}
  </div>

  <!-- Supported Formats -->
  <div class="bg-white rounded-3xl p-5">
    <h3 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider mb-4">Unterstützte Formate</h3>
    <div class="space-y-3.5">
      <div class="flex items-center gap-3.5">
        <div class="w-10 h-10 rounded-2xl bg-amber-50 flex items-center justify-center shrink-0">
          <span class="text-amber-700 text-xs font-extrabold">CD</span>
        </div>
        <div>
          <p class="text-sm font-bold text-(--color-text)">Comdirect</p>
          <p class="text-xs text-(--color-text-secondary)">Semikolon, ISO-8859-1</p>
        </div>
      </div>
      <div class="flex items-center gap-3.5">
        <div class="w-10 h-10 rounded-2xl bg-gray-100 flex items-center justify-center shrink-0">
          <span class="text-gray-700 text-xs font-extrabold">TR</span>
        </div>
        <div>
          <p class="text-sm font-bold text-(--color-text)">Trade Republic</p>
          <p class="text-xs text-(--color-text-secondary)">Komma, UTF-8</p>
        </div>
      </div>
      <div class="flex items-center gap-3.5">
        <div class="w-10 h-10 rounded-2xl bg-purple-50 flex items-center justify-center shrink-0">
          <span class="text-purple-700 text-xs font-extrabold">SC</span>
        </div>
        <div>
          <p class="text-sm font-bold text-(--color-text)">Scalable Capital</p>
          <p class="text-xs text-(--color-text-secondary)">Semikolon, UTF-8</p>
        </div>
      </div>
    </div>
  </div>
{/if}

<!-- ═══════════════════ PREVIEW STAGE ═══════════════════ -->
{#if stage === "preview" && parseResult}
  <!-- Drop zone (compact in preview) -->
  <div
    class="flex items-center gap-3 rounded-2xl border-2 border-dashed border-gray-200 bg-white px-4 py-3 mb-4 cursor-pointer transition-colors hover:border-gray-300"
    role="button"
    tabindex="0"
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
    onclick={() => document.getElementById("file-input-mini")?.click()}
    onkeydown={(e) => e.key === "Enter" && document.getElementById("file-input-mini")?.click()}
  >
    <input id="file-input-mini" type="file" accept=".csv" multiple class="hidden" onchange={handleFileInput} />
    <svg class="w-5 h-5 text-(--color-text-secondary) shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
    </svg>
    <span class="text-sm text-(--color-text-secondary) font-medium">Andere Datei hochladen</span>
  </div>

  <!-- Format + Account badge -->
  {#if parseResult.format && parseResult.format !== "unknown"}
    {@const acct = accountForFormat(parseResult.format)}
    <div class="flex items-center justify-between gap-4 rounded-2xl bg-emerald-50 p-4 mb-3 border border-emerald-100">
      <div class="flex items-center gap-3 flex-1 min-w-0">
        <svg class="w-5 h-5 text-emerald-600 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <div class="min-w-0">
          <p class="text-sm font-bold text-emerald-800">{formatLabel(parseResult.format)} erkannt</p>
          <p class="text-xs text-emerald-600">{parseResult.total_rows} Zeilen &middot; Konto: {acct.name}</p>
        </div>
      </div>
      <div class="w-10 h-10 bg-white/60 rounded-xl flex items-center justify-center shrink-0">
        <svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
        </svg>
      </div>
    </div>
  {/if}

  <!-- Summary stats -->
  <div class="grid grid-cols-2 gap-3 mb-4">
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <p class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider">Buchungen</p>
      <p class="text-2xl font-display font-black text-(--color-text) mt-1">{parseResult.transactions.length}</p>
    </div>
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <p class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider">Ausgaben</p>
      <p class="text-2xl font-display font-black text-rose-500 mt-1">{formatEur(previewTotals.expenses)}</p>
    </div>
  </div>

  <!-- Preview list -->
  {#if parseResult.transactions.length > 0}
    <div class="flex items-center justify-between mb-3 px-1">
      <h3 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider">
        Vorschau ({previewSlice.length} von {parseResult.transactions.length})
      </h3>
      {#if parseResult.transactions.length > 3}
        <button
          class="text-xs font-bold cursor-pointer text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
          onclick={() => (showAllPreview = !showAllPreview)}
        >
          {showAllPreview ? "Weniger" : "Alle anzeigen"}
        </button>
      {/if}
    </div>
    <div class="flex flex-col gap-2 mb-6">
      {#each previewSlice as txn}
        <div class="flex items-center justify-between p-4 bg-white rounded-2xl border border-gray-100">
          <div class="flex items-center gap-3 min-w-0">
            <div
              class="w-10 h-10 rounded-xl flex items-center justify-center text-base shrink-0"
              style="background-color: {CATEGORIES[txn.category]?.color ?? '#9CA3AF'}15"
            >
              {CATEGORIES[txn.category]?.icon ?? "📦"}
            </div>
            <div class="min-w-0">
              <p class="text-sm font-bold truncate text-(--color-text)">{txn.description}</p>
              <p class="text-xs text-(--color-text-secondary) mt-0.5 font-medium">
                {formatDate(txn.date)} &middot; {CATEGORIES[txn.category]?.name ?? "Sonstiges"}
              </p>
            </div>
          </div>
          <p
            class="text-sm font-extrabold tabular-nums shrink-0 ml-3"
            class:text-rose-500={txn.amount < 0}
            class:text-emerald-600={txn.amount > 0}
          >
            {txn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(txn.amount))}
          </p>
        </div>
      {/each}
    </div>
  {/if}

  <!-- CTA -->
  <div class="flex flex-col gap-3 pb-4">
    <button
      onclick={confirmImport}
      disabled={importing}
      class="w-full py-4 rounded-full text-base font-display font-extrabold bg-(--color-accent) text-(--color-text) cursor-pointer hover:bg-(--color-accent-hover) transition-all active:scale-[0.98] disabled:opacity-50 shadow-[0_8px_20px_rgba(255,233,125,0.3)]"
    >
      {#if importing}
        <span class="flex items-center justify-center gap-2">
          <span class="animate-spin w-4 h-4 border-2 border-t-transparent rounded-full border-(--color-text) inline-block"></span>
          Importiere...
        </span>
      {:else}
        {parseResult.transactions.length} Buchungen importieren
      {/if}
    </button>
    <button
      onclick={cancelPreview}
      disabled={importing}
      class="w-full py-3 rounded-full text-sm font-bold text-(--color-text-secondary) cursor-pointer hover:bg-gray-100 transition-colors disabled:opacity-50"
    >
      Abbrechen
    </button>
    <p class="text-center text-(--color-text-secondary) text-[10px] uppercase tracking-widest font-bold mt-1">
      Local-first &middot; Sicherer Import
    </p>
  </div>
{/if}

<!-- ═══════════════════ IMPORTED STAGE ═══════════════════ -->
{#if stage === "imported" && importResult}
  <!-- Success card -->
  <div class="bg-emerald-50 rounded-2xl p-5 mb-3 border border-emerald-100">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-xl bg-emerald-100 flex items-center justify-center shrink-0">
        <svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <div>
        <p class="text-sm font-bold text-emerald-900">Import abgeschlossen</p>
        <p class="text-xs text-emerald-700 mt-0.5">
          {importResult.imported} Buchungen importiert
          {#if importResult.format && importResult.format !== "unknown"}
            &middot; {formatLabel(importResult.format)}
          {/if}
          {#if importResult.errors > 0}
            &middot; {importResult.errors} Fehler
          {/if}
        </p>
      </div>
    </div>
  </div>

  <!-- Duplicate Warning -->
  {#if importResult.skipped_duplicates > 0}
    <div class="bg-amber-50 rounded-2xl p-5 mb-3 border border-amber-100">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-amber-100 flex items-center justify-center shrink-0">
          <svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <div>
          <p class="text-sm font-bold text-amber-900">Duplikat-Hinweis</p>
          <p class="text-xs text-amber-700 mt-0.5">
            {importResult.skipped_duplicates} Buchungen waren bereits vorhanden und wurden übersprungen.
          </p>
        </div>
      </div>
    </div>
  {/if}

  <!-- Action buttons -->
  <div class="flex gap-3 mb-5">
    {#if fileQueue.length > 1 && queueIndex < fileQueue.length - 1}
      <button
        onclick={loadNextFile}
        class="flex-1 py-3 rounded-2xl text-sm font-bold text-white bg-(--color-text) cursor-pointer hover:opacity-90 transition-opacity"
      >
        Nächste Datei ({queueIndex + 2}/{fileQueue.length})
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
      class="flex-1 py-3 rounded-2xl text-sm font-bold text-(--color-text) bg-white border border-gray-200 cursor-pointer hover:bg-gray-50 transition-colors"
    >
      Weitere Datei importieren
    </button>
  </div>

  <!-- Categorization Progress -->
  {#if previewTransactions.length > 0}
    <div class="mb-4">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider">Kategorisierung</h3>
        <span class="text-xs font-bold text-(--color-text-secondary) bg-white px-2.5 py-1 rounded-full border border-gray-100">
          {categorizedCount}/{previewTransactions.length}
        </span>
      </div>
      <div class="w-full h-2 bg-gray-100 rounded-full overflow-hidden">
        <div
          class="h-full rounded-full transition-all duration-500"
          style="width: {(categorizedCount / previewTransactions.length) * 100}%; background-color: {categorizedCount === previewTransactions.length ? '#10b981' : '#34d399'}"
        ></div>
      </div>
    </div>

    {#if uncategorizedTxns.length > 0}
      <p class="text-xs text-(--color-text-secondary) font-medium text-center mb-4">
        Tippe auf eine Buchung, um eine Kategorie zuzuweisen.
      </p>

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

      <!-- Uncategorized transactions -->
      <div class="flex flex-col gap-2 mb-4">
        {#each uncategorizedTxns as txn}
          <button
            class="flex items-center justify-between p-4 bg-white rounded-2xl border border-gray-100 cursor-pointer hover:border-gray-200 transition-all text-left w-full"
            style={selectionMode && selectedTxnIds.has(txn.id) ? "border-color: #10b981; box-shadow: 0 0 0 1px #10b981" : ""}
            onclick={() => {
              if (selectionMode) {
                toggleSelection(txn.id);
              } else {
                editingTxn = txn;
                showCategorySheet = true;
              }
            }}
          >
            <div class="flex items-center gap-3 min-w-0 flex-1">
              {#if selectionMode}
                <div
                  class="w-6 h-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors"
                  class:border-emerald-500={selectedTxnIds.has(txn.id)}
                  class:bg-emerald-500={selectedTxnIds.has(txn.id)}
                  class:border-gray-300={!selectedTxnIds.has(txn.id)}
                >
                  {#if selectedTxnIds.has(txn.id)}
                    <svg class="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" />
                    </svg>
                  {/if}
                </div>
              {/if}
              <div class="w-10 h-10 rounded-xl flex items-center justify-center text-base shrink-0 bg-gray-50">
                📦
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-bold truncate text-(--color-text)">{txn.description}</p>
                <p class="text-xs text-(--color-text-secondary) mt-0.5 font-medium">{formatDate(txn.date)}</p>
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0 ml-2">
              <p
                class="text-sm font-extrabold tabular-nums"
                class:text-rose-500={txn.amount < 0}
                class:text-emerald-600={txn.amount > 0}
              >
                {txn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(txn.amount))}
              </p>
              {#if !selectionMode}
                <svg class="w-4 h-4 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5l7 7-7 7" />
                </svg>
              {/if}
            </div>
          </button>
        {/each}
      </div>

      <!-- Floating action bar for batch selection -->
      {#if selectedCount > 0}
        <div class="fixed bottom-20 left-1/2 -translate-x-1/2 z-30 flex items-center gap-3 bg-white rounded-2xl shadow-lg border border-gray-100 px-4 py-3 max-w-[calc(100%-2rem)]">
          <span class="text-sm font-bold text-(--color-text) whitespace-nowrap">{selectedCount} ausgewählt</span>
          <button
            onclick={() => { editingTxn = null; showCategorySheet = true; }}
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
      <div class="bg-emerald-50 rounded-2xl p-5 mb-5 flex items-center gap-3 border border-emerald-100">
        <span class="text-2xl">🎉</span>
        <div>
          <p class="text-sm font-bold text-emerald-900">Alle Buchungen kategorisiert</p>
          <p class="text-xs text-emerald-700 mt-0.5">Zukünftige Importe profitieren von diesen Zuordnungen.</p>
        </div>
      </div>
    {/if}
  {/if}
{/if}

<!-- ═══════════════════ CATEGORY SHEET ═══════════════════ -->
{#if showCategorySheet}
  <BottomSheet
    open={showCategorySheet}
    onclose={() => { showCategorySheet = false; editingTxn = null; }}
    snaps={[0.55]}
  >
    {#snippet children({ handle, content })}
      <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
        <div class="w-10 h-1 bg-gray-200 rounded-full"></div>
      </div>

      <div class="px-6" {@attach content}>
        <!-- Header -->
        <div class="flex flex-col items-center mb-6 mt-2">
          {#if selectionMode && selectedCount > 0}
            <div class="w-14 h-14 rounded-2xl bg-emerald-50 flex items-center justify-center mb-3">
              <span class="text-xl font-extrabold text-emerald-600">{selectedCount}</span>
            </div>
            <h2 class="text-lg font-display font-extrabold text-center">{selectedCount} Buchungen</h2>
            <p class="text-sm text-(--color-text-secondary) mt-1">Kategorie für alle zuweisen</p>
          {:else if editingTxn}
            <div class="w-14 h-14 rounded-2xl bg-gray-50 flex items-center justify-center mb-3 text-2xl">📦</div>
            <h2 class="text-base font-display font-extrabold text-center leading-tight">{editingTxn.description}</h2>
            <p
              class="text-sm font-display font-extrabold mt-1"
              class:text-rose-500={editingTxn.amount < 0}
              class:text-emerald-600={editingTxn.amount > 0}
            >
              {editingTxn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(editingTxn.amount))}
            </p>
          {/if}
        </div>

        <!-- Category pills -->
        <div class="mb-4">
          <span class="text-(--color-text-secondary) font-bold text-xs uppercase tracking-wider">Kategorie wählen</span>
          <div class="flex flex-wrap gap-2 mt-3">
            {#each Object.entries(CATEGORIES) as [catId, cat]}
              <button
                class="flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold transition-all cursor-pointer border border-transparent hover:border-gray-200"
                style="background-color: {cat.color}10"
                onclick={() => {
                  if (selectionMode && selectedCount > 0) {
                    handleBatchCategory(Number(catId));
                  } else {
                    handleInlineCategory(Number(catId));
                  }
                }}
              >
                <span class="w-2 h-2 rounded-full shrink-0" style="background-color: {cat.color}"></span>
                {cat.name}
              </button>
            {/each}
          </div>
        </div>
      </div>
    {/snippet}
  </BottomSheet>
{/if}
