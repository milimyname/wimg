<script lang="ts">
  import { onMount } from "svelte";
  import { APP_VERSION, RELEASES_URL } from "$lib/version";
  import { generateQRSvg } from "$lib/qr";
  import { getApiKey, setApiKey, removeApiKey } from "$lib/claude";
  import BottomSheet from "../../../components/BottomSheet.svelte";
  import {
    getSyncKey,
    setSyncKey,
    clearSyncKey,
    syncFull,
    syncPull,
    syncPush,
    isSyncEnabled,
    getLastSyncTimestamp,
  } from "$lib/sync";

  let syncEnabled = $state(false);
  let syncKey = $state("");
  let linkInput = $state("");
  let passphrase = $state("");
  let showPassphrase = $state(false);
  let showKey = $state(false);
  let syncing = $state(false);
  let syncError = $state("");
  let syncSuccess = $state("");
  let lastSync = $state(0);
  let confirmReset = $state(false);
  let resetting = $state(false);
  let copied = $state(false);
  let hasLocalData = $state(false);
  let showQR = $state(false);
  let qrSvg = $state("");

  // Claude AI state
  let claudeApiKey = $state("");
  let claudeHasKey = $state(false);
  let claudeShowInput = $state(false);

  const maskedKey = $derived(
    syncKey ? syncKey.slice(0, 4) + "••••-••••-••••-" + syncKey.slice(-4) : "",
  );

  onMount(async () => {
    const stored = getSyncKey();
    if (stored) {
      syncEnabled = true;
      syncKey = stored;
    }
    lastSync = getLastSyncTimestamp();
    claudeHasKey = !!getApiKey();
    claudeApiKey = getApiKey() ?? "";

    try {
      const root = await navigator.storage.getDirectory();
      await root.getFileHandle("wimg.db");
      hasLocalData = true;
    } catch {
      hasLocalData = false;
    }
  });

  async function handleEnableSync() {
    const key = crypto.randomUUID();
    setSyncKey(key);
    syncKey = key;
    syncEnabled = true;
    showKey = true;
    syncError = "";
    syncSuccess = "";

    syncing = true;
    try {
      await syncPush(key);
      syncSuccess = "Sync aktiviert & Daten hochgeladen";
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
    const key = linkInput.trim();
    setSyncKey(key);
    syncKey = key;
    syncEnabled = true;
    linkInput = "";
    syncing = true;
    syncError = "";
    syncSuccess = "";

    try {
      const pulled = await syncPull(key);
      syncSuccess = `Verknüpft & ${pulled} Einträge empfangen`;
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
    qrSvg = generateQRSvg(syncKey);
    showQR = true;
  }

  async function handleResetData() {
    resetting = true;
    try {
      const root = await navigator.storage.getDirectory();
      try {
        await root.removeEntry("wimg.db");
      } catch {
        // File may not exist
      }
      clearSyncKey();
      localStorage.removeItem("wimg_sync_last_ts");
      window.location.reload();
    } catch (e) {
      resetting = false;
      confirmReset = false;
    }
  }

  function handleSaveClaudeKey() {
    const trimmed = claudeApiKey.trim();
    if (trimmed) {
      setApiKey(trimmed);
      claudeHasKey = true;
      claudeShowInput = false;
    }
  }

  function handleRemoveClaudeKey() {
    removeApiKey();
    claudeApiKey = "";
    claudeHasKey = false;
    claudeShowInput = false;
  }

  function formatLastSync(ts: number): string {
    if (ts === 0) return "Noch nie";
    const d = new Date(ts);
    return d.toLocaleDateString("de-DE") + " " + d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
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
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
    </a>
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">Einstellungen</h2>
  </div>

  <!-- Sync Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-2xl bg-amber-100 flex items-center justify-center">
        <svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      </div>
      <div>
        <h3 class="font-bold text-(--color-text)">Synchronisierung</h3>
        <p class="text-xs text-(--color-text-secondary)">Daten zwischen Geräten synchronisieren</p>
      </div>
    </div>

    {#if syncError}
      <div class="rounded-xl bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700">
        {syncError}
      </div>
    {/if}

    {#if syncSuccess}
      <div class="rounded-xl bg-emerald-50 border border-emerald-200 px-3 py-2 text-sm text-emerald-700">
        {syncSuccess}
      </div>
    {/if}

    {#if !syncEnabled}
      <button
        onclick={handleEnableSync}
        disabled={syncing}
        class="w-full py-3 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
      >
        {syncing ? "Aktiviere..." : "Sync aktivieren"}
      </button>
    {:else}
      <div class="space-y-3">
        <!-- Sync Key (masked) -->
        <div>
          <label class="text-xs font-medium text-(--color-text-secondary) mb-1 block" for="sync-key-input">Sync-Schlüssel</label>
          <div class="flex gap-1.5">
            <div class="min-w-0 flex-1 relative">
              <input
                id="sync-key-input"
                type="text"
                readonly
                value={showKey ? syncKey : maskedKey}
                class="w-full bg-(--color-bg) rounded-xl px-3 py-2.5 pr-10 text-xs font-mono text-(--color-text) outline-none truncate"
              />
              <button
                onclick={() => (showKey = !showKey)}
                class="absolute right-2.5 top-1/2 -translate-y-1/2 text-(--color-text-secondary)"
                aria-label={showKey ? "Schlüssel verbergen" : "Schlüssel anzeigen"}
              >
                {#if showKey}
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
                  </svg>
                {:else}
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
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
                <svg class="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
              {:else}
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              {/if}
            </button>
            <button
              onclick={handleShowQR}
              class="shrink-0 w-10 flex items-center justify-center rounded-xl bg-(--color-bg) text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
              aria-label="QR-Code anzeigen"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 3h7v7H3V3zm11 0h7v7h-7V3zM3 14h7v7H3v-7zm14 3h.01M17 14h4v4h-4v-4zm0 4h4v3h-4v-3z" />
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
          disabled={syncing}
          class="w-full py-3 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
        >
          {#if syncing}
            <span class="inline-flex items-center gap-2">
              <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              Synchronisiere...
            </span>
          {:else}
            Jetzt synchronisieren
          {/if}
        </button>

        <!-- Link Device -->
        <div>
          <label class="text-xs font-medium text-(--color-text-secondary) mb-1 block" for="link-input">Gerät verknüpfen</label>
          <div class="flex gap-2">
            <input
              id="link-input"
              type="text"
              bind:value={linkInput}
              placeholder="Sync-Schlüssel einfügen"
              class="flex-1 bg-(--color-bg) rounded-xl px-3 py-2.5 text-sm text-(--color-text) placeholder:text-(--color-text-secondary)/50 outline-none"
            />
            <button
              onclick={handleLink}
              disabled={syncing || !linkInput.trim()}
              class="px-4 rounded-xl bg-amber-500 text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
            >
              Verknüpfen
            </button>
          </div>
        </div>
      </div>
    {/if}
  </div>

  <!-- Encryption Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-2xl bg-emerald-100 flex items-center justify-center">
        <svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>
      </div>
      <div>
        <h3 class="font-bold text-(--color-text)">Verschlüsselung</h3>
        <p class="text-xs text-(--color-text-secondary)">Ende-zu-Ende-Verschlüsselung für Sync</p>
      </div>
    </div>

    <div>
      <label class="text-xs font-medium text-(--color-text-secondary) mb-1 block" for="passphrase-input">Passphrase</label>
      <div class="flex gap-2">
        <div class="flex-1 relative">
          <input
            id="passphrase-input"
            type={showPassphrase ? "text" : "password"}
            bind:value={passphrase}
            placeholder="Passphrase eingeben"
            class="w-full bg-(--color-bg) rounded-xl px-3 py-2.5 pr-10 text-sm text-(--color-text) placeholder:text-(--color-text-secondary)/50 outline-none"
          />
          <button
            onclick={() => showPassphrase = !showPassphrase}
            class="absolute right-3 top-1/2 -translate-y-1/2 text-(--color-text-secondary)"
            aria-label={showPassphrase ? "Passphrase verbergen" : "Passphrase anzeigen"}
          >
            {#if showPassphrase}
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
              </svg>
            {:else}
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
              </svg>
            {/if}
          </button>
        </div>
        <button
          class="px-4 rounded-xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98]"
        >
          Ändern
        </button>
      </div>
    </div>
  </div>

  <!-- Claude AI Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-2xl bg-purple-100 flex items-center justify-center">
        <svg class="w-5 h-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
        </svg>
      </div>
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-(--color-text)">Claude AI</h3>
          {#if claudeHasKey}
            <span class="text-[10px] font-bold text-emerald-600 bg-emerald-50 px-1.5 py-0.5 rounded-full">Aktiv</span>
          {:else}
            <span class="text-[10px] font-bold text-(--color-text-secondary) bg-gray-100 px-1.5 py-0.5 rounded-full">Nicht konfiguriert</span>
          {/if}
        </div>
        <p class="text-xs text-(--color-text-secondary)">KI-Kategorisierung</p>
      </div>
    </div>

    {#if !claudeHasKey || claudeShowInput}
      <div>
        <label class="text-xs font-medium text-(--color-text-secondary) mb-1 block" for="claude-key-input">API-Schlüssel</label>
        <div class="flex gap-2">
          <input
            id="claude-key-input"
            type="password"
            bind:value={claudeApiKey}
            placeholder="sk-ant-..."
            class="flex-1 bg-(--color-bg) rounded-xl px-3 py-2.5 text-sm text-(--color-text) placeholder:text-(--color-text-secondary)/50 outline-none"
          />
          <button
            onclick={handleSaveClaudeKey}
            disabled={!claudeApiKey.trim()}
            class="px-4 rounded-xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            Speichern
          </button>
        </div>
        <p class="text-[10px] text-(--color-text-secondary) mt-1.5">
          Nur lokal gespeichert. Wird nur an die Anthropic API gesendet.
        </p>
      </div>
    {/if}

    {#if claudeHasKey && !claudeShowInput}
      <div class="flex items-center gap-3">
        <button
          onclick={() => (claudeShowInput = true)}
          class="text-xs text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
        >
          Key ändern
        </button>
        <button
          onclick={handleRemoveClaudeKey}
          class="text-xs text-red-400 hover:text-red-600 transition-colors"
        >
          Entfernen
        </button>
      </div>
    {/if}
  </div>

  <!-- About Section -->
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-3">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-2xl bg-gray-100 flex items-center justify-center">
        <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
      <div>
        <h3 class="font-bold text-(--color-text)">Über</h3>
        <p class="text-xs text-(--color-text-secondary)">Version & Links</p>
      </div>
    </div>

    <div class="space-y-1">
      <div class="flex items-center justify-between py-2.5 border-b border-gray-50">
        <span class="text-sm text-(--color-text-secondary)">Version</span>
        <span class="text-sm font-mono font-medium text-(--color-text)">{APP_VERSION}</span>
      </div>

      <button
        class="flex items-center justify-between py-2.5 w-full border-b border-gray-50 group"
      >
        <span class="text-sm text-(--color-text-secondary) group-hover:text-(--color-text) transition-colors">Daten exportieren</span>
        <svg class="w-4 h-4 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5l7 7-7 7" />
        </svg>
      </button>

      <a
        href={RELEASES_URL}
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center justify-between py-2.5 group"
      >
        <span class="text-sm text-(--color-text-secondary) group-hover:text-(--color-text) transition-colors">GitHub</span>
        <svg class="w-4 h-4 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
        </svg>
      </a>
    </div>
  </div>

  <!-- Danger Zone -->
  {#if hasLocalData}
  <div class="bg-white rounded-3xl p-5 shadow-sm space-y-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-2xl bg-red-100 flex items-center justify-center">
        <svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z" />
        </svg>
      </div>
      <div>
        <h3 class="font-bold text-red-700">Daten zurücksetzen</h3>
        <p class="text-xs text-(--color-text-secondary)">Lokale Datenbank & Sync-Daten löschen</p>
      </div>
    </div>

    <button
      onclick={() => (confirmReset = true)}
      class="w-full py-3 rounded-2xl border-2 border-red-200 text-red-600 font-bold text-sm transition-colors hover:bg-red-50 active:scale-[0.98]"
    >
      Alle Daten löschen
    </button>
  </div>
  {/if}
</section>

<!-- QR Code Sheet -->
<BottomSheet open={showQR} onclose={() => (showQR = false)} snaps={[0.52]}>
  {#snippet children({ handle, content })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 pb-8 flex flex-col items-center">
      <h3 class="font-bold text-lg text-(--color-text) mb-1">Sync-Schlüssel</h3>
      <p class="text-xs text-(--color-text-secondary) mb-5">Scanne diesen Code auf dem anderen Gerät</p>

      {#if qrSvg}
        <div class="bg-white rounded-2xl p-4 shadow-sm border border-gray-100 w-64 h-64">
          {@html qrSvg}
        </div>
      {/if}

      <p class="mt-4 text-xs font-mono text-(--color-text-secondary) text-center break-all px-4">{syncKey}</p>

      <button
        onclick={() => (showQR = false)}
        class="mt-5 w-full py-3 rounded-2xl bg-(--color-text) text-white font-bold text-sm transition-transform active:scale-[0.98]"
      >
        Fertig
      </button>
    </div>
  {/snippet}
</BottomSheet>

<!-- Delete Confirmation Sheet -->
<BottomSheet open={confirmReset} onclose={() => (confirmReset = false)} snaps={[0.38]}>
  {#snippet children({ handle, content })}
    <div {@attach handle} class="flex justify-center pt-3 pb-2">
      <div class="w-10 h-1 rounded-full bg-gray-200"></div>
    </div>

    <div {@attach content} class="px-6 pb-8 flex flex-col items-center">
      <div class="w-16 h-16 rounded-full bg-red-100 flex items-center justify-center mb-4 mt-2">
        <svg class="w-8 h-8 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z" />
        </svg>
      </div>

      <h3 class="font-display font-extrabold text-xl text-(--color-text) mb-1">Alle Daten löschen?</h3>
      <p class="text-sm text-(--color-text-secondary) text-center mb-6">
        Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.
      </p>

      <button
        onclick={handleResetData}
        disabled={resetting}
        class="w-full py-3.5 rounded-2xl bg-red-600 text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-50 mb-2"
      >
        {resetting ? "Lösche..." : "Ja, alles löschen"}
      </button>

      <button
        onclick={() => (confirmReset = false)}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-bg) transition-colors"
      >
        Abbrechen
      </button>
    </div>
  {/snippet}
</BottomSheet>
