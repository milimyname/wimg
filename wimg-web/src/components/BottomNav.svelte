<script lang="ts">
  import { page } from "$app/state";

  const tabs = [
    { href: "/dashboard", label: "Home", icon: "home" },
    { href: "/transactions", label: "Umsätze", icon: "list" },
    { href: "/analysis", label: "Analyse", icon: "chart" },
    { href: "/review", label: "Rückblick", icon: "review" },
    { href: "/import", label: "Import", icon: "upload" },
  ];

  function isActive(href: string): boolean {
    return page.url.pathname === href || page.url.pathname === href + "/";
  }
</script>

<nav
  class="fixed bottom-0 left-0 right-0 bg-white border-t border-(--color-border) z-20"
>
  <div class="max-w-2xl mx-auto flex">
    {#each tabs as tab}
      <a
        href={tab.href}
        class="flex-1 flex flex-col items-center py-2 text-xs transition-colors"
        class:text-primary={isActive(tab.href)}
        class:font-semibold={isActive(tab.href)}
        class:text-gray-400={!isActive(tab.href)}
        style={isActive(tab.href) ? "color: var(--color-primary)" : ""}
      >
        {#if tab.icon === "home"}
          <svg class="w-5 h-5 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
          </svg>
        {:else if tab.icon === "list"}
          <svg class="w-5 h-5 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16" />
          </svg>
        {:else if tab.icon === "chart"}
          <svg class="w-5 h-5 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
          </svg>
        {:else if tab.icon === "review"}
          <svg class="w-5 h-5 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
          </svg>
        {:else if tab.icon === "upload"}
          <svg class="w-5 h-5 mb-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
          </svg>
        {/if}
        <span>{tab.label}</span>
      </a>
    {/each}
  </div>
</nav>
