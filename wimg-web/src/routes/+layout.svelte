<script lang="ts">
  import "../app.css";
  import { onMount } from "svelte";
  import { init } from "$lib/wasm";
  import { updateStore } from "$lib/update.svelte";
  import BottomNav from "../components/BottomNav.svelte";
  import Toast from "../components/Toast.svelte";
  import UpdateBanner from "../components/UpdateBanner.svelte";

  let { children } = $props();
  let loading = $state(true);
  let error = $state<string | null>(null);

  onMount(async () => {
    try {
      await init();
    } catch (e) {
      error = e instanceof Error ? e.message : "Failed to initialize";
    } finally {
      loading = false;
    }

    updateStore.init();
  });
</script>

<div class="min-h-screen bg-(--color-bg) pb-16">
  <header
    class="sticky top-0 z-10 bg-white/80 backdrop-blur-sm border-b border-(--color-border) px-4 py-3"
  >
    <h1 class="text-xl font-bold text-(--color-primary)">wimg</h1>
  </header>

  <UpdateBanner />

  {#if loading}
    <div class="flex items-center justify-center py-20">
      <div
        class="animate-spin w-8 h-8 border-4 border-(--color-primary) border-t-transparent rounded-full"
      ></div>
    </div>
  {:else if error}
    <main class="max-w-2xl mx-auto px-4 py-6">
      <div
        class="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700"
      >
        {error}
      </div>
    </main>
  {:else}
    <main class="max-w-2xl mx-auto px-4 py-6">
      {@render children()}
    </main>
  {/if}

  <BottomNav />
  <Toast />
</div>
