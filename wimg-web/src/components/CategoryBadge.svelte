<script lang="ts">
  import { CATEGORIES } from "$lib/wasm";

  let { category, onclick }: { category: number; onclick?: () => void } = $props();

  let cat = $derived(CATEGORIES[category] ?? CATEGORIES[0]);
</script>

<button
  class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-medium shrink-0 transition-transform hover:scale-110"
  class:cursor-pointer={!!onclick}
  style="background-color: {cat.color}20; color: {cat.color}"
  {onclick}
  title={cat.name}
>
  {cat.name.slice(0, 2)}
</button>
