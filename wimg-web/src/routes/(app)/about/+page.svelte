<script lang="ts">
  import { APP_VERSION, RELEASES_URL } from "$lib/version";

  const faqs = [
    {
      q: "Sind meine Daten sicher?",
      a: "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext.",
    },
    {
      q: "Welche Banken werden unterstützt?",
      a: "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden.",
    },
    {
      q: "Wie funktioniert der Import?",
      a: "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln.",
    },
    {
      q: "Ist wimg wirklich kostenlos?",
      a: "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten.",
    },
    {
      q: "Wo werden die Daten gespeichert?",
      a: "Im Browser: OPFS (Origin Private File System). Auf iOS: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt.",
    },
    {
      q: "Was ist der MCP-Server?",
      a: "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen, Kategorien setzen und Schulden verwalten — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert.",
    },
    {
      q: "Gibt es Entwickler-Tools?",
      a: "Ja! Im Dev-Modus oder mit ?devtools in der URL kannst du mit Ctrl+Shift+D ein DevTools-Panel öffnen. Es zeigt WASM-Performance, Speicherverbrauch, Sync-Status, SQL-Abfragen, localStorage und mehr — inspiriert von TanStack DevTools.",
    },
    {
      q: "Wie kann ich beitragen?",
      a: "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen.",
    },
  ];
</script>

