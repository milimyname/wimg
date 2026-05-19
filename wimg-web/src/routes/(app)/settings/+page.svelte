<script lang="ts">
  import { onMount, onDestroy, tick } from "svelte";
  import { APP_VERSION, RELEASES_URL } from "$lib/version";
  import { generateQRSvg } from "$lib/qr";
  import { isDemoLoaded, clearDemoFlag } from "$lib/demo";
  import {
    exportCsv,
    exportDb,
    queryRaw,
    CATEGORIES,
    opfsSave,
  } from "$lib/wasm";
  import { LS_DEMO_LOADED, LS_ONBOARDING_COMPLETED } from "$lib/config";
  import { localeTag } from "$lib/format";
  import { i18n } from "$lib/i18n.svelte";
  import Drawer from "../../../components/Drawer.svelte";
  import InfoTooltip from "../../../components/InfoTooltip.svelte";
  import { lock, AUTOLOCK_OPTIONS, type AutoLockMinutes } from "$lib/lock.svelte";
  import { pushState, replaceState } from "$app/navigation";
  import { page } from "$app/state";
  import {
    getSyncKey,
    setSyncKey,
    clearSyncKey,
    syncFull,
    syncPull,
    syncPush,
    isSyncEnabled,
    getLastSyncTimestamp,
    connectSync,
    disconnectSync,
    isValidSyncKey,
  } from "$lib/sync";

  let syncEnabled = $state(false);
  let syncKey = $state("");
  let linkInput = $state("");
  let showKey = $state(false);
  let syncing = $state(false);
  let syncError = $state("");
  let syncSuccess = $state("");
  let lastSync = $state(0);
  let isOnline = $state(navigator.onLine);
  let confirmReset = $derived(page.state.sheet === "confirm-reset");
  let resetting = $state(false);
  let copied = $state(false);
  let hasLocalData = $state(false);
  let showQR = $derived(page.state.sheet === "qr");
  let qrSvg = $state("");

  // Export state
  let exporting = $state(false);
  let exportSuccess = $state("");
  let showExportSheet = $derived(page.state.sheet === "export");


  // Rules state
  interface Rule {
    rowid: number;
    pattern: string;
    category: number;
    priority: number;
  }
  let rules = $state<Rule[]>([]);
  let rulesExpanded = $state(false);
  let learnedRules = $derived(rules.filter((r) => r.priority <= 1));
  let seedRules = $derived(rules.filter((r) => r.priority > 1));

  function loadRules() {
    try {
      const sql = "SELECT rowid, pattern, category, priority FROM rules ORDER BY priority DESC, pattern ASC";
      const result = queryRaw(sql);
      rules = result.rows.map((r) => ({
        rowid: r[0] as number,
        pattern: r[1] as string,
        category: r[2] as number,
        priority: r[3] as number,
      }));
    } catch {
      rules = [];
    }
  }

  async function deleteRule(rowid: number) {
    queryRaw(`DELETE FROM rules WHERE rowid = ${rowid}`);
    await opfsSave();
    loadRules();
  }

  // Demo state
  const localeOptions = [
    { code: "de", label: "Deutsch" },
    { code: "en", label: "English" },
  ];

  let demoLoaded = $state(false);

  const maskedKey = $derived(
    syncKey ? syncKey.slice(0, 4) + "••••-••••-••••-" + syncKey.slice(-4) : "",
  );

  let pendingSyncKey = $state("");
  let showLinkConfirm = $derived(page.state.sheet === "link-confirm");
  let showSyncInfo = $derived(page.state.sheet === "sync-info");

  // PIN-lock setup flow. `pinStep` drives the wizard:
  //   "set"     → first PIN entry
  //   "confirm" → re-enter to confirm
  let pinStep = $state<"set" | "confirm" | null>(null);
  let pinDraft = $state("");
  let pinConfirm = $state("");
  let pinError = $state("");
  let confirmPinInput = $state<HTMLInputElement | null>(null);

  // The two PIN inputs sit in {#if}/{:else} branches, so `autofocus` only
  // fires on the first one. When the wizard advances to "confirm", manually
  // focus the second input after Svelte has mounted it.
  $effect(() => {
    if (pinStep === "confirm") {
      tick().then(() => confirmPinInput?.focus());
    }
  });

  function startPinSetup() {
    pinDraft = "";
    pinConfirm = "";
    pinError = "";
    pinStep = "set";
  }

  function cancelPinSetup() {
    pinStep = null;
    pinDraft = "";
    pinConfirm = "";
    pinError = "";
  }

  async function submitPin() {
    if (pinStep === "set") {
      if (pinDraft.length !== 4) {
        pinError = "PIN muss 4 Stellen haben.";
        return;
      }
      pinStep = "confirm";
      return;
    }
    if (pinStep === "confirm") {
      if (pinConfirm !== pinDraft) {
        pinError = "PINs stimmen nicht überein.";
        pinConfirm = "";
        return;
      }
      await lock.setupPin(pinDraft);
      cancelPinSetup();
    }
  }

  async function enableBiometric() {
    const ok = await lock.enablePasskey();
    if (!ok) pinError = "Biometrie konnte nicht aktiviert werden.";
  }

  function disableLock() {
    lock.disable();
  }

  function onOnline() {
    isOnline = true;
  }
  function onOffline() {
    isOnline = false;
  }

  onDestroy(() => {
    window.removeEventListener("online", onOnline);
    window.removeEventListener("offline", onOffline);
  });

  onMount(async () => {
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);

    const stored = getSyncKey();
    if (stored) {
      syncEnabled = true;
      syncKey = stored;
    }
    lastSync = getLastSyncTimestamp();
    demoLoaded = isDemoLoaded();
    loadRules();

    try {
      const root = await navigator.storage.getDirectory();
      await root.getFileHandle("wimg.db");
      hasLocalData = true;
    } catch {
      hasLocalData = false;
    }

    // Handle ?sync=<key> from QR code scan
    const params = new URLSearchParams(window.location.search);
    const syncParam = params.get("sync");
    if (syncParam && !syncEnabled) {
      pendingSyncKey = syncParam;
      // Clean URL without reload
      window.history.replaceState({}, "", window.location.pathname);
      pushState("", { sheet: "link-confirm" });
    }
  });

  // Settings-side paste-link panel (separate state from the onboarding overlay).
  let showSettingsLinkPanel = $state(false);
  let settingsLinkInput = $state("");
  let settingsLinking = $state(false);
  let settingsLinkError = $state("");

  async function handleSettingsLink() {
    const raw = settingsLinkInput.trim();
    if (!raw) return;
    if (!isValidSyncKey(raw)) {
      settingsLinkError = "Ungültiger Sync-Schlüssel.";
      return;
    }
    const key = raw.toLowerCase();
    settingsLinking = true;
    settingsLinkError = "";
    try {
      setSyncKey(key);
      const pulled = await syncPull(key);
      connectSync();
      syncKey = key;
      syncEnabled = true;
      lastSync = getLastSyncTimestamp();
      syncSuccess = `Verknüpft — ${pulled} Einträge übernommen`;
      showSettingsLinkPanel = false;
    } catch (e) {
      settingsLinkError = e instanceof Error ? e.message : String(e);
      clearSyncKey();
    } finally {
      settingsLinking = false;
    }
  }

  async function handleEnableSync() {
    const key = generateUUID();
    setSyncKey(key);
    syncKey = key;
    syncEnabled = true;
    showKey = true;
    syncError = "";
    syncSuccess = "";

    syncing = true;
    try {
      const { pushed, pulled } = await syncFull(key);
      connectSync();
      syncSuccess = `Sync aktiviert (${pushed} gesendet, ${pulled} empfangen)`;
      lastSync = getLastSyncTimestamp();
    } catch (e) {
      syncError = e instanceof Error ? e.message : "Sync fehlgeschlagen";
    } finally {
      syncing = false;
    }
  }

  async function handleSyncNow() {
    if (!syncKey) return;
    syncing = true;
    syncError = "";
    syncSuccess = "";

    try {
      const { pushed, pulled } = await syncFull(syncKey);
      syncSuccess = `Synchronisiert (${pushed} gesendet, ${pulled} empfangen)`;
      lastSync = getLastSyncTimestamp();
    } catch (e) {
      syncError = e instanceof Error ? e.message : "Sync fehlgeschlagen";
    } finally {
      syncing = false;
    }
  }

  async function handleLink() {
    if (!linkInput.trim()) return;
    if (!isValidSyncKey(linkInput)) {
      syncError = "Ungültiger Sync-Schlüssel.";
      return;
    }
    const key = linkInput.trim().toLowerCase();
    setSyncKey(key);
    syncKey = key;
    syncEnabled = true;
    linkInput = "";
    syncing = true;
    syncError = "";
    syncSuccess = "";

    try {
      // Full sync: pull remote data first, then push local data
      const pulled = await syncPull(key);
      const pushed = await syncPush(key);
      connectSync();
      syncSuccess = `Verknüpft (${pulled} empfangen, ${pushed} gesendet)`;
      lastSync = getLastSyncTimestamp();
    } catch (e) {
      syncError = e instanceof Error ? e.message : "Verknüpfung fehlgeschlagen";
    } finally {
      syncing = false;
    }
  }

  async function handleCopyKey() {
    await navigator.clipboard.writeText(syncKey);
    copied = true;
    setTimeout(() => (copied = false), 2000);
  }

  function handleShowQR() {
    const syncUrl = `${window.location.origin}/settings?sync=${syncKey}`;
    qrSvg = generateQRSvg(syncUrl);
    pushState("", { sheet: "qr" });
  }

  async function handleConfirmLink() {
    const key = pendingSyncKey;
    pendingSyncKey = "";
    replaceState("", {}); // synchronously clear sheet state
    linkInput = key;
    await handleLink();
  }

  async function handleResetData() {
    resetting = true;
    try {
      const root = await navigator.storage.getDirectory();
      await root.removeEntry("wimg.db").catch(() => {});
      clearSyncKey();
      localStorage.removeItem("wimg_sync_last_ts");
      clearDemoFlag();
      localStorage.removeItem(LS_ONBOARDING_COMPLETED);
      window.location.reload();
    } catch (e) {
      resetting = false;
      history.back();
    }
  }

  function generateUUID(): string {
    if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
    // Fallback for non-secure contexts (e.g. http://192.168.x.x)
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  async function openDataBrowser() {
    const m = await import("$lib/devtools.svelte");
    m.devtoolsStore.enable();
    m.devtoolsStore.activeTab = "sql";
    if (!m.devtoolsStore.open) m.devtoolsStore.toggle();
  }

  function formatLastSync(ts: number): string {
    if (ts === 0) return "Noch nie";
    const d = new Date(ts);
    return (
      d.toLocaleDateString(localeTag()) +
      " " +
      d.toLocaleTimeString(localeTag(), { hour: "2-digit", minute: "2-digit" })
    );
  }

  function downloadFile(content: string, filename: string, mimeType: string) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }

  function handleExportCsv() {
    exporting = true;
    exportSuccess = "";
    try {
      const csv = exportCsv();
      const date = new Date().toISOString().slice(0, 10);
      downloadFile(
        csv,
        `wimg-transaktionen-${date}.csv`,
        "text/csv;charset=utf-8",
      );
      exportSuccess = "CSV heruntergeladen";
    } catch {
      exportSuccess = "Export fehlgeschlagen";
    } finally {
      exporting = false;
      setTimeout(() => {
        exportSuccess = "";
      }, 3000);
    }
  }

  function handleExportJson() {
    exporting = true;
    exportSuccess = "";
    try {
      const json = exportDb();
      const date = new Date().toISOString().slice(0, 10);
      downloadFile(json, `wimg-backup-${date}.json`, "application/json");
      exportSuccess = "Backup heruntergeladen";
    } catch {
      exportSuccess = "Export fehlgeschlagen";
    } finally {
      exporting = false;
      setTimeout(() => {
        exportSuccess = "";
      }, 3000);
    }
  }
