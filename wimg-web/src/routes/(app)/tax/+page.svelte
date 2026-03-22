<script lang="ts">
  import { data } from "$lib/data.svelte";
  import { formatEur, formatDate } from "$lib/format";
  import {
    TAX_CATEGORIES,
    DEFAULT_TAX_CONFIG,
    calcPendlerpauschale,
    calcHomeofficePauschale,
    matchTaxCategory,
    getCategoryKeywords,
    type TaxConfig,
    type TaxCategory,
  } from "$lib/tax";
  import EmptyState from "../../../components/EmptyState.svelte";

  const LS_TAX_KEY = "wimg_tax";

  function loadConfig(): TaxConfig {
    try {
      const stored = localStorage.getItem(LS_TAX_KEY);
      if (stored) return { ...DEFAULT_TAX_CONFIG, ...JSON.parse(stored) };
    } catch { /* ignore */ }
    return { ...DEFAULT_TAX_CONFIG };
  }

  function saveConfig() {
    localStorage.setItem(LS_TAX_KEY, JSON.stringify(config));
  }

  let config = $state(loadConfig());
  let activeFilter = $state<string | null>(null);
  let showKeywords = $state(false);
  let newKeyword = $state("");
  let newKeywordCat = $state(TAX_CATEGORIES[0].id);

  let hasAnyData = $derived(data.hasAnyData());

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
      if (tx.amount >= 0) continue;

      const cat = matchTaxCategory(tx.description, TAX_CATEGORIES, config.customKeywords);
      if (cat) {
        results.push({
          id: tx.id,
          description: tx.description,
          amount: Math.abs(tx.amount),
          date: tx.date,
          taxCategory: cat,
          included: !config.excluded.includes(tx.id),
        });
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

  let pendlerpauschale = $derived(calcPendlerpauschale(config.km, config.workDays));

  let pendlerFormula = $derived.by(() => {
    if (config.km <= 0 || config.workDays <= 0) return "";
    if (config.km <= 20) {
      return `${config.km}km × 0,30€ × ${config.workDays} Tage`;
    }
    return `20km × 0,30€ + ${config.km - 20}km × 0,38€ × ${config.workDays} Tage`;
  });

  let homeofficePauschale = $derived(calcHomeofficePauschale(config.homeofficeDays));

  let werbungskosten = $derived(includedTransactions.reduce((sum, t) => sum + t.amount, 0));
  let pauschalen = $derived(pendlerpauschale + homeofficePauschale);
  let gesamtabzug = $derived(werbungskosten + pauschalen);

  let prevYearTotal = $derived.by(() => {
    const txs = data.allTransactions();
    const prevYear = String(config.year - 1);
    let total = 0;
    for (const tx of txs) {
      if (!tx.date.startsWith(prevYear)) continue;
      if (tx.amount >= 0) continue;
      if (matchTaxCategory(tx.description, TAX_CATEGORIES, config.customKeywords)) {
        total += Math.abs(tx.amount);
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

  function addCustomKeyword() {
    const kw = newKeyword.trim().toLowerCase();
    if (!kw) return;
    if (!config.customKeywords[newKeywordCat]) {
      config.customKeywords[newKeywordCat] = [];
    }
    if (!config.customKeywords[newKeywordCat].includes(kw)) {
      config.customKeywords = {
        ...config.customKeywords,
        [newKeywordCat]: [...config.customKeywords[newKeywordCat], kw],
      };
      saveConfig();
    }
    newKeyword = "";
  }

  function removeCustomKeyword(catId: string, keyword: string) {
    config.customKeywords = {
      ...config.customKeywords,
      [catId]: (config.customKeywords[catId] ?? []).filter((k) => k !== keyword),
    };
    saveConfig();
  }

  let allCustomKeywords = $derived.by(() => {
    const items: { catId: string; catLabel: string; keyword: string }[] = [];
    for (const cat of TAX_CATEGORIES) {
      for (const kw of config.customKeywords[cat.id] ?? []) {
        items.push({ catId: cat.id, catLabel: cat.label, keyword: kw });
      }
    }
    return items;
  });

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

<!-- Custom Keywords -->
<div class="bg-white rounded-[2rem] p-6 shadow-[var(--shadow-soft)] mb-5">
  <button
    onclick={() => (showKeywords = !showKeywords)}
    class="flex items-center justify-between w-full cursor-pointer"
  >
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 bg-orange-50 rounded-xl flex items-center justify-center text-orange-600">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
        </svg>
      </div>
      <div class="text-left">
        <h3 class="font-display font-extrabold text-lg">Eigene Schlüsselwörter</h3>
        <p class="text-xs text-(--color-text-secondary)">Zusätzliche Begriffe für die Erkennung</p>
      </div>
    </div>
    <svg
      class="w-4 h-4 text-(--color-text-secondary) transition-transform {showKeywords ? 'rotate-180' : ''}"
      fill="none" stroke="currentColor" viewBox="0 0 24 24"
    >
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
    </svg>
  </button>

  {#if showKeywords}
    <div class="mt-5 space-y-4">
      <!-- Add form -->
      <div class="flex gap-2">
        <input
          type="text"
          placeholder="z.B. amazon, bücher.de"
          bind:value={newKeyword}
          onkeydown={(e) => e.key === "Enter" && addCustomKeyword()}
          class="flex-1 bg-gray-50 border-none rounded-xl focus:ring-2 focus:ring-(--color-accent) text-sm py-2.5 px-4"
        />
        <select
          bind:value={newKeywordCat}
          class="appearance-none bg-gray-50 border-none rounded-xl text-xs font-bold py-2.5 px-3 pr-7 focus:ring-2 focus:ring-(--color-accent)"
        >
          {#each TAX_CATEGORIES as cat}
            <option value={cat.id}>{cat.icon} {cat.label}</option>
          {/each}
        </select>
        <button
          onclick={addCustomKeyword}
          class="px-4 py-2.5 bg-(--color-accent) rounded-xl text-sm font-bold cursor-pointer hover:bg-(--color-accent-hover) transition-colors"
          aria-label="Schlüsselwort hinzufügen"
        >
          +
        </button>
      </div>

      <!-- Existing custom keywords -->
      {#if allCustomKeywords.length > 0}
        <div class="flex flex-wrap gap-2">
          {#each allCustomKeywords as { catId, catLabel, keyword }}
            <span class="inline-flex items-center gap-1.5 bg-gray-50 rounded-full pl-3 pr-1.5 py-1.5 text-xs font-medium">
              <span class="text-(--color-text-secondary)">{catLabel}:</span>
              <span class="font-bold">{keyword}</span>
              <button
                onclick={() => removeCustomKeyword(catId, keyword)}
                aria-label="Keyword {keyword} entfernen"
                class="w-5 h-5 flex items-center justify-center rounded-full hover:bg-gray-200 text-gray-400 hover:text-rose-500 transition-colors cursor-pointer"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </span>
          {/each}
        </div>
      {:else}
        <p class="text-xs text-(--color-text-secondary) italic">Noch keine eigenen Schlüsselwörter. Füge Begriffe hinzu, die in deinen Transaktionsbeschreibungen vorkommen.</p>
      {/if}
    </div>
  {/if}
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
                {formatDate(tx.date)}
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

<!-- Info links -->
<div class="flex flex-col items-center gap-1.5 mb-4">
  <a
    href="/about#faq-steuern"
    class="text-xs font-medium text-(--color-text-secondary) hover:text-(--color-text) transition-colors underline underline-offset-2"
  >
    Woher kommen die Berechnungen?
  </a>
  <a
    href="https://www.gesetze-im-internet.de/estg/__9.html"
    target="_blank"
    rel="noopener noreferrer"
    class="text-[10px] font-medium text-(--color-text-secondary)/50 hover:text-(--color-text-secondary) transition-colors"
  >
    §9 EStG — Werbungskosten (gesetze-im-internet.de)
  </a>
</div>

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
