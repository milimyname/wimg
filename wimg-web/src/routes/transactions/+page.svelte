<script lang="ts">
  import {
    getTransactionsFiltered,
    setCategory,
    setExcluded,
    undo,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import { formatAmountSigned, formatDateHeading } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { toastStore } from "$lib/toast.svelte";
  import BottomSheet from "../../components/BottomSheet.svelte";

  type Filter = "all" | "expenses" | "income";

  let refreshKey = $state(0);
  let transactions = $derived.by(() => {
    void refreshKey;
    return getTransactionsFiltered(accountStore.selected);
  });
  let filter = $state<Filter>("all");
  let selectedTxn = $state<Transaction | null>(null);
  let originalTxn = $state<Transaction | null>(null);
  let showSheet = $state(false);
  let searchQuery = $state("");
  let showSearch = $state(false);
  let showExcluded = $state(false);

  let filtered = $derived.by(() => {
    let list = transactions;
    if (!showExcluded) list = list.filter((t) => !t.excluded);
    if (filter === "expenses") list = list.filter((t) => t.amount < 0);
    if (filter === "income") list = list.filter((t) => t.amount > 0);
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter((t) => t.description.toLowerCase().includes(q));
    }
    return list;
  });

  let grouped = $derived.by(() => {
    const groups = new Map<string, Transaction[]>();
    for (const txn of filtered) {
      const existing = groups.get(txn.date);
      if (existing) {
        existing.push(txn);
      } else {
        groups.set(txn.date, [txn]);
      }
    }
    return groups;
  });

  function openDetail(txn: Transaction) {
    originalTxn = { ...txn };
    selectedTxn = { ...txn };
    showSheet = true;
  }

  function dismissSheet() {
    showSheet = false;
  }

  function onSheetClosed() {
    showSheet = false;
    selectedTxn = null;
    originalTxn = null;
  }

  function handleCategoryChange(category: number) {
    if (!selectedTxn) return;
    selectedTxn = { ...selectedTxn, category };
  }

  function handleExcludeToggle() {
    if (!selectedTxn) return;
    selectedTxn = { ...selectedTxn, excluded: selectedTxn.excluded ? 0 : 1 };
  }

  async function handleSubmit() {
    if (!selectedTxn || !originalTxn) return;
    const id = selectedTxn.id;
    let changed = false;

    if (selectedTxn.category !== originalTxn.category) {
      await setCategory(id, selectedTxn.category);
      changed = true;
    }

    if (selectedTxn.excluded !== originalTxn.excluded) {
      await setExcluded(id, !!selectedTxn.excluded);
      changed = true;
    }

    if (changed) {
      refreshKey++;
      toastStore.show("Änderungen gespeichert", async () => {
        await undo();
        refreshKey++;
      });
    }

    dismissSheet();
  }

</script>

<!-- Search bar (collapsible) -->
{#if showSearch}
  <div class="mb-4 flex gap-2">
    <input
      type="text"
      bind:value={searchQuery}
      placeholder="Transaktion suchen..."
      class="flex-1 bg-white border border-(--color-border) rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-(--color-primary)/30"
    />
    <button
      onclick={() => {
        showSearch = false;
        searchQuery = "";
      }}
      class="text-sm text-(--color-text-secondary) px-3 cursor-pointer"
    >
      Abbrechen
    </button>
  </div>
{:else}
  <div class="flex items-center justify-between mb-4">
    <button
      onclick={() => (showSearch = true)}
      class="w-9 h-9 flex items-center justify-center rounded-full hover:bg-gray-100 cursor-pointer transition-colors"
      aria-label="Suchen"
    >
      <svg
        class="w-5 h-5 text-(--color-text-secondary)"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
        />
      </svg>
    </button>
    <h2 class="text-lg font-bold">Transaktionen</h2>
    <div class="w-9 h-9"></div>
  </div>
{/if}

<!-- Segmented Control -->
<div class="mb-5">
  <div class="flex bg-gray-100 p-1 rounded-xl">
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "all"}
      class:shadow-sm={filter === "all"}
      class:text-gray-500={filter !== "all"}
      class:font-medium={filter !== "all"}
      onclick={() => (filter = "all")}
    >
      Alle
    </button>
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "expenses"}
      class:shadow-sm={filter === "expenses"}
      class:text-gray-500={filter !== "expenses"}
      class:font-medium={filter !== "expenses"}
      onclick={() => (filter = "expenses")}
    >
      Ausgaben
    </button>
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "income"}
      class:shadow-sm={filter === "income"}
      class:text-gray-500={filter !== "income"}
      class:font-medium={filter !== "income"}
      onclick={() => (filter = "income")}
    >
      Einnahmen
    </button>
  </div>
</div>

<!-- Show excluded toggle -->
<div class="flex items-center justify-end mb-4 -mt-2">
  <label class="flex items-center gap-2 text-xs text-gray-500 cursor-pointer">
    <input type="checkbox" bind:checked={showExcluded} class="rounded" />
    Ausgeblendete anzeigen
  </label>
</div>

