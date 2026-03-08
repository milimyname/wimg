<script lang="ts">
  import { onMount, onDestroy } from "svelte";
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
  import BottomSheet from "../../../components/BottomSheet.svelte";

  type Filter = "all" | "expenses" | "income";

  let refreshKey = $state(0);

  function onSyncReceived() {
    refreshKey++;
  }

  onMount(() => {
    window.addEventListener("wimg:sync-received", onSyncReceived);
  });

  onDestroy(() => {
    window.removeEventListener("wimg:sync-received", onSyncReceived);
  });
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
      class="flex-1 bg-white rounded-2xl px-5 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent) shadow-[var(--shadow-card)]"
    />
    <button
      onclick={() => {
        showSearch = false;
        searchQuery = "";
      }}
      class="text-sm text-(--color-text-secondary) px-3 font-bold cursor-pointer"
    >
      Abbrechen
    </button>
  </div>
{:else}
  <div class="flex items-center justify-between mb-4">
    <button
      onclick={() => (showSearch = true)}
      class="w-10 h-10 flex items-center justify-center rounded-full bg-white shadow-[var(--shadow-card)] cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow"
      aria-label="Suchen"
    >
      <svg class="w-5 h-5 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
    </button>
    <h2 class="text-xl font-display font-extrabold">Transaktionen</h2>
    <div class="w-10 h-10"></div>
  </div>
{/if}

<!-- Segmented Control -->
<div class="mb-5">
  <div class="flex bg-gray-200/60 p-1.5 rounded-full">
    <button
      class="flex-1 py-2.5 rounded-full text-sm font-bold transition-all cursor-pointer"
      class:bg-white={filter === "all"}
      class:shadow-sm={filter === "all"}
      class:text-gray-500={filter !== "all"}
      class:font-medium={filter !== "all"}
      onclick={() => (filter = "all")}
    >
      Alle
    </button>
    <button
      class="flex-1 py-2.5 rounded-full text-sm font-bold transition-all cursor-pointer"
      class:bg-white={filter === "expenses"}
      class:shadow-sm={filter === "expenses"}
      class:text-gray-500={filter !== "expenses"}
      class:font-medium={filter !== "expenses"}
      onclick={() => (filter = "expenses")}
    >
      Ausgaben
    </button>
    <button
      class="flex-1 py-2.5 rounded-full text-sm font-bold transition-all cursor-pointer"
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
  <button
    onclick={() => (showExcluded = !showExcluded)}
    class="flex items-center gap-2 text-xs font-medium cursor-pointer transition-colors"
    class:text-(--color-text)={showExcluded}
    class:text-(--color-text-secondary)={!showExcluded}
  >
    <div
      class="w-8 h-[18px] rounded-full transition-colors relative"
      class:bg-(--color-text)={showExcluded}
      class:bg-gray-300={!showExcluded}
    >
      <div
        class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-white shadow-sm transition-transform"
        class:translate-x-[14px]={showExcluded}
        class:translate-x-[2px]={!showExcluded}
      ></div>
    </div>
    Ausgeblendete anzeigen
  </button>
</div>

