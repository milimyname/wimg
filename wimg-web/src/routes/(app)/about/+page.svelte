<script lang="ts">
  import { APP_VERSION, RELEASES_URL } from "$lib/version";
</script>

<section class="space-y-5">
  <!-- Header -->
  <div class="flex items-center gap-3">
    <a
      href="/more"
      class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
      aria-label="Zurück"
    >
      <svg
        class="w-5 h-5 text-(--color-text)"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M15 19l-7-7 7-7"
        />
      </svg>
    </a>
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">
      Über wimg
    </h2>
  </div>

  <!-- Hero card -->
  <div
    class="border border-gray-100 rounded-3xl p-6 flex flex-col items-center text-center"
  >
    <div
      class="w-16 h-16 rounded-2xl flex items-center justify-center mb-4"
      style="background: #1a1a1a"
    >
      <svg
        class="w-8 h-8 text-white"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
        />
      </svg>
    </div>
    <h3 class="text-xl font-display font-extrabold text-(--color-text) mb-1">
      wimg
    </h3>
    <p class="text-sm text-(--color-text)/70 font-medium">
      Persönliche Finanzverwaltung.<br />Lokal. Privat. Offen.
    </p>
    <p class="text-xs text-(--color-text)/50 mt-3">
      Von <span class="font-semibold">Komiljon Maksudov</span> &middot; Zig + Svelte
      + SQLite
    </p>
  </div>

  <!-- Quick info grid -->
  <div class="grid grid-cols-2 gap-3">
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <div
        class="w-9 h-9 rounded-xl bg-emerald-50 flex items-center justify-center mb-2.5"
      >
        <svg
          class="w-4.5 h-4.5 text-emerald-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
          />
        </svg>
      </div>
      <h4 class="font-bold text-sm text-(--color-text) mb-0.5">Privatsphäre</h4>
      <p class="text-xs text-(--color-text-secondary) leading-snug">
        Keine Werbung. Kein Tracking. Niemals.
      </p>
    </div>
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <div
        class="w-9 h-9 rounded-xl bg-purple-50 flex items-center justify-center mb-2.5"
      >
        <svg
          class="w-4.5 h-4.5 text-purple-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
          />
        </svg>
      </div>
      <h4 class="font-bold text-sm text-(--color-text) mb-0.5">Open Source</h4>
      <p class="text-xs text-(--color-text-secondary) leading-snug">
        Quellcode offen auf GitHub verfügbar.
      </p>
    </div>
  </div>

  <!-- Privacy details -->
  <div class="bg-white rounded-2xl p-5 border border-gray-100 space-y-3">
    <h3 class="font-bold text-sm text-(--color-text)">Datenschutz im Detail</h3>
    {#each [
      { icon: "🔒", title: "Lokal gespeichert", desc: "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig." },
      { icon: "🔐", title: "Ende-zu-Ende verschlüsselt", desc: "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext." },
      { icon: "🏦", title: "FinTS direkt zur Bank", desc: "Kein Drittanbieter zwischen dir und deiner Bank." },
      { icon: "🚫", title: "Kein Tracking", desc: "Keine Analytics, kein Sentry, kein Google. Null Telemetrie." },
      { icon: "👤", title: "Kein Account", desc: "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität." },
      { icon: "🧠", title: "KI sieht keine Klarnamen", desc: "MCP-Antworten werden von IBANs, BICs und Namen bereinigt." },
    ] as item (item.title)}
      <div class="flex gap-3 items-start">
        <span class="text-base leading-none mt-0.5">{item.icon}</span>
        <div>
          <p class="text-xs font-semibold text-(--color-text)">{item.title}</p>
          <p class="text-xs text-(--color-text-secondary) leading-snug">{item.desc}</p>
        </div>
      </div>
    {/each}
  </div>

  <!-- GitHub button -->
  <a
    href="https://github.com/milimyname/wimg"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-center gap-2.5 w-full py-3.5 bg-(--color-text) text-white font-bold text-sm rounded-2xl hover:opacity-90 transition-opacity active:scale-[0.98]"
  >
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path
        d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
      />
    </svg>
    Auf GitHub ansehen
  </a>

  <!-- MCP Connection Guide -->
  <div id="mcp">
    <h3
      class="text-lg font-display font-extrabold text-(--color-text) mb-3 flex items-center gap-2"
    >
      <svg
        class="w-4.5 h-4.5 text-purple-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
        />
      </svg>
      MCP-Verbindung
    </h3>
    <div class="bg-white rounded-2xl p-5 border border-gray-100 space-y-3">
      <p class="text-sm text-(--color-text-secondary) leading-relaxed">
        Verbinde Claude.ai mit deinem wimg, um Finanzfragen mit deinen echten Daten zu beantworten. Aktiviere zuerst Sync unter <a href="/settings" class="font-bold text-(--color-text) underline">Einstellungen</a>, dann nutze:
      </p>
      <div class="space-y-2 text-xs font-mono">
        <div class="bg-gray-50 rounded-lg px-3 py-2 break-all">
          <span class="text-(--color-text-secondary)">URL:</span> https://wimg-sync.mili-my.name/mcp
        </div>
        <div class="bg-gray-50 rounded-lg px-3 py-2">
          <span class="text-(--color-text-secondary)">Auth:</span> Bearer &lt;dein Sync-Schlüssel&gt;
        </div>
      </div>
      <ul class="text-xs text-(--color-text-secondary) leading-relaxed space-y-1 pt-1">
        <li class="flex items-start gap-2">
          <span class="text-emerald-500 shrink-0">&check;</span>
          Sync-Schlüssel = MCP-Zugang, kein extra Setup
        </li>
        <li class="flex items-start gap-2">
          <span class="text-emerald-500 shrink-0">&check;</span>
          Ende-zu-Ende verschlüsselt, Echtzeit-Synchronisierung
        </li>
        <li class="flex items-start gap-2">
          <span class="text-emerald-500 shrink-0">&check;</span>
          PII wird automatisch aus MCP-Antworten entfernt
        </li>
      </ul>
    </div>
  </div>

  <!-- Footer -->
  <footer
    class="flex flex-col items-center gap-2 pt-2 pb-6 text-(--color-text-secondary)"
  >
    <a
      href="/changelog"
      class="text-xs font-bold text-amber-600 hover:underline"
    >
      Was ist neu?
    </a>
    <span class="text-xs font-mono opacity-50">v{APP_VERSION}</span>
  </footer>
</section>
