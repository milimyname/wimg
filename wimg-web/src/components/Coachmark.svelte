<script lang="ts">
  import { coachmarkStore } from "$lib/coachmarks.svelte";

  let {
    key,
    text,
    position = "bottom",
  }: {
    key: string;
    text: string;
    position?: "top" | "bottom";
  } = $props();

  let visible = $derived(coachmarkStore.shouldShow(key));

  function dismiss() {
    coachmarkStore.dismiss(key);
  }
</script>

{#if visible}
  <div
    class="absolute left-1/2 -translate-x-1/2 z-20 flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl shadow-lg text-sm whitespace-nowrap"
    class:bottom-full={position === "top"}
    class:top-full={position === "bottom"}
    class:mb-2={position === "top"}
    class:mt-2={position === "bottom"}
    style="background: var(--color-card-bg, #fff); border: 1px solid rgba(0,0,0,0.08);"
  >
    <!-- Arrow -->
    <div
      class="absolute left-1/2 -translate-x-1/2 w-2.5 h-2.5 rotate-45"
      class:-top-1.5={position === "bottom"}
      class:-bottom-1.5={position === "top"}
      style="background: var(--color-card-bg, #fff); border: 1px solid rgba(0,0,0,0.08); {position === 'bottom' ? 'border-bottom: none; border-right: none;' : 'border-top: none; border-left: none;'}"
    ></div>
    <span class="text-xs font-medium" style="color: var(--color-text-secondary)">{text}</span>
    <button
      onclick={dismiss}
      class="px-2.5 py-1 rounded-full text-xs font-bold text-white cursor-pointer"
      style="background: var(--color-text)"
    >OK</button>
  </div>
{/if}
