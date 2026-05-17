<script lang="ts">
  import { onMount } from "svelte";

  // Web has no FLAG_SECURE / scenePhase equivalent — the OS will always
  // be able to screenshot the browser window. What we CAN do: blur the
  // content the instant the tab loses visibility, so the tab-switcher
  // thumbnail (taken after visibilitychange fires) doesn't reveal
  // transaction data.
  let hidden = $state(false);

  onMount(() => {
    const update = () => {
      hidden = document.visibilityState === "hidden";
    };
    document.addEventListener("visibilitychange", update);
    // pagehide fires before the snapshot is taken when navigating away.
    window.addEventListener("pagehide", () => (hidden = true));
    window.addEventListener("pageshow", () => (hidden = false));
    return () => {
      document.removeEventListener("visibilitychange", update);
    };
  });
</script>

{#if hidden}
  <div class="fixed inset-0 z-[110] bg-(--color-bg) flex flex-col items-center justify-center">
    <div class="w-20 h-20 rounded-full bg-(--color-accent)/20 flex items-center justify-center mb-4">
      <svg class="w-9 h-9 text-(--color-text)/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8"
          d="M12 11a3 3 0 100-6 3 3 0 000 6zm-6 8a6 6 0 1112 0H6z" />
      </svg>
    </div>
    <p class="text-2xl font-display font-black">wimg</p>
  </div>
{/if}
