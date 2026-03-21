<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatEur, formatEurCompact, formatDateShort } from "$lib/format";
  import { accountStore } from "$lib/account.svelte";
  import { data } from "$lib/data.svelte";
  import { dateNav } from "$lib/dateNav.svelte";
  import MonthPicker from "../../../components/MonthPicker.svelte";

  const monthNames = [
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
  ];

  let summary = $derived(data.summary(dateNav.year, dateNav.month, accountStore.selected));

  let prevSummary = $derived.by(() => {
    const pm = dateNav.month === 1 ? 12 : dateNav.month - 1;
    const py = dateNav.month === 1 ? dateNav.year - 1 : dateNav.year;
    return data.summary(py, pm, accountStore.selected);
  });

  let saved = $derived(summary.income + summary.expenses);

  let savingsDelta = $derived.by(() => {
    const prevSaved = prevSummary.income + prevSummary.expenses;
    if (prevSaved === 0) return null;
    return Math.round(((saved - prevSaved) / Math.abs(prevSaved)) * 100);
  });

  // All transactions for this month
  let monthTransactions = $derived.by(() => {
    return data.transactions(accountStore.selected).filter((t: Transaction) => {
      const [ty, tm] = t.date.split("-").map(Number);
      return ty === dateNav.year && tm === dateNav.month;
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

    return items.toSorted(
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
    return results.toSorted((a, b) => b.increase - a.increase);
  });

  // Top spending categories
  let topCategories = $derived.by(() =>
    summary.by_category
      .filter((c) => c.id !== 10 && c.id !== 11 && c.amount !== 0)
      .toSorted((a, b) => Math.abs(b.amount) - Math.abs(a.amount))
      .slice(0, 5),
  );

  function savingsMessage(): string {
    if (saved > 0) return "Dein Sparziel wurde erreicht. Super Leistung!";
    if (saved === 0) return "Einnahmen und Ausgaben waren diesen Monat ausgeglichen.";
    return "Diesen Monat hast du mehr ausgegeben als eingenommen.";
  }
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
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">{monthNames[dateNav.month - 1]} Rückblick</h2>
  </div>

<MonthPicker bind:year={dateNav.year} bind:month={dateNav.month} />

{#if summary.tx_count > 0}
  <!-- Summary Hero Card -->
  <div class="bg-(--color-accent) rounded-[2rem] shadow-[var(--shadow-soft)] overflow-hidden relative mb-6">
    <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>

    <div class="flex w-full flex-col items-center gap-2 py-8 px-6 relative z-10 text-center" style="color: #1a1a1a">
      <p class="text-sm font-bold uppercase tracking-widest mb-2" style="opacity: 0.8">
        {saved >= 0 ? "Gespart" : "Defizit"}
      </p>
      <p class="text-5xl font-display font-black tracking-tighter">
        {Math.abs(saved) >= 10000 ? formatEurCompact(Math.abs(saved)) : formatEur(Math.abs(saved))}
      </p>
      {#if savingsDelta !== null}
        <div class="mt-4 inline-flex items-center justify-center px-3 py-1.5 rounded-full text-xs font-bold gap-1 shadow-md" style="background: #1a1a1a; color: white">
          {#if savingsDelta >= 0}
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 5l5 5H5l5-5z" />
            </svg>
          {:else}
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 15l-5-5h10l-5 5z" />
            </svg>
          {/if}
          <span>{savingsDelta >= 0 ? "+" : ""}{savingsDelta}% vs. {monthNames[dateNav.month === 1 ? 11 : dateNav.month - 2]}</span>
        </div>
      {/if}
      <p class="text-sm mt-4 font-medium leading-relaxed max-w-[280px]" style="opacity: 0.8">
        {savingsMessage()}
      </p>
    </div>

    <div class="px-6 pb-6 pt-2 grid grid-cols-2 gap-4 relative z-10">
      <div class="p-4 rounded-2xl flex flex-col items-center backdrop-blur-sm" style="background: rgba(255,255,255,0.4)">
        <p class="text-xs font-bold uppercase tracking-wider mb-1" style="color: rgba(26,26,26,0.7)">Einnahmen</p>
        <p class="font-extrabold text-lg" style="color: #1a1a1a">{summary.income >= 10000 ? formatEurCompact(summary.income) : formatEur(summary.income)}</p>
      </div>
      <div class="p-4 rounded-2xl flex flex-col items-center backdrop-blur-sm" style="background: rgba(255,255,255,0.4)">
        <p class="text-xs font-bold uppercase tracking-wider mb-1" style="color: rgba(26,26,26,0.7)">Ausgaben</p>
        <p class="font-extrabold text-lg" style="color: #1a1a1a">{Math.abs(summary.expenses) >= 10000 ? formatEurCompact(Math.abs(summary.expenses)) : formatEur(Math.abs(summary.expenses))}</p>
      </div>
    </div>
  </div>

  <!-- Top Categories -->
  {#if topCategories.length > 0}
    <div id="top-categories" class="mb-6">
      <a href="#top-categories" class="text-xl font-display font-extrabold mb-4 px-1 block">Top Kategorien</a>
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
    <div id="checklist" class="mb-6">
      <a href="#checklist" class="text-xl font-display font-extrabold mb-4 px-1 block">Zahlungs-Checkliste</a>
      <div class="space-y-3">
        {#each checklist as item}
          <div class="flex items-center justify-between gap-3 p-4 bg-white rounded-[1.5rem] shadow-[var(--shadow-card)]">
            <div class="flex items-center gap-3 min-w-0">
              <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <div class="min-w-0">
                <p class="text-sm font-bold truncate mb-0.5">
                  {item.description}
                </p>
                <p class="text-xs text-(--color-text-secondary) font-medium">
                  {formatDateShort(item.date)}
                </p>
              </div>
            </div>
            <p class="text-sm font-extrabold tabular-nums shrink-0">
              {Math.abs(item.amount) >= 10000 ? formatEurCompact(Math.abs(item.amount)) : formatEur(Math.abs(item.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Anomalies -->
  {#if anomalies.length > 0}
    <div id="anomalies" class="mb-6">
      <a href="#anomalies" class="text-xl font-display font-extrabold mb-4 px-1 block">Markierte Anomalien</a>
      <div class="space-y-3">
        {#each anomalies as anomaly}
          {@const pct = Math.round(
            (anomaly.increase / anomaly.previousAmount) * 100,
          )}
          <div class="p-5 rounded-[2rem] shadow-[var(--shadow-soft)] text-white relative overflow-hidden" style="background: #1a1a1a">
            <div class="absolute top-0 right-0 w-32 h-32 bg-indigo-500/20 rounded-full blur-2xl -mr-10 -mt-10"></div>
            <div class="flex gap-4 relative z-10">
              <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full" style="background: rgba(255,255,255,0.1)">
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
  <div id="stats" class="mb-6">
    <a href="#stats" class="text-xl font-display font-extrabold mb-4 px-1 block">Statistiken</a>
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
              new Date(dateNav.year, dateNav.month, 0).getDate() /
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
    <p class="text-sm mt-2 mb-4">Importiere Bankdaten um den Rückblick zu sehen</p>
    <a
      href="/import"
      class="inline-block px-5 py-2.5 rounded-full bg-(--color-text) text-white text-sm font-bold no-underline hover:opacity-90 transition-opacity"
    >CSV importieren</a>
  </div>
{/if}
