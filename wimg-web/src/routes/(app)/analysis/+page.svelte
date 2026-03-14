<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { data } from "$lib/data.svelte";
  import MonthPicker from "../../../components/MonthPicker.svelte";
  import DonutChart from "../../../components/DonutChart.svelte";
  import EmptyState from "../../../components/EmptyState.svelte";

  const now = new Date();
  let year = $state(now.getFullYear());
  let month = $state(now.getMonth() + 1);

  let expandedCategory = $state<number | null>(null);

  let summary = $derived(data.summary(year, month, accountStore.selected));

  let prevSummary = $derived.by(() => {
    const pm = month === 1 ? 12 : month - 1;
    const py = month === 1 ? year - 1 : year;
    return data.summary(py, pm, accountStore.selected);
  });

  let allTransactions = $derived(data.transactions(accountStore.selected));

  let categoryTransactions = $derived.by(() => {
    if (expandedCategory === null) return [];
    return allTransactions.filter((t: Transaction) => {
      const [ty, tm] = t.date.split("-").map(Number);
      return ty === year && tm === month && t.category === expandedCategory;
    });
  });

  let expenseCategories = $derived(
    summary.by_category.filter((c) => c.id !== 10 && c.id !== 11),
  );

  let totalExpenses = $derived(Math.abs(summary.expenses));
  let prevTotalExpenses = $derived(Math.abs(prevSummary.expenses));

  let monthDelta = $derived.by(() => {
    if (prevTotalExpenses === 0) return null;
    return Math.round(((totalExpenses - prevTotalExpenses) / prevTotalExpenses) * 100);
  });

  function getPrevAmount(catId: number): number {
    return prevSummary.by_category.find((c) => c.id === catId)?.amount ?? 0;
  }

  function getDeltaPct(current: number, previous: number): number | null {
    if (previous === 0) return null;
    return Math.round(((current - previous) / previous) * 100);
  }

  function getCatPct(amount: number): number {
    if (totalExpenses === 0) return 0;
    return Math.round((Math.abs(amount) / totalExpenses) * 100);
  }

  let hasAnyData = $derived(data.hasAnyData());
</script>

<div class="flex items-center gap-3 mb-5">
    <a
      href="/more"
      class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
      aria-label="Zurück"
    >
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
    </a>
    <h2 class="text-xl font-display font-extrabold">Insights</h2>
</div>

