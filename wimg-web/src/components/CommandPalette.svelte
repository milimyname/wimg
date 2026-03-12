<script lang="ts">
  import { goto } from "$app/navigation";
  import { page } from "$app/state";
  import { ACTIONS, type PaletteAction } from "$lib/actions";
  import { paletteStore } from "$lib/commandPalette.svelte";
  import {
    getTransactions,
    semanticSearch,
    isModelLoaded,
    loadEmbeddingModel,
    embeddingStatus,
    CATEGORIES,
    type Transaction,
    type SemanticSearchResult,
  } from "$lib/wasm";
  import { formatAmountSigned, formatDateShort } from "$lib/format";
  import { toastStore } from "$lib/toast.svelte";
  import BottomSheet from "./BottomSheet.svelte";

  let inputEl = $state<HTMLInputElement | null>(null);
  let resultsEl = $state<HTMLDivElement | null>(null);
  let query = $state("");
  let selectedIndex = $state(0);
  let confirmingAction = $state<PaletteAction | null>(null);
  let semanticResults = $state<SemanticSearchResult[]>([]);
  let semanticLoading = $state(false);
  let semanticTimer: ReturnType<typeof setTimeout> | null = null;
  let expandedMerchant = $state<string | null>(null);
  let modelLoaded = $state(false);
  let modelAutoLoading = $state(false);

  // Derive open from shallow routing state (same pattern as transactions page)
  let showPalette = $derived(page.state.sheet === "command-palette");

  // Auto-load model when palette opens (if embeddings exist but model not loaded)
  $effect(() => {
    if (showPalette) {
      modelLoaded = isModelLoaded();
      if (!modelLoaded && !modelAutoLoading) {
        try {
          const status = embeddingStatus();
          if (status.embedded > 0) {
            modelAutoLoading = true;
            loadEmbeddingModel().then(() => {
              modelLoaded = true;
              modelAutoLoading = false;
            }).catch(() => {
              modelAutoLoading = false;
            });
          }
        } catch { /* wasm not ready */ }
      }
    }
  });

  // Auto-focus input when sheet opens
  $effect(() => {
    if (inputEl && showPalette) {
      setTimeout(() => inputEl?.focus(), 200);
    }
  });

  // Reset state when palette is fully closed (after animation)
  $effect(() => {
    if (!paletteStore.open) {
      query = "";
      selectedIndex = 0;
      confirmingAction = null;
      semanticResults = [];
      semanticLoading = false;
      expandedMerchant = null;
    }
  });

  // Debounced semantic search — fetch more results for merchant grouping
  $effect(() => {
    const q = query;
    if (semanticTimer) clearTimeout(semanticTimer);
    if (!q || q.length < 2 || !modelLoaded) {
      semanticResults = [];
      semanticLoading = false;
      return;
    }
    semanticLoading = true;
    semanticTimer = setTimeout(() => {
      try {
        semanticResults = semanticSearch(q, 30);
        if (semanticResults.length > 0) {
          console.log(`[semantic] query="${q}", top results:`, semanticResults.slice(0, 5).map(r => `${r.description.slice(0, 30)}… sim=${r.similarity.toFixed(4)}`));
        }
      } catch {
        semanticResults = [];
      }
      semanticLoading = false;
    }, 300);
  });

  // Filter actions by query
  const filteredActions = $derived.by(() => {
    const q = query.toLowerCase().trim();
    const available = ACTIONS.filter((a) => !a.enabled || a.enabled());
    const showDanger =
      q.includes("reset") || q.includes("danger") || q.includes("löschen");
    return available.filter((a) => {
      if (a.group === "Danger Zone" && !showDanger) return false;
      if (!q) return a.group !== "Danger Zone";
      return (
        a.label.toLowerCase().includes(q) ||
        a.keywords.some((k) => k.includes(q))
      );
    });
  });

  // Fuzzy transaction search
  const fuzzyTxResults = $derived.by(() => {
    const q = query.toLowerCase().trim();
    if (!q || q.length < 2) return [];
    try {
      return getTransactions()
        .filter((t) => t.description.toLowerCase().includes(q))
        .slice(0, 8);
    } catch {
      return [];
    }
  });

  // Deduplicated semantic results
  const deduplicatedSemantic = $derived.by(() => {
    const fuzzyIds = new Set(fuzzyTxResults.map((t) => t.id));
    return semanticResults.filter((r) => !fuzzyIds.has(r.id));
  });

  const hasSemanticResults = $derived(deduplicatedSemantic.length > 0);

  // --- Merchant grouping for semantic results ---

  interface MerchantGroup {
    merchant: string;
    count: number;
    totalAmount: number;
    category: number;
    topSimilarity: number;
    items: SemanticSearchResult[];
  }

  function extractMerchant(desc: string): string {
    const clean = desc
      .replace(/\/\/.*$/, "") // remove location after //
      .replace(/\s+\d{5,}.*$/, "") // remove trailing reference numbers
      .trim();
    const words = clean.split(/\s+/);
    return words.slice(0, 2).join(" ") || desc.slice(0, 15);
  }

  const semanticGroups = $derived.by((): MerchantGroup[] => {
    if (deduplicatedSemantic.length === 0) return [];
    const groups = new Map<string, MerchantGroup>();
    for (const r of deduplicatedSemantic) {
      const key = extractMerchant(r.description);
      const existing = groups.get(key);
      if (existing) {
        existing.count++;
        existing.totalAmount += r.amount;
        existing.items.push(r);
        if (r.similarity > existing.topSimilarity)
          existing.topSimilarity = r.similarity;
      } else {
        groups.set(key, {
          merchant: key,
          count: 1,
          totalAmount: r.amount,
          category: r.category,
          topSimilarity: r.similarity,
          items: [r],
        });
      }
    }
    return [...groups.values()].toSorted(
      (a, b) => b.topSimilarity - a.topSimilarity,
    );
  });

  const semanticTotal = $derived(
    deduplicatedSemantic.reduce((sum, r) => sum + r.amount, 0),
  );

  // Flat result list with section headers
  interface ResultItem {
    type: "header" | "action" | "transaction" | "merchant-group" | "semantic";
    action?: PaletteAction;
    transaction?: Transaction;
    semantic?: SemanticSearchResult;
    merchantGroup?: MerchantGroup;
    label: string;
  }

  const flatResults = $derived.by(() => {
    const items: ResultItem[] = [];

    if (!query.trim()) {
      const groupOrder: string[] = [];
      const grouped: Record<string, PaletteAction[]> = {};
      for (const a of filteredActions) {
        if (!grouped[a.group]) {
          grouped[a.group] = [];
          groupOrder.push(a.group);
        }
        grouped[a.group].push(a);
      }
      for (const group of groupOrder) {
        items.push({ type: "header", label: group });
        for (const a of grouped[group]) {
          items.push({ type: "action", action: a, label: a.label });
        }
      }
      return items;
    }

    if (filteredActions.length > 0) {
      items.push({ type: "header", label: "Aktionen" });
      for (const a of filteredActions) {
        items.push({ type: "action", action: a, label: a.label });
      }
    }

    if (fuzzyTxResults.length > 0) {
      items.push({ type: "header", label: "Transaktionen" });
      for (const t of fuzzyTxResults) {
        items.push({
          type: "transaction",
          transaction: t,
          label: t.description,
        });
      }
    }

    // Semantic results: merchant groups with drill-down
    if (semanticGroups.length > 0) {
      items.push({ type: "header", label: "Semantische Suche" });
      for (const g of semanticGroups) {
        items.push({
          type: "merchant-group",
          merchantGroup: g,
          label: g.merchant,
        });
        // Drill-down: show individual transactions when expanded
        if (expandedMerchant === g.merchant) {
          for (const s of g.items) {
            items.push({ type: "semantic", semantic: s, label: s.description });
          }
        }
      }
    }

    return items;
  });

  const selectableItems = $derived(
    flatResults.filter((i) => i.type !== "header"),
  );

  // Clamp selected index
  $effect(() => {
    if (selectedIndex >= selectableItems.length) {
      selectedIndex = Math.max(0, selectableItems.length - 1);
    }
  });

  // Scroll selected item into view
  $effect(() => {
    if (!resultsEl) return;
    const sel = resultsEl.querySelector(`[data-idx="${selectedIndex}"]`);
    sel?.scrollIntoView({ block: "nearest" });
  });

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      selectedIndex = Math.min(selectedIndex + 1, selectableItems.length - 1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      selectedIndex = Math.max(selectedIndex - 1, 0);
    } else if (e.key === "Enter") {
      e.preventDefault();
      const item = selectableItems[selectedIndex];
      if (item) executeItem(item);
    } else if (e.key === "Escape") {
      if (confirmingAction) {
        confirmingAction = null;
      } else if (expandedMerchant) {
        expandedMerchant = null;
      } else if (query) {
        query = "";
        selectedIndex = 0;
      } else {
        closePalette();
      }
    }
  }

  function executeItem(item: ResultItem) {
    if (item.type === "action" && item.action) {
      executeAction(item.action);
    } else if (item.type === "transaction" && item.transaction) {
      openTransaction(item.transaction.id);
    } else if (item.type === "semantic" && item.semantic) {
      openTransaction(item.semantic.id);
    } else if (item.type === "merchant-group" && item.merchantGroup) {
      expandedMerchant =
        expandedMerchant === item.merchantGroup.merchant
          ? null
          : item.merchantGroup.merchant;
    }
  }

  function closePalette() {
    history.back();
  }

  function onPaletteClosed() {
    paletteStore.hide();
  }

  function executeAction(action: PaletteAction) {
    if (action.danger && !confirmingAction) {
      confirmingAction = action;
      return;
    }
    confirmingAction = null;
    closePalette();
    try {
      action.handler();
    } catch (err) {
      toastStore.show(`Fehler: ${err}`);
    }
  }

  function openTransaction(id: string) {
    closePalette();
    sessionStorage.setItem("wimg_open_txn", id);
    if (page.url.pathname === "/transactions") {
      // Already on transactions page — dispatch event so it opens the sheet
      window.dispatchEvent(
        new CustomEvent("wimg:open-txn", { detail: { id } }),
      );
    } else {
      goto("/transactions");
    }
  }

  function onInput(e: Event) {
    query = (e.target as HTMLInputElement).value;
    selectedIndex = 0;
    confirmingAction = null;
    expandedMerchant = null;
  }

  function getCategoryName(cat: number): string {
    return CATEGORIES[cat]?.name ?? "";
  }

  function getCategoryIcon(cat: number): string {
    return CATEGORIES[cat]?.icon ?? "📌";
  }

  function getItemKey(item: ResultItem): string {
    if (item.type === "header") return `h-${item.label}`;
    if (item.type === "merchant-group")
      return `mg-${item.merchantGroup?.merchant}`;
    return `${item.type}-${item.action?.id ?? item.transaction?.id ?? item.semantic?.id}`;
  }
