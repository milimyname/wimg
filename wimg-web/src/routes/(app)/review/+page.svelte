<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    getSummaryFiltered,
    getTransactionsFiltered,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import { formatEur, formatDateShort } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import MonthPicker from "../../../components/MonthPicker.svelte";

  const monthNames = [
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
  ];

  const now = new Date();
  let year = $state(now.getFullYear());
  let month = $state(now.getMonth() + 1);
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

  let summary = $derived.by(() => {
    void refreshKey;
    return getSummaryFiltered(year, month, accountStore.selected);
  });

  let prevSummary = $derived.by(() => {
    void refreshKey;
    const pm = month === 1 ? 12 : month - 1;
    const py = month === 1 ? year - 1 : year;
    return getSummaryFiltered(py, pm, accountStore.selected);
  });

  let saved = $derived(summary.income + summary.expenses);

  let savingsDelta = $derived.by(() => {
    const prevSaved = prevSummary.income + prevSummary.expenses;
    if (prevSaved === 0) return null;
    return Math.round(((saved - prevSaved) / Math.abs(prevSaved)) * 100);
  });

  // All transactions for this month
  let monthTransactions = $derived.by(() => {
    void refreshKey;
    return getTransactionsFiltered(accountStore.selected).filter((t: Transaction) => {
      const [ty, tm] = t.date.split("-").map(Number);
      return ty === year && tm === month;
    });
  });

  // Recurring / expected payments detection
  type ChecklistItem = {
    description: string;
    amount: number;
    category: number;
    date: string;
    paid: boolean;
  };

  let checklist = $derived.by((): ChecklistItem[] => {
    const recurringCats = [4, 5, 9, 13];
    const items: ChecklistItem[] = [];

    for (const catId of recurringCats) {
      const txns = monthTransactions.filter(
        (t) => t.category === catId && t.amount < 0,
      );
      if (txns.length > 0) {
        const biggest = txns.reduce((a, b) =>
          Math.abs(a.amount) > Math.abs(b.amount) ? a : b,
        );
        items.push({
          description: biggest.description,
          amount: biggest.amount,
          category: biggest.category,
          date: biggest.date,
          paid: true,
        });
      }
    }

    return items.sort(
      (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
    );
  });

  // Anomaly detection
  type Anomaly = {
    category: number;
    currentAmount: number;
    previousAmount: number;
    increase: number;
  };

  let anomalies = $derived.by((): Anomaly[] => {
    const results: Anomaly[] = [];
    for (const cat of summary.by_category) {
      if (cat.id === 10 || cat.id === 11) continue;
      const prevCat = prevSummary.by_category.find((c) => c.id === cat.id);
      if (!prevCat || prevCat.amount === 0) continue;
      const increase = Math.abs(cat.amount) - Math.abs(prevCat.amount);
      const pct = (increase / Math.abs(prevCat.amount)) * 100;
      if (increase > 500 && pct > 10) {
        results.push({
          category: cat.id,
          currentAmount: Math.abs(cat.amount),
          previousAmount: Math.abs(prevCat.amount),
          increase,
        });
      }
    }
    return results.sort((a, b) => b.increase - a.increase);
  });

  // Top spending categories
  let topCategories = $derived.by(() =>
    summary.by_category
      .filter((c) => c.id !== 10 && c.id !== 11 && c.amount !== 0)
      .sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount))
      .slice(0, 5),
  );

  function savingsMessage(): string {
    if (saved > 0) return "Dein Sparziel wurde erreicht. Super Leistung!";
    if (saved === 0) return "Einnahmen und Ausgaben waren diesen Monat ausgeglichen.";
    return "Diesen Monat hast du mehr ausgegeben als eingenommen.";
  }
</script>

<h2 class="text-xl font-display font-extrabold text-center mb-5">
  {monthNames[month - 1]} Rückblick
</h2>

<MonthPicker bind:year bind:month />