{#if !hasAnyData}
  <EmptyState
    title="Noch keine Daten"
    subtitle="Importiere eine CSV-Datei, um deine Ausgaben zu analysieren."
  >
    {#snippet icon()}
      <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M11 3.055A9.001 9.001 0 1020.945 13H11V3.055z" />
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20.488 9H15V3.512A9.025 9.025 0 0120.488 9z" />
      </svg>
    {/snippet}
    {#snippet actions()}
      <a
        href="/import"
        class="inline-block px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
      >
        CSV importieren
      </a>
    {/snippet}
  </EmptyState>
{:else}

<MonthPicker bind:year bind:month />

{#if summary.by_category.length > 0}
  <!-- Donut Chart Hero Card -->
  <div class="bg-white rounded-[2rem] shadow-[var(--shadow-soft)] p-8 mb-6 flex flex-col items-center">
    <!-- Chart with center text overlay -->
    <div class="relative flex items-center justify-center mb-4">
      <DonutChart data={expenseCategories} size={220} />
      <div class="absolute inset-0 flex flex-col items-center justify-center">
        <p class="text-xs font-bold uppercase tracking-wider text-(--color-text-secondary) mb-1">Ausgaben</p>
        <p class="text-3xl font-display font-black">{formatEur(totalExpenses)}</p>
        {#if monthDelta !== null}
          <div
            class="flex items-center gap-1 mt-2 text-xs font-bold bg-gray-50 px-2.5 py-1 rounded-full"
            class:text-emerald-600={monthDelta <= 0}
            class:text-rose-500={monthDelta > 0}
          >
            {#if monthDelta <= 0}
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10 15l-5-5h10l-5 5z" />
              </svg>
            {:else}
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10 5l5 5H5l5-5z" />
              </svg>
            {/if}
            <span>{Math.abs(monthDelta)}%</span>
          </div>
        {/if}
      </div>
    </div>

    <!-- Income / Expenses split -->
    <div class="flex w-full justify-around mt-4 bg-gray-50 rounded-2xl p-4">
      <div class="text-center flex-1">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase mb-1">Einnahmen</p>
        <p class="font-extrabold text-emerald-600 text-lg">{formatEur(summary.income)}</p>
      </div>
      <div class="w-px bg-gray-200 mx-2"></div>
      <div class="text-center flex-1">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase mb-1">Verfügbar</p>
        <p
          class="font-extrabold text-lg"
          class:text-emerald-600={summary.available >= 0}
          class:text-rose-500={summary.available < 0}
        >
          {formatEur(Math.abs(summary.available))}
        </p>
      </div>
    </div>
  </div>

  <!-- Categories Header -->
  <div id="categories" class="flex items-center justify-between px-1 mb-4">
    <a href="#categories" class="text-2xl font-display font-extrabold">Kategorien</a>
    <div class="flex items-center gap-1 text-sm text-(--color-text-secondary) font-medium bg-white px-3 py-1.5 rounded-full shadow-[var(--shadow-card)]">
      <span>vs. Vormonat</span>
    </div>
  </div>

  <!-- Category Cards -->
  <div class="space-y-4 mb-5">
    {#each expenseCategories as cat}
      {@const prevAmt = getPrevAmount(cat.id)}
      {@const delta = getDeltaPct(Math.abs(cat.amount), Math.abs(prevAmt))}
      {@const pct = getCatPct(cat.amount)}

      <button
        class="bg-white w-full p-5 rounded-[2rem] shadow-[var(--shadow-card)] text-left cursor-pointer hover:shadow-[var(--shadow-soft)] transition-shadow"
        onclick={() =>
          (expandedCategory =
            expandedCategory === cat.id ? null : cat.id)}
      >
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-4">
            <div
              class="w-14 h-14 rounded-[1.25rem] flex items-center justify-center text-2xl"
              style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}15"
            >
              {CATEGORIES[cat.id]?.icon ?? "📦"}
            </div>
            <div>
              <p class="text-lg font-bold">{cat.name}</p>
              <p class="text-sm font-bold text-(--color-text-secondary)">{pct}%</p>
            </div>
          </div>
          <div class="text-right">
            <p class="text-lg font-extrabold">{formatEur(cat.amount)}</p>
            {#if delta !== null}
              <div
                class="flex items-center justify-end gap-0.5 text-xs font-bold mt-0.5"
                class:text-emerald-600={delta <= 0}
                class:text-rose-500={delta > 0}
                class:text-gray-400={delta === 0}
              >
                <span>{delta > 0 ? "+" : ""}{delta}%</span>
                {#if delta < 0}
                  <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10 15l-5-5h10l-5 5z" />
                  </svg>
                {:else if delta > 0}
                  <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10 5l5 5H5l5-5z" />
                  </svg>
                {:else}
                  <span>—</span>
                {/if}
              </div>
            {/if}
          </div>
        </div>

        <!-- Progress bar -->
        <div class="w-full bg-gray-100 h-2.5 rounded-full overflow-hidden">
          <div
            class="h-full rounded-full transition-all"
            style="width: {pct}%; background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}"
          ></div>
        </div>
      </button>

      <!-- Drill-down transactions -->
      {#if expandedCategory === cat.id}
        <div class="bg-white rounded-3xl p-5 -mt-2 ml-3 shadow-[var(--shadow-card)]">
          {#each categoryTransactions as txn}
            <div class="flex justify-between text-sm py-2.5 border-b border-gray-50 last:border-0">
              <span class="truncate flex-1 mr-3 text-(--color-text-secondary)">{txn.description}</span>
              <span class="font-bold tabular-nums shrink-0">{formatEur(Math.abs(txn.amount))}</span>
            </div>
          {/each}
          {#if categoryTransactions.length === 0}
            <p class="text-xs text-(--color-text-secondary)">Keine Transaktionen</p>
          {/if}
        </div>
      {/if}
    {/each}
  </div>
{:else}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">📊</p>
    <p class="font-display font-bold text-lg">Keine Daten</p>
    <p class="text-sm mt-1">Für diesen Monat liegen keine Ausgaben vor</p>
  </div>
{/if}

{/if}
