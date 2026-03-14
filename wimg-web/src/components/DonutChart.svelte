<script lang="ts">
  import { CATEGORIES, type CategoryBreakdown } from "$lib/wasm";

  let { data, size = 220 }: { data: CategoryBreakdown[]; size?: number } =
    $props();

  const THICKNESS = 20;
  const PAD_ANGLE = 0.03; // gap between slices in radians

  let slices = $derived.by(() => {
    const total = data.reduce((sum, d) => sum + Math.abs(d.amount), 0);
    if (total === 0) return [];

    const cx = size / 2;
    const cy = size / 2;
    const outer = size / 2 - 1; // 1px inset to avoid clipping
    const inner = outer - THICKNESS;
    const totalGap = PAD_ANGLE * data.length;
    const available = 2 * Math.PI - totalGap;
    let angle = -Math.PI / 2;

    return data.map((d) => {
      const value = Math.abs(d.amount);
      const sweep = (value / total) * available;
      const start = angle + PAD_ANGLE / 2;
      const end = start + sweep;
      angle = end + PAD_ANGLE / 2;

      const color = CATEGORIES[d.id]?.color ?? "#dfe6e9";
      const largeArc = sweep > Math.PI ? 1 : 0;

      // Outer arc endpoints
      const ox1 = cx + outer * Math.cos(start);
      const oy1 = cy + outer * Math.sin(start);
      const ox2 = cx + outer * Math.cos(end);
      const oy2 = cy + outer * Math.sin(end);

      // Inner arc endpoints
      const ix1 = cx + inner * Math.cos(end);
      const iy1 = cy + inner * Math.sin(end);
      const ix2 = cx + inner * Math.cos(start);
      const iy2 = cy + inner * Math.sin(start);

      const path = [
        `M ${ox1} ${oy1}`,
        `A ${outer} ${outer} 0 ${largeArc} 1 ${ox2} ${oy2}`,
        `L ${ix1} ${iy1}`,
        `A ${inner} ${inner} 0 ${largeArc} 0 ${ix2} ${iy2}`,
        "Z",
      ].join(" ");

      return { color, path };
    });
  });
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 {size} {size}"
  style="display: block;"
>
  {#each slices as slice}
    <path
      d={slice.path}
      fill={slice.color}
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  {/each}
</svg>
