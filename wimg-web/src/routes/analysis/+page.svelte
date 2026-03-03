<script lang="ts">
  import {
    getSummary,
    getTransactions,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import MonthPicker from "../../components/MonthPicker.svelte";
  import DonutChart from "../../components/DonutChart.svelte";

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

  const now = new Date();
  let year = $state(now.getFullYear());
  let month = $state(now.getMonth() + 1);

  let expandedCategory = $state<number | null>(null);

  let summary = $derived.by(() => getSummary(year, month));

  let prevSummary = $derived.by(() => {
    const pm = month === 1 ? 12 : month - 1;
    const py = month === 1 ? year - 1 : year;
    return getSummary(py, pm);
  });

  let allTransactions = $derived.by(() => getTransactions());

  let categoryTransactions = $derived.by(() => {
    if (expandedCategory === null) return [];
    return allTransactions.filter((t: Transaction) => {
      const [ty, tm] = t.date.split("-").map(Number);
      return ty === year && tm === month && t.category === expandedCategory;
    });
  });

  // Only expense categories for the chart
  let expenseCategories = $derived.by(() =>
    summary.by_category.filter((c) => c.id !== 10 && c.id !== 11),
  );

  let totalExpenses = $derived(Math.abs(summary.expenses));
  let prevTotalExpenses = $derived(Math.abs(prevSummary.expenses));

  let monthDelta = $derived.by(() => {
    if (prevTotalExpenses === 0) return null;
    const pct = ((totalExpenses - prevTotalExpenses) / prevTotalExpenses) * 100;
    return Math.round(pct);
  });

  function formatEur(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
    }).format(Math.abs(amount));
  }

  function getPrevAmount(catId: number): number {
    const prev = prevSummary.by_category.find((c) => c.id === catId);
    return prev?.amount ?? 0;
  }

  function getDeltaPct(current: number, previous: number): number | null {
    if (previous === 0) return null;
    return Math.round(((current - previous) / previous) * 100);
  }

  function getCatPct(amount: number): number {
    if (totalExpenses === 0) return 0;
    return Math.round((Math.abs(amount) / totalExpenses) * 100);
  }
</script>

<h2 class="text-lg font-bold text-center mb-4">Ausgabenanalyse</h2>

<MonthPicker bind:year bind:month />

{#if summary.by_category.length > 0}
  <!-- Donut Chart Hero Card -->
  <div
    class="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-5 flex flex-col items-center"
  >
    <!-- Chart with center text overlay -->
    <div class="relative flex items-center justify-center">
      <DonutChart data={expenseCategories} size={200} />
      <div class="absolute inset-0 flex flex-col items-center justify-center">
        <p
          class="text-xs font-medium uppercase tracking-wider text-gray-400 mb-1"
        >
          Ausgaben
        </p>
        <p class="text-2xl font-bold">{formatEur(totalExpenses)}</p>
        {#if monthDelta !== null}
          <div
            class="flex items-center gap-1 mt-1 text-xs font-semibold"
            class:text-emerald-500={monthDelta <= 0}
            class:text-rose-500={monthDelta > 0}
          >
            {#if monthDelta <= 0}
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                <path
                  d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                  transform="rotate(180 10 10)"
                />
              </svg>
            {:else}
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                <path
                  d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                />
              </svg>
            {/if}
            <span>{Math.abs(monthDelta)}% vs. Vormonat</span>
          </div>
        {/if}
      </div>
    </div>

    <!-- Income / Expenses split -->
    <div
      class="flex w-full justify-around mt-6 border-t border-gray-50 pt-5"
    >
      <div class="text-center">
        <p class="text-xs text-gray-400">Einnahmen</p>
        <p class="font-bold text-emerald-500">{formatEur(summary.income)}</p>
      </div>
      <div class="h-8 w-px bg-gray-100"></div>
      <div class="text-center">
        <p class="text-xs text-gray-400">Verfügbar</p>
        <p
          class="font-bold"
          class:text-emerald-500={summary.available >= 0}
          class:text-rose-500={summary.available < 0}
        >
          {formatEur(Math.abs(summary.available))}
        </p>
      </div>
    </div>
  </div>

  <!-- Categories Header -->
  <div class="flex items-center justify-between px-1 mb-3">
    <h3 class="text-lg font-bold">Kategorien</h3>
    <span class="text-sm text-gray-400">vs. Vormonat</span>
  </div>

  <!-- Category Cards -->
  <div class="space-y-3 mb-4">
    {#each expenseCategories as cat}
      {@const prevAmt = getPrevAmount(cat.id)}
      {@const delta = getDeltaPct(Math.abs(cat.amount), Math.abs(prevAmt))}
      {@const pct = getCatPct(cat.amount)}

      <button
        class="bg-white w-full p-4 rounded-xl border border-gray-100 shadow-sm text-left cursor-pointer hover:shadow-md transition-shadow"
        onclick={() =>
          (expandedCategory =
            expandedCategory === cat.id ? null : cat.id)}
      >
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-3">
            <div
              class="w-10 h-10 rounded-lg flex items-center justify-center text-lg"
              style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}20"
            >
              {CATEGORY_ICONS[cat.id] ?? "📦"}
            </div>
            <div>
              <p class="text-sm font-bold">{cat.name}</p>
              <p class="text-xs text-gray-400">{pct}% der Ausgaben</p>
            </div>
          </div>
          <div class="text-right">
            <p class="text-sm font-bold">{formatEur(cat.amount)}</p>
            {#if delta !== null}
              <div
                class="flex items-center justify-end gap-0.5 text-[10px] font-semibold"
                class:text-emerald-500={delta <= 0}
                class:text-rose-500={delta > 0}
                class:text-gray-400={delta === 0}
              >
                <span
                  >{delta > 0 ? "+" : ""}{delta}%</span
                >
                {#if delta < 0}
                  <svg
                    class="w-2.5 h-2.5"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
                    <path d="M10 15l-5-5h10l-5 5z" />
                  </svg>
                {:else if delta > 0}
                  <svg
                    class="w-2.5 h-2.5"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
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
        <div class="w-full bg-gray-100 h-1.5 rounded-full overflow-hidden">
          <div
            class="h-full rounded-full transition-all"
            style="width: {pct}%; background-color: {CATEGORIES[cat.id]
              ?.color ?? '#dfe6e9'}"
          ></div>
        </div>
      </button>

      <!-- Drill-down transactions -->
      {#if expandedCategory === cat.id}
        <div
          class="bg-white rounded-xl border border-gray-100 p-4 -mt-1 ml-2"
        >
          {#each categoryTransactions as txn}
            <div
              class="flex justify-between text-sm py-2 border-b border-gray-50 last:border-0"
            >
              <span class="truncate flex-1 mr-3 text-gray-500"
                >{txn.description}</span
              >
              <span class="font-medium tabular-nums shrink-0"
                >{formatEur(txn.amount)}</span
              >
            </div>
          {/each}
          {#if categoryTransactions.length === 0}
            <p class="text-xs text-gray-400">Keine Transaktionen</p>
          {/if}
        </div>
      {/if}
    {/each}
  </div>
{:else}
  <div class="text-center py-16 text-gray-400">
    <p class="text-3xl mb-3">📊</p>
    <p class="font-medium">Keine Daten</p>
    <p class="text-sm mt-1">Für diesen Monat liegen keine Ausgaben vor</p>
  </div>
{/if}
