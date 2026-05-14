<script lang="ts">
  let { text }: { text: string } = $props();

  // Use the native HTML5 popover API instead of a hand-rolled `position: fixed`
  // popup. The popover top-layer is above every stacking context AND every
  // transform containing block — which matters because the (app) layout wraps
  // pages in a `transform`-based DrawerIndent that traps `position: fixed`.
  // The browser also handles auto-dismiss on outside click and Escape for us.
  const popoverId = `info-${Math.random().toString(36).slice(2, 10)}`;
  let buttonEl: HTMLButtonElement | undefined = $state();
  let popoverEl: HTMLDivElement | undefined = $state();

  const POPOVER_W = 256;
  const HALF_W = POPOVER_W / 2;
  const EDGE_PAD = 8;

  function positionPopover() {
    if (!buttonEl || !popoverEl) return;
    const rect = buttonEl.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const clamped = Math.min(
      Math.max(centerX, HALF_W + EDGE_PAD),
      window.innerWidth - HALF_W - EDGE_PAD,
    );
    popoverEl.style.top = `${rect.bottom + 8}px`;
    popoverEl.style.left = `${clamped - HALF_W}px`;
  }

  // Re-anchor on scroll/resize so the popover follows its trigger. Without
  // this the popover sits at the viewport coords it was opened at while the
  // button scrolls away under it. Use capture:true on the scroll listener
  // because the (app) layout may scroll on a child container, not window.
  function onMaybeReposition() {
    if (popoverEl?.matches(":popover-open")) positionPopover();
  }
</script>

<svelte:window onresize={onMaybeReposition} />
<svelte:document onscrollcapture={onMaybeReposition} />

<button
  bind:this={buttonEl}
  type="button"
  popovertarget={popoverId}
  onclick={positionPopover}
  aria-label="Mehr Infos"
  class="inline-flex items-center justify-center w-4 h-4 rounded-full opacity-50 hover:opacity-100 transition-opacity cursor-help"
>
  <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
    <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zM7.25 4.5a.75.75 0 1 1 1.5 0 .75.75 0 0 1-1.5 0zM7.25 7a.75.75 0 0 1 1.5 0v4.5a.75.75 0 0 1-1.5 0V7z" />
  </svg>
</button>

<!-- inset:auto + margin:0 overrides the [popover] default which centers the
     element in the viewport. We set top/left explicitly to anchor near the
     button. -->
<div
  bind:this={popoverEl}
  id={popoverId}
  popover="auto"
  role="tooltip"
  class="w-64 rounded-2xl bg-white text-(--color-text) text-xs leading-relaxed p-3 shadow-xl ring-1 ring-black/10"
  style="position: fixed; inset: auto; margin: 0;"
>
  {text}
</div>
