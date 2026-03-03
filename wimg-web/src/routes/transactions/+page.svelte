<script lang="ts">
  import {
    getTransactions,
    setCategory,
    undo,
    CATEGORIES,
    type Transaction,
  } from "$lib/wasm";
  import { toastStore } from "$lib/toast.svelte";

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

  type Filter = "all" | "expenses" | "income";

  let transactions = $state<Transaction[]>(getTransactions());
  let filter = $state<Filter>("all");
  let selectedTxn = $state<Transaction | null>(null);
  let showSheet = $state(false);
  let searchQuery = $state("");
  let showSearch = $state(false);

  let filtered = $derived.by(() => {
    let list = transactions;
    if (filter === "expenses") list = list.filter((t) => t.amount < 0);
    if (filter === "income") list = list.filter((t) => t.amount > 0);
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter((t) => t.description.toLowerCase().includes(q));
    }
    return list;
  });

  let grouped = $derived.by(() => {
    const groups = new Map<string, Transaction[]>();
    for (const txn of filtered) {
      const existing = groups.get(txn.date);
      if (existing) {
        existing.push(txn);
      } else {
        groups.set(txn.date, [txn]);
      }
    }
    return groups;
  });

  function openDetail(txn: Transaction) {
    selectedTxn = { ...txn };
    showSheet = true;
  }

  function closeSheet() {
    showSheet = false;
    selectedTxn = null;
  }

  async function handleCategoryChange(category: number) {
    if (!selectedTxn) return;
    const id = selectedTxn.id;
    const catName = CATEGORIES[category]?.name ?? "Uncategorized";
    selectedTxn = { ...selectedTxn, category };
    transactions = transactions.map((t) =>
      t.id === id ? { ...t, category } : t,
    );
    await setCategory(id, category);
    toastStore.show(`Kategorie: ${catName}`, async () => {
      await undo();
      transactions = getTransactions();
    });
  }

  function formatAmount(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
      signDisplay: "always",
    }).format(amount);
  }

  function formatDateHeading(dateStr: string): string {
    const date = new Date(dateStr + "T00:00:00");
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    const day = date.getDate();
    const month = date.toLocaleDateString("de-DE", { month: "long" });

    if (date.toDateString() === today.toDateString())
      return `Heute · ${day}. ${month}`;
    if (date.toDateString() === yesterday.toDateString())
      return `Gestern · ${day}. ${month}`;

    const weekday = date.toLocaleDateString("de-DE", { weekday: "long" });
    return `${weekday} · ${day}. ${month}`;
  }
</script>

<!-- Search bar (collapsible) -->
{#if showSearch}
  <div class="mb-4 flex gap-2">
    <input
      type="text"
      bind:value={searchQuery}
      placeholder="Transaktion suchen..."
      class="flex-1 bg-white border border-(--color-border) rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-(--color-primary)/30"
    />
    <button
      onclick={() => {
        showSearch = false;
        searchQuery = "";
      }}
      class="text-sm text-(--color-text-secondary) px-3 cursor-pointer"
    >
      Abbrechen
    </button>
  </div>
{:else}
  <div class="flex items-center justify-between mb-4">
    <button
      onclick={() => (showSearch = true)}
      class="w-9 h-9 flex items-center justify-center rounded-full hover:bg-gray-100 cursor-pointer transition-colors"
      aria-label="Suchen"
    >
      <svg
        class="w-5 h-5 text-(--color-text-secondary)"
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
    </button>
    <h2 class="text-lg font-bold">Transaktionen</h2>
    <div class="w-9 h-9"></div>
  </div>
{/if}

<!-- Segmented Control -->
<div class="mb-5">
  <div class="flex bg-gray-100 p-1 rounded-xl">
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "all"}
      class:shadow-sm={filter === "all"}
      class:text-gray-500={filter !== "all"}
      class:font-medium={filter !== "all"}
      onclick={() => (filter = "all")}
    >
      Alle
    </button>
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "expenses"}
      class:shadow-sm={filter === "expenses"}
      class:text-gray-500={filter !== "expenses"}
      class:font-medium={filter !== "expenses"}
      onclick={() => (filter = "expenses")}
    >
      Ausgaben
    </button>
    <button
      class="flex-1 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer"
      class:bg-white={filter === "income"}
      class:shadow-sm={filter === "income"}
      class:text-gray-500={filter !== "income"}
      class:font-medium={filter !== "income"}
      onclick={() => (filter = "income")}
    >
      Einnahmen
    </button>
  </div>
</div>