</script>

<section class="space-y-5">
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
      Einstellungen
    </h2>
  </div>

  <!-- Sync Section -->
  <div id="sync" class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div
        class="w-10 h-10 rounded-2xl bg-amber-100 flex items-center justify-center"
      >
        <svg
          class="w-5 h-5 text-amber-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
          />
        </svg>
      </div>
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-(--color-text)">Synchronisierung</h3>
          {#if syncEnabled}
            <span
              class="text-[10px] font-bold text-emerald-600 bg-emerald-50 px-1.5 py-0.5 rounded-full"
              >E2E-verschl.</span
            >
          {/if}
        </div>
        <p class="text-xs text-(--color-text-secondary)">
          Daten zwischen Geräten synchronisieren
        </p>
      </div>
    </div>

    {#if syncError}
      <div
        class="rounded-xl bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700"
      >
        {syncError}
      </div>
    {/if}

    {#if syncSuccess}
      <div
        class="rounded-xl bg-emerald-50 border border-emerald-200 px-3 py-2 text-sm text-emerald-700"
      >
        {syncSuccess}
      </div>
    {/if}

    {#if !isOnline}
      <div
        class="rounded-xl bg-amber-50 border border-amber-200 px-3 py-2 text-sm text-amber-700"
      >
        Kein Internet — Sync nicht verfügbar
      </div>
    {/if}

    {#if !syncEnabled}
      <div class="space-y-2.5">
        <!-- Path 1: paste existing sync key (returning wimg user) -->
        {#if !showSettingsLinkPanel}
          <button
            onclick={() => (showSettingsLinkPanel = true)}
            disabled={!isOnline}
            class="w-full py-3 rounded-2xl bg-(--color-card-bg) border border-(--color-text)/15 text-(--color-text) font-bold text-sm flex items-center justify-center gap-2 transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m-4 6H4m0 0l4 4m-4-4l4-4" />
            </svg>
            Schon wimg-User? Sync-Schlüssel einfügen
          </button>
        {:else}
          <div class="rounded-2xl bg-(--color-card-bg) p-3 space-y-2 border border-(--color-text)/10">
            <div class="flex items-center justify-between">
              <span class="text-xs font-bold text-(--color-text)">Sync-Schlüssel einfügen</span>
              <button
                onclick={() => {
                  showSettingsLinkPanel = false;
                  settingsLinkInput = "";
                  settingsLinkError = "";
                }}
                class="text-xs text-(--color-text-secondary) hover:text-(--color-text)"
              >
                Abbrechen
              </button>
            </div>
            <div class="flex gap-2">
              <input
                type="text"
                bind:value={settingsLinkInput}
                oninput={() => (settingsLinkError = "")}
                placeholder="xxxxxxxx-xxxx-4xxx-xxxx-xxxxxxxxxxxx"
                class="flex-1 bg-(--color-bg) rounded-xl px-3 py-2 text-xs font-mono text-(--color-text) outline-none border focus:border-(--color-text) {settingsLinkError
                  ? 'border-red-400'
                  : 'border-(--color-border)'}"
                autocomplete="off"
                autocapitalize="off"
                spellcheck="false"
              />
              <button
                onclick={handleSettingsLink}
                disabled={settingsLinking || !settingsLinkInput.trim() || !isOnline}
                class="px-3 py-2 rounded-xl bg-(--color-text) text-(--color-bg) text-xs font-bold disabled:opacity-50 transition-opacity"
              >
                {settingsLinking ? "..." : "Verknüpfen"}
              </button>
            </div>
            {#if settingsLinkError}
              <p class="text-xs text-red-600">{settingsLinkError}</p>
            {/if}
          </div>
        {/if}

        <!-- "Or" divider -->
        <div class="flex items-center gap-2 py-1">
          <div class="flex-1 h-px bg-(--color-text)/10"></div>
          <span class="text-[10px] font-extrabold uppercase tracking-widest text-(--color-text-secondary)">oder</span>
          <div class="flex-1 h-px bg-(--color-text)/10"></div>
        </div>

        <!-- Path 2: generate new sync key -->
        <div class="rounded-xl bg-(--color-bg) p-3 space-y-1">
          <p class="text-xs font-bold text-(--color-text)">Neuen Sync-Schlüssel erstellen</p>
          <p class="text-[11px] text-(--color-text-secondary) leading-snug">
            Erstellt einen zufälligen Schlüssel und lädt deine Daten hoch. Du kannst ihn auf weiteren Geräten verwenden, um sie zu verknüpfen.
          </p>
        </div>
        <button
          onclick={() => pushState("", { sheet: "sync-info" })}
          disabled={!isOnline}
          class="w-full py-3 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
        >
          Sync aktivieren
        </button>
      </div>
    {:else}
      <div class="space-y-3">
        <!-- Sync Key (masked) -->
        <div>
          <label
            class="text-xs font-medium text-(--color-text-secondary) mb-1 block"
            for="sync-key-input">Sync-Schlüssel</label
          >
          <div class="flex gap-1.5">
            <div class="min-w-0 flex-1 relative">
              <input
                id="sync-key-input"
                type="text"
                readonly
                autocomplete="off"
                data-1p-ignore
                value={showKey ? syncKey : maskedKey}
                class="w-full bg-(--color-bg) rounded-xl px-3 py-2.5 pr-10 text-xs font-mono text-(--color-text) outline-none truncate"
              />
              <button
                onclick={() => (showKey = !showKey)}
                class="absolute right-2.5 top-1/2 -translate-y-1/2 text-(--color-text-secondary)"
                aria-label={showKey
                  ? "Schlüssel verbergen"
                  : "Schlüssel anzeigen"}
              >
                {#if showKey}
                  <svg
                    class="w-4 h-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="1.5"
                      d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"
                    />
                  </svg>
                {:else}
                  <svg
                    class="w-4 h-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="1.5"
                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="1.5"
                      d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                    />
                  </svg>
                {/if}
              </button>
            </div>
            <button
              onclick={handleCopyKey}
              class="shrink-0 w-10 flex items-center justify-center rounded-xl bg-(--color-bg) text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
              aria-label="Schlüssel kopieren"
            >
              {#if copied}
                <svg
                  class="w-4 h-4 text-emerald-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              {:else}
                <svg
                  class="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                  />
                </svg>
              {/if}
            </button>
            <button
              onclick={handleShowQR}
              class="shrink-0 w-10 flex items-center justify-center rounded-xl bg-(--color-bg) text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
              aria-label="QR-Code anzeigen"
            >
              <svg
                class="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M3 3h7v7H3V3zm11 0h7v7h-7V3zM3 14h7v7H3v-7zm14 3h.01M17 14h4v4h-4v-4zm0 4h4v3h-4v-3z"
                />
              </svg>
            </button>
          </div>
        </div>

        <!-- Sync Status -->
        <div class="flex items-center justify-between py-2">
          <span class="text-sm text-(--color-text-secondary)">Letzte Sync</span>
          <span class="text-sm font-medium text-(--color-text)">
            {formatLastSync(lastSync)}
          </span>
        </div>

        <button
          onclick={handleSyncNow}
          disabled={syncing || !isOnline}
          class="w-full py-3 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
        >
          {#if syncing}
            <span class="inline-flex items-center gap-2">
              <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                />
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                />
              </svg>
              Synchronisiere...
            </span>
          {:else if !isOnline}
            Offline
          {:else}
            Jetzt synchronisieren
          {/if}
        </button>

        <!-- Link Device -->
        <div>
          <label
            class="text-xs font-medium text-(--color-text-secondary) mb-1 block"
            for="link-input">Gerät verknüpfen</label
          >
          <div class="flex gap-2">
            <input
              id="link-input"
              type="text"
              bind:value={linkInput}
              oninput={() => (syncError = "")}
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
              data-1p-ignore
              placeholder="xxxxxxxx-xxxx-4xxx-xxxx-xxxxxxxxxxxx"
              class="flex-1 min-w-0 bg-(--color-bg) rounded-xl px-3 py-2.5 text-sm font-mono text-(--color-text) placeholder:text-(--color-text-secondary)/50 outline-none border border-transparent"
            />
            <button
              onclick={handleLink}
              disabled={syncing || !linkInput.trim()}
              class="shrink-0 px-4 rounded-xl bg-amber-500 text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
            >
              Verknüpfen
            </button>
          </div>
        </div>
      </div>
    {/if}
  </div>

  <!-- Language Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div
        class="w-10 h-10 rounded-2xl bg-sky-100 flex items-center justify-center"
      >
        <svg
          class="w-5 h-5 text-sky-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129"
          />
        </svg>
      </div>
      <div>
        <h3 class="font-bold text-(--color-text)">Sprache</h3>
        <p class="text-xs text-(--color-text-secondary)">
          Language / Sprache
        </p>
      </div>
    </div>

    <div class="flex gap-2">
      {#each localeOptions as lang}
        <button
          onclick={() => i18n.setLocale(lang.code)}
          class="flex-1 py-2.5 rounded-xl text-sm font-bold transition-colors {i18n.locale ===
          lang.code
            ? 'bg-(--color-text) text-white'
            : 'bg-(--color-bg) text-(--color-text-secondary) hover:text-(--color-text)'}"
        >
          {lang.label}
        </button>
      {/each}
    </div>
  </div>

  <!-- Rules Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <button
      onclick={() => (rulesExpanded = !rulesExpanded)}
      class="flex items-center gap-3 w-full text-left"
    >
      <div
        class="w-10 h-10 rounded-2xl bg-violet-100 flex items-center justify-center"
      >
        <svg
          class="w-5 h-5 text-violet-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
          />
        </svg>
      </div>
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-(--color-text)">Regeln</h3>
          {#if rules.length > 0}
            <span
              class="text-[10px] font-bold text-violet-600 bg-violet-50 px-1.5 py-0.5 rounded-full"
              >{rules.length}</span
            >
          {/if}
        </div>
        <p class="text-xs text-(--color-text-secondary)">
          Automatische Kategorisierung
        </p>
      </div>
      <svg
        class="w-4 h-4 text-(--color-text-secondary) transition-transform {rulesExpanded
          ? 'rotate-90'
          : ''}"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M9 5l7 7-7 7"
        />
      </svg>
    </button>

    {#if rulesExpanded}
      {#if rules.length === 0}
        <p class="text-sm text-(--color-text-secondary) py-2">
          Noch keine Regeln. Regeln werden automatisch erstellt, wenn du
          Transaktionen kategorisierst.
        </p>
      {:else}
        {#if learnedRules.length > 0}
          <div>
            <p
              class="text-xs font-semibold text-(--color-text-secondary) uppercase tracking-wider mb-2"
            >
              Gelernte Regeln
            </p>
            <div class="space-y-1">
              {#each learnedRules as rule (rule.rowid)}
                <div
                  class="group flex items-center justify-between py-1.5 px-2 rounded-xl hover:bg-(--color-bg) transition-colors"
                >
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-sm font-mono text-(--color-text) truncate"
                      >{rule.pattern}</span
                    >
                    <svg
                      class="w-3 h-3 text-(--color-text-secondary) shrink-0"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M14 5l7 7m0 0l-7 7m7-7H3"
                      />
                    </svg>
                    {#if CATEGORIES[rule.category]}
                      <span class="text-xs shrink-0"
                        >{CATEGORIES[rule.category].icon}
                        {CATEGORIES[rule.category].name}</span
                      >
                    {:else}
                      <span
                        class="text-xs text-(--color-text-secondary) shrink-0"
                        >#{rule.category}</span
                      >
                    {/if}
                  </div>
                  <button
                    onclick={() => deleteRule(rule.rowid)}
                    class="opacity-40 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity shrink-0 ml-2 w-7 h-7 flex items-center justify-center rounded-lg hover:bg-red-50 text-(--color-text-secondary) hover:text-red-500"
                    aria-label="Regel löschen"
                  >
                    <svg
                      class="w-3.5 h-3.5"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
              {/each}
            </div>
          </div>
        {/if}

        {#if seedRules.length > 0}
          <div>
            <p
              class="text-xs font-semibold text-(--color-text-secondary) uppercase tracking-wider mb-2"
            >
              Standard-Regeln
            </p>
            <div class="space-y-1">
              {#each seedRules as rule (rule.rowid)}
                <div class="flex items-center py-1.5 px-2 rounded-xl">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-sm font-mono text-(--color-text) truncate"
                      >{rule.pattern}</span
                    >
                    <svg
                      class="w-3 h-3 text-(--color-text-secondary) shrink-0"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M14 5l7 7m0 0l-7 7m7-7H3"
                      />
                    </svg>
                    {#if CATEGORIES[rule.category]}
                      <span class="text-xs shrink-0"
                        >{CATEGORIES[rule.category].icon}
                        {CATEGORIES[rule.category].name}</span
                      >
                    {:else}
                      <span
                        class="text-xs text-(--color-text-secondary) shrink-0"
                        >#{rule.category}</span
                      >
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
          </div>
        {/if}
      {/if}
    {/if}
  </div>

  <!-- Sicherheit / App-Sperre -->
  <div class="bg-white rounded-3xl p-5 shadow-sm">
    <div class="flex items-center gap-3 mb-3">
      <div class="w-10 h-10 rounded-2xl bg-blue-100 flex items-center justify-center shrink-0">
        <svg class="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6"
            d="M12 11c-1.1 0-2-.9-2-2V7a2 2 0 014 0v2a2 2 0 01-2 2zm-6 8a6 6 0 0112 0v1H6v-1z" />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-1.5">
          <h3 class="font-bold text-(--color-text)">App-Sperre</h3>
          <InfoTooltip
            text="Sperrt wimg mit einer 4-stelligen PIN, optional zusätzlich mit Face ID / Touch ID / Windows Hello via WebAuthn. Beim Tab-Wechsel oder Minimieren wird der Inhalt verschleiert, damit Vorschaubilder im Tab-Switcher deine Daten nicht zeigen. PIN-Hash bleibt lokal im Browser (PBKDF2-SHA256, 100k Iterationen)."
          />
        </div>
        <p class="text-xs text-(--color-text-secondary)">
          {#if lock.isEnabled}
            {#if lock.hasPasskey}
              Mit PIN und Biometrie geschützt
            {:else}
              Mit PIN geschützt
            {/if}
          {:else}
            Mit PIN und optional Biometrie schützen
          {/if}
        </p>
      </div>
    </div>

    {#if pinStep !== null}
      <!-- Inline PIN wizard -->
      <div class="flex flex-col gap-3">
        <p class="text-sm text-(--color-text-secondary)">
          {#if pinStep === "set"}Neue PIN festlegen (4 Ziffern){:else}PIN bestätigen{/if}
        </p>
        {#if pinStep === "set"}
          <input
            type="password"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength="4"
            autocomplete="off"
            autofocus
            bind:value={pinDraft}
            placeholder="••••"
            class="text-center text-2xl tracking-[0.4em] py-3 rounded-2xl bg-(--color-bg) border border-gray-200 outline-none focus:border-(--color-text)"
          />
        {:else}
          <input
            type="password"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength="4"
            autocomplete="off"
            bind:this={confirmPinInput}
            bind:value={pinConfirm}
            placeholder="••••"
            class="text-center text-2xl tracking-[0.4em] py-3 rounded-2xl bg-(--color-bg) border border-gray-200 outline-none focus:border-(--color-text)"
          />
        {/if}
        {#if pinError}
          <p class="text-xs text-rose-600">{pinError}</p>
        {/if}
        <div class="flex gap-2">
          <button
            type="button"
            onclick={cancelPinSetup}
            class="flex-1 py-3 rounded-2xl bg-gray-100 text-(--color-text) text-sm font-bold active:scale-[0.98] transition-transform"
          >
            Abbrechen
          </button>
          <button
            type="button"
            onclick={submitPin}
            class="flex-1 py-3 rounded-2xl bg-(--color-text) text-white text-sm font-bold active:scale-[0.98] transition-transform"
          >
            {pinStep === "set" ? "Weiter" : "Speichern"}
          </button>
        </div>
      </div>
    {:else if !lock.isEnabled}
      <button
        type="button"
        onclick={startPinSetup}
        class="w-full py-3 rounded-2xl bg-(--color-text) text-white text-sm font-bold active:scale-[0.98] transition-transform"
      >
        PIN einrichten
      </button>
    {:else}
      <!-- Auto-lock selector — only visible when PIN is enabled -->
      <div class="flex items-center justify-between gap-3 mb-2 px-1">
        <label for="autolock" class="text-sm text-(--color-text)">Auto-Sperre nach</label>
        <div class="relative">
          <select
            id="autolock"
            value={lock.autoLockMinutes}
            onchange={(e) =>
              lock.setAutoLockMinutes(
                Number((e.target as HTMLSelectElement).value) as AutoLockMinutes,
              )}
            class="appearance-none rounded-xl bg-(--color-bg) border border-gray-200 pl-3 pr-9 py-2 text-sm"
          >
            {#each AUTOLOCK_OPTIONS as opt}
              <option value={opt}>
                {opt === 0 ? "nie" : opt === 60 ? "1 Stunde" : `${opt} min`}
              </option>
            {/each}
          </select>
          <svg
            class="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 pointer-events-none text-(--color-text-secondary)"
            fill="none" stroke="currentColor" viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        {#if lock.supportsPasskey && !lock.hasPasskey}
          <button
            type="button"
            onclick={enableBiometric}
            class="w-full py-3 rounded-2xl bg-(--color-accent) text-(--color-text) text-sm font-bold active:scale-[0.98] transition-transform flex items-center justify-center gap-2"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8"
                d="M9 11V8a3 3 0 016 0v3m-7 0h8a2 2 0 012 2v6a2 2 0 01-2 2H8a2 2 0 01-2-2v-6a2 2 0 012-2z" />
            </svg>
            Face ID / Touch ID aktivieren
          </button>
        {:else if lock.hasPasskey}
          <button
            type="button"
            onclick={() => lock.removePasskey()}
            class="w-full py-3 rounded-2xl bg-gray-100 text-(--color-text) text-sm font-medium active:scale-[0.98] transition-transform"
          >
            Biometrie entfernen
          </button>
        {/if}
        <button
          type="button"
          onclick={startPinSetup}
          class="w-full py-3 rounded-2xl bg-gray-100 text-(--color-text) text-sm font-medium active:scale-[0.98] transition-transform"
        >
          PIN ändern
        </button>
        <button
          type="button"
          onclick={disableLock}
          class="w-full py-3 rounded-2xl bg-rose-50 text-rose-700 text-sm font-medium active:scale-[0.98] transition-transform"
        >
          App-Sperre deaktivieren
        </button>
      </div>
    {/if}

    {#if !lock.supportsPasskey && !lock.hasPasskey && lock.isEnabled}
      <p class="text-xs text-(--color-text-secondary) mt-3">
        Dieser Browser unterstützt keine biometrische Entsperrung (WebAuthn).
      </p>
    {/if}
  </div>

  <!-- Export Section -->
  <button
    id="export"
    onclick={() => pushState("", { sheet: "export" })}
    class="bg-white rounded-3xl p-5 shadow-sm flex items-center gap-3 w-full text-left group active:scale-[0.98] transition-transform"
  >
    <div
      class="w-10 h-10 rounded-2xl bg-emerald-100 flex items-center justify-center"
    >
      <svg
        class="w-5 h-5 text-emerald-600"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
        />
      </svg>
    </div>
    <div class="flex-1">
      <h3 class="font-bold text-(--color-text)">Daten exportieren</h3>
      <p class="text-xs text-(--color-text-secondary)">
        Transaktionen als CSV oder komplettes Backup
      </p>
    </div>
    <svg
      class="w-4 h-4 text-(--color-text-secondary)"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M9 5l7 7-7 7"
      />
    </svg>
  </button>

  <!-- Daten-Browser (SQL viewer) -->
  <button
    onclick={openDataBrowser}
    class="bg-white rounded-3xl p-5 shadow-sm flex items-center gap-3 w-full text-left group active:scale-[0.98] transition-transform"
  >
    <div
      class="w-10 h-10 rounded-2xl bg-indigo-100 flex items-center justify-center"
    >
      <svg
        class="w-5 h-5 text-indigo-600"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M4 7v10c0 2 1 3 8 3s8-1 8-3V7M4 7c0-2 1-3 8-3s8 1 8 3M4 7c0 2 1 3 8 3s8-1 8-3m-8 7c4 0 8-1 8-3"
        />
      </svg>
    </div>
    <div class="flex-1">
      <h3 class="font-bold text-(--color-text)">Daten-Browser</h3>
      <p class="text-xs text-(--color-text-secondary)">
        SQL-Abfragen gegen die lokale Datenbank
      </p>
    </div>
    <svg
      class="w-4 h-4 text-(--color-text-secondary)"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="1.5"
        d="M9 5l7 7-7 7"
      />
    </svg>
  </button>

  <!-- Demo Data Section -->
  {#if demoLoaded}
    <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
      <div class="flex items-center gap-3">
        <div
          class="w-10 h-10 rounded-2xl bg-amber-100 flex items-center justify-center"
        >
          <svg
            class="w-5 h-5 text-amber-600"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
            />
          </svg>
        </div>
        <div>
          <div class="flex items-center gap-2">
            <h3 class="font-bold text-(--color-text)">Demo-Daten</h3>
            <span
              class="text-[10px] font-bold text-amber-600 bg-amber-50 px-1.5 py-0.5 rounded-full"
              >Aktiv</span
            >
          </div>
          <p class="text-xs text-(--color-text-secondary)">
            Beispieldaten sind geladen
          </p>
        </div>
      </div>

      <button
        onclick={handleResetData}
        class="w-full py-3 rounded-2xl border-2 border-amber-200 text-amber-700 font-bold text-sm transition-colors hover:bg-amber-50 active:scale-[0.98]"
      >
        Demo-Daten löschen
      </button>
    </div>
  {/if}

  <!-- Danger Zone -->
  {#if hasLocalData}
    <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
      <div class="flex items-center gap-3">
        <div
          class="w-10 h-10 rounded-2xl bg-red-100 flex items-center justify-center"
        >
          <svg
            class="w-5 h-5 text-red-600"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
            />
          </svg>
        </div>
        <div>
          <h3 class="font-bold text-red-700">Daten zurücksetzen</h3>
          <p class="text-xs text-(--color-text-secondary)">
            Lokale Datenbank, Sync-Daten & alte Modelle löschen
          </p>
        </div>
      </div>

      <button
        onclick={() => pushState("", { sheet: "confirm-reset" })}
        class="w-full py-3 rounded-2xl border-2 border-red-200 text-red-600 font-bold text-sm transition-colors hover:bg-red-50 active:scale-[0.98]"
      >
        Alle Daten löschen
      </button>
    </div>
  {/if}
</section>

<!-- Sync Info / Confirmation Sheet -->
<Drawer open={showSyncInfo} onclose={() => history.back()}>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6">
      <div class="flex items-center gap-3 mb-5">
        <div
          class="w-12 h-12 rounded-2xl bg-amber-100 flex items-center justify-center shrink-0"
        >
          <svg
            class="w-6 h-6 text-amber-600"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
        </div>
        <div>
          <h3 class="font-display font-extrabold text-lg text-(--color-text)">
            Synchronisierung
          </h3>
          <p class="text-sm text-(--color-text-secondary)">
            Daten zwischen Geräten teilen
          </p>
        </div>
      </div>

      <div class="space-y-3">
        <div class="flex items-start gap-3">
          <div
            class="w-8 h-8 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0 mt-0.5"
          >
            <svg
              class="w-4 h-4 text-emerald-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-(--color-text)">
              Echtzeit-Synchronisierung
            </p>
            <p class="text-xs text-(--color-text-secondary)">
              Änderungen erscheinen sofort auf allen verbundenen Geräten.
            </p>
          </div>
        </div>

        <div class="flex items-start gap-3">
          <div
            class="w-8 h-8 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0 mt-0.5"
          >
            <svg
              class="w-4 h-4 text-emerald-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-(--color-text)">
              Ein Schlüssel, kein Konto
            </p>
            <p class="text-xs text-(--color-text-secondary)">
              Ein zufälliger Sync-Schlüssel wird erstellt. Kein Konto, kein
              Passwort.
            </p>
          </div>
        </div>

        <div class="flex items-start gap-3">
          <div
            class="w-8 h-8 rounded-xl bg-red-50 flex items-center justify-center shrink-0 mt-0.5"
          >
            <svg
              class="w-4 h-4 text-red-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-(--color-text)">
              Schlüssel geheim halten
            </p>
            <p class="text-xs text-(--color-text-secondary)">
              Wer den Schlüssel hat, kann deine Daten sehen. Teile ihn nur mit
              deinen eigenen Geräten.
            </p>
          </div>
        </div>

        <div class="flex items-start gap-3">
          <div
            class="w-8 h-8 rounded-xl bg-purple-50 flex items-center justify-center shrink-0 mt-0.5"
          >
            <svg
              class="w-4 h-4 text-purple-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
              />
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-(--color-text)">
              MCP für KI-Agenten
            </p>
            <p class="text-xs text-(--color-text-secondary)">
              Dein Sync-Schlüssel dient auch als MCP-Zugang. Claude.ai kann
              deine Finanzdaten abfragen und verwalten. Personenbezogene Daten
              (IBANs, Kartennummern, Namen) werden automatisch entfernt.
            </p>
          </div>
        </div>
      </div>
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <button
        onclick={() => {
          history.back();
          handleEnableSync();
        }}
        disabled={syncing}
        class="w-full py-3.5 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50 mb-2"
      >
        {#if syncing}
          <span class="inline-flex items-center gap-2">
            <span
              class="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin"
            ></span>
            Aktiviere...
          </span>
        {:else}
          Sync aktivieren
        {/if}
      </button>
      <button
        onclick={() => history.back()}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
      >
        Abbrechen
      </button>
    </div>
  {/snippet}
</Drawer>

<!-- QR Code Sheet -->
<Drawer open={showQR} onclose={() => history.back()}>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 flex flex-col items-center">
      <h3 class="font-bold text-lg text-(--color-text) mb-1">Sync-Schlüssel</h3>
      <p class="text-xs text-(--color-text-secondary) mb-6">
        Scanne diesen Code auf dem anderen Gerät
      </p>

      {#if qrSvg}
        <div
          class="bg-white rounded-2xl p-5 shadow-sm border border-gray-100 w-64 h-64"
        >
          {@html qrSvg}
        </div>
      {/if}

      <p
        class="mt-5 text-xs font-mono text-(--color-text-secondary) text-center break-all px-4"
      >
        {syncKey}
      </p>
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <button
        onclick={() => history.back()}
        class="w-full py-3.5 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98]"
      >
        Fertig
      </button>
    </div>
  {/snippet}
</Drawer>

<!-- QR Link Confirmation Sheet -->
<Drawer
  open={showLinkConfirm}
  onclose={() => {
    pendingSyncKey = "";
    history.back();
  }}
>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 flex flex-col items-center">
      <div
        class="w-14 h-14 rounded-full bg-blue-50 flex items-center justify-center mb-4"
      >
        <svg
          class="w-7 h-7 text-blue-500"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
          />
        </svg>
      </div>
      <h3 class="font-bold text-lg text-(--color-text) mb-1">
        Gerät verknüpfen?
      </h3>
      <p class="text-sm text-(--color-text-secondary) text-center mb-2">
        Dieses Gerät mit folgendem Sync-Schlüssel verbinden:
      </p>
      <p
        class="text-xs font-mono text-(--color-text-secondary) text-center break-all bg-gray-50 rounded-xl px-4 py-2 w-full"
      >
        {pendingSyncKey.slice(0, 8)}••••{pendingSyncKey.slice(-4)}
      </p>
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <button
        onclick={handleConfirmLink}
        class="w-full py-3.5 rounded-2xl bg-(--color-text) text-white font-bold text-sm mb-3 transition-transform active:scale-[0.98]"
      >
        Verknüpfen
      </button>
      <button
        onclick={() => {
          pendingSyncKey = "";
          history.back();
        }}
        class="w-full py-3 rounded-2xl text-(--color-text-secondary) font-medium text-sm transition-colors hover:text-(--color-text)"
      >
        Abbrechen
      </button>
    </div>
  {/snippet}
</Drawer>

<!-- Delete Confirmation Sheet -->
<Drawer open={confirmReset} onclose={() => history.back()} snaps={[0.48]}>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 flex flex-col items-center">
      <div
        class="w-16 h-16 rounded-full bg-red-100 flex items-center justify-center mb-4 mt-2"
      >
        <svg
          class="w-8 h-8 text-red-500"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
          />
        </svg>
      </div>

      <h3 class="font-display font-extrabold text-xl text-(--color-text) mb-1">
        Alle Daten löschen?
      </h3>
      <p class="text-sm text-(--color-text-secondary) text-center">
        Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann
        nicht rückgängig gemacht werden.
      </p>
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <button
        onclick={handleResetData}
        disabled={resetting}
        class="w-full py-3.5 rounded-2xl bg-red-600 text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50 mb-2"
      >
        {resetting ? "Lösche..." : "Ja, alles löschen"}
      </button>

      <button
        onclick={() => history.back()}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
      >
        Abbrechen
      </button>
    </div>
  {/snippet}
</Drawer>

<!-- Export Sheet -->
<Drawer
  open={showExportSheet}
  onclose={() => history.back()}
  snaps={[0.58]}
>
  {#snippet children({ handle, content, footer })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6">
      <div class="flex items-center gap-3 mb-5">
        <div
          class="w-12 h-12 rounded-2xl bg-emerald-100 flex items-center justify-center shrink-0"
        >
          <svg
            class="w-6 h-6 text-emerald-600"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
            />
          </svg>
        </div>
        <div>
          <h3 class="font-display font-extrabold text-lg text-(--color-text)">
            Daten exportieren
          </h3>
          <p class="text-sm text-(--color-text-secondary)">
            Deine Daten gehören dir
          </p>
        </div>
      </div>

      <div class="space-y-3">
        <!-- CSV Option -->
        <button
          onclick={handleExportCsv}
          disabled={exporting}
          class="w-full rounded-2xl border-2 border-gray-100 p-4 text-left transition-colors hover:border-emerald-200 hover:bg-emerald-50/30 active:scale-[0.98] disabled:opacity-50"
        >
          <div class="flex items-start gap-3">
            <div
              class="w-10 h-10 rounded-xl bg-green-100 flex items-center justify-center shrink-0 mt-0.5"
            >
              <svg
                class="w-5 h-5 text-green-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M3 10h18M3 14h18m-9-4v8m-7 0h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
                />
              </svg>
            </div>
            <div>
              <p class="font-bold text-sm text-(--color-text)">
                Transaktionen (CSV)
              </p>
              <p class="text-xs text-(--color-text-secondary) mt-0.5">
                Alle Transaktionen als Tabelle. Perfekt für Excel, Numbers oder
                Google Sheets.
              </p>
              <p class="text-[10px] text-(--color-text-secondary)/60 mt-1">
                Datum, Beschreibung, Betrag, Kategorie, Konto
              </p>
            </div>
          </div>
        </button>

        <!-- JSON Option -->
        <button
          onclick={handleExportJson}
          disabled={exporting}
          class="w-full rounded-2xl border-2 border-gray-100 p-4 text-left transition-colors hover:border-emerald-200 hover:bg-emerald-50/30 active:scale-[0.98] disabled:opacity-50"
        >
          <div class="flex items-start gap-3">
            <div
              class="w-10 h-10 rounded-xl bg-blue-100 flex items-center justify-center shrink-0 mt-0.5"
            >
              <svg
                class="w-5 h-5 text-blue-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"
                />
              </svg>
            </div>
            <div>
              <p class="font-bold text-sm text-(--color-text)">
                Komplettes Backup (JSON)
              </p>
              <p class="text-xs text-(--color-text-secondary) mt-0.5">
                Die gesamte Datenbank als JSON-Datei. Enthält alle Konten,
                Transaktionen, Schulden und Regeln.
              </p>
              <p class="text-[10px] text-(--color-text-secondary)/60 mt-1">
                Maschinenlesbar, ideal als Sicherungskopie
              </p>
            </div>
          </div>
        </button>
      </div>

      {#if exportSuccess}
        <p class="text-xs text-emerald-600 text-center font-medium mt-4">
          {exportSuccess}
        </p>
      {/if}
    </div>

    <div {@attach footer} class="px-6 pb-8 pt-4">
      <button
        onclick={() => history.back()}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
      >
        Schliessen
      </button>
    </div>
  {/snippet}
</Drawer>
