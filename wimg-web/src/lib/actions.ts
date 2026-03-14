/**
 * Command Palette action registry — central definition of all app actions.
 * Used by CommandPalette.svelte in both page and overlay modes.
 */
import { goto } from "$app/navigation";
import {
  autoCategorize,
  detectRecurring,
  opfsSave,
  exportCsv,
  exportDb,
  takeSnapshot,
  undo,
  redo,
  close,
} from "$lib/wasm";
import {
  getSyncKey,
  setSyncKey,
  clearSyncKey,
  isSyncEnabled,
  syncFull,
  connectSync,
} from "$lib/sync";
import { accountStore } from "$lib/account.svelte";
import { featureStore } from "$lib/features.svelte";
import { updateStore } from "$lib/update.svelte";
import { toastStore } from "$lib/toast.svelte";
import { data } from "$lib/data.svelte";
import { dateNav } from "$lib/dateNav.svelte";
import { themeStore } from "$lib/theme.svelte";

export interface PaletteAction {
  id: string;
  label: string;
  group: string;
  icon: string;
  keywords: string[];
  handler: () => void | Promise<void>;
  enabled?: () => boolean;
  danger?: boolean;
}

const MONTH_NAMES = [
  "Januar",
  "Februar",
  "März",
  "April",
  "Mai",
  "Juni",
  "Juli",
  "August",
  "September",
  "Oktober",
  "November",
  "Dezember",
];

function accountActions(): PaletteAction[] {
  const accounts = accountStore.accounts;
  if (accounts.length < 2) return [];
  const items: PaletteAction[] = [
    {
      id: "account-all",
      label: "Alle Konten",
      group: "Konto",
      icon: "👁️",
      keywords: ["account", "konto", "alle", "all"],
      handler: () => {
        accountStore.select(null);
        toastStore.show("Alle Konten ausgewählt");
      },
      enabled: () => accountStore.selected !== null,
    },
  ];
  for (const acct of accounts) {
    items.push({
      id: `account-${acct.id}`,
      label: acct.name,
      group: "Konto",
      icon: "🏦",
      keywords: ["account", "konto", "wechseln", "switch", acct.name.toLowerCase()],
      handler: () => {
        accountStore.select(acct.id);
        toastStore.show(`Konto: ${acct.name}`);
      },
      enabled: () => accountStore.selected !== acct.id,
    });
  }
  return items;
}

export function getActions(): PaletteAction[] {
  return [...STATIC_ACTIONS, ...accountActions()];
}

