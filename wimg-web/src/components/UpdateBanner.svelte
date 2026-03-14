<script lang="ts">
  import { updateStore } from "$lib/update.svelte";
  import { changelogStore } from "$lib/changelog.svelte";
  import BottomSheet from "./BottomSheet.svelte";

  let updating = $state(false);

  const latestRelease = $derived(changelogStore.releases[0]);
  const releaseItems = $derived.by(() => {
    if (!latestRelease?.body) return [];
    return latestRelease.body
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
      .filter((l) => !l.match(/^release:\s*v[\d.]+$/i))
      .filter((l) => !l.match(/^#{1,3}\s/))
      .map((l) => l.replace(/^[-*]\s*/, "").trim())
      .filter((l) => l.length > 0);
  });

  $effect(() => {
    if (updateStore.sheetOpen) changelogStore.load();
  });

  function handleUpdate() {
    updating = true;
    updateStore.activateUpdate();
  }

  function handleBreakingUpdate() {
    updating = true;
    updateStore.clearDataAndUpdate();
  }
</script>

<BottomSheet
  open={updateStore.sheetOpen}
  onclose={() => (updateStore.sheetOpen = false)}
>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6">
      <div class="flex items-center gap-3 mb-5">
        <div
          class="w-11 h-11 rounded-2xl bg-(--color-accent) flex items-center justify-center shrink-0"
        >
          <svg
            class="w-6 h-6 text-(--color-text)"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
        </div>
        <div>
          <p class="font-bold text-base text-(--color-text)">
            Neue Version verfügbar
          </p>
          <p class="text-sm text-(--color-text-secondary)">
            v{updateStore.targetVersion}
          </p>
        </div>
      </div>

      <!-- Inline changelog -->
      {#if changelogStore.loading && releaseItems.length === 0}
        <div class="space-y-2 animate-pulse">
          <div class="w-full h-3.5 bg-gray-100 rounded"></div>
          <div class="w-3/4 h-3.5 bg-gray-100 rounded"></div>
        </div>
      {:else if releaseItems.length > 0}
        <div class="bg-(--color-bg) rounded-2xl p-4">
          <p
            class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wider mb-3"
          >
            Was ist neu?
          </p>
          <div class="space-y-2">
            {#each releaseItems as item}
              <div class="flex gap-2.5">
                <span class="text-(--color-text-secondary)/40 shrink-0 mt-0.5">
                  <svg
                    class="w-3.5 h-3.5"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 5l7 7-7 7"
                    />
                  </svg>
                </span>
                <p class="text-sm text-(--color-text) leading-relaxed">
                  {item}
                </p>
              </div>
            {/each}
          </div>
          <a
            href="/changelog"
            onclick={() => (updateStore.sheetOpen = false)}
            class="inline-flex items-center gap-1 text-xs font-medium text-(--color-text-secondary) hover:text-(--color-text) transition-colors mt-3"
          >
            Alle Änderungen ansehen
          </a>
        </div>
      {/if}

      {#if updateStore.hasBreaking}
        <div
          class="rounded-xl bg-amber-50 border border-amber-200 px-4 py-3 text-sm text-amber-700 mt-5"
        >
          Diese Version enthält Datenbank-Änderungen. Lokale Daten müssen
          zurückgesetzt werden.
        </div>
      {/if}
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <div class="flex gap-2.5">
        {#if updateStore.hasBreaking}
          <button
            onclick={handleBreakingUpdate}
            disabled={updating}
            class="flex-1 py-3 rounded-xl bg-amber-500 text-sm font-bold text-white transition-all active:scale-[0.98] disabled:opacity-60"
          >
            {#if updating}
              <span class="inline-flex items-center gap-2">
                <span
                  class="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin"
                ></span>
                Aktualisiere...
              </span>
            {:else}
              Daten löschen & aktualisieren
            {/if}
          </button>
        {:else}
          <button
            onclick={handleUpdate}
            disabled={updating}
            class="flex-1 py-3 rounded-xl bg-(--color-text) text-sm font-bold text-white transition-all active:scale-[0.98] disabled:opacity-60"
          >
            {#if updating}
              <span class="inline-flex items-center gap-2">
                <span
                  class="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin"
                ></span>
                Aktualisiere...
              </span>
            {:else}
              Jetzt aktualisieren
            {/if}
          </button>
        {/if}
        {#if !updating}
          <button
            onclick={() => {
              updateStore.sheetOpen = false;
              updateStore.dismiss();
            }}
            class="py-3 px-5 rounded-xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
          >
            Später
          </button>
        {/if}
      </div>
    </div>
  {/snippet}
</BottomSheet>
