<script lang="ts">
  let { text }: { text: string } = $props();
  let open = $state(false);
  let buttonEl: HTMLButtonElement | undefined = $state();
  let popoverEl: HTMLDivElement | undefined = $state();
  // position:fixed coords. position:absolute traps the popover in the parent's
  // stacking context (e.g. the dashboard hero card has `relative z-10` siblings
  // that would render on top of the popover even at z-50). `fixed` escapes
  // every parent stacking context as long as no ancestor uses `transform` or
  // `filter`, which none of the cards do.
  let pos = $state({ top: 0, left: 0 });

  const POPOVER_W = 256;
  const HALF_W = POPOVER_W / 2;
  const EDGE_PAD = 8;

  function reposition() {
    if (!buttonEl) return;
    const rect = buttonEl.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const clamped = Math.min(
      Math.max(centerX, HALF_W + EDGE_PAD),
      window.innerWidth - HALF_W - EDGE_PAD,
    );
    pos = { top: rect.bottom + 8, left: clamped };
  }

  function toggle(e: MouseEvent) {
    e.stopPropagation();
    if (open) {
      open = false;
    } else {
      reposition();
      open = true;
    }
  }

  function onWindowClick(e: MouseEvent) {
    if (!open) return;
    const target = e.target as Node;
    if (buttonEl?.contains(target) || popoverEl?.contains(target)) return;
    open = false;
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === "Escape") open = false;
  }

  function onResize() {
    if (open) reposition();
  }
</script>

<svelte:window onclick={onWindowClick} onkeydown={onKey} onresize={onResize} onscroll={onResize} />

<button
  bind:this={buttonEl}
  type="button"
  onclick={toggle}
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
    class="fixed z-[100] w-64 -translate-x-1/2 rounded-2xl bg-white text-(--color-text) text-xs leading-relaxed p-3 shadow-xl ring-1 ring-black/10"
    style="top: {pos.top}px; left: {pos.left}px;"
  >
    {text}
  </div>
{/if}
