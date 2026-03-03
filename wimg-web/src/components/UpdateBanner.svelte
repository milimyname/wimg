<script lang="ts">
  import { updateStore } from "$lib/update.svelte";

  const MAX_ITEMS = 3;

  const allItems = $derived(updateStore.newEntries.flatMap((e) => e.items));
  const displayItems = $derived(allItems.slice(0, MAX_ITEMS));
  const moreCount = $derived(allItems.length - MAX_ITEMS);
</script>

{#if updateStore.showBanner}
  <div class="mx-4 mt-4 rounded-xl border border-blue-200 bg-blue-50 p-4">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0 flex-1">
        <p class="font-semibold text-(--color-text)">
          Neue Version verfügbar
          <span class="ml-1 text-sm font-normal text-(--color-muted)"
            >v{updateStore.targetVersion}</span
          >
        </p>

        {#if displayItems.length > 0}
          <ul class="mt-2 space-y-1 text-sm text-(--color-muted)">
            {#each displayItems as item}
              <li class="flex items-start gap-1.5">
                <span class="mt-0.5 shrink-0 text-xs text-blue-400">●</span>
                {item}
              </li>
            {/each}
            {#if moreCount > 0}
              <li class="text-xs text-(--color-muted)">
                ...und {moreCount} mehr
              </li>
            {/if}
          </ul>
        {/if}

        {#if updateStore.hasBreaking}
          <div
            class="mt-3 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-800"
          >
            Diese Version enthält Datenbank-Änderungen. Lokale Daten müssen
            zurückgesetzt werden.
          </div>
        {/if}
      </div>

      <button
        onclick={() => updateStore.dismiss()}
        class="shrink-0 text-(--color-muted) hover:text-(--color-text)"
        aria-label="Schließen"
      >
        <svg
          class="h-5 w-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M6 18L18 6M6 6l12 12"
          />
        </svg>
      </button>
    </div>

    <div class="mt-3 flex gap-2">
      {#if updateStore.hasBreaking}
        <button
          onclick={() => updateStore.clearDataAndUpdate()}
          class="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600"
        >
          Daten löschen & aktualisieren
        </button>
      {:else}
        <button
          onclick={() => updateStore.activateUpdate()}
          class="rounded-lg bg-(--color-primary) px-4 py-2 text-sm font-medium text-white hover:opacity-90"
        >
          Jetzt aktualisieren
        </button>
      {/if}
      <button
        onclick={() => updateStore.dismiss()}
        class="rounded-lg px-4 py-2 text-sm text-(--color-muted) hover:bg-gray-100"
      >
        Später
      </button>
    </div>
  </div>
{/if}