<!-- Transaction List -->
{#if transactions.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-3xl mb-3">📋</p>
    <p class="font-medium">Keine Transaktionen</p>
    <p class="text-sm mt-1">
      <a href="/import" class="text-(--color-primary) font-medium"
        >CSV importieren</a
      > um zu starten
    </p>
  </div>
{:else if filtered.length === 0}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-3xl mb-3">🔍</p>
    <p class="font-medium">Keine Ergebnisse</p>
    <p class="text-sm mt-1">Versuche einen anderen Filter</p>
  </div>
{:else}
  {#each [...grouped.entries()] as [date, txns]}
    <h3
      class="text-xs font-bold text-gray-400 mt-6 mb-3 uppercase tracking-wider"
    >
      {formatDateHeading(date)}
    </h3>

    {#each txns as txn}
      <button
        class="bg-white w-full p-4 rounded-xl shadow-sm border border-gray-100 flex items-center justify-between mb-3 cursor-pointer hover:shadow-md transition-shadow text-left"
        onclick={() => openDetail(txn)}
      >
        <div class="flex items-center gap-3">
          <div
            class="w-10 h-10 rounded-full flex items-center justify-center text-lg shrink-0"
            style="background-color: {CATEGORIES[txn.category]?.color ?? '#dfe6e9'}15"
          >
            {CATEGORY_ICONS[txn.category] ?? "📦"}
          </div>
          <div>
            <p class="font-bold text-sm leading-tight">{txn.description}</p>
            <div class="flex items-center gap-1.5 mt-0.5">
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style="background-color: {CATEGORIES[txn.category]?.color ??
                  '#dfe6e9'}"
              ></span>
              <p class="text-xs text-gray-500 font-medium">
                {CATEGORIES[txn.category]?.name ?? "Uncategorized"}
              </p>
            </div>
          </div>
        </div>
        <p
          class="font-bold text-sm tabular-nums shrink-0 ml-3"
          class:text-emerald-500={txn.amount > 0}
        >
          {formatAmount(txn.amount)}
        </p>
      </button>
    {/each}
  {/each}
{/if}

<!-- Bottom Sheet Overlay -->
{#if showSheet && selectedTxn}
  <div
    class="fixed inset-0 bg-black/40 z-30 flex flex-col justify-end"
    onclick={closeSheet}
    onkeydown={(e) => e.key === "Escape" && closeSheet()}
    role="dialog"
    tabindex="-1"
  >
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events -->
    <div
      class="bg-white rounded-t-2xl w-full max-w-2xl mx-auto p-6 pb-10 shadow-2xl"
      onclick={(e) => e.stopPropagation()}
      role="document"
    >
      <!-- Handle -->
      <div class="w-12 h-1 bg-gray-200 rounded-full mx-auto mb-8"></div>

      <!-- Icon + Name -->
      <div class="flex flex-col items-center mb-8">
        <div
          class="w-16 h-16 rounded-2xl flex items-center justify-center mb-3 text-3xl border border-gray-100"
          style="background-color: {CATEGORIES[selectedTxn.category]?.color ??
            '#dfe6e9'}10"
        >
          {CATEGORY_ICONS[selectedTxn.category] ?? "📦"}
        </div>
        <h2 class="text-xl font-bold">{selectedTxn.description}</h2>
        <p class="text-gray-500 text-sm mt-1">
          {new Date(selectedTxn.date + "T00:00:00").toLocaleDateString(
            "de-DE",
            { weekday: "long", day: "numeric", month: "long" },
          )}
        </p>
      </div>

      <!-- Amount -->
      <div
        class="flex justify-between items-center py-4 border-b border-gray-100"
      >
        <span class="text-gray-500 font-medium">Betrag</span>
        <span
          class="text-xl font-bold"
          class:text-emerald-500={selectedTxn.amount > 0}
        >
          {formatAmount(selectedTxn.amount)}
        </span>
      </div>

      <!-- Category Selector -->
      <div class="mt-5 mb-6">
        <span class="text-gray-500 font-medium text-sm">Kategorie</span>
        <div class="flex flex-wrap gap-2 mt-3">
          {#each Object.entries(CATEGORIES) as [catId, cat]}
            <button
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold transition-all cursor-pointer border"
              style="background-color: {Number(catId) === selectedTxn.category
                ? cat.color + '20'
                : '#f9fafb'}; border-color: {Number(catId) ===
              selectedTxn.category
                ? cat.color + '40'
                : 'transparent'}"
              onclick={() => handleCategoryChange(Number(catId))}
            >
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style="background-color: {cat.color}"
              ></span>
              {cat.name}
            </button>
          {/each}
        </div>
      </div>

      <!-- Done Button -->
      <button
        class="w-full text-white font-bold py-3.5 rounded-xl cursor-pointer hover:opacity-90 transition-opacity"
        style="background-color: var(--color-primary)"
        onclick={closeSheet}
      >
        Fertig
      </button>
    </div>
  </div>
{/if}
