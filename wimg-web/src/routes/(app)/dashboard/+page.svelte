<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { data } from "$lib/data.svelte";
  import { loadDemoData } from "$lib/demo";
  import { featureStore } from "$lib/features.svelte";
  import { dateNav } from "$lib/dateNav.svelte";
  import MonthPicker from "../../../components/MonthPicker.svelte";
  import DonutChart from "../../../components/DonutChart.svelte";
  import EmptyState from "../../../components/EmptyState.svelte";
  let loadingDemo = $state(false);

  let hasAnyData = $derived(data.hasAnyData());
  let summary = $derived(data.summary(dateNav.year, dateNav.month, accountStore.selected));

  let prevSummary = $derived.by(() => {
    const pm = dateNav.month === 1 ? 12 : dateNav.month - 1;
    const py = dateNav.month === 1 ? dateNav.year - 1 : dateNav.year;
    return data.summary(py, pm, accountStore.selected);
  });

  let delta = $derived.by(() => {
    if (prevSummary.available === 0) return null;
    return ((summary.available - prevSummary.available) / Math.abs(prevSummary.available)) * 100;
  });

  let recentTransactions = $derived(
    data.transactions(accountStore.selected)
      .filter((t: Transaction) => {
        const [ty, tm] = t.date.split("-").map(Number);
        return ty === dateNav.year && tm === dateNav.month;
      })
      .slice(0, 3),
  );

  let expenseCategories = $derived(
    summary.by_category.filter((c) => c.id !== 10 && c.id !== 11),
  );

  function greeting(): string {
    const h = new Date().getHours();
    if (h < 12) return "Guten Morgen";
    if (h < 18) return "Guten Tag";
    return "Guten Abend";
  }

  async function handleLoadDemo() {
    loadingDemo = true;
    try {
      await loadDemoData();
      accountStore.reload();
      data.bump();
    } finally {
      loadingDemo = false;
    }
  }
</script>

<!-- Greeting -->
<div class="flex items-center gap-3.5 mb-6">
  <div
    class="w-12 h-12 rounded-full flex items-center justify-center text-white font-display font-extrabold text-base shadow-[var(--shadow-card)] bg-(--color-text)"
  >
    K
  </div>
  <div>
    <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-widest mb-0.5">
      Willkommen zurück
    </p>
    <h2 class="text-2xl font-display font-extrabold leading-tight">{greeting()}</h2>
  </div>
</div>

