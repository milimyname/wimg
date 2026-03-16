<script lang="ts">
  import { goto } from "$app/navigation";
  import { page } from "$app/state";
  import { getActions, type PaletteAction } from "$lib/actions";
  import { paletteStore } from "$lib/commandPalette.svelte";
  import { searchTransactions, setCategory, setExcluded, CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatAmountSigned, formatDateShort } from "$lib/format";
  import { toastStore } from "$lib/toast.svelte";
  import { data } from "$lib/data.svelte";
  import { feedbackStore } from "$lib/feedback.svelte";
  import Drawer from "./Drawer.svelte";

  let inputEl = $state<HTMLInputElement | null>(null);
  let editingTxn = $state<Transaction | null>(null);
  let resultsEl = $state<HTMLDivElement | null>(null);
  let query = $state("");
  let selectedIndex = $state(0);
  let confirmingAction = $state<PaletteAction | null>(null);

  // --- Search history (localStorage) ---
  const HISTORY_KEY = "wimg_search_history";
  const MAX_HISTORY = 5;

  function getRecentSearches(): string[] {
    try {
      return JSON.parse(localStorage.getItem(HISTORY_KEY) || "[]");
    } catch {
      return [];
    }
  }

  function saveRecentSearch(q: string) {
    const history = getRecentSearches().filter((h) => h !== q);
    history.unshift(q);
    localStorage.setItem(
      HISTORY_KEY,
      JSON.stringify(history.slice(0, MAX_HISTORY)),
    );
  }

  // Derive open from shallow routing state or URL param (survives reload)
  let showPalette = $derived(
    page.state.sheet === "command-palette" || page.url.searchParams.has("cmd"),
  );

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
      editingTxn = null;
    }
  });

  // Filter actions by query
  const filteredActions = $derived.by(() => {
    const q = query.toLowerCase().trim();
    const available = getActions().filter((a) => !a.enabled || a.enabled());
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

  // SQL LIKE transaction search
  const fuzzyTxResults = $derived.by(() => {
    const q = query.trim();
    if (!q || q.length < 2) return [];
    try {
      const num = parseFloat(q.replace(",", "."));
      const cents = !isNaN(num) ? Math.round(Math.abs(num) * 100) : undefined;
      return searchTransactions(q, 10, cents);
    } catch {
      return [];
    }
  });

  // Flat result list with section headers
  interface ResultItem {
    type: "header" | "action" | "transaction" | "recent";
    action?: PaletteAction;
    transaction?: Transaction;
    label: string;
  }

  const flatResults = $derived.by(() => {
    const items: ResultItem[] = [];

    if (!query.trim()) {
      // Recent searches
      const recentSearches = getRecentSearches();
      if (recentSearches.length > 0) {
        items.push({ type: "header", label: "Letzte Suchen" });
        for (const q of recentSearches) {
          items.push({ type: "recent", label: q });
        }
      }

      // Grouped actions
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
      if (editingTxn) {
        editingTxn = null;
      } else if (confirmingAction) {
        confirmingAction = null;
      } else if (query) {
        query = "";
        selectedIndex = 0;
      } else {
        closePalette();
      }
    }
  }

  function executeItem(item: ResultItem) {
    if (item.type === "recent") {
      query = item.label;
      selectedIndex = 0;
      return;
    }
    if (query.trim().length >= 2) saveRecentSearch(query.trim());
    if (item.type === "action" && item.action) {
      executeAction(item.action);
    } else if (item.type === "transaction" && item.transaction) {
      openTransaction(item.transaction.id);
    }
  }

  function closePalette() {
    history.back();
  }

  function onPaletteClosed() {
    paletteStore.hide();
  }

  async function executeAction(action: PaletteAction) {
    if (action.danger && !confirmingAction) {
      confirmingAction = action;
      return;
    }
    confirmingAction = null;
    try {
      await action.handler();
    } catch (err) {
      toastStore.show(`Fehler: ${err}`);
    }
    // Don't close if a stacked sheet opened (e.g. feedback sheet)
    if (feedbackStore.open) return;
    // Close palette only if handler didn't navigate away (e.g. goto)
    if (showPalette) closePalette();
  }

  function openTransaction(id: string) {
    // Navigate to transactions with ?txn=id — replaces palette history entry
    goto(`/transactions?txn=${id}`, { replaceState: true });
  }

  function onInput(e: Event) {
    query = (e.target as HTMLInputElement).value;
    selectedIndex = 0;
    confirmingAction = null;
  }

  function getCategoryName(cat: number): string {
    return CATEGORIES[cat]?.name ?? "";
  }

  function getCategoryIcon(cat: number): string {
    return CATEGORIES[cat]?.icon ?? "📌";
  }

  function getItemKey(item: ResultItem): string {
    if (item.type === "header") return `h-${item.label}`;
    if (item.type === "recent") return `recent-${item.label}`;
    return `${item.type}-${item.action?.id ?? item.transaction?.id}`;
  }
</script>

<Drawer open={showPalette} onclose={onPaletteClosed} snaps={[0.65, 0.9]}>
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
          class="w-full bg-(--color-bg) border-none rounded-2xl py-3 pl-12 pr-10 text-(--color-text) placeholder:text-(--color-text-secondary) focus:ring-2 focus:ring-amber-400/60 outline-none transition-all text-[15px]"
        />
        {#if query}
          <button
            onclick={() => {
              query = "";
              selectedIndex = 0;
              confirmingAction = null;
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

    <!-- Inline category picker -->
    {#if editingTxn}
      <div class="px-4 py-3 border-b border-(--color-border)">
        <button
          onclick={() => (editingTxn = null)}
          class="text-sm text-gray-500 hover:text-gray-700 font-medium mb-2 flex items-center gap-1"
        >
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Zurück
        </button>
        <p class="text-sm font-bold text-(--color-text) truncate mb-3">{editingTxn.description}</p>
        <div class="flex flex-wrap gap-2">
          {#each Object.entries(CATEGORIES) as [catId, cat]}
            <button
              onclick={async () => {
                if (!editingTxn) return;
                await setCategory(editingTxn.id, Number(catId));
                data.bump();
                toastStore.show(`Kategorie: ${cat.name}`);
                editingTxn = null;
              }}
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all
                {editingTxn.category === Number(catId)
                ? 'ring-2 ring-amber-400 bg-amber-50'
                : 'bg-gray-50 hover:bg-gray-100'}"
            >
              <span>{cat.icon}</span>
              <span>{cat.name}</span>
            </button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Results (scrollable) -->
    <div
      {@attach content}
      bind:this={resultsEl}
      class="palette-scroll p-2 pb-40"
      class:hidden={editingTxn !== null}
    >
      {#if flatResults.length === 0 && query}
        <div class="px-4 py-10 text-center">
          <p class="text-gray-400 text-sm">Keine Ergebnisse für „{query}"</p>
        </div>
      {:else}
        {#each flatResults as item, i (getItemKey(item))}
          {#if item.type === "header"}
            <div>
              <div class="px-4 pt-4 pb-1.5">
                <h2
                  class="text-[11px] font-bold text-gray-400 uppercase tracking-wider"
                >
                  {item.label}
                </h2>
              </div>
            </div>
          {:else}
            {@const selIdx = selectableItems.indexOf(item)}

            {#if item.type === "recent"}
              <button
                data-idx={selIdx}
                class="group w-full flex items-center px-4 py-3 rounded-xl text-left transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/80 border-l-[3px] border-amber-400 pl-[13px]'
                  : 'hover:bg-gray-50 border-l-[3px] border-transparent pl-[13px]'}"
                onclick={() => executeItem(item)}
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <span class="mr-3 text-lg shrink-0 text-gray-400">
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
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </span>
                <span class="flex-1 text-sm font-medium truncate text-gray-700"
                  >{item.label}</span
                >
                <span class="text-[11px] text-gray-400 shrink-0">Suche</span>
              </button>
            {:else if item.type === "action" && item.action}
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
              <div
                data-idx={selIdx}
                class="flex items-center justify-between px-4 py-3 rounded-xl transition-all
                  {selIdx === selectedIndex
                  ? 'bg-amber-50/80 border-l-[3px] border-amber-400 pl-[13px]'
                  : 'hover:bg-gray-50 border-l-[3px] border-transparent pl-[13px]'}"
                role="button"
                tabindex="-1"
                onpointerenter={() => (selectedIndex = selIdx)}
              >
                <button
                  class="flex items-center min-w-0 flex-1 text-left"
                  onclick={() => executeItem(item)}
                >
                  <span class="mr-3 text-lg shrink-0"
                    >{getCategoryIcon(item.transaction.category)}</span
                  >
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-(--color-text) truncate" class:opacity-40={item.transaction.excluded}>
                      {item.transaction.description}
                    </p>
                    <p class="text-[11px] text-gray-400">
                      {getCategoryName(item.transaction.category)}
                    </p>
                  </div>
                </button>
                <div class="flex items-center gap-1 ml-2 shrink-0">
                  <button
                    onclick={() => { editingTxn = item.transaction ?? null; }}
                    class="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400 hover:text-gray-600 transition-colors"
                    aria-label="Kategorie ändern"
                    title="Kategorie ändern"
                  >
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
                    </svg>
                  </button>
                  <button
                    onclick={async () => {
                      if (!item.transaction) return;
                      const tx = item.transaction;
                      const nowExcluded = !tx.excluded;
                      await setExcluded(tx.id, nowExcluded);
                      data.bump();
                      toastStore.show(nowExcluded ? "Ausgeblendet" : "Eingeblendet");
                    }}
                    class="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400 hover:text-gray-600 transition-colors"
                    aria-label={item.transaction.excluded ? "Einblenden" : "Ausblenden"}
                    title={item.transaction.excluded ? "Einblenden" : "Ausblenden"}
                  >
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      {#if item.transaction.excluded}
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                      {:else}
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
                      {/if}
                    </svg>
                  </button>
                  <div class="text-right ml-1">
                    <p
                      class="text-sm font-bold tabular-nums"
                      class:text-emerald-600={item.transaction.amount > 0}
                      class:text-(--color-text)={item.transaction.amount <= 0}
                    >
                      {formatAmountSigned(item.transaction.amount)}
                    </p>
                    <p class="text-[11px] text-gray-400">
                      {formatDateShort(item.transaction.date)}
                    </p>
                  </div>
                </div>
              </div>
            {/if}
          {/if}
        {/each}
      {/if}
    </div>

    <!-- Footer -->
    <div
      {@attach footer}
      class="p-3 bg-(--color-bg)/80 text-center border-t border-(--color-border)"
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
      </p>
    </div>
  {/snippet}
</Drawer>

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