{#if summary.tx_count > 0}
  <!-- Summary Hero Card -->
  <div class="bg-(--color-accent) rounded-[2rem] shadow-[var(--shadow-soft)] overflow-hidden relative mb-6">
    <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>

    <div class="flex w-full flex-col items-center gap-2 py-8 px-6 relative z-10 text-center">
      <p class="text-(--color-text)/80 text-sm font-bold uppercase tracking-widest mb-2">
        {saved >= 0 ? "Gespart" : "Defizit"}
      </p>
      <p class="text-(--color-text) text-5xl font-display font-black tracking-tighter">
        {formatEur(Math.abs(saved))}
      </p>
      {#if savingsDelta !== null}
        <div class="mt-4 inline-flex items-center justify-center bg-(--color-text) text-white px-3 py-1.5 rounded-full text-xs font-bold gap-1 shadow-md">
          {#if savingsDelta >= 0}
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 5l5 5H5l5-5z" />
            </svg>
          {:else}
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 15l-5-5h10l-5 5z" />
            </svg>
          {/if}
          <span>{savingsDelta >= 0 ? "+" : ""}{savingsDelta}% vs. {monthNames[month === 1 ? 11 : month - 2]}</span>
        </div>
      {/if}
      <p class="text-(--color-text)/80 text-sm mt-4 font-medium leading-relaxed max-w-[280px]">
        {savingsMessage()}
      </p>
    </div>

    <div class="px-6 pb-6 pt-2 grid grid-cols-2 gap-4 relative z-10">
      <div class="bg-white/40 p-4 rounded-2xl flex flex-col items-center backdrop-blur-sm">
        <p class="text-(--color-text)/70 text-xs font-bold uppercase tracking-wider mb-1">Einnahmen</p>
        <p class="text-(--color-text) font-extrabold text-lg">{formatEur(summary.income)}</p>
      </div>
      <div class="bg-white/40 p-4 rounded-2xl flex flex-col items-center backdrop-blur-sm">
        <p class="text-(--color-text)/70 text-xs font-bold uppercase tracking-wider mb-1">Ausgaben</p>
        <p class="text-(--color-text) font-extrabold text-lg">{formatEur(Math.abs(summary.expenses))}</p>
      </div>
    </div>
  </div>

  <!-- Top Categories -->
  {#if topCategories.length > 0}
    <div class="mb-6">
      <h3 class="text-xl font-display font-extrabold mb-4 px-1">Top Kategorien</h3>
      <div class="space-y-3">
        {#each topCategories as cat}
          {@const pct =
            Math.abs(summary.expenses) > 0
              ? Math.round(
                  (Math.abs(cat.amount) / Math.abs(summary.expenses)) * 100,
                )
              : 0}
          <div class="flex items-center gap-3.5 p-4 bg-white rounded-[1.5rem] shadow-[var(--shadow-card)]">
            <div
              class="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0"
              style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}15"
            >
              {CATEGORIES[cat.id]?.icon ?? "📦"}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between mb-1.5">
                <p class="text-sm font-bold truncate">{cat.name}</p>
                <p class="text-sm font-extrabold tabular-nums">
                  {formatEur(Math.abs(cat.amount))}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <div class="flex-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all"
                    style="width: {pct}%; background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}"
                  ></div>
                </div>
                <span class="text-xs text-(--color-text-secondary) font-bold tabular-nums w-8 text-right">{pct}%</span>
              </div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Payment Checklist -->
  {#if checklist.length > 0}
    <div class="mb-6">
      <h3 class="text-xl font-display font-extrabold mb-4 px-1">Zahlungs-Checkliste</h3>
      <div class="space-y-3">
        {#each checklist as item}
          <div class="flex items-center justify-between p-4 bg-white rounded-[1.5rem] shadow-[var(--shadow-card)]">
            <div class="flex items-center gap-4">
              <div class="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <div>
                <p class="text-base font-bold truncate max-w-[180px] mb-0.5">
                  {item.description}
                </p>
                <p class="text-xs text-(--color-text-secondary) font-medium">
                  {formatDateShort(item.date)}
                </p>
              </div>
            </div>
            <p class="text-base font-extrabold tabular-nums">
              {formatEur(Math.abs(item.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Anomalies -->
  {#if anomalies.length > 0}
    <div class="mb-6">
      <h3 class="text-xl font-display font-extrabold mb-4 px-1">Markierte Anomalien</h3>
      <div class="space-y-3">
        {#each anomalies as anomaly}
          {@const pct = Math.round(
            (anomaly.increase / anomaly.previousAmount) * 100,
          )}
          <div class="p-5 bg-(--color-text) rounded-[2rem] shadow-[var(--shadow-soft)] text-white relative overflow-hidden">
            <div class="absolute top-0 right-0 w-32 h-32 bg-indigo-500/20 rounded-full blur-2xl -mr-10 -mt-10"></div>
            <div class="flex gap-4 relative z-10">
              <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/10">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
                </svg>
              </div>
              <div>
                <p class="text-base font-bold mb-2">Preiserhöhung erkannt</p>
                <p class="text-sm text-gray-300 leading-relaxed">
                  Deine <strong>{CATEGORIES[anomaly.category]?.name ?? "Sonstiges"}</strong>-Kosten sind um {formatEur(anomaly.increase / 100)} gestiegen ({pct}% mehr).
                </p>
                <div class="flex items-center gap-4 mt-2 text-xs text-gray-400">
                  <span>Vormonat: {formatEur(anomaly.previousAmount / 100)}</span>
                  <span>Aktuell: {formatEur(anomaly.currentAmount / 100)}</span>
                </div>
              </div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {:else if prevSummary.tx_count > 0}
    <div class="mb-6">
      <h3 class="text-xl font-display font-extrabold mb-4 px-1">Markierte Anomalien</h3>
      <div class="p-5 bg-emerald-50 rounded-[2rem] shadow-[var(--shadow-card)]">
        <div class="flex gap-3">
          <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-emerald-600">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <div>
            <p class="text-base font-bold text-emerald-800">Keine Auffälligkeiten</p>
            <p class="text-sm text-emerald-600 mt-1">
              Keine ungewöhnlichen Preiserhöhungen in diesem Monat erkannt.
            </p>
          </div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Monthly Stats -->
  <div class="mb-6">
    <h3 class="text-xl font-display font-extrabold mb-4 px-1">Statistiken</h3>
    <div class="grid grid-cols-2 gap-4">
      <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)]">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide">Transaktionen</p>
        <p class="text-2xl font-display font-extrabold mt-1">{summary.tx_count}</p>
      </div>
      <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)]">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide">Kategorien</p>
        <p class="text-2xl font-display font-extrabold mt-1">
          {summary.by_category.filter((c) => c.count > 0).length}
        </p>
      </div>
      <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)]">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide">Ausgaben/Tag</p>
        <p class="text-lg font-display font-extrabold mt-1">
          {formatEur(
            Math.abs(summary.expenses) /
              new Date(year, month, 0).getDate() /
              100,
          )}
        </p>
      </div>
      <div class="bg-white rounded-[1.75rem] p-5 shadow-[var(--shadow-card)]">
        <p class="text-xs text-(--color-text-secondary) font-bold uppercase tracking-wide">Sparquote</p>
        <p
          class="text-lg font-display font-extrabold mt-1"
          class:text-emerald-600={saved >= 0}
          class:text-rose-600={saved < 0}
        >
          {summary.income > 0
            ? Math.round((saved / summary.income) * 100)
            : 0}%
        </p>
      </div>
    </div>
  </div>
{:else}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">📋</p>
    <p class="font-display font-bold text-lg">Keine Daten für diesen Monat</p>
    <p class="text-sm mt-2">
      <a href="/import" class="font-bold text-(--color-text) underline underline-offset-2">CSV importieren</a> um zu starten
    </p>
  </div>
{/if}