</script>

<BottomSheet open={showPalette} onclose={onPaletteClosed} snaps={[0.65, 0.9]}>
  {#snippet children({ handle, content, footer })}
    <!-- Handle + Search input (not scrollable) -->
    <div {@attach handle}>
      <div class="flex justify-center pt-3 pb-2">
        <div class="w-10 h-1 rounded-full bg-gray-200"></div>
      </div>
    </div>

    <div class="px-4 pb-3">
      <div class="relative flex items-center">
        <div class="absolute left-4 text-gray-400 pointer-events-none">
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
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
        <input
          bind:this={inputEl}
          type="text"
          value={query}
          oninput={onInput}
          onkeydown={handleKeydown}
          placeholder="Suche oder frage etwas..."
          class="w-full bg-gray-50 border-none rounded-2xl py-3 pl-12 pr-10 text-gray-800 placeholder:text-gray-400 focus:ring-2 focus:ring-amber-400/60 outline-none transition-all text-[15px]"
        />
        {#if query}
          <button
            onclick={() => {
              query = "";
              selectedIndex = 0;
              confirmingAction = null;
              expandedMerchant = null;
            }}
            class="absolute right-3 text-gray-400 hover:text-gray-600 transition-colors"
            aria-label="Suche leeren"
          >
            <svg
              class="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        {/if}
      </div>
      <!-- Semantic status indicator -->
      {#if modelAutoLoading}
        <div class="flex items-center gap-1.5 mt-2 ml-1">
          <span class="w-1.5 h-1.5 bg-amber-400 rounded-full animate-pulse"></span>
          <span class="text-[11px] text-amber-600">KI-Modell wird geladen…</span>
        </div>
      {:else if modelLoaded && query.length >= 2}
        <div class="flex items-center gap-1.5 mt-2 ml-1">
          {#if semanticLoading}
            <span class="w-1.5 h-1.5 bg-amber-400 rounded-full animate-pulse"
            ></span>
            <span class="text-[11px] text-amber-600">KI-Suche läuft…</span>
          {:else if hasSemanticResults}
            <span class="w-1.5 h-1.5 bg-emerald-400 rounded-full"></span>
            <span class="text-[11px] text-emerald-600"
              >{deduplicatedSemantic.length} semantische Treffer</span
            >
          {/if}
        </div>
      {/if}
    </div>

    <!-- Confirm dialog -->
    {#if confirmingAction}
      <div class="mx-4 mb-2 p-3 bg-red-50 rounded-2xl border border-red-100">
        <p class="text-sm text-red-700 font-semibold">
          {confirmingAction.label}
        </p>
        <p class="text-xs text-red-600/70 mt-0.5">
          Diese Aktion kann nicht rückgängig gemacht werden.
        </p>
        <div class="flex gap-2 mt-2.5">
          <button
            onclick={() => {
              if (confirmingAction) executeAction(confirmingAction);
            }}
            class="px-3.5 py-1.5 text-xs font-bold text-white bg-red-500 rounded-xl hover:bg-red-600 transition-colors"
            >Ja, ausführen</button
          >
          <button
            onclick={() => (confirmingAction = null)}
            class="px-3.5 py-1.5 text-xs font-bold text-gray-600 bg-white rounded-xl hover:bg-gray-50 border border-gray-200 transition-colors"
            >Abbrechen</button
          >
        </div>
      </div>
    {/if}

    <!-- Results (scrollable) -->
    <div {@attach content} bind:this={resultsEl} class="palette-scroll p-2">
      {#if flatResults.length === 0 && query}
        <div class="px-4 py-10 text-center">
          <p class="text-gray-400 text-sm">Keine Ergebnisse für „{query}"</p>
        </div>
      {:else}
        {#each flatResults as item, i (getItemKey(item))}
          {#if item.type === "header"}
            <div>
              <div class="flex items-center justify-between px-4 pt-4 pb-1.5">
                <h2
                  class="text-[11px] font-bold text-gray-400 uppercase tracking-wider"
                >
                  {item.label}
                </h2>
                {#if item.label === "Semantische Suche"}
                  <span
                    class="bg-amber-50 text-amber-700 text-[10px] font-bold px-2 py-0.5 rounded-full flex items-center gap-1.5 border border-amber-200/60"
                  >
                    <span
                      class="w-1.5 h-1.5 bg-amber-400 rounded-full animate-pulse"
                    ></span>
                    KI-SUCHE
                  </span>
                {/if}
              </div>
              <!-- Semantic summary: total count + amount -->
              {#if item.label === "Semantische Suche" && semanticGroups.length > 0}
                <div
                  class="mx-4 mb-2 px-3 py-2 bg-amber-50/60 rounded-xl border border-amber-100/80"
                >
                  <p class="text-[12px] text-gray-600">
                    {deduplicatedSemantic.length} Treffer ·
                    <span
                      class="font-bold tabular-nums"
                      class:text-emerald-600={semanticTotal > 0}
                      class:text-gray-800={semanticTotal <= 0}
                    >
                      {formatAmountSigned(semanticTotal)}
                    </span>
                    gesamt · {semanticGroups.length}
                    {semanticGroups.length === 1 ? "Händler" : "Händler"}
                  </p>
                </div>
              {/if}
            </div>
          {:else}
            {@const selIdx = selectableItems.indexOf(item)}

            {#if item.type === "action" && item.action}
              <button
                data-idx={selIdx}
                class="group w-full flex items-center px-4 py-3 rounded-xl text-left transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/80 border-l-[3px] border-amber-400 pl-[13px]'
                  : 'hover:bg-gray-50 border-l-[3px] border-transparent pl-[13px]'}
                  {item.action.danger ? 'text-red-600' : 'text-gray-700'}"
                onclick={() => executeItem(item)}
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <span
                  class="mr-3 text-lg group-hover:scale-110 transition-transform shrink-0"
                  >{item.action.icon}</span
                >
                <span class="flex-1 text-sm font-medium truncate"
                  >{item.action.label}</span
                >
                <span class="text-[11px] text-gray-400 shrink-0"
                  >{item.action.group}</span
                >
              </button>
            {:else if item.type === "transaction" && item.transaction}
              <button
                data-idx={selIdx}
                class="w-full flex items-center justify-between px-4 py-3 rounded-xl cursor-pointer transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/80 border-l-[3px] border-amber-400 pl-[13px]'
                  : 'hover:bg-gray-50 border-l-[3px] border-transparent pl-[13px]'}"
                onclick={() => executeItem(item)}
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <div class="flex items-center min-w-0">
                  <span class="mr-3 text-lg shrink-0"
                    >{getCategoryIcon(item.transaction.category)}</span
                  >
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-gray-900 truncate">
                      {item.transaction.description}
                    </p>
                    <p class="text-[11px] text-gray-400">
                      {getCategoryName(item.transaction.category)}
                    </p>
                  </div>
                </div>
                <div class="text-right ml-3 shrink-0">
                  <p
                    class="text-sm font-bold tabular-nums"
                    class:text-emerald-600={item.transaction.amount > 0}
                    class:text-gray-900={item.transaction.amount <= 0}
                  >
                    {formatAmountSigned(item.transaction.amount)}
                  </p>
                  <p class="text-[11px] text-gray-400">
                    {formatDateShort(item.transaction.date)}
                  </p>
                </div>
              </button>
            {:else if item.type === "merchant-group" && item.merchantGroup}
              {@const isExpanded =
                expandedMerchant === item.merchantGroup.merchant}
              <button
                data-idx={selIdx}
                class="w-full flex items-center justify-between px-4 py-3 rounded-xl cursor-pointer transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/80 border-l-[3px] border-amber-400 pl-[13px]'
                  : 'hover:bg-gray-50 border-l-[3px] border-transparent pl-[13px]'}"
                onclick={() => executeItem(item)}
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <div class="flex items-center min-w-0">
                  <span class="mr-3 text-lg shrink-0"
                    >{getCategoryIcon(item.merchantGroup.category)}</span
                  >
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-gray-900 truncate">
                      {item.merchantGroup.merchant}
                    </p>
                    <p class="text-[11px] text-gray-400">
                      {item.merchantGroup.count}× · {getCategoryName(
                        item.merchantGroup.category,
                      )}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2 ml-3 shrink-0">
                  <div class="text-right">
                    <p
                      class="text-sm font-bold tabular-nums"
                      class:text-emerald-600={item.merchantGroup.totalAmount >
                        0}
                      class:text-gray-900={item.merchantGroup.totalAmount <= 0}
                    >
                      {formatAmountSigned(item.merchantGroup.totalAmount)}
                    </p>
                  </div>
                  <svg
                    class="w-3.5 h-3.5 text-gray-400 transition-transform {isExpanded
                      ? 'rotate-90'
                      : ''}"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 5l7 7-7 7"
                    />
                  </svg>
                </div>
              </button>
            {:else if item.type === "semantic" && item.semantic}
              <!-- Drill-down: individual transaction under expanded merchant group -->
              <button
                data-idx={selIdx}
                class="w-full flex items-center justify-between rounded-xl cursor-pointer transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/60 border-l-[3px] border-amber-300 pl-[45px] pr-4 py-2'
                  : 'hover:bg-gray-50/50 border-l-[3px] border-transparent pl-[45px] pr-4 py-2'}"
                onclick={() => executeItem(item)}
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <p class="text-[13px] text-gray-600 truncate min-w-0">
                  {item.semantic.description}
                </p>
                <div class="flex items-center gap-2 ml-3 shrink-0">
                  <p
                    class="text-[13px] font-semibold tabular-nums"
                    class:text-emerald-600={item.semantic.amount > 0}
                    class:text-gray-700={item.semantic.amount <= 0}
                  >
                    {formatAmountSigned(item.semantic.amount)}
                  </p>
                  <span
                    class="text-[9px] font-mono text-amber-600 bg-amber-50 px-1 py-0.5 rounded border border-amber-100"
                  >
                    {(item.semantic.similarity * 100).toFixed(0)}%
                  </span>
                </div>
              </button>
            {/if}
          {/if}
        {/each}
      {/if}
    </div>

    <!-- Footer -->
    <div
      {@attach footer}
      class="p-3 bg-gray-50/80 text-center border-t border-gray-100"
    >
      <p
        class="text-[10px] text-gray-400 font-medium flex items-center justify-center gap-3"
      >
        <span
          ><kbd
            class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-gray-500 shadow-sm text-[10px]"
            >↑↓</kbd
          > Navigation</span
        >
        <span
          ><kbd
            class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-gray-500 shadow-sm text-[10px]"
            >↵</kbd
          > Ausführen</span
        >
        {#if query}
          <span
            ><kbd
              class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-gray-500 shadow-sm text-[10px]"
              >Esc</kbd
            > Leeren</span
          >
        {:else}
          <span
            ><kbd
              class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-gray-500 shadow-sm text-[10px]"
              >Esc</kbd
            > Schließen</span
          >
        {/if}
        {#if modelLoaded}
          <span class="ml-auto flex items-center gap-1 text-amber-500">
            <span class="w-1.5 h-1.5 bg-amber-400 rounded-full"></span>
            Semantic
          </span>
        {/if}
      </p>
    </div>
  {/snippet}
</BottomSheet>

<style>
  .palette-scroll::-webkit-scrollbar {
    width: 4px;
  }
  .palette-scroll::-webkit-scrollbar-thumb {
    background: #e5e7eb;
    border-radius: 10px;
  }
  .palette-scroll::-webkit-scrollbar-thumb:hover {
    background: #d1d5db;
  }
</style>
