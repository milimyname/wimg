<script lang="ts">
  import { updateStore } from "$lib/update.svelte";
  import BottomSheet from "./BottomSheet.svelte";
</script>

<BottomSheet open={updateStore.sheetOpen} onclose={() => (updateStore.sheetOpen = false)} snaps={[0.42]}>
  {#snippet children({ handle, content })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 pb-8">
      <div class="flex items-center gap-3 mb-5">
        <div class="w-11 h-11 rounded-2xl bg-(--color-accent) flex items-center justify-center shrink-0">
          <svg class="w-6 h-6 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </div>
        <div>
          <p class="font-bold text-base text-(--color-text)">Neue Version verfügbar</p>
          <p class="text-sm text-(--color-text-secondary)">v{updateStore.targetVersion}</p>
        </div>
      </div>

      <a
        href={updateStore.releasesUrl}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1.5 text-sm font-medium text-(--color-text-secondary) hover:text-(--color-text) transition-colors mb-5"
      >
        Was ist neu?
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
        </svg>
      </a>

      {#if updateStore.hasBreaking}
        <div class="rounded-xl bg-amber-50 border border-amber-200 px-4 py-3 text-sm text-amber-700 mb-5">
          Diese Version enthält Datenbank-Änderungen. Lokale Daten müssen zurückgesetzt werden.
        </div>
      {/if}

      <div class="flex gap-2.5">
        {#if updateStore.hasBreaking}
          <button
            onclick={() => updateStore.clearDataAndUpdate()}
            class="flex-1 py-3 rounded-xl bg-amber-500 text-sm font-bold text-white transition-transform active:scale-[0.98]"
          >
            Daten löschen & aktualisieren
          </button>
        {:else}
          <button
            onclick={() => updateStore.activateUpdate()}
            class="flex-1 py-3 rounded-xl bg-(--color-text) text-sm font-bold text-white transition-transform active:scale-[0.98]"
          >
            Jetzt aktualisieren
          </button>
        {/if}
        <button
          onclick={() => {
            updateStore.sheetOpen = false;
            updateStore.dismiss();
          }}
          class="py-3 px-5 rounded-xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
        >
          Später
        </button>
      </div>
    </div>
  {/snippet}
</BottomSheet>
