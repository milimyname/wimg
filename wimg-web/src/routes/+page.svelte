<script lang="ts">
  import { onMount } from "svelte";
  import {
    init,
    importCsv,
    getTransactions,
    setCategory,
    CATEGORIES,
    type Transaction,
    type ImportResult,
  } from "$lib/wasm";

  let loading = $state(true);
  let error = $state<string | null>(null);
  let transactions = $state<Transaction[]>([]);
  let importResult = $state<ImportResult | null>(null);
  let dragging = $state(false);
  let editingId = $state<string | null>(null);

  // Group transactions by date
  let grouped = $derived.by(() => {
    const groups = new Map<string, Transaction[]>();
    for (const txn of transactions) {
      const existing = groups.get(txn.date);
      if (existing) {
        existing.push(txn);
      } else {
        groups.set(txn.date, [txn]);
      }
    }
    return groups;
  });

  onMount(async () => {
    try {
      await init();
      transactions = getTransactions();
    } catch (e) {
      error = e instanceof Error ? e.message : "Failed to initialize";
    } finally {
      loading = false;
    }
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

    const file = e.dataTransfer?.files[0];
    if (!file) return;
    await processFile(file);
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
      error = null;
      const buffer = await file.arrayBuffer();
      importResult = await importCsv(buffer);
      transactions = getTransactions();
    } catch (e) {
      error = e instanceof Error ? e.message : "Import failed";
    }
  }

  async function handleCategoryChange(txnId: string, category: number) {
    try {
      // Update UI optimistically
      transactions = transactions.map((t) =>
        t.id === txnId ? { ...t, category } : t,
      );
      editingId = null;
      await setCategory(txnId, category);
    } catch (e) {
      error = e instanceof Error ? e.message : "Failed to update category";
    }
  }

  function formatAmount(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
    }).format(amount);
  }

  function formatDate(dateStr: string): string {
    const [y, m, d] = dateStr.split("-");
    return `${d}.${m}.${y}`;
  }

  function formatDateHeading(dateStr: string): string {
    const date = new Date(dateStr);
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    if (date.toDateString() === today.toDateString()) return "Today";
    if (date.toDateString() === yesterday.toDateString()) return "Yesterday";

    return date.toLocaleDateString("de-DE", {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
    });
  }
</script>

{#if loading}
  <div class="flex items-center justify-center py-20">
    <div
      class="animate-spin w-8 h-8 border-4 border-(--color-primary) border-t-transparent rounded-full"
    ></div>
  </div>
{:else if error}
  <div class="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700">
    {error}
  </div>
{:else}
  <!-- Import zone -->
  <div
    class="border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition-all mb-6"
    style="border-color: {dragging
      ? 'var(--color-primary)'
      : '#d1d5db'}; background-color: {dragging
      ? 'var(--color-primary-light)'
      : 'transparent'}"
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
    <div class="text-3xl mb-2 text-(--color-text-secondary)">
      {#if dragging}
        <svg
          class="w-10 h-10 mx-auto"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          ><path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 4v16m8-8H4"
          /></svg
        >
      {:else}
        <svg
          class="w-10 h-10 mx-auto"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          ><path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
          /></svg
        >
      {/if}
    </div>
    <p class="text-(--color-text-secondary)">
      Drop a Comdirect CSV here, or click to browse
    </p>
  </div>

  <!-- Import result -->
  {#if importResult}
    <div class="bg-green-50 border border-green-200 rounded-xl p-4 mb-6">
      <p class="font-medium text-green-800">Import complete</p>
      <div class="text-sm text-green-700 mt-1">
        {importResult.imported} imported,
        {importResult.skipped_duplicates} duplicates skipped
        {#if importResult.errors > 0}
          , {importResult.errors} errors
        {/if}
      </div>
    </div>
  {/if}

  <!-- Transactions list -->
  {#if transactions.length === 0}
    <div class="text-center py-12 text-(--color-text-secondary)">
      <p class="text-lg">No transactions yet</p>
      <p class="text-sm mt-1">Import a Comdirect CSV to get started</p>
    </div>
  {:else}
    {#each [...grouped.entries()] as [date, txns]}
      <div class="mb-6">
        <h2
          class="text-sm font-semibold text-(--color-text-secondary) mb-2 px-1"
        >
          {formatDateHeading(date)}
        </h2>
        <div
          class="bg-white rounded-xl shadow-sm border border-(--color-border) divide-y divide-(--color-border)"
        >
          {#each txns as txn}
            <div class="flex items-center gap-3 p-4">
              <!-- Category badge -->
              <button
                class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-medium shrink-0 cursor-pointer transition-transform hover:scale-110"
                style="background-color: {CATEGORIES[txn.category]?.color ??
                  '#dfe6e9'}20; color: {CATEGORIES[txn.category]?.color ??
                  '#666'}"
                onclick={() =>
                  (editingId = editingId === txn.id ? null : txn.id)}
                title="Change category"
              >
                {(CATEGORIES[txn.category]?.name ?? "?").slice(0, 2)}
              </button>

              <!-- Description -->
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate">{txn.description}</p>
                <p class="text-xs text-(--color-text-secondary)">
                  {formatDate(txn.date)}
                </p>
              </div>

              <!-- Amount -->
              <span
                class="text-sm font-semibold tabular-nums"
                class:text-green-600={txn.amount > 0}
                class:text-red-600={txn.amount < 0}
              >
                {formatAmount(txn.amount)}
              </span>
            </div>

            <!-- Category selector (expandable) -->
            {#if editingId === txn.id}
              <div class="px-4 py-3 bg-gray-50 flex flex-wrap gap-2">
                {#each Object.entries(CATEGORIES) as [catId, cat]}
                  <button
                    class="px-3 py-1 rounded-full text-xs font-medium transition-all cursor-pointer"
                    class:ring-2={txn.category === Number(catId)}
                    class:ring-offset-1={txn.category === Number(catId)}
                    style="background-color: {cat.color}20; color: {cat.color}; --tw-ring-color: {cat.color}"
                    onclick={() => handleCategoryChange(txn.id, Number(catId))}
                  >
                    {cat.name}
                  </button>
                {/each}
              </div>
            {/if}
          {/each}
        </div>
      </div>
    {/each}
  {/if}
{/if}
