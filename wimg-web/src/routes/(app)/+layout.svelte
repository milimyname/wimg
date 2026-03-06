<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { init } from "$lib/wasm";
  import { accountStore } from "$lib/account.svelte";
  import { updateStore } from "$lib/update.svelte";
  import { dropStore } from "$lib/drop.svelte";
  import BottomNav from "../../components/BottomNav.svelte";
  import Toast from "../../components/Toast.svelte";
  import UpdateBanner from "../../components/UpdateBanner.svelte";
  import AccountSwitcher from "../../components/AccountSwitcher.svelte";
  import GlobalDropOverlay from "../../components/GlobalDropOverlay.svelte";

  let { children } = $props();
  let loading = $state(true);
  let error = $state<string | null>(null);
  let showDrop = $state(false);
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

  function handleFileDrop(file: File) {
    showDrop = false;
    dragCounter = 0;
    dropStore.set(file);
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

    updateStore.init();
  });
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

<svelte:window
  ondragenter={handleDragEnter}
  ondragleave={handleDragLeave}
  ondrop={handleDrop}
/>

<GlobalDropOverlay visible={showDrop} ondrop={handleFileDrop} />
