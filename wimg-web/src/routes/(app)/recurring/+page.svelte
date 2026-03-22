<script lang="ts">
  import {
    detectRecurring,
    opfsSave,
    CATEGORIES,
    type RecurringPattern,
  } from "$lib/wasm";
  import { formatEur, formatEurCompact, formatDateShort } from "$lib/format";
  import { localeTag } from "$lib/format";
  import { data } from "$lib/data.svelte";
  import { page } from "$app/state";
  import EmptyState from "../../../components/EmptyState.svelte";

  let patterns = $derived(data.recurring());
  let detecting = $state(false);
  let hasDetected = $state(false);
  let hasData = $derived(data.hasAnyData());
  let tab = $state<"subscriptions" | "calendar">(
    page.url.searchParams.get("tab") === "calendar" ? "calendar" : "subscriptions",
  );

  let activePatterns = $derived(patterns.filter((p) => p.active));
  let priceAlerts = $derived(
    activePatterns.filter((p) => p.price_change && Math.abs(p.price_change) > 0),
  );
  let monthlyTotal = $derived(
    activePatterns
      .filter((p) => p.interval === "monthly")
      .reduce((sum, p) => sum + Math.abs(p.amount), 0),
  );

  // Group by interval
  let grouped = $derived.by(() => {
    const groups: Record<string, RecurringPattern[]> = {};
    for (const p of activePatterns) {
      const key = p.interval;
      if (!groups[key]) groups[key] = [];
      groups[key].push(p);
    }
    return groups;
  });

  const intervalLabels: Record<string, string> = {
    weekly: "Wöchentlich",
    monthly: "Monatlich",
    quarterly: "Vierteljährlich",
    annual: "Jährlich",
  };

  // --- Calendar logic ---

  interface FuturePayment {
    date: string;
    merchant: string;
    amount: number;
    category: number;
    interval: string;
  }

  function addInterval(date: Date, interval: string): Date {
    const d = new Date(date);
    if (interval === "weekly") d.setDate(d.getDate() + 7);
    else if (interval === "monthly") d.setMonth(d.getMonth() + 1);
    else if (interval === "quarterly") d.setMonth(d.getMonth() + 3);
    else if (interval === "annual") d.setFullYear(d.getFullYear() + 1);
    return d;
  }

  let futurePayments = $derived.by(() => {
    const now = new Date();
    const end = new Date(now);
    end.setFullYear(end.getFullYear() + 1);
    const payments: FuturePayment[] = [];

    for (const p of activePatterns) {
      if (!p.next_due) continue;
      let d = new Date(p.next_due + "T00:00:00");
      // If overdue, step forward to present
      while (d < now) d = addInterval(d, p.interval);
      // Generate occurrences for 12 months
      while (d <= end) {
        payments.push({
          date: d.toISOString().slice(0, 10),
          merchant: p.merchant,
          amount: p.amount,
          category: p.category,
          interval: p.interval,
        });
        d = addInterval(d, p.interval);
      }
    }
    return payments.sort((a, b) => a.date.localeCompare(b.date));
  });

  let paymentsByMonth = $derived.by(() => {
    const groups: Record<string, FuturePayment[]> = {};
    for (const p of futurePayments) {
      const key = p.date.slice(0, 7);
      if (!groups[key]) groups[key] = [];
      groups[key].push(p);
    }
    return groups;
  });

  let next30DaysTotal = $derived(
    futurePayments
      .filter((p) => {
        const d = new Date(p.date + "T00:00:00");
        const now = new Date();
        const diffMs = d.getTime() - now.getTime();
        return diffMs >= 0 && diffMs <= 30 * 24 * 60 * 60 * 1000;
      })
      .reduce((sum, p) => sum + Math.abs(p.amount), 0),
  );

  let next30DaysCount = $derived(
    futurePayments.filter((p) => {
      const d = new Date(p.date + "T00:00:00");
      const now = new Date();
      const diffMs = d.getTime() - now.getTime();
      return diffMs >= 0 && diffMs <= 30 * 24 * 60 * 60 * 1000;
    }).length,
  );

  // 12-month overview
  let monthlyOverview = $derived.by(() => {
    const now = new Date();
    const months: { key: string; label: string; total: number }[] = [];
    for (let i = 0; i < 12; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() + i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      const label = d.toLocaleDateString(localeTag(), { month: "short", year: i === 0 || d.getMonth() === 0 ? "numeric" : undefined });
      const items = paymentsByMonth[key] ?? [];
      const total = items.reduce((sum, p) => sum + Math.abs(p.amount), 0);
      months.push({ key, label, total });
    }
    return months;
  });

  let maxMonthlyTotal = $derived(Math.max(...monthlyOverview.map((m) => m.total), 1));

  // --- End calendar logic ---

  async function handleDetect() {
    detecting = true;
    try {
      detectRecurring();
      await opfsSave();
      data.bump();
      hasDetected = true;
    } finally {
      detecting = false;
    }
  }

  function formatNextDue(dateStr: string | null): string {
    if (!dateStr) return "";
    const d = new Date(dateStr + "T00:00:00");
    const now = new Date();
    const diffMs = d.getTime() - now.getTime();
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    if (diffDays < 0) return `${Math.abs(diffDays)}T überfällig`;
    if (diffDays === 0) return "Heute";
    if (diffDays === 1) return "Morgen";
    if (diffDays <= 7) return `In ${diffDays} Tagen`;
    return formatDateShort(d.toISOString().slice(0, 10));
  }

  function formatMonthHeading(key: string): string {
    const d = new Date(key + "-01T00:00:00");
    return d.toLocaleDateString(localeTag(), { month: "long", year: "numeric" });
  }

  function formatDayLabel(dateStr: string): string {
    const d = new Date(dateStr + "T00:00:00");
    const now = new Date();
    const diffMs = d.getTime() - now.getTime();
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    if (diffDays === 0) return "Heute";
    if (diffDays === 1) return "Morgen";
    if (diffDays <= 7) return `In ${diffDays} Tagen`;
    return d.toLocaleDateString(localeTag(), { day: "numeric", month: "short" });
  }

  function getCategoryColor(cat: number): string {
    return CATEGORIES[cat]?.color ?? "#9CA3AF";
  }

  function getCategoryIcon(cat: number): string {
    return CATEGORIES[cat]?.icon ?? "?";
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
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">Wiederkehrend</h2>
  </div>

<!-- Segmented Control -->
{#if activePatterns.length > 0}
  <div class="mb-5">
    <div class="relative flex bg-gray-200/60 p-1.5 rounded-full segment-track">
      <div
        class="absolute top-1.5 bottom-1.5 rounded-full bg-white shadow-sm transition-transform duration-300 ease-[cubic-bezier(0.25,0.1,0.25,1)]"
        style="width: calc((100% - 12px) / 2); left: 6px; transform: translateX({tab === 'subscriptions' ? '0%' : '100%'})"
      ></div>
      <button
        class="relative z-10 flex-1 py-2.5 rounded-full text-sm font-bold transition-colors duration-200 cursor-pointer"
        class:text-gray-500={tab !== "subscriptions"}
        onclick={() => (tab = "subscriptions")}
      >
        Abonnements
      </button>
      <button
        class="relative z-10 flex-1 py-2.5 rounded-full text-sm font-bold transition-colors duration-200 cursor-pointer"
        class:text-gray-500={tab !== "calendar"}
        onclick={() => (tab = "calendar")}
      >
        Kalender
      </button>
    </div>
  </div>
{/if}

{#if tab === "subscriptions"}
  <!-- Hero Card: Monthly Total -->
  {#if activePatterns.length > 0}
    <div class="bg-emerald-400 rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
      <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>
      <div class="flex flex-col gap-1 relative z-10">
        <p class="font-bold text-sm uppercase tracking-wide text-white/80">
          Monatliche Fixkosten
        </p>
        <p class="text-4xl font-display font-black tracking-tight text-white mt-1">
          {Math.abs(monthlyTotal) >= 10000 ? formatEurCompact(monthlyTotal) : formatEur(monthlyTotal)}
        </p>
        <p class="text-white/70 font-medium text-sm mt-1">
          {activePatterns.length} erkannte Muster
        </p>
      </div>
    </div>
  {/if}

  <!-- Price Alerts -->
  {#if priceAlerts.length > 0}
    <div id="price-alerts" class="mb-5">
      <a href="#price-alerts" class="text-lg font-display font-extrabold mb-3 px-1 block">Preisänderungen</a>
      <div class="flex flex-col gap-3">
        {#each priceAlerts as alert}
          {@const isUp = (alert.price_change ?? 0) > 0}
          <div class="bg-white p-4 rounded-2xl shadow-[var(--shadow-card)] flex items-center gap-4">
            <div
              class="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
              style="background-color: {isUp ? '#FEF2F2' : '#F0FDF4'}; color: {isUp ? '#DC2626' : '#16A34A'}"
            >
              {isUp ? "↑" : "↓"}
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-bold text-sm truncate">{alert.merchant}</p>
              <p class="text-xs text-(--color-text-secondary)">
                {formatEur(Math.abs(alert.prev_amount ?? 0))} → {formatEur(Math.abs(alert.amount))}
              </p>
            </div>
            <span
              class="text-sm font-bold shrink-0"
              style="color: {isUp ? '#DC2626' : '#16A34A'}"
            >
              {isUp ? "+" : ""}{formatEur(alert.price_change ?? 0)}
            </span>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Section Title + Detect Button -->
  <div id="subscriptions" class="flex items-center justify-between mb-4 px-1">
    <a href="#subscriptions" class="text-2xl font-display font-extrabold">Abonnements</a>
    <button
      onclick={handleDetect}
      disabled={detecting || !hasData}
      class="flex items-center gap-1.5 px-4 py-2 bg-(--color-accent) hover:bg-(--color-accent-hover) text-(--color-text) text-sm font-bold rounded-2xl cursor-pointer transition-colors shadow-sm disabled:opacity-50"
    >
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
      {detecting ? "Erkennung..." : "Erkennen"}
    </button>
  </div>

  <!-- Recurring Patterns -->
  {#if activePatterns.length === 0}
    {#if !hasData}
      <EmptyState
        title="Keine Transaktionen"
        subtitle="Importiere zuerst Transaktionen, um wiederkehrende Zahlungen erkennen zu können."
      >
        {#snippet icon()}
          <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
        {/snippet}
        {#snippet actions()}
          <a
            href="/import"
            class="px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98] inline-block"
          >
            CSV importieren
          </a>
        {/snippet}
      </EmptyState>
    {:else if hasDetected}
      <EmptyState
        title="Keine Muster gefunden"
        subtitle="Die Erkennung hat keine wiederkehrenden Zahlungen in deinen Transaktionen gefunden. Mehr Daten über mehrere Monate verbessern die Erkennung."
      >
        {#snippet icon()}
          <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        {/snippet}
      </EmptyState>
    {:else}
      <EmptyState
        title="Muster erkennen"
        subtitle="Analysiere deine Transaktionen, um Abos und regelmäßige Zahlungen automatisch zu finden."
      >
        {#snippet icon()}
          <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        {/snippet}
        {#snippet actions()}
          <button
            onclick={handleDetect}
            disabled={detecting}
            class="px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {detecting ? "Erkennung..." : "Muster erkennen"}
          </button>
        {/snippet}
      </EmptyState>
    {/if}
  {:else}
    {#each Object.entries(grouped) as [interval, items]}
      <div class="mb-5">
        <h4 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider mb-3 px-1">
          {intervalLabels[interval] ?? interval}
        </h4>
        <div class="flex flex-col gap-3">
          {#each items as pattern}
            <div class="bg-white p-4 rounded-3xl shadow-[var(--shadow-card)] flex items-center gap-3">
              <!-- Category icon -->
              <div
                class="w-10 h-10 rounded-2xl flex items-center justify-center text-lg shrink-0"
                style="background-color: {getCategoryColor(pattern.category)}20"
              >
                {getCategoryIcon(pattern.category)}
              </div>

              <!-- Info -->
              <div class="flex-1 min-w-0">
                <p class="font-extrabold text-sm truncate">{pattern.merchant}</p>
                <p class="text-xs font-medium text-(--color-text-secondary) mt-0.5 truncate">
                  {#if pattern.next_due}
                    {formatNextDue(pattern.next_due)} ·
                  {/if}
                  Zuletzt: {formatDateShort(pattern.last_seen)}
                </p>
              </div>

              <!-- Amount -->
              <div class="text-right shrink-0">
                <p class="font-extrabold text-sm">{formatEurCompact(Math.abs(pattern.amount))}</p>
                {#if pattern.price_change && Math.abs(pattern.price_change) > 0}
                  {@const isUp = pattern.price_change > 0}
                  <p class="text-[11px] font-bold" style="color: {isUp ? '#DC2626' : '#16A34A'}">
                    {isUp ? "+" : ""}{formatEurCompact(pattern.price_change)}
                  </p>
                {/if}
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/each}
  {/if}

{:else}
  <!-- ===== CALENDAR TAB ===== -->

  <!-- Hero Card: Next 30 Days -->
  <div class="bg-amber-400 rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
    <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>
    <div class="flex flex-col gap-1 relative z-10">
      <p class="font-bold text-sm uppercase tracking-wide text-white/80">
        Nächste 30 Tage
      </p>
      <p class="text-4xl font-display font-black tracking-tight text-white mt-1">
        {Math.abs(next30DaysTotal) >= 10000 ? formatEurCompact(next30DaysTotal) : formatEur(next30DaysTotal)}
      </p>
      <p class="text-white/70 font-medium text-sm mt-1">
        {next30DaysCount} {next30DaysCount === 1 ? "Zahlung" : "Zahlungen"}
      </p>
    </div>
  </div>

  <!-- 12-Month Overview -->
  <div class="mb-6">
    <h3 class="text-lg font-display font-extrabold mb-3 px-1">12-Monats-Übersicht</h3>
    <div class="bg-white rounded-3xl shadow-[var(--shadow-card)] p-5">
      <div class="flex flex-col gap-2.5">
        {#each monthlyOverview as month, i}
          {@const barWidth = month.total > 0 ? (month.total / maxMonthlyTotal) * 100 : 0}
          <div class="flex items-center gap-3">
            <span class="text-xs font-bold text-(--color-text-secondary) w-16 shrink-0 truncate">{month.label}</span>
            <div class="flex-1 h-6 bg-gray-100 rounded-full overflow-hidden">
              {#if barWidth > 0}
                <div
                  class="h-full rounded-full transition-all duration-500"
                  style="width: {barWidth}%; background-color: {i === 0 ? '#F59E0B' : 'var(--color-accent)'}"
                ></div>
              {/if}
            </div>
            <span class="text-xs font-extrabold tabular-nums w-16 text-right shrink-0">
              {month.total > 0 ? formatEurCompact(month.total) : "–"}
            </span>
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Timeline: Upcoming Payments by Month -->
  <h3 class="text-lg font-display font-extrabold mb-3 px-1">Anstehende Zahlungen</h3>
  {#each Object.entries(paymentsByMonth) as [monthKey, payments]}
    <div class="mb-5">
      <h4 class="text-sm font-bold text-(--color-text-secondary) uppercase tracking-wider mb-3 px-1">
        {formatMonthHeading(monthKey)}
      </h4>
      <div class="flex flex-col gap-3">
        {#each payments as payment}
          <div class="bg-white p-4 rounded-3xl shadow-[var(--shadow-card)] flex items-center gap-3">
            <div
              class="w-10 h-10 rounded-2xl flex items-center justify-center text-lg shrink-0"
              style="background-color: {getCategoryColor(payment.category)}20"
            >
              {getCategoryIcon(payment.category)}
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-extrabold text-sm truncate">{payment.merchant}</p>
              <p class="text-xs font-medium text-(--color-text-secondary) mt-0.5">
                {formatDayLabel(payment.date)}
                <span class="text-(--color-text-secondary)/50 mx-0.5">·</span>
                {intervalLabels[payment.interval] ?? payment.interval}
              </p>
            </div>
            <p class="font-extrabold text-sm tabular-nums shrink-0">
              {formatEurCompact(Math.abs(payment.amount))}
            </p>
          </div>
        {/each}
      </div>
    </div>
  {/each}

  {#if futurePayments.length === 0}
    <EmptyState
      title="Keine anstehenden Zahlungen"
      subtitle="Erkenne zuerst wiederkehrende Muster im Abonnements-Tab."
    >
      {#snippet icon()}
        <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      {/snippet}
      {#snippet actions()}
        <button
          onclick={() => (tab = "subscriptions")}
          class="px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
        >
          Zu Abonnements
        </button>
      {/snippet}
    </EmptyState>
  {/if}
{/if}
