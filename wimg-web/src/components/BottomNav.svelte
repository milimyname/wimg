<script lang="ts">
  import { page } from "$app/state";
  import { pushState } from "$app/navigation";
  import { updateStore } from "$lib/update.svelte";
  import { featureStore } from "$lib/features.svelte";
  import { paletteStore } from "$lib/commandPalette.svelte";

  const tabs = [
    { href: "/dashboard", label: "Home", icon: "home" },
    { href: "/transactions", label: "Umsätze", icon: "list" },
    { href: "/more", label: "Mehr", icon: "more" },
  ];

  const featureRoutes: Record<string, string> = {
    "/debts": "debts",
    "/recurring": "recurring",
    "/review": "review",
  };

  const moreSubRoutes = $derived(
    ["/more", "/analysis", "/debts", "/recurring", "/import", "/review", "/settings", "/about"].filter(
      (r) => !featureRoutes[r] || featureStore.isEnabled(featureRoutes[r]),
    ),
  );

  function isActive(href: string): boolean {
    if (href === "/more") {
      return moreSubRoutes.some(
        (r) =>
          page.url.pathname === r || page.url.pathname === r + "/",
      );
    }
    return page.url.pathname === href || page.url.pathname === href + "/";
  }
</script>

<nav
  class="nav-bar fixed bottom-0 left-0 right-0 bg-white/95 backdrop-blur-xl z-20 rounded-t-[2rem] shadow-[0_-4px_24px_-8px_rgba(0,0,0,0.05)]"
  style="padding-bottom: env(safe-area-inset-bottom, 0px)"
>
  <div class="max-w-lg mx-auto flex px-4 pt-3 pb-4">
    <!-- Search button (opens Command Palette) -->
    <button
      onclick={() => { pushState("?cmd", { sheet: "command-palette" }); paletteStore.show(); }}
      class="flex-1 flex flex-col items-center gap-1 py-1.5 text-gray-400 transition-colors bg-transparent border-none cursor-pointer"
      style="-webkit-tap-highlight-color: transparent"
    >
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
      <span class="text-[11px] font-bold">Suche</span>
    </button>

    {#each tabs as tab}
      <a
        href={tab.href}
        class="flex-1 flex flex-col items-center gap-1 py-1.5 transition-colors"
        class:text-amber-600={isActive(tab.href)}
        class:font-bold={isActive(tab.href)}
        class:text-gray-400={!isActive(tab.href)}
      >
        {#if tab.icon === "home"}
          <svg class="w-6 h-6" fill={isActive(tab.href) ? "currentColor" : "none"} stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width={isActive(tab.href) ? "0" : "1.5"} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
          </svg>
        {:else if tab.icon === "list"}
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 6h16M4 10h16M4 14h16M4 18h16" />
          </svg>
        {:else if tab.icon === "more"}
          <svg class="w-6 h-6" fill={isActive(tab.href) ? "currentColor" : "none"} stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width={isActive(tab.href) ? "0" : "1.5"} d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
          </svg>
        {/if}
        <span class="text-[11px] font-bold">{tab.label}</span>
      </a>
    {/each}

    {#if updateStore.showBanner}
      <button
        onclick={() => (updateStore.sheetOpen = true)}
        class="update-tab flex-1 flex flex-col items-center gap-1 py-1.5"
      >
        <div class="update-icon-wrap">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          <span class="sparkle sparkle-1"></span>
          <span class="sparkle sparkle-2"></span>
          <span class="sparkle sparkle-3"></span>
        </div>
        <span class="text-[11px] font-bold">Update</span>
      </button>
    {/if}
  </div>
</nav>

<style>
  .update-tab {
    animation: tab-pop-in 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
    color: var(--color-accent);
    position: relative;
    border: none;
    background: none;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  .update-tab:active {
    transform: scale(0.92);
    transition: transform 0.1s;
  }

  .update-icon-wrap {
    position: relative;
    animation: icon-glow 2.5s ease-in-out infinite;
  }

  /* Sparkle particles */
  .sparkle {
    position: absolute;
    width: 4px;
    height: 4px;
    border-radius: 9999px;
    background: var(--color-accent);
    opacity: 0;
    pointer-events: none;
  }

  .sparkle-1 {
    top: -2px;
    right: -3px;
    animation: sparkle-pop 2.5s ease-in-out infinite 0.2s;
  }
  .sparkle-2 {
    top: -4px;
    left: 50%;
    width: 3px;
    height: 3px;
    animation: sparkle-pop 2.5s ease-in-out infinite 0.8s;
  }
  .sparkle-3 {
    bottom: 0;
    right: -4px;
    width: 3px;
    height: 3px;
    animation: sparkle-pop 2.5s ease-in-out infinite 1.4s;
  }

  @keyframes tab-pop-in {
    0% {
      opacity: 0;
      transform: scale(0.5) translateY(8px);
    }
    100% {
      opacity: 1;
      transform: scale(1) translateY(0);
    }
  }

  @keyframes icon-glow {
    0%, 100% {
      filter: drop-shadow(0 0 0px transparent);
    }
    50% {
      filter: drop-shadow(0 0 6px var(--color-accent));
    }
  }

  @keyframes sparkle-pop {
    0%, 100% {
      opacity: 0;
      transform: scale(0);
    }
    15% {
      opacity: 1;
      transform: scale(1);
    }
    30% {
      opacity: 0;
      transform: scale(0);
    }
  }

  /* Smooth fade-out when BottomSheet opens */
  .nav-bar {
    transition: opacity 0.25s ease, transform 0.25s ease;
  }

  :global(html.sheet-active) .nav-bar {
    opacity: 0;
    transform: translateY(100%);
    pointer-events: none;
  }
</style>
