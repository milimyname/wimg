<script lang="ts">
  import { toastStore } from "$lib/toast.svelte";
</script>

{#if toastStore.visible}
  <div
    class="fixed bottom-20 left-1/2 -translate-x-1/2 z-30 w-[calc(100%-2rem)] max-w-lg"
  >
    <div
      class="bg-gray-900 text-white rounded-xl px-4 py-3 shadow-lg flex items-center justify-between gap-3"
    >
      <span class="text-sm font-medium truncate">{toastStore.message}</span>
      <div class="flex items-center gap-2 shrink-0">
        {#if toastStore.hasUndo}
          <button
            onclick={() => toastStore.triggerUndo()}
            class="text-sm font-bold cursor-pointer hover:opacity-80 transition-opacity"
            style="color: var(--color-primary-light)"
          >
            Rückgängig
          </button>
        {/if}
        <button
          onclick={() => toastStore.dismiss()}
          class="text-gray-400 hover:text-white cursor-pointer transition-colors"
          aria-label="Schließen"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
    </div>
  </div>
{/if}
