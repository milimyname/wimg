<script lang="ts">
  import { onMount, onDestroy, tick } from "svelte";
  import { goto, pushState } from "$app/navigation";
  import { page } from "$app/state";
  import { init, takeSnapshot } from "$lib/wasm";
  import { accountStore } from "$lib/account.svelte";
  import { updateStore } from "$lib/update.svelte";
  import { dropStore } from "$lib/drop.svelte";
  import { isSyncEnabled, connectSync, disconnectSync } from "$lib/sync";
  import { paletteStore } from "$lib/commandPalette.svelte";
  import { LS_ONBOARDING_COMPLETED, LS_LAST_SNAPSHOT_MONTH } from "$lib/config";
  import BottomNav from "../../components/BottomNav.svelte";
  import Toast from "../../components/Toast.svelte";
  import UpdateBanner from "../../components/UpdateBanner.svelte";
  import AccountSwitcher from "../../components/AccountSwitcher.svelte";
  import GlobalDropOverlay from "../../components/GlobalDropOverlay.svelte";
  import OnboardingOverlay from "../../components/OnboardingOverlay.svelte";

  let { children } = $props();
  let loading = $state(true);
  let error = $state<string | null>(null);
  let showDrop = $state(false);
  let showOnboarding = $state(false);
  let showDevTools = $state(false);
  let dragCounter = 0;

  function hasFiles(e: DragEvent): boolean {
    return e.dataTransfer?.types.includes("Files") ?? false;
  }

  function handleDragEnter(e: DragEvent) {
    if (!hasFiles(e)) return;
    dragCounter++;
    if (dragCounter === 1) showDrop = true;
  }

  function handleDragLeave() {
    dragCounter--;
    if (dragCounter <= 0) {
      dragCounter = 0;
      showDrop = false;
    }
  }

  function handleDrop(e: DragEvent) {
    e.preventDefault();
    dragCounter = 0;
    showDrop = false;
  }

  function handleFileDrop(files: File[]) {
    showDrop = false;
    dragCounter = 0;
    dropStore.set(files);
    goto("/import");
  }

  onMount(async () => {
    try {
      await init();
      accountStore.reload();
    } catch (e) {
      error = e instanceof Error ? e.message : "Failed to initialize";
    } finally {
      loading = false;
    }

    // Scroll to hash anchor after content is rendered (SvelteKit can't do it
    // while the loading gate hides children)
    if (window.location.hash) {
      await tick();
      document.getElementById(window.location.hash.slice(1))?.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    // Show onboarding on first visit
    if (!localStorage.getItem(LS_ONBOARDING_COMPLETED)) {
      showOnboarding = true;
    }

    // Auto-snapshot: take monthly snapshot if we haven't this month
    try {
      const now = new Date();
      const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
      const lastSnapshot = localStorage.getItem(LS_LAST_SNAPSHOT_MONTH);
      if (lastSnapshot !== currentMonth) {
        takeSnapshot(now.getFullYear(), now.getMonth() + 1);
        localStorage.setItem(LS_LAST_SNAPSHOT_MONTH, currentMonth);
      }
    } catch {
      // Silently ignore snapshot errors
    }

    // DevTools: enabled in dev mode or via ?devtools URL param
    if (import.meta.env.DEV || new URLSearchParams(window.location.search).has("devtools")) {
      showDevTools = true;
      import("$lib/devtools.svelte").then((m) => m.devtoolsStore.enable());
    }

    // Dev mode: unregister stale service workers so rebuilt WASM isn't served from cache
    if (import.meta.env.DEV && "serviceWorker" in navigator) {
      navigator.serviceWorker.getRegistrations().then((regs) => {
        for (const reg of regs) reg.unregister();
      });
    }

    updateStore.init();

    // Real-time sync: connect WebSocket (onReconnect handles initial pull)
    if (isSyncEnabled()) {
      connectSync();
    }
  });

  onDestroy(() => {
    disconnectSync();
  });

  function openPalette() {
    if (paletteStore.open) return;
    pushState("", { sheet: "command-palette" });
    paletteStore.show();
  }
</script>

<div
  class="min-h-screen bg-(--color-bg) page-shell"
  style="padding-bottom: calc(5.5rem + env(safe-area-inset-bottom, 0px))"
>
  <header class="sticky top-0 z-10 bg-(--color-bg)/90 backdrop-blur-xl px-5 py-4 flex items-center justify-between">
    <h1 class="text-xl font-display font-extrabold text-(--color-text)">wimg</h1>
    <AccountSwitcher />
  </header>

  <UpdateBanner />

  {#if loading}
    <div class="flex items-center justify-center py-20">
      <div
        class="animate-spin w-8 h-8 border-4 border-(--color-text) border-t-transparent rounded-full"
      ></div>
    </div>
  {:else if error}
    <main class="max-w-lg mx-auto px-5 py-6">
      <div
        class="bg-red-50 rounded-3xl p-5 text-red-700 text-sm"
      >
        {error}
      </div>
    </main>
  {:else}
    <main class="max-w-lg mx-auto px-5 py-2">
      {@render children()}
    </main>
  {/if}
  <BottomNav />
</div>

<Toast />

{#if showDevTools}
  {#await import("../../components/DevTools.svelte") then DevTools}
    <DevTools.default />
  {/await}
{/if}

{#if paletteStore.open}
  {#await import("../../components/CommandPalette.svelte") then Palette}
    <Palette.default />
  {/await}
{/if}

{#if showOnboarding}
  <OnboardingOverlay
    onclose={() => {
      localStorage.setItem(LS_ONBOARDING_COMPLETED, "true");
      showOnboarding = false;
    }}
  />
{/if}

<svelte:window
  ondragenter={handleDragEnter}
  ondragleave={handleDragLeave}
  ondrop={handleDrop}
  onkeydown={(e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      if (page.state.sheet === "command-palette") {
        history.back();
      } else {
        openPalette();
      }
    }
    if (showDevTools && e.ctrlKey && e.shiftKey && e.key === "D") {
      e.preventDefault();
      import("$lib/devtools.svelte").then((m) => m.devtoolsStore.toggle());
    }
  }}
/>

<GlobalDropOverlay visible={showDrop} ondrop={handleFileDrop} />