<!-- Transaction List -->
{#if transactions.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">📋</p>
    <p class="font-display font-bold text-lg">Keine Transaktionen</p>
    <p class="text-sm mt-2">
      <a href="/import" class="text-(--color-text) font-bold underline underline-offset-2">CSV importieren</a> um zu starten
    </p>
  </div>
{:else if filtered.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">🔍</p>
    <p class="font-display font-bold text-lg">Keine Ergebnisse</p>
    <p class="text-sm mt-1">Versuche einen anderen Filter</p>
  </div>
{:else}
  {#each [...grouped.entries()] as [date, txns]}
    <h3 class="text-lg font-display font-extrabold mt-7 mb-4">
      {formatDateHeading(date)}
    </h3>

    {#each txns as txn}
      <button
        class="bg-white w-full p-4 rounded-3xl shadow-[var(--shadow-card)] flex items-center justify-between mb-3 cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow text-left"
        class:opacity-40={!!txn.excluded}
        onclick={() => openDetail(txn)}
      >
        <div class="flex items-center gap-3.5 min-w-0">
          <div
            class="w-14 h-14 rounded-full flex items-center justify-center text-xl shrink-0"
            style="background-color: {CATEGORIES[txn.category]?.color ?? '#dfe6e9'}15"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <div class="min-w-0">
            <p class="font-bold text-base leading-tight mb-0.5 truncate">{txn.description}</p>
            <p class="text-xs text-(--color-text-secondary) font-medium">
              {CATEGORIES[txn.category]?.name ?? "Uncategorized"}
            </p>
          </div>
        </div>
        <p
          class="font-extrabold text-base tabular-nums shrink-0 ml-3"
          class:text-emerald-600={txn.amount > 0}
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
    {#snippet children({ handle, content, footer })}
      <!-- Handle -->
      <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
        <div class="w-12 h-1.5 bg-gray-200 rounded-full"></div>
      </div>

      <!-- Content -->
      <div class="px-6" {@attach content}>
        <!-- Icon + Name -->
        <div class="flex flex-col items-center mb-8 mt-4">
          <div
            class="w-24 h-24 rounded-full flex items-center justify-center mb-4 text-4xl"
            style="background-color: {CATEGORIES[txn.category]?.color ?? '#dfe6e9'}15"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <h2 class="text-2xl font-display font-extrabold text-center leading-tight">
            {txn.description}
          </h2>
          <p class="text-(--color-text-secondary) text-sm mt-1.5 font-medium">
            {new Date(txn.date + "T00:00:00").toLocaleDateString("de-DE", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}
          </p>
        </div>

        <!-- Amount -->
        <div class="flex justify-between items-center py-5 border-b border-gray-100">
          <span class="text-(--color-text-secondary) font-medium text-base">Betrag</span>
          <span
            class="text-2xl font-display font-extrabold"
            class:text-emerald-600={txn.amount > 0}
          >
            {formatAmountSigned(txn.amount)}
          </span>
        </div>

        <!-- Category Selector -->
        <div class="mt-5 mb-6">
          <span class="text-(--color-text-secondary) font-bold text-xs uppercase tracking-wider">Kategorie</span>
          <div class="flex flex-wrap gap-2 mt-3">
            {#each Object.entries(CATEGORIES) as [catId, cat]}
              <button
                class="flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold transition-all cursor-pointer border"
                style="background-color: {Number(catId) === txn.category
                  ? cat.color + '20'
                  : '#f5f3ef'}; border-color: {Number(catId) === txn.category
                  ? cat.color + '40'
                  : 'transparent'}"
                onclick={() => handleCategoryChange(Number(catId))}
              >
                <span class="w-2 h-2 rounded-full shrink-0" style="background-color: {cat.color}"></span>
                {cat.name}
              </button>
            {/each}
          </div>
        </div>
      </div>

      <!-- Footer: sticky CTAs -->
      <div {@attach footer} class="px-6 pb-8 pt-4">
        <!-- Exclude Toggle -->
        <button
          class="w-full py-3.5 rounded-2xl cursor-pointer font-bold text-sm transition-all mb-3"
          class:bg-gray-100={!txn.excluded}
          class:text-gray-700={!txn.excluded}
          class:bg-amber-50={!!txn.excluded}
          class:text-amber-700={!!txn.excluded}
          onclick={handleExcludeToggle}
        >
          {txn.excluded ? "Transaktion einblenden" : "Transaktion ausblenden"}
        </button>

        <!-- Done Button -->
        <button
          class="w-full bg-(--color-accent) text-(--color-text) font-display font-extrabold text-lg py-4 rounded-2xl cursor-pointer hover:bg-(--color-accent-hover) transition-colors shadow-[0_8px_20px_rgba(255,233,125,0.25)]"
          onclick={handleSubmit}
        >
          Fertig
        </button>
      </div>
    {/snippet}
  </BottomSheet>
{/if}
