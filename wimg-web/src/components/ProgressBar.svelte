<script lang="ts">
  let {
    value,
    max,
    color = "var(--color-primary)",
  }: { value: number; max: number; color?: string } = $props();

  let percent = $derived(max > 0 ? Math.min((value / max) * 100, 100) : 0);
</script>

<div class="w-full bg-gray-100 rounded-full h-2.5 overflow-hidden">
  <div
    class="h-full rounded-full transition-all duration-500"
    style="width: {percent}%; background-color: {color}"
  ></div>
</div>
