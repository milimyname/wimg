<script lang="ts">
  import { CATEGORIES } from "$lib/wasm";

  let { category, onclick }: { category: number; onclick?: () => void } = $props();

  let cat = $derived(CATEGORIES[category] ?? CATEGORIES[0]);
</script>

<button
  class="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0 transition-transform hover:scale-105"
  class:cursor-pointer={!!onclick}
  style="background-color: {cat.color}15"
  {onclick}
  title={cat.name}
>
  {cat.icon ?? cat.name.slice(0, 2)}
</button>
