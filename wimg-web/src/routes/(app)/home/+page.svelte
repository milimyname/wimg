<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatEur, formatEurCompact, formatDateShort } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { data } from "$lib/data.svelte";
  import { loadDemoData } from "$lib/demo";
  import { dateNav } from "$lib/dateNav.svelte";
  import MonthPicker from "../../../components/MonthPicker.svelte";
  import DonutChart from "../../../components/DonutChart.svelte";
  import EmptyState from "../../../components/EmptyState.svelte";
  import InfoTooltip from "../../../components/InfoTooltip.svelte";
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

  // expenses comes as positive from Zig (negated for display)
  let sparquote = $derived(
    summary.income > 0
      ? Math.round(((summary.income - summary.expenses) / summary.income) * 100)
      : 0,
  );

  let prevSparquote = $derived(
    prevSummary.income > 0
      ? Math.round(((prevSummary.income - prevSummary.expenses) / prevSummary.income) * 100)
      : 0,
  );

  let expenseCategories = $derived(
    summary.by_category.filter((c) => c.id !== 10 && c.id !== 11),
  );

  // Lifetime balance across the selected account (or all accounts).
  // Sum of every transaction's signed amount in scope.
  let totalBalance = $derived(
    data.transactions(accountStore.selected).reduce((s, t) => s + t.amount, 0),
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
    class="w-12 h-12 rounded-full flex items-center justify-center text-white font-display font-extrabold text-base shadow-[var(--shadow-card)]" style="background: #1a1a1a"
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

<!-- Combined balance hero: Gesamtsaldo + Einnahmen/Ausgaben in one robust card -->
<section class="bg-white rounded-3xl p-6 mb-5 shadow-[var(--shadow-soft)]">
  <div class="flex flex-col items-center text-center pb-6 mb-6 border-b border-gray-100">
    <div class="flex items-center gap-1.5 mb-2">
      <svg class="w-4 h-4 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
      </svg>
      <p class="text-[10px] text-(--color-text-secondary) font-bold uppercase tracking-widest">
        Gesamtsaldo
      </p>
    </div>
    <h1
      class="text-5xl font-display font-black tracking-tight tabular-nums"
      class:text-emerald-600={totalBalance > 0}
      class:text-rose-500={totalBalance < 0}
      class:text-(--color-text)={totalBalance === 0}
    >
      {Math.abs(totalBalance) >= 100000 ? formatEurCompact(totalBalance) : formatEur(totalBalance)}
    </h1>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-2xl bg-emerald-50 flex items-center justify-center text-emerald-600 shrink-0">
        <svg class="w-4.5 h-4.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
        </svg>
      </div>
      <div class="min-w-0">
        <p class="text-[10px] text-(--color-text-secondary) font-bold uppercase tracking-wider">Einnahmen</p>
        <p class="text-sm font-display font-bold text-emerald-700 truncate">+ {formatEurCompact(summary.income)}</p>
      </div>
    </div>
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-2xl bg-rose-50 flex items-center justify-center text-rose-600 shrink-0">
        <svg class="w-4.5 h-4.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 10l7-7m0 0l7 7m-7-7v18" />
        </svg>
      </div>
      <div class="min-w-0">
        <p class="text-[10px] text-(--color-text-secondary) font-bold uppercase tracking-wider">Ausgaben</p>
        <p class="text-sm font-display font-bold text-rose-700 truncate">- {formatEurCompact(Math.abs(summary.expenses))}</p>
      </div>
    </div>
  </div>
</section>

<!-- Verfügbares Einkommen — compact highlight card -->
<div class="bg-(--color-accent) rounded-3xl p-6 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden" style="color: #1a1a1a">
  <div class="absolute -right-8 -top-8 w-32 h-32 bg-white/25 rounded-full blur-2xl pointer-events-none"></div>
  <div class="relative z-10">
    <div class="flex items-center gap-1.5 mb-1">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a2.25 2.25 0 00-2.25-2.25H5.25a2.25 2.25 0 000 4.5h13.5A2.25 2.25 0 0021 12zM4 7.5A2.5 2.5 0 016.5 5h11a2.5 2.5 0 010 5h-11A2.5 2.5 0 014 7.5zM18 14.5v.01" />
      </svg>
      <p class="text-[10px] font-bold uppercase tracking-widest" style="opacity: 0.8">Verfügbares Einkommen</p>
      <InfoTooltip text="Einnahmen minus Ausgaben in diesem Monat. Was dir zum Sparen oder Investieren bleibt." />
    </div>
    <div class="flex items-baseline justify-between gap-3">
      <h2 class="text-3xl font-display font-black tracking-tight tabular-nums">
        {Math.abs(summary.available) >= 10000 ? formatEurCompact(summary.available) : formatEur(summary.available)}
      </h2>
      {#if delta !== null}
        <span
          class="shrink-0 inline-flex items-center rounded-full px-2.5 py-1 text-[10px] font-black backdrop-blur-sm border border-white/20"
          style="background: rgba(255,255,255,0.4); color: #1a1a1a"
        >
          {#if delta >= 0}
            <svg class="w-3 h-3 mr-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" />
            </svg>
          {:else}
            <svg class="w-3 h-3 mr-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" />
            </svg>
          {/if}
          {delta >= 0 ? "+" : ""}{delta.toFixed(1)}%
        </span>
      {/if}
    </div>
  </div>
</div>

<!-- Sparquote -->
{#if summary.income > 0}
  <div class="bg-white rounded-[1.75rem] p-5 mb-5 shadow-[var(--shadow-card)] flex items-center gap-5">
    <div class="relative w-16 h-16 shrink-0">
      <svg viewBox="0 0 36 36" class="w-full h-full -rotate-90">
        <circle cx="18" cy="18" r="15.5" fill="none" stroke="currentColor" stroke-width="3" class="text-gray-100" />
        <circle
          cx="18" cy="18" r="15.5" fill="none" stroke-width="3"
          stroke-dasharray="{Math.max(0, Math.min(sparquote, 100)) * 97.4 / 100} 97.4"
          stroke-linecap="round"
          class={sparquote >= 20 ? "text-emerald-500" : sparquote >= 0 ? "text-amber-500" : "text-rose-500"}
          stroke="currentColor"
        />
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-sm font-display font-black">{sparquote}%</span>
      </div>
    </div>
    <div class="flex-1 min-w-0">
      <div class="flex items-center gap-1.5">
        <p class="text-sm font-bold text-(--color-text)">Sparquote</p>
        <InfoTooltip text="Prozent deines Einkommens, das du sparst: (Einnahmen − Ausgaben) ÷ Einnahmen × 100. Ab 20 % gilt als gut." />
      </div>
      <p class="text-xs text-(--color-text-secondary) mt-0.5">
        Du sparst {formatEur(summary.available)} von {formatEur(summary.income)}
      </p>
      {#if prevSparquote > 0}
        {@const sqDelta = sparquote - prevSparquote}
        <p
          class="text-xs font-bold mt-1"
          class:text-emerald-600={sqDelta >= 0}
          class:text-rose-500={sqDelta < 0}
        >
          {sqDelta >= 0 ? "+" : ""}{sqDelta}pp vs. Vormonat
        </p>
      {/if}
    </div>
  </div>
{/if}

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

    <div class="flex items-center gap-5">
      <div class="relative shrink-0">
        <DonutChart data={expenseCategories} size={120} />
        <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span class="text-[10px] text-(--color-text-secondary) font-bold uppercase tracking-wide">Total</span>
          <span class="text-base font-display font-extrabold">{formatEurCompact(Math.abs(summary.expenses))}</span>
        </div>
      </div>
      <div class="flex flex-col gap-4 flex-1 min-w-0">
        {#each expenseCategories.slice(0, 4) as cat}
          {@const pct =
            Math.abs(summary.expenses) > 0
              ? (
                  (Math.abs(cat.amount) / Math.abs(summary.expenses)) *
                  100
                ).toFixed(0)
              : "0"}
          <div class="flex items-center justify-between text-sm gap-2">
            <div class="flex items-center gap-2 min-w-0">
              <div
                class="w-2.5 h-2.5 rounded-full shrink-0"
                style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}"
              ></div>
              <span class="text-(--color-text-secondary) font-medium truncate">{cat.name}</span>
            </div>
            <span class="font-extrabold shrink-0">{pct}%</span>
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Quick Links -->
  <div class="grid grid-cols-2 gap-4 mb-5">
    <a
      href="/review"
      class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex items-center gap-3 hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div class="w-10 h-10 rounded-2xl bg-indigo-50 flex items-center justify-center text-indigo-600 shrink-0">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
        </svg>
      </div>
      <span class="text-sm font-bold">Rückblick</span>
    </a>
    <a
      href="/recurring"
      class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)] flex items-center gap-3 hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div class="w-10 h-10 rounded-2xl bg-emerald-50 flex items-center justify-center text-emerald-600 shrink-0">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      </div>
      <span class="text-sm font-bold">Wiederkehrend</span>
    </a>
  </div>

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
                {formatDateShort(txn.date)} &middot; {CATEGORIES[txn.category]?.name ?? "Sonstiges"}
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
