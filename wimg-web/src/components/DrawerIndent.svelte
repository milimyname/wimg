<script lang="ts">
  import { drawerStore } from "$lib/drawer.svelte";
  let { children } = $props();

  let isActive = $derived(drawerStore.openCount > 0);
  let scrollY = $state(0);

  $effect(() => {
    if (isActive) {
      // 1. Capture the scroll position immediately
      scrollY = window.scrollY;

      // 2. Lock the document so the background doesn't move
      document.documentElement.style.scrollBehavior = "auto"; // Prevent smooth scroll jumps
      document.body.style.overflow = "hidden";
    } else {
      // 3. When closing, wait for the transition to finish before restoring
      const timer = setTimeout(() => {
        document.body.style.overflow = "";
        window.scrollTo(0, scrollY);
      }, 400); // Match your CSS transition time
      return () => clearTimeout(timer);
    }
  });
</script>

<div class="drawer-indent-bg" data-active={isActive ? "" : undefined}></div>

<div
  class="drawer-wrapper"
  data-active={isActive ? "" : undefined}
  style:--st={isActive ? `${-scrollY}px` : "0px"}
>
  {@render children()}
</div>

<style>
  .drawer-indent-bg {
    position: fixed;
    inset: 0;
    background: black;
    z-index: 0;
    opacity: 0;
    transition: opacity 0.4s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .drawer-indent-bg[data-active] {
    opacity: 1;
  }

  .drawer-wrapper {
    position: relative;
    z-index: 1;
    min-height: 100dvh;
    background: white; /* Match your page background */

    /* Origin is top center so the 'card' stays pinned to the status bar area */
    transform-origin: center top;

    transition:
      transform 0.3s cubic-bezier(0.32, 0.72, 0, 1),
      border-radius 0.3s cubic-bezier(0.32, 0.72, 0, 1);
  }

  .drawer-wrapper[data-active] {
    /* THE FIX: Move it to fixed, but offset it by the saved scroll */
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    transform: translateY(var(--st)) scale(0.93)
      translateY(calc(-1 * var(--st) + 12px));

    border-radius: 20px;
    overflow: hidden;
    pointer-events: none; /* Prevent interaction with background card */
  }
</style>
