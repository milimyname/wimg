<script lang="ts">
  const items = [
    { href: "/debts", label: "Schulden", icon: "creditcard", color: "bg-rose-100 text-rose-600" },
    { href: "/import", label: "Import", icon: "upload", color: "bg-blue-100 text-blue-600" },
    { href: "/review", label: "Rückblick", icon: "review", color: "bg-violet-100 text-violet-600" },
    { href: "/settings", label: "Einstellungen", icon: "settings", color: "bg-amber-100 text-amber-600" },
  ];
</script>

<section class="space-y-5">
  <h2 class="text-2xl font-display font-extrabold text-(--color-text)">Mehr</h2>

  <div class="grid grid-cols-2 gap-4">
    {#each items as item}
      <a
        href={item.href}
        class="bg-white rounded-3xl p-5 flex flex-col items-center gap-3 shadow-sm hover:shadow-md transition-shadow active:scale-[0.98]"
      >
        <div class="w-12 h-12 rounded-2xl {item.color} flex items-center justify-center">
          {#if item.icon === "creditcard"}
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
            </svg>
          {:else if item.icon === "upload"}
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
            </svg>
          {:else if item.icon === "review"}
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
            </svg>
          {:else if item.icon === "settings"}
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          {/if}
        </div>
        <span class="text-sm font-bold text-(--color-text)">{item.label}</span>
      </a>
    {/each}
  </div>
</section>
