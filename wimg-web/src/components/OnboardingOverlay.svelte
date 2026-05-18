<script lang="ts">
  import { setSyncKey, syncPull, connectSync, clearSyncKey } from "$lib/sync";

  let { onclose }: { onclose: () => void } = $props();

  let step = $state(0);
  let showLinkPanel = $state(false);
  let pasteInput = $state("");
  let linking = $state(false);
  let linkError = $state("");
  let linkSuccess = $state("");

  async function handleLink() {
    const key = pasteInput.trim();
    if (!key) return;
    linking = true;
    linkError = "";
    linkSuccess = "";
    try {
      setSyncKey(key);
      const pulled = await syncPull(key);
      connectSync();
      linkSuccess = `Verknüpft — ${pulled} Einträge übernommen`;
      // Brief beat for the user to see the success state.
      setTimeout(() => onclose(), 600);
    } catch (e) {
      linkError = e instanceof Error ? e.message : String(e);
      // Bogus key or pull failed — roll back so we don't leave a stale key
      // (also clears LS_SYNC_LAST_TS and the in-memory encryption key).
      clearSyncKey();
    } finally {
      linking = false;
    }
  }

  const cards = [
    {
      title: "Deine Finanzen, auf deinem Ger\u00e4t",
      subtitle:
        "Keine Cloud, kein Konto. Deine Daten bleiben auf deinem Ger\u00e4t \u2014 lokal, privat, offline.",
      iconBg: "bg-emerald-100",
      iconColor: "text-emerald-600",
      icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" /></svg>`,
    },
    {
      title: "Importiere deine Bankdaten",
      subtitle:
        "Lade eine CSV-Datei von Comdirect, Trade Republic oder Scalable Capital hoch.",
      iconBg: "bg-blue-100",
      iconColor: "text-blue-600",
      icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" /></svg>`,
    },
    {
      title: "Wiederkehrend erkennen",
      subtitle:
        "Erkenne Abos und Fixkosten automatisch. Sieh, was monatlich f\u00e4llig wird.",
      iconBg: "bg-emerald-100",
      iconColor: "text-emerald-600",
      icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg>`,
    },
    {
      title: "Ger\u00e4te synchronisieren",
      subtitle:
        "Synchronisiere optional zwischen Ger\u00e4ten \u2014 Ende-zu-Ende verschl\u00fcsselt.",
      iconBg: "bg-amber-100",
      iconColor: "text-amber-600",
      icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 12a9 9 0 016.5-8.63m5 0A9 9 0 0121 12m0 0a9 9 0 01-6.5 8.63m-5 0A9 9 0 013 12" /></svg>`,
    },
  ];

  $effect(() => {
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
    };
  });

  let startX = 0;
  let deltaX = $state(0);

  function handleTouchStart(e: TouchEvent) {
    startX = e.touches[0].clientX;
    deltaX = 0;
  }

  function handleTouchMove(e: TouchEvent) {
    deltaX = e.touches[0].clientX - startX;
  }

  function handleTouchEnd() {
    if (deltaX < -50 && step < cards.length - 1) step++;
    else if (deltaX > 50 && step > 0) step--;
    deltaX = 0;
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm flex items-center justify-center p-5"
  ontouchstart={handleTouchStart}
  ontouchmove={handleTouchMove}
  ontouchend={handleTouchEnd}
>
  <div class="max-w-sm w-full bg-white rounded-3xl p-8 shadow-xl relative">
    <!-- Skip -->
    <button
      onclick={onclose}
      class="absolute top-5 right-6 text-sm font-medium text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
    >
      Überspringen
    </button>

    <!-- Card content -->
    {#each cards as card, i}
      {#if i === step}
        <div class="flex flex-col items-center text-center pt-6">
          <!-- Icon -->
          <div
            class="w-20 h-20 rounded-full {card.iconBg} flex items-center justify-center mb-6 {card.iconColor}"
          >
            {@html card.icon}
          </div>

          <h2 class="text-xl font-display font-extrabold mb-3">{card.title}</h2>
          <p class="text-sm text-(--color-text-secondary) leading-relaxed mb-8">
            {card.subtitle}
          </p>
        </div>
      {/if}
    {/each}

    <!-- Dots -->
    <div class="flex justify-center gap-2 mb-6">
      {#each cards as _, i}
        <button
          onclick={() => (step = i)}
          class="w-2 h-2 rounded-full transition-all {i === step
            ? 'bg-(--color-text) w-6'
            : 'bg-gray-300'}"
          aria-label="Seite {i + 1}"
        ></button>
      {/each}
    </div>

    <!-- Action button -->
    <button
      onclick={() => {
        if (step < cards.length - 1) {
          step++;
        } else {
          onclose();
        }
      }}
      class="w-full py-3.5 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
    >
      {step < cards.length - 1 ? "Weiter" : "Los geht's"}
    </button>

    <!-- Existing-user shortcut on the last (sync) card -->
    {#if step === cards.length - 1}
      {#if !showLinkPanel}
        <button
          onclick={() => (showLinkPanel = true)}
          class="w-full mt-3 flex items-center justify-center gap-1.5 text-xs font-extrabold text-(--color-text) hover:opacity-70 transition-opacity"
        >
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m-4 6H4m0 0l4 4m-4-4l4-4" />
          </svg>
          Schon wimg-User? Sync-Schlüssel einfügen
        </button>
      {:else}
        <div class="mt-4 pt-4 border-t border-(--color-border) space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-xs font-bold text-(--color-text)">Sync-Schlüssel einfügen</span>
            <button
              onclick={() => {
                showLinkPanel = false;
                pasteInput = "";
                linkError = "";
                linkSuccess = "";
              }}
              class="text-xs text-(--color-text-secondary) hover:text-(--color-text)"
            >
              Abbrechen
            </button>
          </div>
          <div class="flex gap-2">
            <input
              type="text"
              bind:value={pasteInput}
              placeholder="XXXX-XXXX-XXXX-XXXX"
              class="flex-1 bg-(--color-bg) rounded-xl px-3 py-2 text-xs font-mono text-(--color-text) outline-none border border-(--color-border) focus:border-(--color-text)"
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
            />
            <button
              onclick={handleLink}
              disabled={linking || !pasteInput.trim()}
              class="px-3 py-2 rounded-xl bg-(--color-text) text-(--color-bg) text-xs font-bold disabled:opacity-50 transition-opacity"
            >
              {linking ? "..." : "Verknüpfen"}
            </button>
          </div>
          {#if linkError}
            <p class="text-xs text-red-600">{linkError}</p>
          {/if}
          {#if linkSuccess}
            <p class="text-xs text-emerald-600">{linkSuccess}</p>
          {/if}
        </div>
      {/if}
    {/if}
  </div>
</div>
