<script lang="ts">
  import Drawer from "../../../components/Drawer.svelte";

  let drawerAOpen = $state(false);
  let drawerBOpen = $state(false);
</script>

<div class="space-y-6 px-4 py-6">
  <h2 class="text-2xl font-display font-extrabold">Drawer Test</h2>
  <p class="text-sm text-(--color-text-secondary)">
    Test stacking, indent effect, input isolation, and close behavior.
  </p>

  <button
    onclick={() => (drawerAOpen = true)}
    class="w-full py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm"
  >
    Open Drawer A
  </button>

  <!-- Scrollable content to verify indent -->
  <div class="space-y-3">
    {#each Array(20) as _, i}
      <div
        class="h-14 rounded-xl bg-gray-100 flex items-center px-4 text-sm text-gray-400"
      >
        Item {i + 1}
      </div>
    {/each}
  </div>

  <button
    onclick={() => (drawerAOpen = true)}
    class="w-full py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm"
  >
    Open Drawer A (bottom)
  </button>
</div>

<!-- Drawer A -->
<Drawer
  open={drawerAOpen}
  onclose={() => (drawerAOpen = false)}
  snaps={[0.55, 0.88]}
>
  {#snippet children({ handle, content })}
    <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
      <div class="w-12 h-1.5 bg-gray-200 rounded-full"></div>
    </div>
    <div class="px-6 pb-6" {@attach content}>
      <h3 class="text-lg font-bold mb-4">Drawer A</h3>
      <p class="text-sm text-gray-500 mb-4">
        This is the first drawer. Open Drawer B to test stacking.
      </p>

      <button
        onclick={() => (drawerBOpen = true)}
        class="w-full py-3 rounded-xl bg-indigo-100 text-indigo-700 font-bold text-sm mb-4"
      >
        Open Drawer B (nested)
      </button>

      <div class="space-y-2">
        {#each Array(15) as _, i}
          <div
            class="h-10 rounded-lg bg-gray-50 flex items-center px-3 text-sm text-gray-400"
          >
            List item {i + 1}
          </div>
        {/each}
      </div>
    </div>
  {/snippet}
</Drawer>

<!-- Drawer B (stacks on top of A) -->
<Drawer open={drawerBOpen} onclose={() => (drawerBOpen = false)} snaps={[0.45]}>
  {#snippet children({ handle, content })}
    <div class="pt-3 pb-2 flex justify-center shrink-0" {@attach handle}>
      <div class="w-12 h-1.5 bg-gray-200 rounded-full"></div>
    </div>
    <div class="px-6 pb-6" {@attach content}>
      <h3 class="text-lg font-bold mb-2">Drawer B (nested)</h3>
      <p class="text-sm text-gray-500 mb-4">
        Drawer A should be scaled down and dimmed behind this one. Swiping on
        Drawer A should do nothing.
      </p>
      <button
        onclick={() => (drawerBOpen = false)}
        class="w-full py-3 rounded-xl bg-red-100 text-red-700 font-bold text-sm"
      >
        Close Drawer B
      </button>
    </div>
  {/snippet}
</Drawer>
