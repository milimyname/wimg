<script lang="ts">
  import {
    getSummary,
    getTransactions,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import MonthPicker from "../../components/MonthPicker.svelte";

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

  const monthNames = [
    "Januar",
    "Februar",
    "März",
    "April",
    "Mai",
    "Juni",
    "Juli",
    "August",
    "September",
    "Oktober",
    "November",
    "Dezember",
  ];

  const now = new Date();
  let year = $state(now.getFullYear());
  let month = $state(now.getMonth() + 1);

  let summary = $derived.by(() => getSummary(year, month));

  let prevSummary = $derived.by(() => {
    const pm = month === 1 ? 12 : month - 1;
    const py = month === 1 ? year - 1 : year;
    return getSummary(py, pm);
  });

  let saved = $derived(summary.income + summary.expenses);

  let savingsDelta = $derived.by(() => {
    const prevSaved = prevSummary.income + prevSummary.expenses;
    if (prevSaved === 0) return null;
    return Math.round(((saved - prevSaved) / Math.abs(prevSaved)) * 100);
  });

  // All transactions for this month
  let monthTransactions = $derived.by(() => {
    return getTransactions().filter((t: Transaction) => {
      const [ty, tm] = t.date.split("-").map(Number);
      return ty === year && tm === month;
    });
  });

  // Recurring / expected payments detection:
  // Group by category, find the largest expense per category as "expected" payments
  type ChecklistItem = {
    description: string;
    amount: number;
    category: number;
    date: string;
    paid: boolean;
  };

  let checklist = $derived.by((): ChecklistItem[] => {
    // Categories typically associated with recurring bills
    const recurringCats = [4, 5, 9, 13]; // Housing, Utilities, Insurance, Subscriptions
    const items: ChecklistItem[] = [];

    for (const catId of recurringCats) {
      const txns = monthTransactions.filter(
        (t) => t.category === catId && t.amount < 0,
      );
      if (txns.length > 0) {
        // Take the largest expense per category
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

  // Anomaly detection: find categories with significant spending increases
  type Anomaly = {
    category: number;
    currentAmount: number;
    previousAmount: number;
    increase: number;
  };

  let anomalies = $derived.by((): Anomaly[] => {
    const results: Anomaly[] = [];
    for (const cat of summary.by_category) {
      if (cat.id === 10 || cat.id === 11) continue; // skip income/transfer
      const prevCat = prevSummary.by_category.find((c) => c.id === cat.id);
      if (!prevCat || prevCat.amount === 0) continue;
      const increase =
        Math.abs(cat.amount) - Math.abs(prevCat.amount);
      const pct =
        (increase / Math.abs(prevCat.amount)) * 100;
      if (increase > 500 && pct > 10) {
        // > 5€ increase AND > 10%
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

  function formatEur(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
    }).format(amount);
  }

  function formatDate(dateStr: string): string {
    const d = new Date(dateStr + "T00:00:00");
    return d.toLocaleDateString("de-DE", { day: "2-digit", month: "short" });
  }

  function savingsMessage(): string {
    if (saved > 0) return "Dein Sparziel wurde erreicht. Super Leistung!";
    if (saved === 0)
      return "Einnahmen und Ausgaben waren diesen Monat ausgeglichen.";
    return "Diesen Monat hast du mehr ausgegeben als eingenommen.";
  }
</script>

<h2 class="text-lg font-bold text-center mb-4">
  {monthNames[month - 1]} Rückblick
</h2>

<MonthPicker bind:year bind:month />

{#if summary.tx_count > 0}
  <!-- Summary Hero Card -->
  <div
    class="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden mb-5"
  >
    <!-- Gradient Header -->
    <div
      class="h-28 flex items-center justify-center"
      style="background: linear-gradient(135deg, var(--color-primary-light, #e8e0ff) 0%, var(--color-primary-bg, #f3f0ff) 100%)"
    >
      <div class="text-center">
        <span class="text-4xl mb-1 block">📈</span>
        <p
          class="text-xs font-bold uppercase tracking-wider"
          style="color: var(--color-primary)"
        >
          {saved >= 0 ? "Ersparnis" : "Defizit"}
        </p>
      </div>
    </div>

    <!-- Content -->
    <div class="px-5 py-4">
      <p class="text-sm text-gray-400 font-medium">Übersicht</p>
      <div class="flex items-center justify-between mt-1">
        <p
          class="text-2xl font-bold tracking-tight"
          class:text-emerald-600={saved >= 0}
          class:text-rose-600={saved < 0}
        >
          {saved >= 0 ? "Gespart" : "Defizit"} {formatEur(Math.abs(saved))}
        </p>
        {#if savingsDelta !== null}
          <span
            class="px-2 py-1 rounded-full text-[10px] font-bold"
            class:bg-emerald-50={savingsDelta >= 0}
            class:text-emerald-700={savingsDelta >= 0}
            class:bg-rose-50={savingsDelta < 0}
            class:text-rose-700={savingsDelta < 0}
          >
            {savingsDelta >= 0 ? "+" : ""}{savingsDelta}%
          </span>
        {/if}
      </div>
      <p class="text-sm text-gray-500 mt-2 leading-relaxed">
        {savingsMessage()}
      </p>
    </div>

    <!-- Income / Expenses -->
    <div class="px-5 pb-5 grid grid-cols-2 gap-4">
      <div class="bg-gray-50 p-3 rounded-lg">
        <p class="text-[10px] font-bold uppercase text-gray-400">Einnahmen</p>
        <p class="font-bold">{formatEur(summary.income)}</p>
      </div>
      <div class="bg-gray-50 p-3 rounded-lg">
        <p class="text-[10px] font-bold uppercase text-gray-400">Ausgaben</p>
        <p class="font-bold">{formatEur(Math.abs(summary.expenses))}</p>
      </div>
    </div>
  </div>

  <!-- Top Categories -->
  {#if topCategories.length > 0}
    <div class="mb-5">
      <h3 class="text-base font-bold mb-3">Top Kategorien</h3>
      <div class="space-y-2">
        {#each topCategories as cat}
          {@const pct =
            Math.abs(summary.expenses) > 0
              ? Math.round(
                  (Math.abs(cat.amount) / Math.abs(summary.expenses)) * 100,
                )
              : 0}
          <div
            class="flex items-center gap-3 p-3 bg-white rounded-xl border border-gray-100"
          >
            <div
              class="w-10 h-10 rounded-full flex items-center justify-center text-lg"
              style="background-color: {CATEGORIES[cat.id]?.color ?? '#dfe6e9'}20"
            >
              {CATEGORY_ICONS[cat.id] ?? "📦"}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between mb-1">
                <p class="text-sm font-semibold truncate">{cat.name}</p>
                <p class="text-sm font-bold tabular-nums">
                  {formatEur(Math.abs(cat.amount))}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <div class="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all"
                    style="width: {pct}%; background-color: {CATEGORIES[cat.id]
                      ?.color ?? '#dfe6e9'}"
                  ></div>
                </div>
                <span class="text-xs text-gray-400 font-medium tabular-nums w-8 text-right"
                  >{pct}%</span
                >
              </div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Payment Checklist -->
  {#if checklist.length > 0}
    <div class="mb-5">
      <h3 class="text-base font-bold mb-3">Zahlungs-Checkliste</h3>
      <div class="space-y-2">
        {#each checklist as item}
          <div
            class="flex items-center justify-between p-4 bg-white rounded-xl border border-gray-100"
          >
            <div class="flex items-center gap-3">
              <div
                class="flex h-10 w-10 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"
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
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              </div>
              <div>
                <p class="text-sm font-semibold truncate max-w-[180px]">
                  {item.description}
                </p>
                <p class="text-xs text-gray-400">
                  Abgeschlossen am {formatDate(item.date)}
                </p>
              </div>
            </div>
            <p class="text-sm font-medium tabular-nums text-gray-600">
              {formatEur(Math.abs(item.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Anomalies -->
  {#if anomalies.length > 0}
    <div class="mb-5">
      <h3 class="text-base font-bold mb-3">Markierte Anomalien</h3>
      <div class="space-y-3">
        {#each anomalies as anomaly}
          {@const pct = Math.round(
            (anomaly.increase / anomaly.previousAmount) * 100,
          )}
          <div
            class="p-4 rounded-xl border"
            style="background-color: var(--color-primary-bg, #f8f6ff); border-color: var(--color-primary-light, #e8e0ff)"
          >
            <div class="flex gap-3">
              <span class="text-xl">⚠️</span>
              <div>
                <p class="text-sm font-bold">Preiserhöhung erkannt</p>
                <p class="text-xs text-gray-500 mt-1 leading-relaxed">
                  Deine <strong
                    >{CATEGORIES[anomaly.category]?.name ?? "Sonstiges"}</strong
                  >-Kosten sind um {formatEur(anomaly.increase / 100)} gestiegen
                  ({pct}% mehr als im Vormonat).
                </p>
                <div class="flex items-center gap-4 mt-2 text-xs text-gray-400">
                  <span
                    >Vormonat: {formatEur(anomaly.previousAmount / 100)}</span
                  >
                  <span>Aktuell: {formatEur(anomaly.currentAmount / 100)}</span>
                </div>
              </div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {:else if prevSummary.tx_count > 0}
    <div class="mb-5">
      <h3 class="text-base font-bold mb-3">Markierte Anomalien</h3>
      <div class="p-4 bg-emerald-50 rounded-xl border border-emerald-100">
        <div class="flex gap-3">
          <span class="text-xl">✅</span>
          <div>
            <p class="text-sm font-bold text-emerald-800">
              Keine Auffälligkeiten
            </p>
            <p class="text-xs text-emerald-600 mt-1">
              Keine ungewöhnlichen Preiserhöhungen in diesem Monat erkannt.
            </p>
          </div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Monthly Stats -->
  <div class="mb-5">
    <h3 class="text-base font-bold mb-3">Statistiken</h3>
    <div class="grid grid-cols-2 gap-3">
      <div class="bg-white rounded-xl border border-gray-100 p-4">
        <p class="text-xs text-gray-400 font-medium">Transaktionen</p>
        <p class="text-2xl font-bold mt-1">{summary.tx_count}</p>
      </div>
      <div class="bg-white rounded-xl border border-gray-100 p-4">
        <p class="text-xs text-gray-400 font-medium">Kategorien</p>
        <p class="text-2xl font-bold mt-1">
          {summary.by_category.filter((c) => c.count > 0).length}
        </p>
      </div>
      <div class="bg-white rounded-xl border border-gray-100 p-4">
        <p class="text-xs text-gray-400 font-medium">Ausgaben/Tag</p>
        <p class="text-lg font-bold mt-1">
          {formatEur(
            Math.abs(summary.expenses) /
              new Date(year, month, 0).getDate() /
              100,
          )}
        </p>
      </div>
      <div class="bg-white rounded-xl border border-gray-100 p-4">
        <p class="text-xs text-gray-400 font-medium">Sparquote</p>
        <p
          class="text-lg font-bold mt-1"
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
  <div class="text-center py-16 text-gray-400">
    <p class="text-3xl mb-3">📋</p>
    <p class="font-medium">Keine Daten für diesen Monat</p>
    <p class="text-sm mt-1">
      <a href="/import" class="font-medium" style="color: var(--color-primary)"
        >CSV importieren</a
      > um zu starten
    </p>
  </div>
{/if}
