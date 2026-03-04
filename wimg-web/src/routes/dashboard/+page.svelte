<script lang="ts">
  import {
    getSummaryFiltered,
    getTransactionsFiltered,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import MonthPicker from "../../components/MonthPicker.svelte";
  import DonutChart from "../../components/DonutChart.svelte";

  const now = new Date();
  let year = $state(now.getFullYear());
  let month = $state(now.getMonth() + 1);

  let summary = $derived.by(() =>
    getSummaryFiltered(year, month, accountStore.selected),
  );

  let prevSummary = $derived.by(() => {
    const pm = month === 1 ? 12 : month - 1;
    const py = month === 1 ? year - 1 : year;
    return getSummaryFiltered(py, pm, accountStore.selected);
  });

  let delta = $derived.by(() => {
    if (prevSummary.available === 0) return null;
    const diff =
      ((summary.available - prevSummary.available) /
        Math.abs(prevSummary.available)) *
      100;
    return diff;
  });

  // Latest transactions for "Kommende Zahlungen" preview
  let recentTransactions = $derived.by(() => {
    return getTransactionsFiltered(accountStore.selected)
      .filter((t: Transaction) => {
        const [ty, tm] = t.date.split("-").map(Number);
        return ty === year && tm === month;
      })
      .slice(0, 3);
  });

  // Expense categories only for donut
  let expenseCategories = $derived.by(() =>
    summary.by_category.filter((c) => c.id !== 10 && c.id !== 11),
  );

  function greeting(): string {
    const h = new Date().getHours();
    if (h < 12) return "Guten Morgen";
    if (h < 18) return "Guten Tag";
    return "Guten Abend";
  }
</script>

<!-- Greeting -->
<div class="flex items-center gap-3 mb-5">
  <div
    class="w-11 h-11 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-sm"
    style="background-color: var(--color-primary)"
  >
    K
  </div>
  <div>
    <p class="text-xs text-gray-400 font-medium uppercase tracking-wider">
      Willkommen zurück
    </p>
    <h2 class="text-xl font-bold leading-tight">{greeting()}</h2>
  </div>
</div>

<MonthPicker bind:year bind:month />

<!-- Hero: Verfügbares Einkommen -->
<div class="bg-white rounded-xl border border-gray-100 p-6 mb-4 shadow-sm">
  <div class="flex justify-between items-start mb-2">
    <p class="text-sm text-gray-400 font-medium">Verfügbares Einkommen</p>
    <svg
      class="w-6 h-6"
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
  <p class="text-[40px] font-semibold tracking-tight leading-tight">
    {formatEur(summary.available)}
  </p>
  {#if delta !== null}
    <div class="mt-3">
      <span
        class="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium"
        class:bg-emerald-50={delta >= 0}
        class:text-emerald-700={delta >= 0}
        class:bg-rose-50={delta < 0}
        class:text-rose-700={delta < 0}
      >
        {#if delta >= 0}
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
            />
          </svg>
        {:else}
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z"
            />
          </svg>
        {/if}
        {delta >= 0 ? "+" : ""}{delta.toFixed(1)}% vs. Vormonat
      </span>
    </div>
  {/if}
</div>

<!-- Income / Expenses Grid -->
<div class="grid grid-cols-2 gap-3 mb-4">
  <div
    class="bg-white rounded-xl border border-gray-100 p-4 shadow-sm flex flex-col gap-2"
  >
    <div
      class="w-8 h-8 rounded-lg bg-emerald-50 flex items-center justify-center text-emerald-600"
    >
      <svg
        class="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M19 14l-7 7m0 0l-7-7m7 7V3"
        />
      </svg>
    </div>
    <div>
      <p class="text-xs text-gray-400 font-medium">Einnahmen</p>
      <p class="text-base font-bold text-emerald-600">
        + {formatEur(summary.income)}
      </p>
    </div>
  </div>
  <div
    class="bg-white rounded-xl border border-gray-100 p-4 shadow-sm flex flex-col gap-2"
  >
    <div
      class="w-8 h-8 rounded-lg bg-rose-50 flex items-center justify-center text-rose-600"
    >
      <svg
        class="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M5 10l7-7m0 0l7 7m-7-7v18"
        />
      </svg>
    </div>
    <div>
      <p class="text-xs text-gray-400 font-medium">Ausgaben</p>
      <p class="text-base font-bold text-rose-600">
        - {formatEur(Math.abs(summary.expenses))}
      </p>
    </div>
  </div>
</div>

<!-- Budget Übersicht: Donut Chart -->
{#if expenseCategories.length > 0}
  <div class="bg-white rounded-xl border border-gray-100 p-6 mb-4 shadow-sm">
    <div class="flex justify-between items-center mb-5">
      <h3 class="text-lg font-bold">Budget Übersicht</h3>
      <a
        href="/analysis"
        class="text-sm font-semibold"
        style="color: var(--color-primary)">Details</a
      >
    </div>

    <div class="flex items-center gap-6">
      <div class="relative shrink-0">
        <DonutChart data={expenseCategories} size={130} />
        <div class="absolute inset-0 flex flex-col items-center justify-center">
          <span class="text-xs text-gray-400">Total</span>
          <span class="text-sm font-bold"
            >{formatEur(Math.abs(summary.expenses))}</span
          >
        </div>
      </div>
      <div class="flex flex-col gap-3 flex-1">
        {#each expenseCategories.slice(0, 4) as cat}
          {@const pct =
            Math.abs(summary.expenses) > 0
              ? (
                  (Math.abs(cat.amount) / Math.abs(summary.expenses)) *
                  100
                ).toFixed(0)
              : "0"}
          <div class="flex items-center justify-between text-sm">
            <div class="flex items-center gap-2">
              <div
                class="w-2 h-2 rounded-full"
                style="background-color: {CATEGORIES[cat.id]?.color ??
                  '#dfe6e9'}"
              ></div>
              <span class="text-gray-500">{cat.name}</span>
            </div>
            <span class="font-semibold">{pct}%</span>
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Quick Links -->
  <div class="grid grid-cols-2 gap-3 mb-4">
    <a
      href="/debts"
      class="bg-white rounded-xl border border-gray-100 p-4 shadow-sm flex items-center gap-3 hover:bg-gray-50 transition-colors"
    >
      <div
        class="w-9 h-9 rounded-lg bg-amber-50 flex items-center justify-center text-amber-600"
      >
        <svg
          class="w-5 h-5"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
      </div>
      <span class="text-sm font-semibold">Schulden</span>
    </a>
    <a
      href="/review"
      class="bg-white rounded-xl border border-gray-100 p-4 shadow-sm flex items-center gap-3 hover:bg-gray-50 transition-colors"
    >
      <div
        class="w-9 h-9 rounded-lg bg-indigo-50 flex items-center justify-center text-indigo-600"
      >
        <svg
          class="w-5 h-5"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"
          />
        </svg>
      </div>
      <span class="text-sm font-semibold">Rückblick</span>
    </a>
  </div>

  <!-- Letzte Transaktionen -->
  {#if recentTransactions.length > 0}
    <div class="mb-4">
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-lg font-bold">Letzte Transaktionen</h3>
        <a
          href="/transactions"
          class="text-sm font-semibold"
          style="color: var(--color-primary)">Alle</a
        >
      </div>
      <div
        class="bg-white rounded-xl shadow-sm border border-gray-100 divide-y divide-gray-50 overflow-hidden"
      >
        {#each recentTransactions as txn}
          <div class="flex items-center gap-3 p-4">
            <div
              class="w-10 h-10 rounded-lg flex items-center justify-center text-lg"
              style="background-color: {CATEGORIES[txn.category]?.color ??
                '#dfe6e9'}15"
            >
              {CATEGORIES[txn.category]?.icon ?? "📦"}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-bold truncate">{txn.description}</p>
              <p class="text-xs text-gray-400">
                {new Date(txn.date + "T00:00:00").toLocaleDateString("de-DE", {
                  day: "numeric",
                  month: "short",
                })} &middot; {CATEGORIES[txn.category]?.name ?? "Sonstiges"}
              </p>
            </div>
            <p
              class="text-sm font-bold tabular-nums shrink-0"
              class:text-rose-500={txn.amount < 0}
              class:text-emerald-500={txn.amount > 0}
            >
              {txn.amount < 0 ? "- " : "+ "}{formatEur(Math.abs(txn.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/if}
{:else}
  <div class="text-center py-16 text-gray-400">
    <p class="text-3xl mb-3">📊</p>
    <p class="font-medium">Keine Daten für diesen Monat</p>
    <p class="text-sm mt-1">
      <a href="/import" class="font-medium" style="color: var(--color-primary)"
        >CSV importieren</a
      > um zu starten
    </p>
  </div>
{/if}
