<script lang="ts">
  import { toastStore } from "$lib/toast.svelte";

  const DURATION = 5;
  const R = 9;
  const C = 2 * Math.PI * R; // circumference
</script>

{#if toastStore.visible}
  <div
    class="fixed bottom-24 left-1/2 -translate-x-1/2 z-50 w-[calc(100%-2rem)] max-w-lg"
  >
    <div
      class="bg-(--color-text) text-white rounded-2xl px-5 py-3.5 shadow-[var(--shadow-soft)] flex items-center justify-between gap-3"
    >
      <span class="text-sm font-bold truncate">{toastStore.message}</span>
      <div class="flex items-center gap-2 shrink-0">
        {#if toastStore.hasUndo}
          <button
            onclick={() => toastStore.triggerUndo()}
            class="text-sm font-bold cursor-pointer hover:opacity-80 transition-opacity text-(--color-accent)"
          >
            Rückgängig
          </button>
        {/if}
        <button
          onclick={() => toastStore.dismiss()}
          class="relative w-7 h-7 flex items-center justify-center cursor-pointer group"
          aria-label="Schließen"
        >
          {#key toastStore.message}
            <svg class="absolute inset-0 w-7 h-7 -rotate-90" viewBox="0 0 22 22">
              <circle
                cx="11"
                cy="11"
                r={R}
                fill="none"
                stroke="rgba(255,255,255,0.15)"
                stroke-width="2"
              />
              <circle
                cx="11"
                cy="11"
                r={R}
                fill="none"
                stroke="rgba(255,255,255,0.5)"
                stroke-width="2"
                stroke-linecap="round"
                stroke-dasharray={C}
                stroke-dashoffset="0"
                class="countdown-ring"
                style="--c: {C}; --d: {DURATION}s"
              />
            </svg>
          {/key}
          <svg
            class="relative w-3 h-3 text-gray-400 group-hover:text-white transition-colors"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2.5"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .countdown-ring {
    animation: countdown var(--d) linear forwards;
  }

  @keyframes countdown {
    from {
      stroke-dashoffset: 0;
    }
    to {
      stroke-dashoffset: var(--c);
    }
  }
</style>