<!-- Transaction List -->
{#if transactions.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-3xl mb-3">📋</p>
    <p class="font-medium">Keine Transaktionen</p>
    <p class="text-sm mt-1">
      <a href="/import" class="text-(--color-primary) font-medium"
        >CSV importieren</a
      > um zu starten
    </p>
  </div>
{:else if filtered.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-3xl mb-3">🔍</p>
    <p class="font-medium">Keine Ergebnisse</p>
    <p class="text-sm mt-1">Versuche einen anderen Filter</p>
  </div>
{:else}
  {#each [...grouped.entries()] as [date, txns]}
    <h3
      class="text-xs font-bold text-gray-400 mt-6 mb-3 uppercase tracking-wider"
    >
      {formatDateHeading(date)}
    </h3>

    {#each txns as txn}
      <button
        class="bg-white w-full p-4 rounded-xl shadow-sm border border-gray-100 flex items-center justify-between mb-3 cursor-pointer hover:shadow-md transition-shadow text-left"
        class:opacity-40={!!txn.excluded}
        onclick={() => openDetail(txn)}
      >
        <div class="flex items-center gap-3">
          <div
            class="w-10 h-10 rounded-full flex items-center justify-center text-lg shrink-0"
            style="background-color: {CATEGORIES[txn.category]?.color ?? '#dfe6e9'}15"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <div>
            <p class="font-bold text-sm leading-tight">{txn.description}</p>
            <div class="flex items-center gap-1.5 mt-0.5">
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style="background-color: {CATEGORIES[txn.category]?.color ??
                  '#dfe6e9'}"
              ></span>
              <p class="text-xs text-gray-500 font-medium">
                {CATEGORIES[txn.category]?.name ?? "Uncategorized"}
              </p>
            </div>
          </div>
        </div>
        <p
          class="font-bold text-sm tabular-nums shrink-0 ml-3"
          class:text-emerald-500={txn.amount > 0}
        >
          {formatAmountSigned(txn.amount)}
        </p>
      </button>
    {/each}
  {/each}
{/if}

<!-- Bottom Sheet -->
{#if selectedTxn}
  {@const txn = selectedTxn}
  <BottomSheet open={showSheet} onclose={onSheetClosed}>
    {#snippet children({ handle, content })}
      <!-- Handle -->
      <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
        <div class="w-10 h-1 bg-gray-300 rounded-full"></div>
      </div>

      <!-- Content -->
      <div class="flex-1 min-h-0 px-6 pb-10" {@attach content}>
        <!-- Icon + Name -->
        <div class="flex flex-col items-center mb-6 mt-2">
          <div
            class="w-14 h-14 rounded-2xl flex items-center justify-center mb-2.5 text-2xl border border-gray-100"
            style="background-color: {CATEGORIES[txn.category]?.color ??
              '#dfe6e9'}10"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <h2 class="text-lg font-bold text-center leading-tight">
            {txn.description}
          </h2>
          <p class="text-gray-400 text-xs mt-1">
            {new Date(txn.date + "T00:00:00").toLocaleDateString("de-DE", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}
          </p>
        </div>

        <!-- Amount -->
        <div
          class="flex justify-between items-center py-3.5 border-b border-gray-100"
        >
          <span class="text-gray-500 font-medium text-sm">Betrag</span>
          <span
            class="text-lg font-bold"
            class:text-emerald-500={txn.amount > 0}
          >
            {formatAmountSigned(txn.amount)}
          </span>
        </div>

        <!-- Category Selector -->
        <div class="mt-4 mb-5">
          <span
            class="text-gray-500 font-medium text-xs uppercase tracking-wide"
            >Kategorie</span
          >
          <div class="flex flex-wrap gap-2 mt-2.5">
            {#each Object.entries(CATEGORIES) as [catId, cat]}
              <button
                class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold transition-all cursor-pointer border"
                style="background-color: {Number(catId) === txn.category
                  ? cat.color + '20'
                  : '#f9fafb'}; border-color: {Number(catId) === txn.category
                  ? cat.color + '40'
                  : 'transparent'}"
                onclick={() => handleCategoryChange(Number(catId))}
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

        <!-- Exclude Toggle -->
        <button
          class="w-full py-3 rounded-xl cursor-pointer font-semibold text-sm transition-all border mb-3"
          class:bg-gray-100={!txn.excluded}
          class:text-gray-700={!txn.excluded}
          class:border-gray-200={!txn.excluded}
          class:bg-amber-50={!!txn.excluded}
          class:text-amber-700={!!txn.excluded}
          class:border-amber-200={!!txn.excluded}
          onclick={handleExcludeToggle}
        >
          {txn.excluded
            ? "Transaktion einblenden"
            : "Transaktion ausblenden"}
        </button>

        <!-- Done Button -->
        <button
          class="w-full text-white font-bold py-3.5 rounded-xl cursor-pointer hover:opacity-90 transition-opacity"
          style="background-color: var(--color-primary)"
          onclick={handleSubmit}
        >
          Fertig
        </button>
      </div>
    {/snippet}
  </BottomSheet>
{/if}
