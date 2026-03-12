<script lang="ts">
  import { onMount, onDestroy, tick } from "svelte";
  import {
    getTransactionsFiltered,
    setCategory,
    setExcluded,
    undo,
    smartCategorize,
    isModelLoaded,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import { formatAmountSigned, formatDateHeading } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { toastStore } from "$lib/toast.svelte";
  import BottomSheet from "../../../components/BottomSheet.svelte";
  import { pushState, replaceState } from "$app/navigation";
  import { page } from "$app/state";

  type Filter = "all" | "expenses" | "income";

  const OPEN_TXN_KEY = "wimg_open_txn";

  let refreshKey = $state(0);
  let sheetDismissed = $state(false);

  function onSyncReceived() {
    refreshKey++;
  }

  function onOpenTxn(e: Event) {
    const id = (e as CustomEvent<{ id: string }>).detail.id;
    const tx = transactions.find((t) => t.id === id);
    if (tx) {
      openDetail(tx);
      sessionStorage.removeItem(OPEN_TXN_KEY);
    }
  }

  onMount(() => {
    window.addEventListener("wimg:sync-received", onSyncReceived);
    window.addEventListener("wimg:open-txn", onOpenTxn);

    // Restore sheet on page reload (check URL params first, then sessionStorage)
    if (!page.state.txnId) {
      const storedId = sessionStorage.getItem(OPEN_TXN_KEY);
      if (storedId) {
        const tx = transactions.find((t) => t.id === storedId);
        if (tx) {
          selectedTxn = { ...tx };
          originalTxn = { ...tx };
          replaceState("", { sheet: "txn-detail", txnId: storedId });
          tick().then(() => {
            document.getElementById(storedId)?.scrollIntoView({ behavior: "smooth", block: "center" });
          });
        } else {
          sessionStorage.removeItem(OPEN_TXN_KEY);
        }
      }
    }
  });

  onDestroy(() => {
    window.removeEventListener("wimg:sync-received", onSyncReceived);
    window.removeEventListener("wimg:open-txn", onOpenTxn);
  });
  let txResult = $derived.by(() => {
    void refreshKey;
    try {
      return {
        data: getTransactionsFiltered(accountStore.selected),
        error: null as string | null,
      };
    } catch (e) {
      return {
        data: [] as Transaction[],
        error: e instanceof Error ? e.message : "Fehler beim Laden",
      };
    }
  });
  let transactions = $derived(txResult.data);
  let loadError = $derived(txResult.error);
  let filter = $state<Filter>("all");
  let selectedTxn = $state<Transaction | null>(null);
  let originalTxn = $state<Transaction | null>(null);
  let showSheet = $derived(page.state.sheet === "txn-detail" && selectedTxn != null);
  let searchQuery = $state("");
  let showExcluded = $state(false);
  let filterCategories = $state<number[]>([]);
  let showAdvancedSearch = $derived(page.state.sheet === "txn-filter");
  let dateQuick = $state<string | null>(null);
  let dateFrom = $state("");
  let dateTo = $state("");
  let amountQuick = $state<string | null>(null);

  const QUICK_CATEGORIES = [1, 2, 3, 7, 6]; // groceries, dining, transport, shopping, entertainment

  function getDateFrom(range: string): string {
    const today = new Date();
    if (range === "30d") {
      const d = new Date(today);
      d.setDate(d.getDate() - 30);
      return d.toISOString().slice(0, 10);
    }
    if (range === "month") {
      return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-01`;
    }
    const d = new Date(today);
    d.setMonth(d.getMonth() - 3);
    return d.toISOString().slice(0, 10);
  }

  let activeFilterCount = $derived(
    (dateQuick || dateFrom || dateTo ? 1 : 0) +
      (amountQuick ? 1 : 0) +
      (filterCategories.length > 0 ? 1 : 0) +
      (searchQuery.trim() ? 1 : 0),
  );

  let filtered = $derived.by(() => {
    let list = transactions;
    if (!showExcluded) list = list.filter((t) => !t.excluded);
    if (filter === "expenses") list = list.filter((t) => t.amount < 0);
    if (filter === "income") list = list.filter((t) => t.amount > 0);
    if (filterCategories.length > 0)
      list = list.filter((t) => filterCategories.includes(t.category));
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter((t) => t.description.toLowerCase().includes(q));
    }
    if (dateQuick) {
      const from = getDateFrom(dateQuick);
      list = list.filter((t) => t.date >= from);
    } else {
      if (dateFrom) list = list.filter((t) => t.date >= dateFrom);
      if (dateTo) list = list.filter((t) => t.date <= dateTo);
    }
    if (amountQuick) {
      if (amountQuick === "lt50")
        list = list.filter((t) => Math.abs(t.amount) < 50);
      else if (amountQuick === "50-200")
        list = list.filter(
          (t) => Math.abs(t.amount) >= 50 && Math.abs(t.amount) <= 200,
        );
      else if (amountQuick === "gt200")
        list = list.filter((t) => Math.abs(t.amount) > 200);
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
    sheetDismissed = false;
    sessionStorage.setItem(OPEN_TXN_KEY, txn.id);
    // Replace existing shallow entry instead of stacking multiple
    if (page.state.sheet === "txn-detail") {
      replaceState("", { sheet: "txn-detail", txnId: txn.id });
    } else {
      pushState("", { sheet: "txn-detail", txnId: txn.id });
    }
  }

  // Restore transaction detail on back navigation (page.state preserved by SvelteKit)
  $effect(() => {
    const stateId = page.state.txnId;
    if (stateId && !selectedTxn && !sheetDismissed) {
      const tx = transactions.find((t) => t.id === stateId);
      if (tx) {
        selectedTxn = { ...tx };
        originalTxn = { ...tx };
        tick().then(() => {
          document.getElementById(stateId)?.scrollIntoView({ behavior: "smooth", block: "center" });
        });
      }
    }
  });

  function dismissSheet() {
    sheetDismissed = true;
    sessionStorage.removeItem(OPEN_TXN_KEY);
    history.back();
  }

  function onSheetClosed() {
    // Don't pop history — preserve the entry so back navigation can restore the sheet
    selectedTxn = null;
    originalTxn = null;
    sheetDismissed = true;
    sessionStorage.removeItem(OPEN_TXN_KEY);
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

  function toggleFilterCategory(catId: number) {
    if (filterCategories.includes(catId)) {
      filterCategories = filterCategories.filter((c) => c !== catId);
    } else {
      filterCategories = [...filterCategories, catId];
    }
  }

  function clearAllFilters() {
    searchQuery = "";
    dateQuick = null;
    dateFrom = "";
    dateTo = "";
    amountQuick = null;
    filterCategories = [];
  }

  let categorizing = $state(false);
  let categorizeResult = $state("");
  let hasModel = $derived.by(() => {
    try { return isModelLoaded(); } catch { return false; }
  });

  function handleSmartCategorize() {
    categorizing = true;
    categorizeResult = "";
    try {
      const count = smartCategorize();
      categorizeResult = count === -2 ? "Zuerst manuell kategorisieren" : count > 0 ? `${count} kategorisiert` : "Keine unkategorisierten gefunden";
      if (count > 0) refreshKey++;
      setTimeout(() => { categorizeResult = ""; }, 4000);
    } catch {
      categorizeResult = "Fehler";
    } finally {
      categorizing = false;
    }
  }
</script>

<!-- Header -->
<div class="flex items-center justify-between mb-4">
  <button
    onclick={() => pushState("", { sheet: "txn-filter" })}
    class="w-10 h-10 flex items-center justify-center rounded-full bg-white shadow-[var(--shadow-card)] cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow"
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
  <h2 class="text-xl font-display font-extrabold">Transaktionen</h2>
  <button
    onclick={() => pushState("", { sheet: "txn-filter" })}
    class="w-10 h-10 flex items-center justify-center rounded-full bg-white shadow-[var(--shadow-card)] cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow relative"
    aria-label="Filter"
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
        d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
      />
    </svg>
    {#if activeFilterCount > 0}
      <span
        class="absolute -top-1 -right-1 w-5 h-5 bg-(--color-accent) rounded-full text-[10px] font-bold flex items-center justify-center"
        >{activeFilterCount}</span
      >
    {/if}
  </button>
</div>

<!-- Segmented Control -->
<div class="mb-5">
  <div class="relative flex bg-gray-200/60 p-1.5 rounded-full">
    <!-- Sliding indicator -->
    <div
      class="absolute top-1.5 bottom-1.5 rounded-full bg-white shadow-sm transition-transform duration-300 ease-[cubic-bezier(0.25,0.1,0.25,1)]"
      style="width: calc((100% - 12px) / 3); left: 6px; transform: translateX({filter === 'all' ? '0%' : filter === 'expenses' ? '100%' : '200%'})"
    ></div>
    <button
      class="relative z-10 flex-1 py-2.5 rounded-full text-sm font-bold transition-colors duration-200 cursor-pointer"
      class:text-gray-500={filter !== "all"}
      onclick={() => (filter = "all")}
    >
      Alle
    </button>
    <button
      class="relative z-10 flex-1 py-2.5 rounded-full text-sm font-bold transition-colors duration-200 cursor-pointer"
      class:text-gray-500={filter !== "expenses"}
      onclick={() => (filter = "expenses")}
    >
      Ausgaben
    </button>
    <button
      class="relative z-10 flex-1 py-2.5 rounded-full text-sm font-bold transition-colors duration-200 cursor-pointer"
      class:text-gray-500={filter !== "income"}
      onclick={() => (filter = "income")}
    >
      Einnahmen
    </button>
  </div>
</div>

<!-- Quick Category Filter (top 5) -->
{#if Object.keys(CATEGORIES).length > 0}
  <div class="flex justify-between mb-8 px-2">
    {#each QUICK_CATEGORIES as catId}
      {@const cat = CATEGORIES[catId]}
      {#if cat}
        {@const active =
          filterCategories.length === 1 && filterCategories[0] === catId}
        <button
          class="flex flex-col items-center gap-2 cursor-pointer"
          onclick={() => {
            if (active) {
              filterCategories = [];
            } else {
              filterCategories = [catId];
            }
          }}
        >
          <div
            class="w-14 h-14 rounded-full flex items-center justify-center text-xl transition-all"
            style="background-color: {cat.color}15;{active
              ? ` box-shadow: 0 0 0 2.5px ${cat.color}`
              : ''}"
          >
            {cat.icon}
          </div>
          <span
            class="text-xs text-center transition-colors"
            class:font-bold={active}
            class:font-medium={!active}
            class:text-(--color-text)={active}
            class:text-(--color-text-secondary)={!active}
          >
            {cat.name}
          </span>
        </button>
      {/if}
    {/each}
  </div>
{/if}

<!-- Transaction List -->
{#if loadError}
  <div class="bg-red-50 border border-red-200 rounded-2xl p-5 mb-4">
    <p class="font-bold text-red-700 text-sm">{loadError}</p>
  </div>
{:else if transactions.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">📋</p>
    <p class="font-display font-bold text-lg">Keine Transaktionen</p>
    <p class="text-sm mt-2">
      <a
        href="/import"
        class="text-(--color-text) font-bold underline underline-offset-2"
        >CSV importieren</a
      > um zu starten
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
    <h3
      class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider mt-6 mb-3"
    >
      {formatDateHeading(date)}
    </h3>

    {#each txns as txn}
      <button
        id={txn.id}
        class="bg-white w-full p-4 rounded-2xl shadow-[var(--shadow-card)] border border-gray-100/80 flex items-center justify-between mb-2.5 cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow text-left"
        class:opacity-40={!!txn.excluded}
        onclick={() => openDetail(txn)}
      >
        <div class="flex items-center gap-3 min-w-0">
          <div
            class="w-12 h-12 rounded-xl flex items-center justify-center text-lg shrink-0"
            style="background-color: {CATEGORIES[txn.category]?.color ??
              '#dfe6e9'}15"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <div class="min-w-0">
            <p class="font-bold text-sm leading-tight mb-0.5 truncate">
              {txn.description}
            </p>
            <p class="text-xs text-(--color-text-secondary) font-medium">
              {CATEGORIES[txn.category]?.name ?? "Uncategorized"}
            </p>
          </div>
        </div>
        <p
          class="font-extrabold text-sm tabular-nums shrink-0 ml-3"
          class:text-emerald-600={txn.amount > 0}
        >
          {formatAmountSigned(txn.amount)}
        </p>
      </button>
    {/each}
  {/each}
{/if}

<!-- Advanced Search Bottom Sheet -->
<BottomSheet
  open={showAdvancedSearch}
  onclose={() => history.back()}
  snaps={[0.92]}
>
  {#snippet children({ handle, content, footer })}
    <!-- Handle -->
    <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
      <div class="w-12 h-1.5 bg-gray-200 rounded-full"></div>
    </div>

    <!-- Content -->
    <div class="px-6" {@attach content}>
      <!-- Search input -->
      <div class="relative mb-6 pt-1">
        <div
          class="absolute inset-y-0 left-4 flex items-center pointer-events-none"
        >
          <svg
            class="w-5 h-5 text-gray-400"
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
        </div>
        <input
          type="text"
          bind:value={searchQuery}
          placeholder="Suchen nach..."
          class="w-full bg-gray-50 border-none rounded-2xl py-3.5 pl-12 pr-4 focus:outline-none focus:ring-2 focus:ring-(--color-accent) text-base"
        />
      </div>

      <!-- Date Range -->
      <section class="mb-6">
        <h2 class="text-base font-display font-extrabold mb-3">Zeitraum</h2>
        <div class="flex flex-wrap gap-2 mb-4">
          {#each [{ id: "30d", label: "Letzte 30 Tage" }, { id: "month", label: "Aktueller Monat" }, { id: "quarter", label: "Letztes Quartal" }] as chip}
            <button
              class="px-4 py-2.5 rounded-full text-sm font-bold cursor-pointer transition-all"
              class:bg-(--color-accent)={dateQuick === chip.id}
              class:bg-gray-50={dateQuick !== chip.id}
              class:border={dateQuick !== chip.id}
              class:border-gray-200={dateQuick !== chip.id}
              onclick={() => {
                dateQuick = dateQuick === chip.id ? null : chip.id;
                if (dateQuick) { dateFrom = ""; dateTo = ""; }
              }}
            >
              {chip.label}
            </button>
          {/each}
        </div>
        <div class="flex gap-3">
          <label class="flex-1">
            <span class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider mb-1.5 block">Von</span>
            <input
              type="date"
              bind:value={dateFrom}
              onchange={() => { if (dateFrom) dateQuick = null; }}
              class="w-full bg-gray-50 border border-gray-200 rounded-2xl py-3 px-4 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-(--color-accent) focus:border-transparent"
            />
          </label>
          <label class="flex-1">
            <span class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider mb-1.5 block">Bis</span>
            <input
              type="date"
              bind:value={dateTo}
              onchange={() => { if (dateTo) dateQuick = null; }}
              class="w-full bg-gray-50 border border-gray-200 rounded-2xl py-3 px-4 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-(--color-accent) focus:border-transparent"
            />
          </label>
        </div>
      </section>

      <!-- Categories -->
      <section class="mb-6">
        <div class="flex justify-between items-end mb-3">
          <h2 class="text-base font-display font-extrabold">Kategorien</h2>
          {#if filterCategories.length > 0}
            <button
              onclick={() => (filterCategories = [])}
              class="text-xs text-(--color-text-secondary) font-bold cursor-pointer"
            >
              Zurücksetzen
            </button>
          {/if}
        </div>
        <div class="grid grid-cols-4 gap-4">
          {#each Object.entries(CATEGORIES) as [catId, cat]}
            {@const id = Number(catId)}
            {@const active = filterCategories.includes(id)}
            <button
              class="flex flex-col items-center gap-2 cursor-pointer"
              onclick={() => toggleFilterCategory(id)}
            >
              <div
                class="w-12 h-12 rounded-xl flex items-center justify-center text-lg transition-all"
                style="background-color: {cat.color}15;{active
                  ? ` box-shadow: 0 0 0 2.5px ${cat.color}`
                  : ''}"
              >
                {cat.icon}
              </div>
              <span
                class="text-[10px] text-center"
                class:font-bold={active}
                class:font-medium={!active}
                class:text-(--color-text)={active}
                class:text-(--color-text-secondary)={!active}
              >
                {cat.name}
              </span>
            </button>
          {/each}
        </div>
      </section>

      <!-- Amount -->
      <section class="mb-6">
        <h2 class="text-base font-display font-extrabold mb-3">Betrag</h2>
        <div class="flex gap-2">
          {#each [{ id: "lt50", label: "< 50\u20AC" }, { id: "50-200", label: "50 \u2013 200\u20AC" }, { id: "gt200", label: "> 200\u20AC" }] as chip}
            <button
              class="flex-1 py-3 rounded-2xl text-sm font-bold cursor-pointer transition-all"
              class:bg-(--color-accent)={amountQuick === chip.id}
              class:bg-gray-50={amountQuick !== chip.id}
              class:border={amountQuick !== chip.id}
              class:border-gray-200={amountQuick !== chip.id}
              onclick={() =>
                (amountQuick = amountQuick === chip.id ? null : chip.id)}
            >
              {chip.label}
            </button>
          {/each}
        </div>
      </section>

      <!-- Show excluded toggle -->
      <section class="mb-4">
        <div class="flex items-center justify-between py-3">
          <span class="text-sm font-medium text-(--color-text-secondary)"
            >Ausgeblendete anzeigen</span
          >
          <button
            onclick={() => (showExcluded = !showExcluded)}
            class="cursor-pointer"
            aria-label="Ausgeblendete anzeigen"
          >
            <div
              class="w-10 h-6 rounded-full transition-colors relative"
              class:bg-(--color-accent)={showExcluded}
              class:bg-gray-300={!showExcluded}
            >
              <div
                class="absolute top-[3px] w-[18px] h-[18px] rounded-full bg-white shadow-sm transition-transform"
                class:translate-x-[19px]={showExcluded}
                class:translate-x-[3px]={!showExcluded}
              ></div>
            </div>
          </button>
        </div>
      </section>

      <!-- Smart Categorize -->
      {#if hasModel}
        <section class="mb-4">
          <button
            onclick={handleSmartCategorize}
            disabled={categorizing}
            class="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl bg-indigo-50 text-indigo-700 font-bold text-sm transition-all active:scale-[0.98] disabled:opacity-50"
          >
            {#if categorizing}
              <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              Kategorisiere...
            {:else}
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
              Smart Kategorisieren
            {/if}
          </button>
          {#if categorizeResult}
            <p class="text-xs text-center text-indigo-600 font-medium mt-2">{categorizeResult}</p>
          {/if}
        </section>
      {/if}
    </div>

    <!-- Footer -->
    <div {@attach footer} class="px-6 pb-8 pt-4">
      <div class="flex gap-3">
        {#if activeFilterCount > 0}
          <button
            onclick={clearAllFilters}
            class="px-5 py-4 rounded-2xl bg-gray-100 font-bold text-sm cursor-pointer"
          >
            Zurücksetzen
          </button>
        {/if}
        <button
          class="flex-1 bg-(--color-accent) text-(--color-text) font-display font-extrabold text-lg py-4 rounded-2xl cursor-pointer hover:bg-(--color-accent-hover) transition-colors shadow-[0_8px_20px_rgba(255,233,125,0.25)]"
          onclick={() => history.back()}
        >
          Ergebnisse anzeigen
        </button>
      </div>
    </div>
  {/snippet}
</BottomSheet>

<!-- Bottom Sheet -->
{#if selectedTxn}
  {@const txn = selectedTxn}
  <BottomSheet open={showSheet} onclose={onSheetClosed} snaps={[0.88]}>
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
            class="w-20 h-20 rounded-2xl flex items-center justify-center mb-4 text-4xl"
            style="background-color: {CATEGORIES[txn.category]?.color ??
              '#dfe6e9'}15"
          >
            {CATEGORIES[txn.category]?.icon ?? "📦"}
          </div>
          <h2
            class="text-2xl font-display font-extrabold text-center leading-tight"
          >
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
        <div
          class="flex justify-between items-center py-5 border-b border-gray-100"
        >
          <span class="text-(--color-text-secondary) font-medium text-base"
            >Betrag</span
          >
          <span
            class="text-2xl font-display font-extrabold"
            class:text-emerald-600={txn.amount > 0}
          >
            {formatAmountSigned(txn.amount)}
          </span>
        </div>

        <!-- Category Selector -->
        <div class="mt-5 mb-6">
          <span
            class="text-(--color-text-secondary) font-bold text-xs uppercase tracking-wider"
            >Kategorie</span
          >
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
