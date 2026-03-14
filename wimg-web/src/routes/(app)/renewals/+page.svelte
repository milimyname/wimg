<script lang="ts">
  import { CATEGORIES, type RecurringPattern } from "$lib/wasm";
  import { formatEur, formatEurCompact } from "$lib/format";
  import { data } from "$lib/data.svelte";
  import { toastStore } from "$lib/toast.svelte";
  import EmptyState from "../../../components/EmptyState.svelte";

  const MONTH_NAMES = [
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
  ];

  let patterns = $derived(data.recurring());
  let annualPatterns = $derived(
    patterns.filter((p) => p.active && p.interval === "annual"),
  );

  let totalAnnual = $derived(
    annualPatterns.reduce((sum, p) => sum + Math.abs(p.amount), 0),
  );

  // Group by month of next_due (or last_seen month if no next_due)
  let groupedByMonth = $derived.by(() => {
    const groups: Record<number, RecurringPattern[]> = {};
    for (const p of annualPatterns) {
      const dateStr = p.next_due ?? p.last_seen;
      if (!dateStr) continue;
      const month = new Date(dateStr + "T00:00:00").getMonth();
      if (!groups[month]) groups[month] = [];
      groups[month].push(p);
    }
    // Sort by month, starting from current month
    const now = new Date().getMonth();
    const sorted: [number, RecurringPattern[]][] = [];
    for (let i = 0; i < 12; i++) {
      const m = (now + i) % 12;
      if (groups[m]) sorted.push([m, groups[m]]);
    }
    return sorted;
  });

  function getStatus(p: RecurringPattern): { label: string; color: string; dot: string } {
    if (!p.next_due) return { label: "", color: "text-(--color-text-secondary)", dot: "bg-gray-400" };
    const d = new Date(p.next_due + "T00:00:00");
    const now = new Date();
    const diffMs = d.getTime() - now.getTime();
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    if (diffDays < 0)
      return { label: `${Math.abs(diffDays)}T überfällig`, color: "text-red-500", dot: "bg-red-500" };
    if (diffDays === 0) return { label: "Heute", color: "text-amber-600", dot: "bg-amber-500" };
    if (diffDays <= 30)
      return { label: `In ${diffDays} Tagen`, color: "text-amber-600", dot: "bg-amber-500" };
    if (diffDays <= 90)
      return { label: `In ${Math.round(diffDays / 30)} Monaten`, color: "text-(--color-text-secondary)", dot: "bg-gray-400" };
    return { label: `In ${Math.round(diffDays / 30)} Monaten`, color: "text-(--color-text-secondary)", dot: "bg-gray-400" };
  }

  function getCategoryIcon(cat: number): string {
    return CATEGORIES[cat]?.icon ?? "📦";
  }

  function getCategoryColor(cat: number): string {
    return CATEGORIES[cat]?.color ?? "#9CA3AF";
  }
</script>

<!-- Header -->
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
  <h2 class="text-xl font-display font-extrabold">Jährliche Zahlungen</h2>
</div>

{#if annualPatterns.length === 0}
  <EmptyState
    title="Keine jährlichen Zahlungen"
    subtitle="Jährliche Zahlungen werden automatisch aus deinen Transaktionen erkannt. Importiere mindestens 12 Monate Daten."
  >
    {#snippet icon()}
      <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
      </svg>
    {/snippet}
    {#snippet actions()}
      <a
        href="/recurring"
        class="inline-block px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
      >
        Wiederkehrende anzeigen
      </a>
    {/snippet}
  </EmptyState>
{:else}
  <!-- Hero Card -->
  <div class="bg-(--color-accent) rounded-[2rem] p-7 mb-6 shadow-[var(--shadow-soft)] relative overflow-hidden" style="color: #1a1a1a">
    <div class="absolute -right-8 -top-8 w-32 h-32 bg-white/25 rounded-full blur-2xl pointer-events-none"></div>
    <div class="relative z-10">
      <p class="text-sm font-bold uppercase tracking-wider mb-1" style="opacity: 0.8">Total jährlich</p>
      <p class="text-4xl font-display font-black tracking-tight">
        {totalAnnual >= 10000 ? formatEurCompact(totalAnnual) : formatEur(totalAnnual)}
      </p>
    </div>
    <div class="flex items-center mt-4 relative z-10">
      <span class="px-4 py-1.5 rounded-full text-xs font-bold" style="background: rgba(255,255,255,0.4)">
        {annualPatterns.length} {annualPatterns.length === 1 ? "Verlängerung" : "Verlängerungen"}
      </span>
    </div>
  </div>

  <!-- Timeline grouped by month -->
  <div class="space-y-6">
    {#each groupedByMonth as [monthIdx, items]}
      <div>
        <h3 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider mb-3 px-1">
          {MONTH_NAMES[monthIdx]}
        </h3>
        <div class="space-y-3">
          {#each items as pattern}
            {@const status = getStatus(pattern)}
            {@const isUrgent = status.dot === "bg-amber-500" || status.dot === "bg-red-500"}
            <div
              class="bg-white p-5 rounded-[2rem] shadow-[var(--shadow-card)]"
              class:ring-2={isUrgent}
              class:ring-amber-200={status.dot === "bg-amber-500"}
              class:ring-red-200={status.dot === "bg-red-500"}
            >
              <div class="flex items-center justify-between gap-3 mb-4">
                <div class="flex items-center gap-3 min-w-0">
                  <div
                    class="w-11 h-11 rounded-2xl flex items-center justify-center text-lg shrink-0"
                    style="background-color: {getCategoryColor(pattern.category)}20"
                  >
                    {getCategoryIcon(pattern.category)}
                  </div>
                  <div class="min-w-0">
                    <p class="font-extrabold text-base truncate">{pattern.merchant}</p>
                    <div class="flex items-center gap-1.5 mt-0.5">
                      <span class="w-2 h-2 rounded-full shrink-0 {status.dot}"></span>
                      <p class="text-xs font-medium {status.color}">{status.label}</p>
                    </div>
                  </div>
                </div>
                <p class="font-display font-extrabold text-lg shrink-0">
                  {formatEurCompact(Math.abs(pattern.amount))}
                </p>
              </div>

              <button
                onclick={() => toastStore.show("Erinnerungen kommen bald!")}
                class="w-full py-3 px-4 bg-(--color-bg) rounded-2xl text-sm font-semibold text-(--color-text-secondary) flex items-center justify-center gap-2 hover:bg-gray-100 transition-colors cursor-pointer"
              >
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                </svg>
                Erinnerung erstellen
              </button>
            </div>
          {/each}
        </div>
      </div>
    {/each}
  </div>
{/if}
