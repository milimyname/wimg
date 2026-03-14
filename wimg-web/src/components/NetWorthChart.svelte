<script lang="ts">
  import { formatEur, formatEurCompact } from "$lib/format";
  import type { Snapshot } from "$lib/wasm";

  const MONTH_SHORT = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"];
  const MONTH_NAMES = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];

  let { snapshots }: { snapshots: Snapshot[] } = $props();

  // Sort chronologically and compute cumulative net worth
  let chartData = $derived.by(() => {
    const sorted = [...snapshots].sort((a, b) => a.date.localeCompare(b.date));
    let cumulative = 0;
    return sorted.map((s) => {
      cumulative += s.net_worth;
      const [, m] = s.date.split("-").map(Number);
      return { ...s, cumulative, monthIdx: m - 1 };
    });
  });

  let currentValue = $derived(chartData.length > 0 ? chartData[chartData.length - 1].cumulative : 0);

  // Year-over-year growth
  let yoyGrowth = $derived.by(() => {
    if (chartData.length < 2) return null;
    const now = new Date();
    const curYear = now.getFullYear();
    const lastYearEnd = chartData.filter((d) => d.date.startsWith(`${curYear - 1}`));
    const thisYearData = chartData.filter((d) => d.date.startsWith(`${curYear}`));
    if (lastYearEnd.length === 0 || thisYearData.length === 0) return null;
    const prevVal = lastYearEnd[lastYearEnd.length - 1].cumulative;
    if (prevVal === 0) return null;
    return ((currentValue - prevVal) / Math.abs(prevVal)) * 100;
  });

  // Stats
  let highest = $derived.by(() => {
    if (chartData.length === 0) return null;
    return chartData.reduce((max, d) => (d.cumulative > max.cumulative ? d : max), chartData[0]);
  });

  let lowest = $derived.by(() => {
    if (chartData.length === 0) return null;
    return chartData.reduce((min, d) => (d.cumulative < min.cumulative ? d : min), chartData[0]);
  });

  let average = $derived(
    chartData.length > 0
      ? chartData.reduce((sum, d) => sum + d.cumulative, 0) / chartData.length
      : 0,
  );

  // SVG chart dimensions
  const W = 400;
  const H = 150;
  const PAD_TOP = 10;
  const PAD_BOTTOM = 10;

  // Generate SVG path and points
  let chartPath = $derived.by(() => {
    if (chartData.length < 2) return { line: "", area: "", dots: [] as { x: number; y: number }[] };

    const values = chartData.map((d) => d.cumulative);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;

    const points = chartData.map((d, i) => ({
      x: (i / (chartData.length - 1)) * W,
      y: PAD_TOP + ((max - d.cumulative) / range) * (H - PAD_TOP - PAD_BOTTOM),
    }));

    // Build smooth cubic bezier path
    let line = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const cpx = (prev.x + curr.x) / 2;
      line += ` C ${cpx} ${prev.y}, ${cpx} ${curr.y}, ${curr.x} ${curr.y}`;
    }

    // Area: same path + close to bottom
    const area = `${line} L ${W} ${H} L 0 ${H} Z`;

    return { line, area, dots: points };
  });

  let xLabels = $derived(chartData.map((d) => MONTH_SHORT[d.monthIdx]));
</script>

<div class="bg-white rounded-[2rem] shadow-[var(--shadow-soft)] p-8 mb-6 border border-gray-100">
  <!-- Header -->
  <div class="flex justify-between items-start mb-2">
    <div class="space-y-1">
      <h3 class="font-display font-extrabold text-2xl text-(--color-text) tracking-tight">Vermögen</h3>
      <p class="font-display font-extrabold text-4xl text-(--color-text)">
        {formatEur(currentValue)}
      </p>
    </div>
    {#if yoyGrowth !== null}
      <span
        class="px-3 py-1 rounded-full text-xs font-bold mt-1"
        class:bg-emerald-50={yoyGrowth >= 0}
        class:text-emerald-600={yoyGrowth >= 0}
        class:bg-rose-50={yoyGrowth < 0}
        class:text-rose-500={yoyGrowth < 0}
      >
        {yoyGrowth >= 0 ? "+" : ""}{yoyGrowth.toFixed(1)}% vs. Vorjahr
      </span>
    {/if}
  </div>

  <!-- Chart -->
  <div class="mt-6 mb-8">
    <div class="relative" style="height: 180px;">
      <svg class="w-full h-full overflow-visible" viewBox="0 0 {W} {H}" preserveAspectRatio="none">
        <defs>
          <linearGradient id="nwGradient" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="var(--color-accent)" stop-opacity="0.8" />
            <stop offset="100%" stop-color="var(--color-accent)" stop-opacity="0" />
          </linearGradient>
        </defs>
        <path d={chartPath.area} fill="url(#nwGradient)" />
        <path d={chartPath.line} fill="none" stroke="var(--color-text)" stroke-width="1.5" />
        {#each chartPath.dots as dot}
          <circle cx={dot.x} cy={dot.y} r="2.5" fill="var(--color-text)" />
        {/each}
      </svg>
    </div>
    <!-- X-axis labels -->
    <div class="flex justify-between px-1 mt-4 text-[10px] font-bold text-(--color-text-secondary)/60 uppercase tracking-widest">
      {#each xLabels as label}
        <span>{label}</span>
      {/each}
    </div>
  </div>

  <!-- Stats Grid -->
  <div class="grid grid-cols-3 gap-4 border-t border-gray-100 pt-6">
    {#if highest}
      <div class="flex flex-col">
        <span class="text-[10px] uppercase tracking-wider text-(--color-text-secondary)/60 font-medium">Höchster</span>
        <span class="text-xs text-(--color-text-secondary) font-semibold mt-0.5">
          {MONTH_NAMES[highest.monthIdx]} ({formatEurCompact(highest.cumulative)})
        </span>
      </div>
    {/if}
    {#if lowest}
      <div class="flex flex-col">
        <span class="text-[10px] uppercase tracking-wider text-(--color-text-secondary)/60 font-medium">Niedrigster</span>
        <span class="text-xs text-(--color-text-secondary) font-semibold mt-0.5">
          {MONTH_NAMES[lowest.monthIdx]} ({formatEurCompact(lowest.cumulative)})
        </span>
      </div>
    {/if}
    <div class="flex flex-col">
      <span class="text-[10px] uppercase tracking-wider text-(--color-text-secondary)/60 font-medium">Durchschnitt</span>
      <span class="text-xs text-(--color-text-secondary) font-semibold mt-0.5">
        {formatEurCompact(average)}
      </span>
    </div>
  </div>
</div>