{#if !hasAnyData}
  <EmptyState
    title="Willkommen bei wimg"
    subtitle="Importiere eine CSV-Datei oder lade Beispieldaten, um loszulegen."
  >
    {#snippet icon()}
      <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
      </svg>
    {/snippet}
    {#snippet actions()}
      <div class="flex flex-col gap-3 items-center">
        <a
          href="/import"
          class="px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
        >
          CSV importieren
        </a>
        <button
          onclick={handleLoadDemo}
          disabled={loadingDemo}
          class="px-6 py-3 rounded-2xl bg-gray-100 text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
        >
          {loadingDemo ? "Lade..." : "Beispieldaten laden"}
        </button>
      </div>
    {/snippet}
  </EmptyState>
{:else}

<MonthPicker bind:year={dateNav.year} bind:month={dateNav.month} />

<!-- Hero: Verfügbares Einkommen -->
<div class="bg-(--color-accent) rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
  <div class="absolute -right-8 -top-8 w-32 h-32 bg-white/25 rounded-full blur-2xl pointer-events-none"></div>
  <div class="flex justify-between items-start mb-3 relative z-10">
    <div class="flex items-center gap-2">
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
      </svg>
      <p class="text-(--color-text)/80 text-sm font-bold uppercase tracking-wide">Verfügbares Einkommen</p>
    </div>
  </div>
  <p class="text-[2.75rem] font-display font-black tracking-tight leading-tight text-(--color-text) relative z-10 mb-4">
    {formatEur(summary.available)}
  </p>
  {#if delta !== null}
    <div class="relative z-10">
      <span
        class="inline-flex items-center rounded-full bg-white/50 backdrop-blur-sm px-3 py-1.5 text-xs font-bold text-(--color-text) shadow-sm"
      >
        {#if delta >= 0}
          <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
            <path d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" />
          </svg>
        {:else}
          <svg class="w-3.5 h-3.5 mr-1" fill="currentColor" viewBox="0 0 20 20">
            <path d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" />
          </svg>
        {/if}
        {delta >= 0 ? "+" : ""}{delta.toFixed(1)}% vs. Vormonat
      </span>
    </div>
  {/if}
</div>

<!-- Income / Expenses Grid -->
<div class="grid grid-cols-2 gap-4 mb-5">
  <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex flex-col gap-3">
    <div class="w-10 h-10 rounded-2xl bg-emerald-50 flex items-center justify-center text-emerald-500">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
      </svg>
    </div>
    <div>
      <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide mb-1">Einnahmen</p>
      <p class="text-lg font-display font-extrabold text-emerald-600">+ {formatEur(summary.income)}</p>
    </div>
  </div>
  <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex flex-col gap-3">
    <div class="w-10 h-10 rounded-2xl bg-rose-50 flex items-center justify-center text-rose-500">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 10l7-7m0 0l7 7m-7-7v18" />
      </svg>
    </div>
    <div>
      <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide mb-1">Ausgaben</p>
      <p class="text-lg font-display font-extrabold text-rose-600">- {formatEur(Math.abs(summary.expenses))}</p>
    </div>
  </div>
</div>

<!-- Budget Übersicht: Donut Chart -->
{#if expenseCategories.length > 0}
  <div class="bg-white rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)]">
    <div class="flex justify-between items-center mb-6">
      <h3 class="text-xl font-display font-extrabold">Budget Übersicht</h3>
      <a
        href="/analysis"
        class="text-sm font-bold bg-(--color-accent)/40 text-(--color-text) px-3.5 py-1.5 rounded-full hover:bg-(--color-accent)/60 transition-colors"
      >Details</a>
    </div>

    <div class="flex items-center gap-8">
      <div class="relative shrink-0">
        <DonutChart data={expenseCategories} size={130} />
        <div class="absolute inset-0 flex flex-col items-center justify-center">
          <span class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide">Total</span>
          <span class="text-lg font-display font-extrabold">{formatEur(Math.abs(summary.expenses))}</span>
        </div>
      </div>
      <div class="flex flex-col gap-4 flex-1">
        {#each expenseCategories.slice(0, 4) as cat}
          {@const pct =
            Math.abs(summary.expenses) > 0
              ? (
                  (Math.abs(cat.amount) / Math.abs(summary.expenses)) *
                  100
                ).toFixed(0)
              : "0"}
          <div class="flex items-center justify-between text-sm">
            <div class="flex items-center gap-3">
              <div
                class="w-2.5 h-2.5 rounded-full"
                style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}"
              ></div>
              <span class="text-(--color-text-secondary) font-medium">{cat.name}</span>
            </div>
            <span class="font-extrabold">{pct}%</span>
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Quick Links -->
  {#if featureStore.isEnabled("debts") || featureStore.isEnabled("review")}
  <div class="grid grid-cols-2 gap-4 mb-5">
    {#if featureStore.isEnabled("debts")}
    <a
      href="/debts"
      class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex items-center gap-3 hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div class="w-10 h-10 rounded-2xl bg-amber-50 flex items-center justify-center text-amber-600">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
      <span class="text-sm font-bold">Schulden</span>
    </a>
    {/if}
    {#if featureStore.isEnabled("review")}
    <a
      href="/review"
      class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex items-center gap-3 hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div class="w-10 h-10 rounded-2xl bg-indigo-50 flex items-center justify-center text-indigo-600">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
        </svg>
      </div>
      <span class="text-sm font-bold">Rückblick</span>
    </a>
    {/if}
  </div>
  {/if}

  <!-- Letzte Transaktionen -->
  {#if recentTransactions.length > 0}
    <div class="mb-5">
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-xl font-display font-extrabold">Letzte Transaktionen</h3>
        <a
          href="/transactions"
          class="text-sm font-bold text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
        >Alle</a>
      </div>
      <div class="bg-white rounded-[2rem] shadow-[var(--shadow-soft)] overflow-hidden p-2">
        {#each recentTransactions as txn}
          <div class="flex items-center gap-3.5 p-4 rounded-[1.5rem] hover:bg-gray-50 transition-colors">
            <div
              class="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0"
              style="background-color: {CATEGORIES[txn.category]?.color ?? '#dfe6e9'}15"
            >
              {CATEGORIES[txn.category]?.icon ?? "📦"}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-base font-bold truncate">{txn.description}</p>
              <p class="text-xs text-(--color-text-secondary) font-medium mt-0.5">
                {new Date(txn.date + "T00:00:00").toLocaleDateString("de-DE", {
                  day: "numeric",
                  month: "short",
                })} &middot; {CATEGORIES[txn.category]?.name ?? "Sonstiges"}
              </p>
            </div>
            <p
              class="text-base font-extrabold tabular-nums shrink-0"
              class:text-rose-500={txn.amount < 0}
              class:text-emerald-600={txn.amount > 0}
            >
              {txn.amount < 0 ? "- " : "+ "}{formatEur(Math.abs(txn.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/if}
{:else}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">📊</p>
    <p class="font-display font-bold text-lg">Keine Daten für diesen Monat</p>
    <p class="text-sm mt-2">
      <a href="/import" class="font-bold text-(--color-text) underline underline-offset-2">CSV importieren</a> um zu starten
    </p>
  </div>
{/if}

{/if}