<section class="space-y-6">
  <!-- Header with back -->
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

  <!-- Hero -->
  <div class="flex flex-col items-center text-center pt-4 pb-2">
    <div class="relative mb-5">
      <div
        class="w-20 h-20 rounded-2xl bg-(--color-text) flex items-center justify-center shadow-lg"
      >
        <svg
          class="w-10 h-10 text-white"
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
      <div
        class="absolute -bottom-1.5 -right-1.5 w-7 h-7 bg-emerald-500 rounded-full border-[3px] border-(--color-bg) flex items-center justify-center"
      >
        <svg
          class="w-3.5 h-3.5 text-white"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2.5"
            d="M5 13l4 4L19 7"
          />
        </svg>
      </div>
    </div>

    <h3 class="text-2xl font-display font-extrabold text-(--color-text) mb-1">
      wimg
    </h3>
    <p class="text-(--color-text-secondary) leading-snug max-w-[260px]">
      Persönliche Finanzverwaltung. Lokal. Privat. Offen.
    </p>
  </div>

  <!-- About text -->
  <div class="text-center px-2">
    <p class="text-(--color-text-secondary) text-sm leading-relaxed">
      Ein Open-Source-Projekt von <span
        class="font-semibold text-(--color-text)">Komiljon Maksudov</span
      >. Gebaut mit <span class="font-medium text-(--color-text)">Zig</span>,
      <span class="font-medium text-(--color-text)">Svelte 5</span> und
      <span class="font-medium text-(--color-text)">SQLite</span>.
    </p>
  </div>

  <!-- Privacy badge -->
  <div class="bg-emerald-50 p-4 rounded-2xl flex items-center gap-4">
    <div
      class="w-11 h-11 rounded-full bg-emerald-500 flex items-center justify-center shrink-0"
    >
      <svg
        class="w-5 h-5 text-white"
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
    <div>
      <h4 class="font-bold text-(--color-text) text-sm">Privatsphäre zuerst</h4>
      <p class="text-xs text-(--color-text-secondary)">
        Keine Werbung. Kein Tracking. Niemals.
      </p>
    </div>
  </div>

  <!-- GitHub button -->
  <a
    href="https://github.com/milimyname/wimg"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-center gap-2 w-full py-3.5 border-2 border-(--color-text) text-(--color-text) font-bold text-sm rounded-2xl hover:bg-(--color-text) hover:text-white transition-colors active:scale-[0.98]"
  >
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path
        d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
      />
    </svg>
    GitHub
  </a>

  <!-- MCP Connection Guide -->
  <div id="mcp">
    <a href="#mcp" class="text-xl font-display font-extrabold text-(--color-text) mb-4 flex items-center gap-2">
      <svg
        class="w-5 h-5 text-purple-500"
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
    </a>

    <p class="text-sm text-(--color-text-secondary) leading-relaxed mb-4">
      Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per
      MCP-Protokoll Zugriff auf deine Finanzdaten geben.
    </p>

    <!-- Steps -->
    <div class="space-y-3 mb-4">
      <a
        href="/settings#sync"
        class="bg-white rounded-2xl p-4 shadow-sm flex gap-3 items-center hover:shadow-md transition-shadow"
      >
        <span
          class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-sm shrink-0"
          >1</span
        >
        <div class="flex-1">
          <p class="font-semibold text-sm text-(--color-text)">
            Sync aktivieren
          </p>
          <p class="text-xs text-(--color-text-secondary) mt-0.5">
            Unter Einstellungen einen Sync-Schlüssel erstellen.
          </p>
        </div>
        <svg
          class="w-4 h-4 text-(--color-text-secondary) shrink-0"
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
      </a>
      <div class="bg-white rounded-2xl p-4 shadow-sm flex gap-3">
        <span
          class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-sm shrink-0"
          >2</span
        >
        <div>
          <p class="font-semibold text-sm text-(--color-text)">
            MCP-Client konfigurieren
          </p>
          <p class="text-xs text-(--color-text-secondary) mt-0.5">
            In Claude Desktop oder Claude Code die folgende Konfiguration
            hinzufügen:
          </p>
          <div
            class="mt-2 bg-gray-50 rounded-xl p-3 text-xs font-mono text-(--color-text) overflow-x-auto"
            style="scrollbar-width: none;"
          >
            <pre>{`{
  "mcpServers": {
    "wimg": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://wimg-sync.mili-my.name/mcp",
        "--header",
        "Authorization: Bearer DEIN-SYNC-SCHLÜSSEL"
      ]
    }
  }
}`}</pre>
          </div>
        </div>
      </div>
      <div class="bg-white rounded-2xl p-4 shadow-sm flex gap-3">
        <span
          class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-sm shrink-0"
          >3</span
        >
        <div>
          <p class="font-semibold text-sm text-(--color-text)">Nutzen</p>
          <p class="text-xs text-(--color-text-secondary) mt-0.5">
            Frage Claude z.B. "Zeig mir meine Ausgaben diesen Monat" oder
            "Kategorisiere meine letzten Transaktionen".
          </p>
        </div>
      </div>
    </div>

    <!-- Privacy Warning -->
    <div class="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex gap-3">
      <svg
        class="w-5 h-5 text-amber-600 shrink-0 mt-0.5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.072 16.5c-.77.833.192 2.5 1.732 2.5z"
        />
      </svg>
      <div>
        <h4 class="font-bold text-amber-800 text-sm mb-1">
          Datenschutz-Hinweis
        </h4>
        <p class="text-xs text-amber-700 leading-relaxed">
          Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten
          (Transaktionen, Schulden, Konten) an diesen Client weitergegeben. Die
          Daten sind zwar Ende-zu-Ende verschlüsselt zwischen deinen Geräten und
          dem Server, aber der MCP-Client selbst kann die entschlüsselten Daten
          lesen. <strong>Zum Schutz deiner Privatsphäre werden personenbezogene
          Daten (IBANs, Kartennummern, Referenznummern, Namen) automatisch aus
          Transaktionsbeschreibungen entfernt, bevor sie an den MCP-Client
          gesendet werden.</strong> Händlernamen bleiben erhalten, damit die
          KI-Kategorisierung funktioniert. Verwende nur vertrauenswürdige
          MCP-Clients und teile deinen Sync-Schlüssel niemals mit Dritten.
        </p>
      </div>
    </div>
  </div>

  <!-- FAQ -->
  <div id="faq">
    <a href="#faq" class="text-xl font-display font-extrabold text-(--color-text) mb-4 flex items-center gap-2">
      <svg
        class="w-5 h-5 text-amber-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      Häufig gestellte Fragen
    </a>

    <div class="space-y-3">
      {#each faqs as faq}
        <details class="group bg-white rounded-2xl shadow-sm overflow-hidden">
          <summary
            class="flex cursor-pointer items-center justify-between p-4 list-none select-none"
          >
            <span class="font-semibold text-sm text-(--color-text) pr-4"
              >{faq.q}</span
            >
            <svg
              class="w-4 h-4 text-(--color-text-secondary) shrink-0 transition-transform group-open:rotate-180"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </summary>
          <div
            class="px-4 pb-4 text-sm text-(--color-text-secondary) leading-relaxed"
          >
            {faq.a}
          </div>
        </details>
      {/each}
    </div>
  </div>

  <!-- Footer -->
  <footer
    class="flex flex-col items-center gap-3 pt-4 pb-6 text-(--color-text-secondary)"
  >
    <a
      href={RELEASES_URL}
      target="_blank"
      rel="noopener noreferrer"
      class="text-xs font-bold text-amber-600 hover:underline"
    >
      Was ist neu?
    </a>
    <span class="text-xs font-mono opacity-60">Version {APP_VERSION}</span>
  </footer>
</section>

<style>
  summary::-webkit-details-marker,
  summary::marker {
    display: none;
  }
</style>