const STATIC_ACTIONS: PaletteAction[] = [
  // --- Navigation ---
  {
    id: "nav-dashboard",
    label: "Dashboard",
    group: "Navigation",
    icon: "🏠",
    keywords: ["home", "start", "übersicht"],
    handler: () => goto("/home"),
  },
  {
    id: "nav-transactions",
    label: "Transaktionen",
    group: "Navigation",
    icon: "📋",
    keywords: ["umsätze", "list", "transactions"],
    handler: () => goto("/transactions"),
  },
  {
    id: "nav-analysis",
    label: "Analyse",
    group: "Navigation",
    icon: "📊",
    keywords: ["chart", "spending", "ausgaben"],
    handler: () => goto("/analysis"),
  },
  {
    id: "nav-import",
    label: "Import",
    group: "Navigation",
    icon: "📥",
    keywords: ["csv", "upload", "datei"],
    handler: () => goto("/import"),
  },
  {
    id: "nav-debts",
    label: "Schulden",
    group: "Navigation",
    icon: "💳",
    keywords: ["debts", "kredit"],
    handler: () => goto("/debts"),
    enabled: () => featureStore.isEnabled("debts"),
  },
  {
    id: "nav-goals",
    label: "Sparziele",
    group: "Navigation",
    icon: "🎯",
    keywords: ["goals", "sparziel", "sparen", "savings"],
    handler: () => goto("/goals"),
    enabled: () => featureStore.isEnabled("goals"),
  },
  {
    id: "nav-recurring",
    label: "Wiederkehrend",
    group: "Navigation",
    icon: "🔄",
    keywords: ["recurring", "abo", "subscription"],
    handler: () => goto("/recurring"),
    enabled: () => featureStore.isEnabled("recurring"),
  },
  {
    id: "nav-review",
    label: "Rückblick",
    group: "Navigation",
    icon: "📅",
    keywords: ["review", "monthly", "monat"],
    handler: () => goto("/review"),
    enabled: () => featureStore.isEnabled("review"),
  },
  {
    id: "nav-settings",
    label: "Einstellungen",
    group: "Navigation",
    icon: "⚙️",
    keywords: ["settings", "config"],
    handler: () => goto("/settings"),
  },
  {
    id: "nav-about",
    label: "Über wimg",
    group: "Navigation",
    icon: "ℹ️",
    keywords: ["about", "info", "version"],
    handler: () => goto("/about"),
  },
  {
    id: "nav-changelog",
    label: "Changelog",
    group: "Navigation",
    icon: "📝",
    keywords: ["changelog", "updates", "neu", "version", "release"],
    handler: () => goto("/changelog"),
  },

  // --- Hilfe & FAQ ---
  {
    id: "help-mcp",
    label: "MCP-Verbindung einrichten",
    group: "Hilfe",
    icon: "🔗",
    keywords: ["mcp", "claude", "ai", "verbindung", "server", "anleitung"],
    handler: () => gotoHash("/about#mcp"),
  },
  {
    id: "faq-sicherheit",
    label: "Sind meine Daten sicher?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "sicherheit", "daten", "verschlüsselung", "privat"],
    handler: () => gotoHash("/about#faq-sicherheit"),
  },
  {
    id: "faq-banken",
    label: "Welche Banken werden unterstützt?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "banken", "comdirect", "trade republic", "scalable"],
    handler: () => gotoHash("/about#faq-banken"),
  },
  {
    id: "faq-import",
    label: "Wie funktioniert der Import?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "import", "csv", "hochladen", "anleitung"],
    handler: () => gotoHash("/about#faq-import"),
  },
  {
    id: "faq-kategorisierung",
    label: "Wie funktioniert die Kategorisierung?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "kategorie", "regeln", "automatisch", "lernen"],
    handler: () => gotoHash("/about#faq-kategorisierung"),
  },
  {
    id: "faq-kostenlos",
    label: "Ist wimg wirklich kostenlos?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "kostenlos", "preis", "gratis", "open source"],
    handler: () => gotoHash("/about#faq-kostenlos"),
  },
  {
    id: "faq-speicherung",
    label: "Wo werden die Daten gespeichert?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "speicher", "opfs", "lokal", "browser", "ios"],
    handler: () => gotoHash("/about#faq-speicherung"),
  },
  {
    id: "faq-mcp",
    label: "Was ist der MCP-Server?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "mcp", "server", "claude", "ki", "ai"],
    handler: () => gotoHash("/about#faq-mcp"),
  },
  {
    id: "faq-devtools",
    label: "Gibt es Entwickler-Tools?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "devtools", "entwickler", "debug", "panel"],
    handler: () => gotoHash("/about#faq-devtools"),
  },
  {
    id: "faq-autolearn",
    label: "Wie funktioniert Auto-Learn?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "auto", "learn", "regeln", "rules", "kategorisierung"],
    handler: () => gotoHash("/about#faq-autolearn"),
  },
  {
    id: "faq-vermoegen",
    label: "Was zeigt das Vermögens-Diagramm?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "vermögen", "net worth", "chart", "diagramm", "snapshots"],
    handler: () => gotoHash("/about#faq-vermoegen"),
  },
  {
    id: "faq-sync",
    label: "Wie synchronisiere ich zwischen Geräten?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "sync", "geräte", "synchron", "verknüpfen"],
    handler: () => gotoHash("/about#faq-sync"),
  },
  {
    id: "faq-sparziele",
    label: "Wie funktionieren Sparziele?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "sparziel", "goals", "sparen", "ziel"],
    handler: () => gotoHash("/about#faq-sparziele"),
  },
  {
    id: "faq-recurring",
    label: "Wie erkennt wimg Abos?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "abo", "recurring", "wiederkehrend", "muster"],
    handler: () => gotoHash("/about#faq-recurring"),
  },
  {
    id: "faq-offline",
    label: "Funktioniert wimg offline?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "offline", "pwa", "installieren", "internet"],
    handler: () => gotoHash("/about#faq-offline"),
  },
  {
    id: "faq-darkmode",
    label: "Gibt es einen Dark Mode?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "dark", "dunkel", "design", "theme", "mode"],
    handler: () => gotoHash("/about#faq-darkmode"),
  },
  {
    id: "faq-multiaccounts",
    label: "Kann ich mehrere Konten verwalten?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "konto", "konten", "multi", "account", "switcher"],
    handler: () => gotoHash("/about#faq-multiaccounts"),
  },
  {
    id: "faq-undo",
    label: "Kann ich Änderungen rückgängig machen?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "undo", "rückgängig", "zurück", "wiederherstellen"],
    handler: () => gotoHash("/about#faq-undo"),
  },
  {
    id: "faq-datenloeschen",
    label: "Wie lösche ich meine Daten?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "löschen", "daten", "reset", "zurücksetzen"],
    handler: () => gotoHash("/about#faq-datenloeschen"),
  },
  {
    id: "faq-beitragen",
    label: "Wie kann ich beitragen?",
    group: "Hilfe",
    icon: "❓",
    keywords: ["faq", "beitragen", "github", "contribute", "helfen"],
    handler: () => gotoHash("/about#faq-beitragen"),
  },

  // --- Categorization ---
  {
    id: "auto-categorize",
    label: "Auto-Kategorisieren",
    group: "Kategorisierung",
    icon: "🏷️",
    keywords: ["categorize", "auto", "rules", "regeln"],
    handler: () => {
      const n = autoCategorize();
      toastStore.show(n > 0 ? `${n} Transaktionen kategorisiert` : "Keine neuen Kategorien");
    },
  },
  {
    id: "detect-recurring",
    label: "Wiederkehrende erkennen",
    group: "Kategorisierung",
    icon: "🔍",
    keywords: ["recurring", "detect", "erkennen", "abo", "muster"],
    handler: async () => {
      const n = detectRecurring();
      await opfsSave();
      data.bump();
      toastStore.show(n > 0 ? `${n} Muster erkannt` : "Keine neuen Muster");
    },
    enabled: () => featureStore.isEnabled("recurring"),
  },

  // --- Data ---
  {
    id: "import-csv",
    label: "CSV importieren",
    group: "Daten",
    icon: "📂",
    keywords: ["import", "csv", "file", "datei"],
    handler: () => goto("/import"),
  },
  {
    id: "export-csv",
    label: "CSV exportieren",
    group: "Daten",
    icon: "📤",
    keywords: ["export", "csv", "download"],
    handler: () => {
      const csv = exportCsv();
      downloadText(csv, "wimg-export.csv", "text/csv");
      toastStore.show("CSV exportiert");
    },
  },
  {
    id: "export-db",
    label: "Datenbank exportieren",
    group: "Daten",
    icon: "💾",
    keywords: ["export", "database", "db", "sqlite", "backup"],
    handler: () => {
      const json = exportDb();
      const date = new Date().toISOString().slice(0, 10);
      downloadText(json, `wimg-backup-${date}.json`, "application/json");
      toastStore.show("Backup exportiert");
    },
  },
  {
    id: "take-snapshot",
    label: "Snapshot erstellen",
    group: "Daten",
    icon: "📸",
    keywords: ["snapshot", "backup", "monat"],
    handler: () => {
      const now = new Date();
      takeSnapshot(now.getFullYear(), now.getMonth() + 1);
      toastStore.show("Snapshot erstellt");
    },
  },

  // --- Sync ---
  {
    id: "sync-enable",
    label: "Sync aktivieren",
    group: "Sync",
    icon: "🔗",
    keywords: ["sync", "enable", "aktivieren", "key"],
    handler: async () => {
      const key = crypto.randomUUID();
      setSyncKey(key);
      await syncFull(key);
      connectSync();
      toastStore.show("Sync aktiviert");
    },
    enabled: () => !isSyncEnabled(),
  },
  {
    id: "sync-link",
    label: "Gerät verknüpfen",
    group: "Sync",
    icon: "📲",
    keywords: ["sync", "link", "device", "gerät", "verknüpfen", "paste", "einfügen"],
    handler: async () => {
      try {
        const key = await navigator.clipboard.readText();
        if (!key || key.length < 10) {
          toastStore.show("Kein gültiger Sync-Key in der Zwischenablage");
          return;
        }
        setSyncKey(key);
        await syncFull(key);
        connectSync();
        toastStore.show("Gerät verknüpft — Sync aktiv");
      } catch {
        toastStore.show("Zwischenablage konnte nicht gelesen werden");
      }
    },
    enabled: () => !isSyncEnabled(),
  },
  {
    id: "sync-now",
    label: "Jetzt synchronisieren",
    group: "Sync",
    icon: "🔄",
    keywords: ["sync", "push", "pull", "now", "jetzt"],
    handler: async () => {
      const key = getSyncKey();
      if (!key) return;
      const r = await syncFull(key);
      toastStore.show(`Sync: ${r.pushed} hoch, ${r.pulled} runter`);
    },
    enabled: () => isSyncEnabled(),
  },
  {
    id: "sync-copy-key",
    label: "Sync-Key kopieren",
    group: "Sync",
    icon: "📋",
    keywords: ["sync", "key", "copy", "kopieren", "clipboard"],
    handler: async () => {
      const key = getSyncKey();
      if (!key) return;
      await navigator.clipboard.writeText(key);
      toastStore.show("Sync-Key kopiert");
    },
    enabled: () => isSyncEnabled(),
  },
  {
    id: "sync-disconnect",
    label: "Sync trennen",
    group: "Sync",
    icon: "🔌",
    keywords: ["sync", "disconnect", "trennen", "remove"],
    handler: () => {
      clearSyncKey();
      toastStore.show("Sync getrennt");
    },
    enabled: () => isSyncEnabled(),
    danger: true,
  },

  // --- Undo/Redo ---
  {
    id: "undo",
    label: "Rückgängig",
    group: "Bearbeiten",
    icon: "↩️",
    keywords: ["undo", "zurück", "rückgängig"],
    handler: async () => {
      const r = await undo();
      if (r) toastStore.show(`Rückgängig: ${r.op} ${r.table}`);
    },
  },
  {
    id: "redo",
    label: "Wiederherstellen",
    group: "Bearbeiten",
    icon: "↪️",
    keywords: ["redo", "wiederherstellen", "repeat"],
    handler: async () => {
      const r = await redo();
      if (r) toastStore.show(`Wiederhergestellt: ${r.op} ${r.table}`);
    },
  },

  // --- Feature Flags ---
  {
    id: "toggle-debts",
    label: "Schulden ein/aus",
    group: "Features",
    icon: "💳",
    keywords: ["feature", "debts", "schulden", "toggle"],
    handler: () => {
      featureStore.toggle("debts");
      toastStore.show(`Schulden: ${featureStore.isEnabled("debts") ? "Ein" : "Aus"}`);
    },
  },
  {
    id: "toggle-recurring",
    label: "Wiederkehrend ein/aus",
    group: "Features",
    icon: "🔄",
    keywords: ["feature", "recurring", "wiederkehrend", "toggle"],
    handler: () => {
      featureStore.toggle("recurring");
      toastStore.show(`Wiederkehrend: ${featureStore.isEnabled("recurring") ? "Ein" : "Aus"}`);
    },
  },
  {
    id: "toggle-goals",
    label: "Sparziele ein/aus",
    group: "Features",
    icon: "🎯",
    keywords: ["feature", "goals", "sparziele", "toggle"],
    handler: () => {
      featureStore.toggle("goals");
      toastStore.show(`Sparziele: ${featureStore.isEnabled("goals") ? "Ein" : "Aus"}`);
    },
  },
  {
    id: "toggle-review",
    label: "Rückblick ein/aus",
    group: "Features",
    icon: "📅",
    keywords: ["feature", "review", "rückblick", "toggle"],
    handler: () => {
      featureStore.toggle("review");
      toastStore.show(`Rückblick: ${featureStore.isEnabled("review") ? "Ein" : "Aus"}`);
    },
  },

  // --- Month Navigation ---
  {
    id: "date-prev",
    label: "Vorheriger Monat",
    group: "Zeitraum",
    icon: "⬅️",
    keywords: ["monat", "zurück", "prev", "vorherig", "month"],
    handler: () => {
      dateNav.prev();
      toastStore.show(`${MONTH_NAMES[dateNav.month - 1]} ${dateNav.year}`);
    },
  },
  {
    id: "date-next",
    label: "Nächster Monat",
    group: "Zeitraum",
    icon: "➡️",
    keywords: ["monat", "weiter", "next", "nächst", "month"],
    handler: () => {
      dateNav.next();
      toastStore.show(`${MONTH_NAMES[dateNav.month - 1]} ${dateNav.year}`);
    },
  },
  {
    id: "date-today",
    label: "Aktueller Monat",
    group: "Zeitraum",
    icon: "📅",
    keywords: ["heute", "today", "jetzt", "aktuell", "current"],
    handler: () => {
      dateNav.reset();
      toastStore.show(`${MONTH_NAMES[dateNav.month - 1]} ${dateNav.year}`);
    },
  },

  // --- Theme ---
  {
    id: "theme-toggle",
    label: "Design wechseln",
    group: "App",
    icon: "🌗",
    keywords: ["dark", "light", "theme", "dunkel", "hell", "design", "mode", "nacht"],
    handler: () => {
      themeStore.toggle();
      const labels = { light: "Hell", dark: "Dunkel", system: "System" };
      toastStore.show(`Design: ${labels[themeStore.mode]}`);
    },
  },

  // --- PWA Update ---
  {
    id: "pwa-update",
    label: "App aktualisieren",
    group: "App",
    icon: "🔄",
    keywords: ["update", "aktualisieren", "version", "pwa"],
    handler: () => {
      updateStore.sheetOpen = true;
    },
    enabled: () => updateStore.showBanner,
  },

  // --- DevTools ---
  {
    id: "devtools-open",
    label: "DevTools öffnen",
    group: "DevTools",
    icon: "🛠️",
    keywords: ["devtools", "debug", "developer"],
    handler: async () => {
      const m = await import("$lib/devtools.svelte");
      m.devtoolsStore.enable();
      m.devtoolsStore.open = true;
    },
    enabled: () =>
      import.meta.env.DEV || new URLSearchParams(window.location.search).has("devtools"),
  },
  {
    id: "devtools-sql",
    label: "SQL ausführen",
    group: "DevTools",
    icon: "🗄️",
    keywords: ["sql", "query", "database", "devtools"],
    handler: async () => {
      const m = await import("$lib/devtools.svelte");
      m.devtoolsStore.enable();
      m.devtoolsStore.open = true;
      m.devtoolsStore.activeTab = "sql";
    },
    enabled: () =>
      import.meta.env.DEV || new URLSearchParams(window.location.search).has("devtools"),
  },

  // --- Danger Zone ---
  {
    id: "danger-clear-db",
    label: "Datenbank löschen",
    group: "Danger Zone",
    icon: "⚠️",
    keywords: ["reset", "danger", "clear", "opfs", "löschen", "datenbank"],
    handler: async () => {
      try {
        const root = await navigator.storage.getDirectory();
        await Promise.allSettled(
          ["wimg.db", "e5-small-q8-v7.gguf"].map((n) => root.removeEntry(n)),
        );
      } catch {
        /* ignore */
      }
      window.location.reload();
    },
    danger: true,
  },
  {
    id: "danger-full-reset",
    label: "Vollständiger Reset",
    group: "Danger Zone",
    icon: "💥",
    keywords: ["reset", "danger", "full", "alles", "komplett"],
    handler: async () => {
      try {
        close();
        const root = await navigator.storage.getDirectory();
        await Promise.allSettled(
          ["wimg.db", "e5-small-q8-v7.gguf"].map((n) => root.removeEntry(n)),
        );
      } catch {
        /* ignore */
      }
      clearSyncKey();
      localStorage.clear();
      window.location.reload();
    },
    danger: true,
  },
];

// --- Helpers ---

function gotoHash(path: string) {
  return goto(path, { noScroll: true });
}

function downloadText(content: string, filename: string, mime: string) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
