<script lang="ts">
  let { text }: { text: string } = $props();
  let open = $state(false);
  let buttonEl: HTMLButtonElement | undefined = $state();
  let popoverEl: HTMLDivElement | undefined = $state();

  function onWindowClick(e: MouseEvent) {
    if (!open) return;
    const target = e.target as Node;
    if (buttonEl?.contains(target) || popoverEl?.contains(target)) return;
    open = false;
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === "Escape") open = false;
  }
</script>

<svelte:window onclick={onWindowClick} onkeydown={onKey} />

<span class="relative inline-flex">
  <button
    bind:this={buttonEl}
    type="button"
    onclick={(e) => {
      e.stopPropagation();
      open = !open;
    }}
    aria-label="Mehr Infos"
    aria-expanded={open}
    class="inline-flex items-center justify-center w-4 h-4 rounded-full opacity-50 hover:opacity-100 transition-opacity cursor-help"
  >
    <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
      <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zM7.25 4.5a.75.75 0 1 1 1.5 0 .75.75 0 0 1-1.5 0zM7.25 7a.75.75 0 0 1 1.5 0v4.5a.75.75 0 0 1-1.5 0V7z" />
    </svg>
  </button>

  {#if open}
    <div
      bind:this={popoverEl}
      role="tooltip"
      class="absolute z-50 top-full mt-2 left-1/2 -translate-x-1/2 w-64 rounded-2xl bg-white text-(--color-text) text-xs leading-relaxed p-3 shadow-[var(--shadow-card)] ring-1 ring-black/5"
    >
      {text}
    </div>
  {/if}
</span>
