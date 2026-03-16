<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import { APP_VERSION, RELEASES_URL } from "$lib/version";

  // Scroll to hash anchor and auto-open <details> after navigation completes.
  // When navigating from the Command Palette, the Drawer locks body scroll
  // with position:fixed — scrollIntoView won't work until the sheet closes and
  // unlocks the body. We poll until the body is unlocked, then scroll.
  afterNavigate(() => {
    const hash = window.location.hash;
    if (!hash) return;
    const id = hash.slice(1);

    function scrollToAnchor() {
      // Wait for Drawer to unlock body scroll
      if (document.body.style.position === "fixed") {
        requestAnimationFrame(scrollToAnchor);
        return;
      }
      const el = document.getElementById(id);
      if (!el) return;
      if (el.tagName === "DETAILS") (el as HTMLDetailsElement).open = true;
      el.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    scrollToAnchor();
  });

  const faqs = [
    {
      id: "faq-sicherheit",
      q: "Sind meine Daten sicher?",
      a: "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext.",
    },
    {
      id: "faq-banken",
      q: "Welche Banken werden unterstützt?",
      a: "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden.",
    },
    {
      id: "faq-import",
      q: "Wie funktioniert der Import?",
      a: "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln.",
    },
    {
      id: "faq-kategorisierung",
      q: "Wie funktioniert die Kategorisierung?",
      a: "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an. Für den Rest hilft Claude per MCP.",
    },
    {
      id: "faq-kostenlos",
      q: "Ist wimg wirklich kostenlos?",
      a: "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten.",
    },
    {
      id: "faq-speicherung",
      q: "Wo werden die Daten gespeichert?",
      a: "Im Browser: OPFS (Origin Private File System). Auf iOS: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt.",
    },
    {
      id: "faq-mcp",
      q: "Was ist der MCP-Server?",
      a: "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen, Kategorien setzen und Schulden verwalten — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert.",
    },
    {
      id: "faq-devtools",
      q: "Gibt es Entwickler-Tools?",
      a: "Ja! Im Dev-Modus oder mit ?devtools in der URL kannst du mit Ctrl+Shift+D ein DevTools-Panel öffnen. Es zeigt WASM-Performance, Speicherverbrauch, Sync-Status, SQL-Abfragen, localStorage und mehr — inspiriert von TanStack DevTools.",
    },
    {
      id: "faq-autolearn",
      q: "Wie funktioniert Auto-Learn?",
      a: "Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort (z.B. \"REWE\" → Lebensmittel). Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet. Alle gelernten Regeln findest du unter Einstellungen → Regeln, wo du sie auch einzeln löschen kannst.",
    },
    {
      id: "faq-vermoegen",
      q: "Was zeigt das Vermögens-Diagramm?",
      a: "Das Vermögens-Diagramm auf der Analyse-Seite zeigt dein kumulatives Nettovermögen über die Zeit — basierend auf monatlichen Snapshots (Einnahmen minus Ausgaben). Du brauchst mindestens 2 Snapshots. Snapshots werden automatisch jeden Monat erstellt, oder manuell über die Command Palette (\"Snapshot erstellen\").",
    },
    {
      id: "faq-sync",
      q: "Wie synchronisiere ich zwischen Geräten?",
      a: "Gehe zu Einstellungen → Sync aktivieren. Dadurch wird ein einzigartiger Sync-Schlüssel erstellt. Kopiere diesen Schlüssel und füge ihn auf dem zweiten Gerät ein (Einstellungen → Gerät verknüpfen). Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt. Ohne Sync funktioniert alles lokal weiter.",
    },
    {
      id: "faq-sparziele",
      q: "Wie funktionieren Sparziele?",
      a: "Unter Mehr → Sparziele kannst du Sparziele mit Name, Icon, Zielbetrag und optionaler Deadline erstellen. Über den \"Einzahlen\"-Button trägst du Beträge ein und siehst deinen Fortschritt als Prozentbalken. Sparziele werden über Sync zwischen Geräten synchronisiert.",
    },
    {
      id: "faq-recurring",
      q: "Wie erkennt wimg Abos und wiederkehrende Zahlungen?",
      a: "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos mit Betrag, Intervall und dem nächsten Fälligkeitsdatum. Preisänderungen werden ebenfalls erkannt.",
    },
    {
      id: "faq-offline",
      q: "Funktioniert wimg offline?",
      a: "Ja, vollständig. wimg ist eine PWA (Progressive Web App) und kann über den Browser installiert werden. Alle Daten liegen lokal in SQLite (OPFS). Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion. Sync ist optional und funktioniert nur bei Internetverbindung.",
    },
    {
      id: "faq-darkmode",
      q: "Gibt es einen Dark Mode?",
      a: "Ja! Über die Command Palette (Cmd+K → \"Design wechseln\") kannst du zwischen Hell, Dunkel und System wählen. Der Dark Mode hat ein Premium-Design mit dunklem Hintergrund und dezenten Akzenten. Die Einstellung wird gespeichert und beim nächsten Start automatisch angewendet.",
    },
    {
      id: "faq-multiaccounts",
      q: "Kann ich mehrere Konten verwalten?",
      a: "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell in den Einstellungen angelegt werden. Dashboard, Transaktionen und Analyse filtern automatisch nach dem gewählten Konto.",
    },
    {
      id: "faq-undo",
      q: "Kann ich Änderungen rückgängig machen?",
      a: "Ja. Nach jeder Aktion (Kategorisierung, Schuld hinzufügen, Sparziel löschen etc.) erscheint ein Undo-Toast am unteren Bildschirmrand. Auch über die Command Palette (Cmd+K → \"Rückgängig\") oder Cmd+Z kannst du die letzte Aktion rückgängig machen. wimg speichert bis zu 50 Undo-Schritte.",
    },
    {
      id: "faq-datenloeschen",
      q: "Wie lösche ich meine Daten?",
      a: "Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Über die Command Palette findest du auch \"Datenbank löschen\" (löscht nur die SQLite-Datei) und \"Vollständiger Reset\" (löscht Datenbank, Sync-Schlüssel und alle Einstellungen). Diese Aktionen können nicht rückgängig gemacht werden.",
    },
    {
      id: "faq-steuern",
      q: "Was kann die Steuern-Seite?",
      a: "Die Steuern-Seite hilft dir, absetzbare Ausgaben für deine Steuererklärung zu finden. Transaktionen werden nach Schlüsselwörtern gescannt (Arbeitsmittel, Fortbildung, Fahrtkosten etc.) — du kannst eigene Schlüsselwörter ergänzen. Die Pendlerpauschale berechnet sich nach §9 EStG: 0,30 €/km für die ersten 20 km, 0,38 €/km ab dem 21. km. Die Homeoffice-Pauschale beträgt 6 €/Tag (max. 210 Tage, §4 Abs. 5 Nr. 6c EStG). Einzelne Transaktionen lassen sich ein-/ausblenden, und alles kann als CSV für ELSTER oder WISO exportiert werden. Keine Steuerberatung — nur eine Übersicht deiner Zahlen.",
    },
    {
      id: "faq-sparquote",
      q: "Was ist die Sparquote?",
      a: "Die Sparquote zeigt, wie viel Prozent deines Einkommens du sparst: (Einnahmen \u2212 Ausgaben) \u00f7 Einnahmen \u00d7 100. Sie erscheint auf dem Dashboard neben dem verfügbaren Einkommen. Eine höhere Sparquote bedeutet schnelleren Vermögensaufbau. Die Änderung zum Vormonat wird in Prozentpunkten (pp) angezeigt.",
    },
    {
      id: "faq-heatmap",
      q: "Was zeigt die Ausgaben-Heatmap?",
      a: "Die Heatmap auf der Analyse-Seite zeigt deine monatlichen Ausgaben als Farbgitter \u2014 inspiriert vom GitHub Contribution Graph. Jede Zelle ist ein Monat, dunklere Farben bedeuten höhere Ausgaben. So erkennst du auf einen Blick saisonale Muster (z.B. Dezember-Spitzen, günstige Sommermonate). Die Daten kommen aus deinen monatlichen Snapshots.",
    },
    {
      id: "faq-beitragen",
      q: "Wie kann ich beitragen?",
      a: "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen.",
    },
  ];
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
      class="w-16 h-16 rounded-2xl flex items-center justify-center mb-4" style="background: #1a1a1a"
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

  <!-- Export Guides -->
  <div>
    <h3 class="text-lg font-display font-extrabold text-(--color-text) mb-3">
      Export-Guides
    </h3>
    <div class="grid grid-cols-3 gap-2.5">
      <div
        class="bg-white rounded-2xl p-3.5 border border-gray-100 text-center"
      >
        <div
          class="w-9 h-9 rounded-xl bg-amber-50 flex items-center justify-center mx-auto mb-2"
        >
          <span class="text-lg">&#127974;</span>
        </div>
        <p class="text-xs font-bold text-(--color-text)">Comdirect</p>
        <p class="text-[10px] text-(--color-text-secondary) mt-0.5">
          Umsätze &rarr; CSV
        </p>
      </div>
      <div
        class="bg-white rounded-2xl p-3.5 border border-gray-100 text-center"
      >
        <div
          class="w-9 h-9 rounded-xl bg-gray-100 flex items-center justify-center mx-auto mb-2"
        >
          <span class="text-lg">&#128200;</span>
        </div>
        <p class="text-xs font-bold text-(--color-text)">Trade Republic</p>
        <p class="text-[10px] text-(--color-text-secondary) mt-0.5">
          Aktivität &rarr; CSV
        </p>
      </div>
      <div
        class="bg-white rounded-2xl p-3.5 border border-gray-100 text-center"
      >
        <div
          class="w-9 h-9 rounded-xl bg-violet-50 flex items-center justify-center mx-auto mb-2"
        >
          <span class="text-lg">&#128640;</span>
        </div>
        <p class="text-xs font-bold text-(--color-text)">Scalable</p>
        <p class="text-[10px] text-(--color-text-secondary) mt-0.5">
          Transaktionen &rarr; CSV
        </p>
      </div>
    </div>
  </div>

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

    <p class="text-sm text-(--color-text-secondary) leading-relaxed mb-3">
      Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per
      MCP-Protokoll Zugriff auf deine Finanzdaten geben.
    </p>

    <div class="space-y-2.5 mb-3">
      <a
        href="/settings#sync"
        class="bg-white rounded-2xl p-4 border border-gray-100 flex gap-3 items-center hover:border-gray-200 transition-colors"
      >
        <span
          class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-xs shrink-0"
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
      <div
        class="bg-white rounded-2xl p-4 border border-gray-100 flex flex-col gap-3"
      >
        <div class="flex gap-3">
          <span
            class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-xs shrink-0"
          >
            2
          </span>
          <div>
            <p class="font-semibold text-sm text-(--color-text)">
              MCP-Client konfigurieren
            </p>
            <p class="text-xs text-(--color-text-secondary) mt-0.5">
              In Claude Desktop oder Claude Code hinzufügen:
            </p>
          </div>
        </div>
        <div
          class="overflow-auto bg-gray-50 rounded-xl p-3 text-xs font-mono text-(--color-text) overflow-x-auto"
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
      <div class="bg-white rounded-2xl p-4 border border-gray-100 flex gap-3">
        <span
          class="w-7 h-7 rounded-full bg-(--color-accent) flex items-center justify-center font-bold text-xs shrink-0"
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
    <div
      class="bg-amber-50 border border-dashed border-amber-300 rounded-2xl p-4 flex gap-3"
    >
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
          an diesen Client weitergegeben. <strong
            >Personenbezogene Daten (IBANs, Kartennummern, Namen) werden
            automatisch entfernt.</strong
          > Verwende nur vertrauenswürdige MCP-Clients.
        </p>
      </div>
    </div>
  </div>

  <!-- Datenschutz -->
  <div
    class="bg-emerald-50/50 border border-dashed border-emerald-300 rounded-2xl p-5"
  >
    <div class="flex items-center gap-2 mb-2.5">
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
      <h3 class="text-base font-display font-extrabold text-(--color-text)">
        Datenschutz
      </h3>
    </div>
    <ul
      class="space-y-1.5 text-xs text-(--color-text-secondary) leading-relaxed"
    >
      <li class="flex gap-2">
        <span class="text-emerald-500 shrink-0">&check;</span>
        Alle Daten bleiben auf deinem Gerät (OPFS / lokale Datei)
      </li>
      <li class="flex gap-2">
        <span class="text-emerald-500 shrink-0">&check;</span>
        Sync ist optional und Ende-zu-Ende verschlüsselt
      </li>
      <li class="flex gap-2">
        <span class="text-emerald-500 shrink-0">&check;</span>
        Keine Konten, keine Passwörter, kein Tracking
      </li>
      <li class="flex gap-2">
        <span class="text-emerald-500 shrink-0">&check;</span>
        PII wird automatisch aus MCP-Antworten entfernt
      </li>
    </ul>
  </div>

  <!-- FAQ -->
  <div id="faq">
    <h3
      class="text-lg font-display font-extrabold text-(--color-text) mb-3 flex items-center gap-2"
    >
      <svg
        class="w-4.5 h-4.5 text-amber-500"
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
    </h3>

    <div class="space-y-2">
      {#each faqs as faq}
        <details
          id={faq.id}
          class="group bg-white rounded-2xl border border-gray-100 overflow-hidden"
        >
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

<style>
  summary::-webkit-details-marker,
  summary::marker {
    display: none;
  }
</style>
