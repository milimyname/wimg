<script lang="ts">
  import {
    importCsv,
    autoCategorize,
    getTransactions,
    CATEGORIES,
    type ImportResult,
    type Transaction,
  } from "$lib/wasm";
  import {
    categorizeWithClaude,
    getApiKey,
    setApiKey,
    removeApiKey,
  } from "$lib/claude";

  const CATEGORY_ICONS: Record<number, string> = {
    0: "?",
    1: "🛒",
    2: "🍽️",
    3: "🚆",
    4: "🏠",
    5: "⚡",
    6: "🎬",
    7: "🛍️",
    8: "💊",
    9: "🛡️",
    10: "💰",
    11: "🔄",
    12: "💵",
    13: "📱",
    14: "✈️",
    15: "🎓",
    255: "📦",
  };

  let dragging = $state(false);
  let importing = $state(false);
  let importError = $state<string | null>(null);
  let importResult = $state<ImportResult | null>(null);

  // Preview of recently imported transactions
  let previewTransactions = $state<Transaction[]>([]);
  let showAllPreview = $state(false);

  // Auto-categorize
  let recategorizeCount = $state<number | null>(null);

  // Claude API state
  let apiKey = $state(getApiKey() ?? "");
  let hasKey = $state(!!getApiKey());
  let showKeyInput = $state(false);
  let claudeLoading = $state(false);
  let claudeResult = $state<{
    categorized: number;
    errors: string[];
  } | null>(null);

  let previewSlice = $derived(
    showAllPreview ? previewTransactions : previewTransactions.slice(0, 3),
  );

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
    const file = e.dataTransfer?.files[0];
    if (file) await processFile(file);
  }

  async function handleFileInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    await processFile(file);
    input.value = "";
  }

  async function processFile(file: File) {
    try {
      importError = null;
      importResult = null;
      recategorizeCount = null;
      claudeResult = null;
      importing = true;
      const buffer = await file.arrayBuffer();
      importResult = await importCsv(buffer);

      // Load recently added transactions for preview
      const allTxns = getTransactions();
      previewTransactions = allTxns.slice(0, 20);
      showAllPreview = false;
    } catch (e) {
      importError = e instanceof Error ? e.message : "Import fehlgeschlagen";
    } finally {
      importing = false;
    }
  }

  function handleAutoCategorize() {
    const count = autoCategorize();
    recategorizeCount = count;
    // Refresh preview
    previewTransactions = getTransactions().slice(0, 20);
  }

  function handleSaveKey() {
    const trimmed = apiKey.trim();
    if (trimmed) {
      setApiKey(trimmed);
      hasKey = true;
      showKeyInput = false;
    }
  }

  function handleRemoveKey() {
    removeApiKey();
    apiKey = "";
    hasKey = false;
    showKeyInput = false;
  }

  async function handleClaudeCategorize() {
    claudeLoading = true;
    claudeResult = null;
    try {
      const transactions = getTransactions();
      claudeResult = await categorizeWithClaude(transactions);
      // Refresh preview
      previewTransactions = getTransactions().slice(0, 20);
    } catch (e) {
      claudeResult = {
        categorized: 0,
        errors: [e instanceof Error ? e.message : "Unbekannter Fehler"],
      };
    } finally {
      claudeLoading = false;
    }
  }

  function formatEur(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
    }).format(amount);
  }

  function formatDate(dateStr: string): string {
    const d = new Date(dateStr + "T00:00:00");
    return d.toLocaleDateString("de-DE", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  }

  function formatLabel(format: string): string {
    const map: Record<string, string> = {
      comdirect: "Comdirect",
      trade_republic: "Trade Republic",
      scalable: "Scalable Capital",
    };
    return map[format] ?? format;
  }
</script>

<h2 class="text-lg font-bold text-center mb-4">CSV Import</h2>

<!-- Drop Zone -->
<div
  class="flex flex-col items-center gap-5 rounded-xl border-2 border-dashed px-6 py-10 mb-4 transition-all cursor-pointer bg-white"
  style="border-color: {dragging
    ? 'var(--color-primary)'
    : 'rgba(var(--color-primary-rgb, 67, 97, 238), 0.25)'}"
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
    class="hidden"
    onchange={handleFileInput}
  />

  {#if importing}
    <div
      class="animate-spin w-10 h-10 border-4 border-t-transparent rounded-full"
      style="border-color: var(--color-primary); border-top-color: transparent"
    ></div>
    <p class="text-sm text-gray-500">Importiere...</p>
  {:else}
    <div
      class="w-16 h-16 rounded-full flex items-center justify-center"
      style="background-color: var(--color-primary-light, #e8e0ff)"
    >
      {#if dragging}
        <svg
          class="w-8 h-8"
          style="color: var(--color-primary)"
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
          class="w-8 h-8"
          style="color: var(--color-primary)"
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
      <p class="text-lg font-bold">CSV-Datei hochladen</p>
      <p class="text-sm text-gray-400 mt-1 max-w-[240px]">
        Ziehe deine Bankdatei hierhin oder tippe zum Durchsuchen
      </p>
    </div>
    <button
      class="px-6 py-2.5 rounded-full text-sm font-bold text-white shadow-md cursor-pointer hover:opacity-90 transition-opacity"
      style="background-color: var(--color-primary)"
      onclick={(e) => {
        e.stopPropagation();
        document.getElementById("file-input")?.click();
      }}
    >
      Datei auswählen
    </button>
  {/if}
</div>

<!-- Error -->
{#if importError}
  <div
    class="bg-red-50 border border-red-200 rounded-xl p-4 mb-4 text-red-700 text-sm"
  >
    {importError}
  </div>
{/if}

<!-- Post-Import Results -->
{#if importResult}
  <!-- Detected Format Card -->
  {#if importResult.format && importResult.format !== "unknown"}
    <div
      class="flex items-center justify-between gap-4 rounded-xl bg-white p-4 shadow-sm border border-gray-100 mb-3"
    >
      <div class="flex flex-col gap-1 flex-1">
        <div class="flex items-center gap-2">
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
              d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <p class="text-base font-bold">
            {formatLabel(importResult.format)} CSV erkannt
          </p>
        </div>
        <p class="text-xs text-gray-400 pl-7">
          Format automatisch erkannt und verarbeitet
        </p>
      </div>
      <div
        class="w-14 h-14 rounded-lg flex items-center justify-center"
        style="background-color: var(--color-primary-light, #f0edff)"
      >
        <svg
          class="w-7 h-7 opacity-40"
          style="color: var(--color-primary)"
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

  <!-- Import Summary -->
  <div
    class="bg-emerald-50 border border-emerald-100 rounded-xl p-4 mb-3 flex gap-3"
  >
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
        {#if importResult.categorized > 0}
          &middot; {importResult.categorized} auto-kategorisiert
        {/if}
        {#if importResult.errors > 0}
          &middot; {importResult.errors} Fehler
        {/if}
      </p>
    </div>
  </div>

  <!-- Duplicate Warning -->
  {#if importResult.skipped_duplicates > 0}
    <div
      class="bg-amber-50 border border-amber-100 rounded-xl p-4 mb-3 flex gap-3"
    >
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

  <!-- Transaction Preview -->
  {#if previewTransactions.length > 0}
    <div class="flex items-center justify-between mb-2 mt-5">
      <h3 class="text-base font-bold">
        Vorschau ({previewTransactions.length} Buchungen)
      </h3>
      {#if previewTransactions.length > 3}
        <button
          class="text-xs font-semibold cursor-pointer"
          style="color: var(--color-primary)"
          onclick={() => (showAllPreview = !showAllPreview)}
        >
          {showAllPreview ? "Weniger" : "Alle anzeigen"}
        </button>
      {/if}
    </div>
    <div class="flex flex-col gap-2 mb-5">
      {#each previewSlice as txn}
        <div
          class="flex items-center justify-between p-4 bg-white rounded-xl border border-gray-50 shadow-sm"
        >
          <div class="flex items-center gap-3">
            <div
              class="w-10 h-10 rounded-full flex items-center justify-center text-lg"
              style="background-color: {CATEGORIES[txn.category]?.color ??
                '#dfe6e9'}15"
            >
              {CATEGORY_ICONS[txn.category] ?? "📦"}
            </div>
            <div class="min-w-0">
              <p class="text-sm font-bold truncate max-w-[180px]">
                {txn.description}
              </p>
              <p class="text-xs text-gray-400">
                {formatDate(txn.date)} &middot; {CATEGORIES[txn.category]
                  ?.name ?? "Sonstiges"}
              </p>
            </div>
          </div>
          <p
            class="text-sm font-bold tabular-nums shrink-0"
            class:text-rose-500={txn.amount < 0}
            class:text-emerald-500={txn.amount > 0}
          >
            {txn.amount < 0 ? "-" : "+"}{formatEur(Math.abs(txn.amount))}
          </p>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Categorization Section -->
  <div class="mb-4">
    <h3 class="text-base font-bold mb-3">Kategorisierung</h3>

    <!-- Auto-Categorize (Rules) -->
    <div class="bg-white rounded-xl border border-gray-100 p-4 mb-3">
      <div class="flex items-center gap-3">
        <div
          class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
          style="background-color: var(--color-primary-light, #f0edff)"
        >
          <svg
            class="w-5 h-5"
            style="color: var(--color-primary)"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
        </div>
        <div class="flex-1">
          <p class="text-sm font-bold">Regel-Engine</p>
          <p class="text-xs text-gray-400">
            Keyword-Regeln auf alle unkategorisierten Buchungen anwenden
          </p>
        </div>
        <button
          onclick={handleAutoCategorize}
          class="px-4 py-2 rounded-lg text-xs font-bold text-white cursor-pointer hover:opacity-90 transition-opacity"
          style="background-color: var(--color-primary)"
        >
          Starten
        </button>
      </div>
      {#if recategorizeCount !== null}
        <p class="text-xs text-emerald-600 mt-2 pl-13">
          {recategorizeCount} Buchungen kategorisiert
        </p>
      {/if}
    </div>

    <!-- Claude AI Categorization -->
    <div class="bg-white rounded-xl border border-gray-100 p-4">
      <div class="flex items-center gap-3">
        <div
          class="w-10 h-10 rounded-full bg-purple-50 flex items-center justify-center shrink-0"
        >
          <svg
            class="w-5 h-5 text-purple-600"
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
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <p class="text-sm font-bold">Claude AI</p>
            {#if hasKey}
              <span
                class="text-[10px] font-bold text-emerald-600 bg-emerald-50 px-1.5 py-0.5 rounded-full"
                >Aktiv</span
              >
            {/if}
          </div>
          <p class="text-xs text-gray-400">
            KI-gestützte Kategorisierung für verbleibende Buchungen
          </p>
        </div>
      </div>

      <!-- API Key Input -->
      {#if !hasKey || showKeyInput}
        <div class="mt-3 pl-13">
          <div class="flex gap-2">
            <input
              type="password"
              bind:value={apiKey}
              placeholder="sk-ant-..."
              class="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-xs"
            />
            <button
              onclick={handleSaveKey}
              disabled={!apiKey.trim()}
              class="px-3 py-2 rounded-lg text-xs font-bold text-white cursor-pointer hover:opacity-90 transition-opacity disabled:opacity-50"
              style="background-color: var(--color-primary)"
            >
              Speichern
            </button>
          </div>
          <p class="text-[10px] text-gray-400 mt-1.5">
            Nur lokal gespeichert. Wird nur an die Anthropic API gesendet.
          </p>
        </div>
      {/if}

      <!-- Actions -->
      {#if hasKey}
        <div class="flex items-center gap-2 mt-3 pl-13">
          <button
            onclick={handleClaudeCategorize}
            disabled={claudeLoading}
            class="px-4 py-2 rounded-lg text-xs font-bold text-white cursor-pointer hover:opacity-90 transition-opacity disabled:opacity-50 bg-purple-600"
          >
            {claudeLoading ? "Kategorisiere..." : "Mit Claude kategorisieren"}
          </button>
          <button
            onclick={() => (showKeyInput = !showKeyInput)}
            class="text-xs text-gray-400 px-2 py-2 hover:bg-gray-50 rounded-lg cursor-pointer transition-colors"
          >
            {showKeyInput ? "Abbrechen" : "Key ändern"}
          </button>
          {#if !showKeyInput}
            <button
              onclick={handleRemoveKey}
              class="text-xs text-red-400 px-2 py-2 hover:bg-red-50 rounded-lg cursor-pointer transition-colors"
            >
              Entfernen
            </button>
          {/if}
        </div>
      {/if}

      <!-- Claude Result -->
      {#if claudeResult}
        <div class="mt-2 pl-13">
          {#if claudeResult.categorized > 0}
            <p class="text-xs text-emerald-600">
              {claudeResult.categorized} Buchungen von Claude kategorisiert
            </p>
          {:else if claudeResult.errors.length === 0}
            <p class="text-xs text-gray-400">
              Keine unkategorisierten Buchungen gefunden
            </p>
          {/if}
          {#each claudeResult.errors as err}
            <p class="text-xs text-red-500 mt-1">{err}</p>
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

<!-- Supported Formats (show when no import yet) -->
{#if !importResult}
  <div class="bg-white rounded-xl border border-gray-100 p-4 shadow-sm">
    <h3 class="text-sm font-bold mb-3">Unterstützte Formate</h3>
    <div class="space-y-3">
      <div class="flex items-center gap-3">
        <div
          class="w-9 h-9 rounded-lg bg-blue-50 flex items-center justify-center shrink-0"
        >
          <span class="text-blue-600 text-xs font-bold">CD</span>
        </div>
        <div>
          <p class="text-sm font-semibold">Comdirect</p>
          <p class="text-xs text-gray-400">
            Semikolon, ISO-8859-1, dd.MM.yyyy
          </p>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <div
          class="w-9 h-9 rounded-lg bg-green-50 flex items-center justify-center shrink-0"
        >
          <span class="text-green-600 text-xs font-bold">TR</span>
        </div>
        <div>
          <p class="text-sm font-semibold">Trade Republic</p>
          <p class="text-xs text-gray-400">Komma, UTF-8, YYYY-MM-DD</p>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <div
          class="w-9 h-9 rounded-lg bg-purple-50 flex items-center justify-center shrink-0"
        >
          <span class="text-purple-600 text-xs font-bold">SC</span>
        </div>
        <div>
          <p class="text-sm font-semibold">Scalable Capital</p>
          <p class="text-xs text-gray-400">Semikolon, UTF-8, flexible Daten</p>
        </div>
      </div>
    </div>
    <p
      class="text-center text-[10px] text-gray-400 mt-4 uppercase tracking-widest font-medium"
    >
      Local-first &middot; Sicherer Import
    </p>
  </div>
{/if}
