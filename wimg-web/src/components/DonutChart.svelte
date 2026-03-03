<script lang="ts">
  import { PieChart } from "layerchart";
  import { CATEGORIES, type CategoryBreakdown } from "$lib/wasm";

  let { data, size = 220 }: { data: CategoryBreakdown[]; size?: number } =
    $props();

  let chartData = $derived(
    data.map((d) => ({
      ...d,
      amount: Math.abs(d.amount),
      color: CATEGORIES[d.id]?.color ?? "#dfe6e9",
    })),
  );
</script>

<div style="width: {size}px; height: {size}px;">
  <PieChart
    data={chartData}
    key="name"
    value="amount"
    c="color"
    innerRadius={-20}
    cornerRadius={4}
    padAngle={0.02}
    tooltip={false}
  />
</div>
