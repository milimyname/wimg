/**
 * Command Palette action registry — central definition of all app actions.
 * Used by CommandPalette.svelte in both page and overlay modes.
 */
import { goto } from "$app/navigation";
import { autoCategorize, exportCsv, exportDb, takeSnapshot, undo, redo, close } from "$lib/wasm";
import {
  getSyncKey,
  setSyncKey,
  clearSyncKey,
  isSyncEnabled,
  syncFull,
  connectSync,
} from "$lib/sync";
import { featureStore } from "$lib/features.svelte";
import { toastStore } from "$lib/toast.svelte";

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

export const ACTIONS: PaletteAction[] = [
  // --- Navigation ---
  {
    id: "nav-dashboard",
    label: "Dashboard",
    group: "Navigation",
    icon: "🏠",
    keywords: ["home", "start", "übersicht"],
    handler: () => goto("/dashboard"),
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
      const b64 = exportDb();
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      downloadBlob(bytes, "wimg.db", "application/x-sqlite3");
      toastStore.show("Datenbank exportiert");
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
        await root.removeEntry("wimg.db");
      } catch {
        /* may not exist */
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
        await root.removeEntry("wimg.db");
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

function downloadText(content: string, filename: string, mime: string) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function downloadBlob(bytes: Uint8Array, filename: string, mime: string) {
  const blob = new Blob([new Uint8Array(bytes)], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
