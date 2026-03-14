<script lang="ts">
  import { data } from "$lib/data.svelte";
  import { formatEur } from "$lib/format";
  import EmptyState from "../../../components/EmptyState.svelte";

  const LS_TAX_KEY = "wimg_tax";

  interface TaxConfig {
    year: number;
    km: number;
    workDays: number;
    homeofficeDays: number;
    excluded: string[]; // transaction IDs excluded from tax
  }

  interface TaxCategory {
    id: string;
    label: string;
    icon: string;
    color: string;
    textColor: string;
    keywords: string[];
  }

  const TAX_CATEGORIES: TaxCategory[] = [
    {
      id: "arbeitsmittel",
      label: "Arbeitsmittel",
      icon: "💻",
      color: "bg-blue-100",
      textColor: "text-blue-700",
      keywords: ["apple", "mediamarkt", "saturn", "büro", "computer", "laptop", "monitor", "tastatur", "logitech", "dell", "lenovo", "thinkpad", "macbook", "ipad"],
    },
    {
      id: "fortbildung",
      label: "Fortbildung",
      icon: "📚",
      color: "bg-emerald-100",
      textColor: "text-emerald-700",
      keywords: ["udemy", "coursera", "kurs", "seminar", "weiterbildung", "fortbildung", "schulung", "linkedin learning", "pluralsight"],
    },
    {
      id: "fachliteratur",
      label: "Fachliteratur",
      icon: "📖",
      color: "bg-violet-100",
      textColor: "text-violet-700",
      keywords: ["fachbuch", "o'reilly", "manning", "apress", "springer", "thalia fach"],
    },
    {
      id: "fahrtkosten",
      label: "Fahrtkosten",
      icon: "🚆",
      color: "bg-amber-100",
      textColor: "text-amber-700",
      keywords: ["deutsche bahn", "db fernverkehr", "db regio", "flixbus", "flixtrain", "bvg", "mvv", "hvv", "rheinbahn", "kvb"],
    },
    {
      id: "versicherung",
      label: "Versicherungen",
      icon: "🛡️",
      color: "bg-rose-100",
      textColor: "text-rose-700",
      keywords: ["berufshaftpflicht", "rechtsschutz", "berufsunfähigkeit"],
    },
  ];

  function loadConfig(): TaxConfig {
    try {
      const stored = localStorage.getItem(LS_TAX_KEY);
      if (stored) return JSON.parse(stored);
    } catch { /* ignore */ }
    return { year: new Date().getFullYear(), km: 0, workDays: 220, homeofficeDays: 0, excluded: [] };
  }

  function saveConfig() {
    localStorage.setItem(LS_TAX_KEY, JSON.stringify(config));
  }

  let config = $state(loadConfig());
  let activeFilter = $state<string | null>(null);

  let hasAnyData = $derived(data.hasAnyData());

  // Scan transactions for tax-relevant keywords
  interface TaggedTx {
    id: string;
    description: string;
    amount: number;
    date: string;
    taxCategory: TaxCategory;
    included: boolean;
  }

  let taggedTransactions = $derived.by(() => {
    const txs = data.allTransactions();
    const results: TaggedTx[] = [];
    const yearStr = String(config.year);

    for (const tx of txs) {
      if (!tx.date.startsWith(yearStr)) continue;
      if (tx.amount >= 0) continue; // only expenses

      const descLower = tx.description.toLowerCase();
      for (const cat of TAX_CATEGORIES) {
        if (cat.keywords.some((kw) => descLower.includes(kw))) {
          results.push({
            id: tx.id,
            description: tx.description,
            amount: Math.abs(tx.amount),
            date: tx.date,
            taxCategory: cat,
            included: !config.excluded.includes(tx.id),
          });
          break; // first match wins
        }
      }
    }

    return results.toSorted((a, b) => b.date.localeCompare(a.date));
  });

  let filteredTransactions = $derived(
    activeFilter
      ? taggedTransactions.filter((t) => t.taxCategory.id === activeFilter)
      : taggedTransactions,
  );

  let includedTransactions = $derived(taggedTransactions.filter((t) => t.included));

  // Pendlerpauschale calculation
  let pendlerpauschale = $derived.by(() => {
    if (config.km <= 0 || config.workDays <= 0) return 0;
    const first20 = Math.min(config.km, 20) * 0.30;
    const beyond20 = Math.max(config.km - 20, 0) * 0.38;
    return (first20 + beyond20) * config.workDays;
  });

  let pendlerFormula = $derived.by(() => {
    if (config.km <= 0 || config.workDays <= 0) return "";
    if (config.km <= 20) {
      return `${config.km}km × 0,30€ × ${config.workDays} Tage`;
    }
    return `20km × 0,30€ + ${config.km - 20}km × 0,38€ × ${config.workDays} Tage`;
  });

  // Homeoffice calculation
  let homeofficePauschale = $derived(Math.min(config.homeofficeDays, 210) * 6);

  // Totals
  let werbungskosten = $derived(includedTransactions.reduce((sum, t) => sum + t.amount, 0));
  let pauschalen = $derived(pendlerpauschale + homeofficePauschale);
  let gesamtabzug = $derived(werbungskosten + pauschalen);

  // Previous year comparison
  let prevYearTotal = $derived.by(() => {
    const txs = data.allTransactions();
    const prevYear = String(config.year - 1);
    let total = 0;
    for (const tx of txs) {
      if (!tx.date.startsWith(prevYear)) continue;
      if (tx.amount >= 0) continue;
      const descLower = tx.description.toLowerCase();
      for (const cat of TAX_CATEGORIES) {
        if (cat.keywords.some((kw) => descLower.includes(kw))) {
          total += Math.abs(tx.amount);
          break;
        }
      }
    }
    return total;
  });

  let progressVsPrev = $derived(prevYearTotal > 0 ? Math.round((gesamtabzug / prevYearTotal) * 100) : 0);

  function toggleTransaction(txId: string) {
    if (config.excluded.includes(txId)) {
      config.excluded = config.excluded.filter((id) => id !== txId);
    } else {
      config.excluded = [...config.excluded, txId];
    }
    saveConfig();
  }

  function handleConfigChange() {
    saveConfig();
  }

  function exportCsv() {
    const lines = ["Datum;Beschreibung;Betrag;Kategorie"];
    for (const tx of includedTransactions) {
      lines.push(`${tx.date};${tx.description};${tx.amount.toFixed(2)};${tx.taxCategory.label}`);
    }
    if (pendlerpauschale > 0) {
      lines.push(`;Pendlerpauschale (${config.km}km × ${config.workDays} Tage);${pendlerpauschale.toFixed(2)};Pauschale`);
    }
    if (homeofficePauschale > 0) {
      lines.push(`;Homeoffice-Pauschale (${config.homeofficeDays} Tage);${homeofficePauschale.toFixed(2)};Pauschale`);
    }
    lines.push(`;;${gesamtabzug.toFixed(2)};GESAMT`);

    const blob = new Blob([lines.join("\n")], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `wimg-steuern-${config.year}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // Available years from transactions
  let availableYears = $derived.by(() => {
    const txs = data.allTransactions();
    const years = new Set<number>();
    for (const tx of txs) {
      const y = Number.parseInt(tx.date.split("-")[0]);
      if (!Number.isNaN(y)) years.add(y);
    }
    return [...years].toSorted((a, b) => b - a);
  });
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
  <h2 class="text-2xl font-display font-extrabold text-(--color-text)">Steuern</h2>
</div>

{#if !hasAnyData}
  <EmptyState
    title="Keine Transaktionen"
    subtitle="Importiere eine CSV-Datei um steuerlich relevante Ausgaben zu erkennen."
  >
    {#snippet icon()}
      <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16l3.5-2 3.5 2 3.5-2 3.5 2z" />
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

<!-- Hero Card -->
<div class="bg-(--color-accent) rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
  <div class="absolute -right-4 -top-4 w-24 h-24 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>
  <div class="flex justify-between items-start mb-2 relative z-10">
    <p class="uppercase text-xs font-bold tracking-wider text-(--color-text)/60">Absetzbare Ausgaben</p>
    <div class="relative">
      <select
        bind:value={config.year}
        onchange={handleConfigChange}
        class="appearance-none bg-white/40 pl-3 pr-8 py-1.5 rounded-full text-xs font-bold border-none focus:ring-0 cursor-pointer"
      >
        {#each availableYears as year}
          <option value={year}>{year}</option>
        {/each}
        {#if availableYears.length === 0}
          <option value={config.year}>{config.year}</option>
        {/if}
      </select>
      <svg class="absolute right-2.5 top-1/2 -translate-y-1/2 w-3 h-3 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 9l6 6 6-6" />
      </svg>
    </div>
  </div>
  <div class="space-y-1 relative z-10">
    <p class="font-display font-extrabold text-4xl text-(--color-text)">
      {formatEur(gesamtabzug)}
    </p>
    <p class="text-sm text-(--color-text)/70">Geschätztes Steuerjahr {config.year}</p>
  </div>
  {#if prevYearTotal > 0}
    <div class="mt-5 flex items-center gap-2 relative z-10">
      <div class="h-1.5 flex-1 bg-white/30 rounded-full overflow-hidden">
        <div
          class="bg-(--color-text) h-full rounded-full transition-all"
          style="width: {Math.min(progressVsPrev, 100)}%"
        ></div>
      </div>
      <span class="text-[10px] font-bold text-(--color-text)/60">{progressVsPrev}% von {config.year - 1}</span>
    </div>
  {/if}
</div>

<!-- Summary Grid -->
<div class="grid grid-cols-3 gap-3 mb-5">
  <div class="bg-white rounded-2xl p-3 shadow-[var(--shadow-card)] text-center">
    <p class="text-[10px] uppercase font-bold text-(--color-text-secondary) mb-1">Werbung</p>
    <p class="font-bold text-sm">{formatEur(werbungskosten)}</p>
  </div>
  <div class="bg-white rounded-2xl p-3 shadow-[var(--shadow-card)] text-center">
    <p class="text-[10px] uppercase font-bold text-(--color-text-secondary) mb-1">Pauschalen</p>
    <p class="font-bold text-sm">{formatEur(pauschalen)}</p>
  </div>
  <div class="bg-white rounded-2xl p-3 shadow-[var(--shadow-card)] text-center">
    <p class="text-[10px] uppercase font-bold text-(--color-text-secondary) mb-1">Gesamt</p>
    <p class="font-bold text-sm">{formatEur(gesamtabzug)}</p>
  </div>
</div>

<!-- Pendlerpauschale -->
<div class="bg-white rounded-[2rem] p-6 shadow-[var(--shadow-soft)] mb-4">
  <div class="flex items-center gap-3 mb-5">
    <div class="w-10 h-10 bg-blue-50 rounded-xl flex items-center justify-center text-blue-600">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
      </svg>
    </div>
    <h3 class="font-display font-extrabold text-lg">Pendlerpauschale</h3>
  </div>
  <div class="grid grid-cols-2 gap-4 mb-5">
    <label class="space-y-1.5">
      <span class="text-[11px] font-bold text-(--color-text-secondary) uppercase px-1">Entfernung (km)</span>
      <input
        type="number"
        bind:value={config.km}
        oninput={handleConfigChange}
        min="0"
        class="w-full bg-gray-50 border-none rounded-xl focus:ring-2 focus:ring-(--color-accent) font-bold py-3 px-4"
      />
    </label>
    <label class="space-y-1.5">
      <span class="text-[11px] font-bold text-(--color-text-secondary) uppercase px-1">Arbeitstage</span>
      <input
        type="number"
        bind:value={config.workDays}
        oninput={handleConfigChange}
        min="0"
        max="365"
        class="w-full bg-gray-50 border-none rounded-xl focus:ring-2 focus:ring-(--color-accent) font-bold py-3 px-4"
      />
    </label>
  </div>
  {#if pendlerpauschale > 0}
    <div class="bg-gray-50 rounded-2xl p-4 flex justify-between items-center">
      <div>
        <p class="text-xs text-(--color-text-secondary) italic">{pendlerFormula}</p>
        <p class="font-display font-extrabold text-xl mt-0.5">{formatEur(pendlerpauschale)}</p>
      </div>
      <div class="bg-emerald-100 text-emerald-700 px-3 py-1 rounded-full text-[10px] font-bold">Aktiv</div>
    </div>
  {/if}
</div>

<!-- Homeoffice -->
<div class="bg-white rounded-[2rem] p-6 shadow-[var(--shadow-soft)] mb-5">
  <div class="flex items-center gap-3 mb-5">
    <div class="w-10 h-10 bg-purple-50 rounded-xl flex items-center justify-center text-purple-600">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
      </svg>
    </div>
    <h3 class="font-display font-extrabold text-lg">Homeoffice</h3>
  </div>
  <label class="block space-y-1.5 mb-5">
    <span class="text-[11px] font-bold text-(--color-text-secondary) uppercase px-1">Anzahl Homeoffice-Tage</span>
    <div class="relative">
      <input
        type="number"
        bind:value={config.homeofficeDays}
        oninput={handleConfigChange}
        min="0"
        max="210"
        class="w-full bg-gray-50 border-none rounded-xl focus:ring-2 focus:ring-(--color-accent) font-bold py-3 px-4 pr-16"
      />
      <div class="absolute right-4 top-1/2 -translate-y-1/2 text-(--color-text-secondary) text-xs font-bold">TAGE</div>
    </div>
  </label>
  <div class="flex justify-between items-center">
    <p class="text-sm font-medium text-(--color-text-secondary)">6 €/Tag (max. 210 Tage)</p>
    <p class="font-display font-extrabold text-lg">{formatEur(homeofficePauschale)}</p>
  </div>
</div>

<!-- Tagged Transactions -->
{#if taggedTransactions.length > 0}
  <div class="pt-2 mb-5">
    <div class="flex justify-between items-end px-1 mb-4">
      <h3 class="font-display font-extrabold text-xl">Erkannte Ausgaben</h3>
      <span class="text-xs font-bold text-(--color-text-secondary)">{includedTransactions.length} von {taggedTransactions.length}</span>
    </div>

    <!-- Filter Chips -->
    <div class="flex gap-2 overflow-x-auto -mx-5 px-5 mb-4" style="scrollbar-width: none;">
      <button
        onclick={() => (activeFilter = null)}
        class="px-4 py-2 rounded-full text-xs font-semibold whitespace-nowrap transition-colors {activeFilter === null ? 'bg-(--color-text) text-white' : 'bg-white border border-gray-100'}"
      >
        Alle
      </button>
      {#each TAX_CATEGORIES as cat}
        {@const count = taggedTransactions.filter((t) => t.taxCategory.id === cat.id).length}
        {#if count > 0}
          <button
            onclick={() => (activeFilter = activeFilter === cat.id ? null : cat.id)}
            class="px-4 py-2 rounded-full text-xs font-semibold whitespace-nowrap transition-colors {activeFilter === cat.id ? 'bg-(--color-text) text-white' : 'bg-white border border-gray-100'}"
          >
            {cat.label} ({count})
          </button>
        {/if}
      {/each}
    </div>

    <!-- Transaction Cards -->
    <div class="space-y-3">
      {#each filteredTransactions as tx}
        <div class="bg-white p-4 rounded-3xl shadow-[var(--shadow-card)] flex items-center gap-4">
          <div class="w-12 h-12 bg-gray-100 rounded-2xl flex items-center justify-center text-xl shrink-0">
            {tx.taxCategory.icon}
          </div>
          <div class="flex-1 min-w-0">
            <h4 class="font-bold text-sm truncate" class:opacity-40={!tx.included}>{tx.description}</h4>
            <div class="flex items-center gap-2 mt-1">
              <span class="{tx.taxCategory.color} {tx.taxCategory.textColor} text-[9px] font-bold px-2 py-0.5 rounded-full uppercase">
                {tx.taxCategory.label}
              </span>
              <span class="text-[10px] text-(--color-text-secondary)">
                {new Date(tx.date + "T00:00:00").toLocaleDateString("de-DE", { day: "numeric", month: "short", year: "numeric" })}
              </span>
            </div>
          </div>
          <div class="text-right flex flex-col items-end gap-2 shrink-0">
            <p class="font-bold" class:opacity-40={!tx.included}>{formatEur(tx.amount)}</p>
            <label class="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={tx.included}
                onchange={() => toggleTransaction(tx.id)}
                class="sr-only peer"
              />
              <div class="w-9 h-5 bg-gray-200 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-(--color-text)"></div>
            </label>
          </div>
        </div>
      {/each}
    </div>
  </div>
{/if}

<!-- Export Button -->
<button
  onclick={exportCsv}
  class="w-full bg-(--color-text) text-white font-display font-extrabold py-4 rounded-full shadow-xl hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-3 mb-5"
>
  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3" />
  </svg>
  Als CSV exportieren
</button>

{/if}
