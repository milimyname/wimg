<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    icon,
    title,
    subtitle,
    actions,
  }: {
    icon: Snippet;
    title: string;
    subtitle: string;
    actions?: Snippet;
  } = $props();
</script>

<div class="text-center py-12">
  <!-- Illustration circle -->
  <div
    class="w-28 h-28 mx-auto mb-6 rounded-full bg-(--color-accent)/20 flex items-center justify-center"
  >
    {@render icon()}
  </div>
  <h2 class="text-xl font-display font-extrabold mb-2">{title}</h2>
  <p class="text-sm text-(--color-text-secondary) mb-8 max-w-[280px] mx-auto">
    {subtitle}
  </p>
  {#if actions}
    {@render actions()}
  {/if}
</div>
