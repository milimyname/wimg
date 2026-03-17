<script lang="ts">
  import { formatEurCompact } from "$lib/format";
  import type { Snapshot } from "$lib/wasm";

  const MONTHS = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];

  let { snapshots }: { snapshots: Snapshot[] } = $props();

  // Group snapshots by year → month grid
  let grid = $derived.by(() => {
    const map = new Map<string, number>();
    for (const s of snapshots) {
      map.set(s.date.slice(0, 7), Math.abs(s.expenses));
    }

    const years = [...new Set(snapshots.map((s) => parseInt(s.date.slice(0, 4))))].toSorted();
    if (years.length === 0) return { years: [] as number[], cells: [] as { year: number; month: number; amount: number }[], max: 0 };

    const cells: { year: number; month: number; amount: number }[] = [];
    let max = 0;
    for (const year of years) {
      for (let m = 0; m < 12; m++) {
        const key = `${year}-${String(m + 1).padStart(2, "0")}`;
        const amount = map.get(key) ?? 0;
        if (amount > max) max = amount;
        cells.push({ year, month: m, amount });
      }
    }
    return { years, cells, max };
  });

  // Color scale: light brand → deep indigo
  function cellColor(amount: number, max: number): string {
    if (amount === 0 || max === 0) return "var(--color-border, #f0ece6)";
    const t = amount / max;
    if (t < 0.25) return "#c7d2fe"; // indigo-200
    if (t < 0.5) return "#818cf8";  // indigo-400
    if (t < 0.75) return "#6366f1"; // indigo-500
    return "#4338ca";               // indigo-700
  }

  const CELL = 28;
  const GAP = 3;
  const LABEL_W = 36;
  const HEADER_H = 20;

  let svgW = $derived(LABEL_W + grid.years.length * (CELL + GAP));
  let svgH = $derived(HEADER_H + 12 * (CELL + GAP));

  let tooltip = $state<{ x: number; y: number; text: string } | null>(null);
</script>

<div class="bg-white rounded-[2rem] shadow-[var(--shadow-soft)] p-8 mb-6 border border-gray-100">
  <div class="flex justify-between items-start mb-6">
    <div>
      <h3 class="font-display font-extrabold text-2xl text-(--color-text) tracking-tight">Ausgaben-Heatmap</h3>
      <p class="text-xs text-(--color-text-secondary) font-medium mt-1">Monatliche Ausgaben im Zeitverlauf</p>
    </div>
  </div>

  <div class="relative overflow-x-auto">
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <svg
      width={svgW}
      height={svgH}
      class="select-none"
      onmouseleave={() => (tooltip = null)}
    >
      <!-- Year headers -->
      {#each grid.years as year, col}
        <text
          x={LABEL_W + col * (CELL + GAP) + CELL / 2}
          y={14}
          text-anchor="middle"
          class="fill-(--color-text-secondary)"
          style="font-size: 10px; font-weight: 700; letter-spacing: 0.05em"
        >{year}</text>
      {/each}

      <!-- Month labels -->
      {#each MONTHS as name, row}
        <text
          x={LABEL_W - 6}
          y={HEADER_H + row * (CELL + GAP) + CELL / 2 + 4}
          text-anchor="end"
          class="fill-(--color-text-secondary)"
          style="font-size: 9px; font-weight: 600"
        >{name}</text>
      {/each}

      <!-- Cells -->
      {#each grid.cells as cell}
        {@const col = grid.years.indexOf(cell.year)}
        {@const x = LABEL_W + col * (CELL + GAP)}
        {@const y = HEADER_H + cell.month * (CELL + GAP)}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <rect
          {x}
          {y}
          width={CELL}
          height={CELL}
          rx="4"
          fill={cellColor(cell.amount, grid.max)}
          class="cursor-pointer transition-opacity hover:opacity-80"
          onmouseenter={(e) => {
            const rect = (e.target as SVGRectElement).getBoundingClientRect();
            tooltip = {
              x: rect.left + rect.width / 2,
              y: rect.top,
              text: `${MONTHS[cell.month]} ${cell.year}: ${cell.amount > 0 ? formatEurCompact(cell.amount) : "—"}`,
            };
          }}
          onmouseleave={() => (tooltip = null)}
        />
      {/each}
    </svg>
  </div>

  <!-- Legend -->
  <div class="flex items-center justify-end gap-2 mt-4 text-[10px] font-bold text-(--color-text-secondary)">
    <span>Wenig</span>
    <div class="flex gap-0.5">
      <div class="w-3 h-3 rounded-sm" style="background: var(--color-border, #f0ece6)"></div>
      <div class="w-3 h-3 rounded-sm" style="background: #c7d2fe"></div>
      <div class="w-3 h-3 rounded-sm" style="background: #818cf8"></div>
      <div class="w-3 h-3 rounded-sm" style="background: #6366f1"></div>
      <div class="w-3 h-3 rounded-sm" style="background: #4338ca"></div>
    </div>
    <span>Viel</span>
  </div>
</div>

{#if tooltip}
  <div
    class="fixed z-50 px-3 py-1.5 rounded-lg text-xs font-bold text-white shadow-lg pointer-events-none"
    style="background: #1a1a1a; left: {tooltip.x}px; top: {tooltip.y - 36}px; transform: translateX(-50%)"
  >
    {tooltip.text}
  </div>
{/if}
