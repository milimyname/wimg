<script lang="ts">
  import { devtoolsStore, type SyncEvent, type SyncDiff } from "$lib/devtools.svelte";
  import { syncWS } from "$lib/sync-ws.svelte";
  import { getWasmMemoryBytes, getWasmDbSize, getTransactions, getAccounts, getDebts, getRecurring, getSnapshots, close, queryRaw, type QueryResult } from "$lib/wasm";
  import { clearSyncKey, getSyncKey } from "$lib/sync";
  import { featureStore } from "$lib/features.svelte";

  const TABS = ["wasm", "memory", "sync", "data", "sql"] as const;
  const TAB_LABELS: Record<(typeof TABS)[number], string> = {
    wasm: "WASM",
    memory: "Memory",
    sync: "Sync",
    data: "Data",
    sql: "SQL",
  };

  // Memory tab auto-refresh
  let memoryBytes = $state(0);
  let initialMemoryBytes = $state(0);
  let dbSizeBytes = $state(0);

  $effect(() => {
    if (!devtoolsStore.open || devtoolsStore.activeTab !== "memory") return;
    const update = () => {
      memoryBytes = getWasmMemoryBytes();
      dbSizeBytes = getWasmDbSize();
      if (initialMemoryBytes === 0 && memoryBytes > 0) initialMemoryBytes = memoryBytes;
    };
    update();
    const interval = setInterval(update, 2000);
    return () => clearInterval(interval);
  });

  // Data tab counts
  let dataCounts = $state<{ label: string; count: number }[]>([]);

  function refreshData() {
    try {
      dataCounts = [
        { label: "Transaktionen", count: getTransactions().length },
        { label: "Konten", count: getAccounts().length },
        { label: "Schulden", count: getDebts().length },
        { label: "Wiederkehrend", count: getRecurring().length },
        { label: "Snapshots", count: getSnapshots().length },
      ];
    } catch {
      dataCounts = [];
    }
  }

  $effect(() => {
    if (devtoolsStore.open && devtoolsStore.activeTab === "data") {
      refreshData();
    }
  });

  function relativeTime(ts: number): string {
    const diff = Math.floor((Date.now() - ts) / 1000);
    if (diff < 1) return "now";
    if (diff < 60) return `${diff}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    return `${Math.floor(diff / 3600)}h ago`;
  }

  function durationBadgeClass(ms: number): string {
    if (ms < 1) return "bg-green-100 text-green-700";
    if (ms <= 5) return "bg-amber-100 text-amber-700";
    return "bg-red-100 text-red-700";
  }

  function syncTypeIcon(type: SyncEvent["type"]): string {
    switch (type) {
      case "push": return "\u2191";
      case "pull": return "\u2193";
      case "ws-connect": return "\u26A1";
      case "ws-disconnect": return "\u26D4";
      case "ws-message": return "\u2709";
    }
  }

  function formatBytes(bytes: number, unit: "MB" | "KB" = "MB"): string {
    if (unit === "KB") return (bytes / 1024).toFixed(1);
    return (bytes / 1024 / 1024).toFixed(1);
  }

  // SQL tab
  let sqlInput = $state("SELECT * FROM transactions LIMIT 10");
  let sqlResult = $state<QueryResult | null>(null);
  let sqlError = $state<string | null>(null);
  let sqlRunning = $state(false);

  function runSql() {
    sqlError = null;
    sqlResult = null;
    sqlRunning = true;
    try {
      sqlResult = queryRaw(sqlInput);
    } catch (e) {
      sqlError = e instanceof Error ? e.message : String(e);
    } finally {
      sqlRunning = false;
    }
  }

  // SQL history
  let sqlHistory = $state<string[]>([]);

  function addToHistory(sql: string) {
    const trimmed = sql.trim();
    if (!trimmed) return;
    sqlHistory = [trimmed, ...sqlHistory.filter(h => h !== trimmed)].slice(0, 20);
  }

  // Schema inspector
  interface TableSchema { name: string; sql: string; rowCount: number }
  let schemaOpen = $state(false);
  let schemaData = $state<TableSchema[]>([]);
  let expandedTable = $state<string | null>(null);

  function loadSchema() {
    try {
      const result = queryRaw("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      schemaData = result.rows.map((row) => {
        const name = row[0] as string;
        let rowCount = 0;
        try {
          const countResult = queryRaw(`SELECT COUNT(*) FROM "${name}"`);
          rowCount = (countResult.rows[0]?.[0] as number) ?? 0;
        } catch { /* ignore */ }
        return { name, sql: (row[1] as string) ?? "", rowCount };
      });
    } catch (err) {
      console.error("[DevTools] loadSchema failed:", err);
      schemaData = [];
    }
  }

  // localStorage inspector
  interface LsEntry { key: string; value: string; size: number }
  let lsEntries = $state<LsEntry[]>([]);
  let lsEditKey = $state<string | null>(null);
  let lsEditValue = $state("");

  function refreshLs() {
    const entries: LsEntry[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key) continue;
      const value = localStorage.getItem(key) ?? "";
      entries.push({ key, value, size: new Blob([value]).size });
    }
    entries.sort((a, b) => a.key.localeCompare(b.key));
    lsEntries = entries;
  }

  function saveLsEdit() {
    if (lsEditKey) {
      localStorage.setItem(lsEditKey, lsEditValue);
      lsEditKey = null;
      refreshLs();
    }
  }

  function deleteLsKey(key: string) {
    localStorage.removeItem(key);
    refreshLs();
  }

  $effect(() => {
    if (devtoolsStore.open && devtoolsStore.activeTab === "data") {
      refreshLs();
    }
  });

  // Feature flags
  const featureToggles = [
    { key: "debts", label: "Schulden" },
    { key: "recurring", label: "Wiederkehrend" },
    { key: "review", label: "Rückblick" },
  ];

  // OPFS file browser
  interface OpfsFile { name: string; size: number }
  let opfsFiles = $state<OpfsFile[]>([]);
  let opfsLoading = $state(false);

  async function refreshOpfs() {
    opfsLoading = true;
    try {
      const root = await navigator.storage.getDirectory();
      const files: OpfsFile[] = [];
      for await (const [name, handle] of (root as any).entries()) {
        if (handle.kind === "file") {
          const file = await (handle as FileSystemFileHandle).getFile();
          files.push({ name, size: file.size });
        } else {
          files.push({ name: name + "/", size: -1 });
        }
      }
      files.sort((a, b) => a.name.localeCompare(b.name));
      opfsFiles = files;
    } catch {
      opfsFiles = [];
    } finally {
      opfsLoading = false;
    }
  }

  async function downloadOpfsFile(name: string) {
    try {
      const root = await navigator.storage.getDirectory();
      const fh = await root.getFileHandle(name);
      const file = await fh.getFile();
      const url = URL.createObjectURL(file);
      const a = document.createElement("a");
      a.href = url;
      a.download = name;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error("[DevTools] OPFS download failed:", e);
    }
  }

  async function deleteOpfsFile(name: string) {
    try {
      const root = await navigator.storage.getDirectory();
      await root.removeEntry(name);
      await refreshOpfs();
    } catch (e) {
      console.error("[DevTools] OPFS delete failed:", e);
    }
  }

  $effect(() => {
    if (devtoolsStore.open && devtoolsStore.activeTab === "data") {
      refreshOpfs();
    }
  });

  // Sync diff expand
  let expandedDiff = $state<number | null>(null);

  function diffDirectionIcon(dir: SyncDiff["direction"]): string {
    return dir === "push" ? "\u2191" : dir === "pull" ? "\u2193" : "\u26A1";
  }

  // State snapshots (save/restore)
  async function saveStateSnapshot() {
    const state: Record<string, unknown> = {};

    // localStorage
    const ls: Record<string, string> = {};
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key) ls[key] = localStorage.getItem(key) ?? "";
    }
    state.localStorage = ls;

    // OPFS
    try {
      const root = await navigator.storage.getDirectory();
      const files: Record<string, string> = {};
      for await (const [name, handle] of (root as any).entries()) {
        if (handle.kind === "file") {
          const file = await (handle as FileSystemFileHandle).getFile();
          const buf = await file.arrayBuffer();
          // Base64 encode binary data
          const bytes = new Uint8Array(buf);
          let binary = "";
          for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
          files[name] = btoa(binary);
        }
      }
      state.opfs = files;
    } catch { /* no OPFS */ }

    state._meta = { version: 1, timestamp: Date.now(), url: window.location.href };

    const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `wimg-state-${new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-")}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function restoreStateSnapshot(file: File) {
    try {
      const text = await file.text();
      const state = JSON.parse(text) as Record<string, unknown>;

      // Restore localStorage
      const ls = state.localStorage as Record<string, string> | undefined;
      if (ls) {
        localStorage.clear();
        for (const [key, value] of Object.entries(ls)) {
          localStorage.setItem(key, value);
        }
      }

      // Restore OPFS
      const opfs = state.opfs as Record<string, string> | undefined;
      if (opfs) {
        const root = await navigator.storage.getDirectory();
        for (const [name, b64] of Object.entries(opfs)) {
          const binary = atob(b64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const fh = await root.getFileHandle(name, { create: true }); // eslint-disable-line no-await-in-loop -- sequential OPFS writes
          const writable = await fh.createWritable(); // eslint-disable-line no-await-in-loop
          await writable.write(bytes); // eslint-disable-line no-await-in-loop
          await writable.close(); // eslint-disable-line no-await-in-loop
        }
      }

      window.location.reload();
    } catch (e) {
      console.error("[DevTools] Restore failed:", e);
    }
  }

  // Sparkline refresh ticker
  let sparklineTick = $state(0);
  $effect(() => {
    if (!devtoolsStore.open || devtoolsStore.activeTab !== "wasm") return;
    const interval = setInterval(() => { sparklineTick++; }, 1000);
    return () => clearInterval(interval);
  });

  // Responsive: mobile = full-width bottom panel, desktop = floating right panel
  let isMobile = $state(false);

  $effect(() => {
    const mq = window.matchMedia("(max-width: 639px)");
    isMobile = mq.matches;
    const handler = (e: MediaQueryListEvent) => { isMobile = e.matches; };
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  });

  // Panel sizing — draggable resize (corner on desktop, top edge on mobile)
  // Size stored in devtoolsStore so it persists across open/close
  let isResizing = $state(false);
  let resizeStartY = 0;
  let resizeStartX = 0;
  let resizeStartW = 0;
  let resizeStartH = 0;

  function onResizeStart(e: PointerEvent) {
    e.preventDefault();
    isResizing = true;
    resizeStartX = e.clientX;
    resizeStartY = e.clientY;
    resizeStartW = devtoolsStore.panelWidth;
    resizeStartH = devtoolsStore.panelHeight;
    document.addEventListener("pointermove", onResizeMove);
    document.addEventListener("pointerup", onResizeEnd);
  }

  function onResizeMove(e: PointerEvent) {
    const dy = resizeStartY - e.clientY; // dragging up = taller
    const maxH = Math.min(800, window.innerHeight - 120);
    devtoolsStore.panelHeight = Math.max(200, Math.min(maxH, resizeStartH + dy));

    if (!isMobile) {
      const dx = resizeStartX - e.clientX; // dragging left = wider
      const maxW = Math.min(900, window.innerWidth - 24);
      devtoolsStore.panelWidth = Math.max(300, Math.min(maxW, resizeStartW + dx));
    }
  }

  function onResizeEnd() {
    isResizing = false;
    document.removeEventListener("pointermove", onResizeMove);
    document.removeEventListener("pointerup", onResizeEnd);
  }

  // Danger zone
  let confirmAction = $state<string | null>(null);

  async function clearOpfs() {
    try {
      const root = await navigator.storage.getDirectory();
      await root.removeEntry("wimg.db");
    } catch { /* may not exist */ }
    window.location.reload();
  }

  function clearLocalStorage() {
    localStorage.clear();
    window.location.reload();
  }

  async function fullReset() {
    try {
      close();
      const root = await navigator.storage.getDirectory();
      await root.removeEntry("wimg.db");
    } catch { /* ignore */ }
    clearSyncKey();
    localStorage.clear();
    window.location.reload();
  }
</script>

{#if isResizing}
  <!-- Overlay to maintain resize cursor and prevent text selection during drag -->
  <div class="fixed inset-0 z-[100] {isMobile ? 'cursor-ns-resize' : 'cursor-nw-resize'} select-none" aria-hidden="true"></div>
{/if}

{#if devtoolsStore.open}
  <div
    class="fixed z-60 flex flex-col {isMobile ? 'left-0 right-0' : 'right-3'}"
    style="bottom: calc(6rem + env(safe-area-inset-bottom, 0px)); {isMobile ? '' : `width: ${devtoolsStore.panelWidth}px;`} height: {devtoolsStore.panelHeight}px;"
  >
    <div
      class="relative flex flex-col h-full overflow-hidden border border-(--color-border) bg-(--color-card)/95 backdrop-blur-xl {isMobile ? 'rounded-t-2xl border-b-0' : 'rounded-2xl'}"
      style="box-shadow: var(--shadow-soft);"
    >
      <!-- Resize grip: top edge drag handle on mobile, corner grip on desktop -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      {#if isMobile}
        <div
          onpointerdown={onResizeStart}
          class="flex items-center justify-center py-1.5 cursor-ns-resize touch-none shrink-0"
          aria-hidden="true"
        >
          <div class="w-10 h-1 rounded-full bg-(--color-text-secondary)/30"></div>
        </div>
      {:else}
        <div
          onpointerdown={onResizeStart}
          class="absolute top-0.5 left-0.5 w-4 h-4 cursor-nw-resize z-10 touch-none group/grip"
          aria-hidden="true"
        >
          <svg class="w-full h-full text-(--color-text-secondary)/30 group-hover/grip:text-(--color-accent)/60 transition-colors" viewBox="0 0 16 16" fill="none">
            <line x1="14" y1="2" x2="2" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
            <line x1="14" y1="6" x2="6" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
            <line x1="14" y1="10" x2="10" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
          </svg>
        </div>
      {/if}

      <!-- Header -->
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-(--color-border)">
        <span class="text-xs font-bold text-(--color-text) tracking-wide">DevTools</span>
        <div class="flex items-center gap-1.5">
          <button
            onclick={() => devtoolsStore.clear()}
            class="text-[10px] font-medium text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1.5 py-0.5 rounded hover:bg-(--color-bg) transition-colors"
            aria-label="Clear logs"
          >
            clear
          </button>
          <button
            onclick={() => { devtoolsStore.open = false; }}
            class="w-6 h-6 flex items-center justify-center text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer rounded-lg hover:bg-(--color-bg) transition-colors"
            aria-label="Close DevTools"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex border-b border-(--color-border)">
        {#each TABS as tab}
          <button
            onclick={() => { devtoolsStore.activeTab = tab; }}
            class="flex-1 text-[11px] font-semibold py-2 cursor-pointer transition-colors {devtoolsStore.activeTab === tab ? 'text-(--color-text) bg-(--color-accent)/20 border-b-2 border-(--color-accent-hover)' : 'text-(--color-text-secondary) hover:text-(--color-text) hover:bg-(--color-bg)'}"
          >
            {TAB_LABELS[tab]}
          </button>
        {/each}
      </div>

      <!-- Content -->
      <div class="overflow-y-auto flex-1 min-h-0">
        {#if devtoolsStore.activeTab === "wasm"}
          <!-- Aggregate stats -->
          {@const stats = devtoolsStore.aggregateStats}
          {@const totalCalls = devtoolsStore.wasmCalls.length}
          {@const totalMs = stats.reduce((s, st) => s + st.totalMs, 0)}
          {@const slowest = stats.length > 0 ? stats.reduce((a, b) => {
            const aMax = devtoolsStore.wasmCalls.filter(c => c.name === a.name).reduce((m, c) => Math.max(m, c.duration), 0);
            const bMax = devtoolsStore.wasmCalls.filter(c => c.name === b.name).reduce((m, c) => Math.max(m, c.duration), 0);
            return aMax > bMax ? a : b;
          }) : null}

          <div class="px-3 py-2 bg-(--color-bg)/50 border-b border-(--color-border)">
            <div class="flex gap-3 text-[10px]">
              <div>
                <span class="text-(--color-text-secondary)">Calls</span>
                <span class="font-bold text-(--color-text) ml-1">{totalCalls}</span>
              </div>
              <div>
                <span class="text-(--color-text-secondary)">Avg</span>
                <span class="font-bold text-(--color-text) ml-1">{totalCalls ? (totalMs / totalCalls).toFixed(1) : '0'}ms</span>
              </div>
              {#if slowest}
                <div>
                  <span class="text-(--color-text-secondary)">Slowest</span>
                  <span class="font-bold text-(--color-text) ml-1">{slowest.name}</span>
                </div>
              {/if}
            </div>
            <!-- Sparkline: call frequency over last 60s -->
            {#if totalCalls > 0}
              {@const _ = sparklineTick}
              {@const data = devtoolsStore.sparklineData}
              {@const max = Math.max(...data, 1)}
              <div class="flex items-center gap-1.5 mt-1.5">
                <span class="text-[9px] text-(--color-text-secondary)/50 shrink-0">60s</span>
                <div class="relative flex-1 group/spark">
                  <svg class="w-full" viewBox="0 0 240 20" preserveAspectRatio="none" style="height: 20px;">
                {#each data as count, i}
                  {#if count > 0}
                    <rect
                      x={i * 4}
                      y={20 - (count / max) * 20}
                      width="3"
                      height={(count / max) * 20}
                      rx="0.5"
                      class="fill-amber-400/70"
                    />
                  {/if}
                {/each}
              </svg>
                  <!-- Tooltip on hover -->
                  <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-1.5 px-2.5 py-1.5 rounded-lg bg-(--color-text) text-white text-[10px] leading-tight whitespace-nowrap opacity-0 pointer-events-none group-hover/spark:opacity-100 transition-opacity z-20">
                    WASM calls/sec over last 60s
                    <div class="absolute top-full left-1/2 -translate-x-1/2 w-0 h-0 border-x-4 border-x-transparent border-t-4 border-t-(--color-text)"></div>
                  </div>
                </div>
                <span class="text-[9px] text-(--color-text-secondary)/50 shrink-0">now</span>
              </div>
            {/if}
          </div>

          <!-- Call log -->
          {#if devtoolsStore.wasmCalls.length === 0}
            <div class="px-4 py-6 text-center text-xs text-(--color-text-secondary)">
              No WASM calls recorded yet
            </div>
          {:else}
            <div class="divide-y divide-(--color-border)/50">
              {#each devtoolsStore.wasmCalls as call}
                <div class="px-3 py-1.5 flex items-center justify-between gap-2">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-[11px] font-mono font-medium text-(--color-text) truncate">{call.name}</span>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full {durationBadgeClass(call.duration)}">{call.duration.toFixed(1)}ms</span>
                    <span class="text-[9px] text-(--color-text-secondary) w-12 text-right">{relativeTime(call.timestamp)}</span>
                  </div>
                </div>
              {/each}
            </div>
          {/if}

          <!-- Action Log -->
          {#if devtoolsStore.actions.length > 0}
            <div class="px-3 py-1.5 bg-(--color-bg)/50 border-t border-(--color-border)">
              <span class="text-[9px] font-bold text-(--color-text-secondary) tracking-wide uppercase">Actions</span>
            </div>
            <div class="divide-y divide-(--color-border)/50">
              {#each devtoolsStore.actions as entry}
                <div class="px-3 py-1.5 flex items-center justify-between gap-2">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-blue-100 text-blue-700">{entry.action}</span>
                    <span class="text-[10px] text-(--color-text-secondary) truncate">{entry.details}</span>
                  </div>
                  <span class="text-[9px] text-(--color-text-secondary) shrink-0 w-12 text-right">{relativeTime(entry.timestamp)}</span>
                </div>
              {/each}
            </div>
          {/if}

        {:else if devtoolsStore.activeTab === "memory"}
          <div class="p-4 space-y-4">
            <!-- WASM Memory -->
            <div>
              <div class="flex items-center justify-between mb-1.5">
                <span class="text-[11px] font-semibold text-(--color-text)">WASM Linear Memory</span>
                <span class="text-[11px] font-bold text-(--color-text)">{formatBytes(memoryBytes)} MB</span>
              </div>
              {#if memoryBytes > initialMemoryBytes && initialMemoryBytes > 0}
                <div class="text-[9px] text-amber-600 mt-0.5">
                  Grew from {formatBytes(initialMemoryBytes)} MB (init)
                </div>
              {/if}
            </div>

            <!-- DB File Size -->
            <div>
              <div class="flex items-center justify-between mb-1">
                <span class="text-[11px] font-semibold text-(--color-text)">SQLite DB</span>
                <span class="text-[11px] font-bold text-(--color-text)">{formatBytes(dbSizeBytes, "KB")} KB</span>
              </div>
            </div>
          </div>

        {:else if devtoolsStore.activeTab === "sync"}
          <div class="p-3 space-y-3">
            <!-- WS Status -->
            <div class="flex items-center gap-2">
              {#if !getSyncKey()}
                <span class="w-2 h-2 rounded-full bg-gray-400"></span>
                <span class="text-[11px] font-semibold text-gray-500">No sync key</span>
              {:else if syncWS.connected}
                <span class="w-2 h-2 rounded-full bg-green-500"></span>
                <span class="text-[11px] font-semibold text-green-700">Connected</span>
              {:else}
                <span class="w-2 h-2 rounded-full bg-red-400"></span>
                <span class="text-[11px] font-semibold text-red-600">Disconnected</span>
              {/if}
            </div>

            <!-- Sync event log -->
            {#if devtoolsStore.syncEvents.length === 0}
              <div class="py-4 text-center text-xs text-(--color-text-secondary)">
                No sync events recorded yet
              </div>
            {:else}
              <div class="divide-y divide-(--color-border)/50 rounded-xl border border-(--color-border) overflow-hidden">
                {#each devtoolsStore.syncEvents as event}
                  <div class="px-3 py-1.5 flex items-center gap-2 bg-(--color-card)">
                    <span class="text-sm w-5 text-center">{syncTypeIcon(event.type)}</span>
                    <span class="text-[10px] font-semibold text-(--color-text) flex-1 truncate">{event.type}</span>
                    <span class="text-[9px] text-(--color-text-secondary) truncate max-w-[10rem]">{event.details}</span>
                    <span class="text-[9px] text-(--color-text-secondary) shrink-0">{relativeTime(event.timestamp)}</span>
                  </div>
                {/each}
              </div>
            {/if}

            <!-- Sync Diff Viewer -->
            {#if devtoolsStore.syncDiffs.length > 0}
              <div class="mt-3 pt-2 border-t border-(--color-border)">
                <span class="text-[9px] font-bold text-(--color-text-secondary) tracking-wide uppercase">Row Diffs</span>
                <div class="mt-1.5 space-y-1">
                  {#each devtoolsStore.syncDiffs as diff, idx}
                    <div class="rounded-lg border border-(--color-border) overflow-hidden">
                      <button
                        onclick={() => { expandedDiff = expandedDiff === idx ? null : idx; }}
                        class="w-full flex items-center justify-between px-2.5 py-1.5 hover:bg-(--color-bg)/30 cursor-pointer transition-colors"
                      >
                        <div class="flex items-center gap-2">
                          <span class="text-sm">{diffDirectionIcon(diff.direction)}</span>
                          <span class="text-[10px] font-semibold text-(--color-text)">{diff.direction}</span>
                          <span class="text-[9px] text-(--color-text-secondary)">{diff.rows.length} row{diff.rows.length !== 1 ? "s" : ""}</span>
                        </div>
                        <span class="text-[9px] text-(--color-text-secondary)">{relativeTime(diff.timestamp)}</span>
                      </button>
                      {#if expandedDiff === idx}
                        <div class="px-2.5 pb-2 space-y-1">
                          {#each diff.rows.slice(0, 20) as row}
                            <div class="text-[9px] font-mono bg-(--color-bg) rounded px-2 py-1">
                              <span class="font-bold text-(--color-text)">{row.table}</span>
                              <span class="text-(--color-text-secondary)">.</span>
                              <span class="text-(--color-text)">{row.id.slice(0, 12)}...</span>
                              {#if row.fields.length > 0}
                                <span class="text-(--color-text-secondary) ml-1">[{row.fields.join(", ")}]</span>
                              {/if}
                            </div>
                          {/each}
                          {#if diff.rows.length > 20}
                            <div class="text-[9px] text-(--color-text-secondary) text-center">+{diff.rows.length - 20} more</div>
                          {/if}
                        </div>
                      {/if}
                    </div>
                  {/each}
                </div>
              </div>
            {/if}
          </div>

        {:else if devtoolsStore.activeTab === "data"}
          <div class="p-3">
            <div class="flex items-center justify-between mb-3">
              <span class="text-[11px] font-semibold text-(--color-text)">Entity Counts</span>
              <button
                onclick={refreshData}
                class="text-[10px] font-medium text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1.5 py-0.5 rounded hover:bg-(--color-bg) transition-colors"
              >
                refresh
              </button>
            </div>
            {#if dataCounts.length === 0}
              <div class="py-4 text-center text-xs text-(--color-text-secondary)">
                No data loaded
              </div>
            {:else}
              <div class="grid grid-cols-2 gap-2">
                {#each dataCounts as item}
                  <div class="rounded-xl bg-(--color-bg) px-3 py-2.5 text-center">
                    <div class="text-lg font-bold text-(--color-text)">{item.count}</div>
                    <div class="text-[10px] text-(--color-text-secondary) font-medium">{item.label}</div>
                  </div>
                {/each}
              </div>
            {/if}

            <!-- Feature Flags -->
            <div class="mt-4 pt-3 border-t border-(--color-border)">
              <span class="text-[11px] font-semibold text-(--color-text)">Feature Flags</span>
              <div class="mt-2 space-y-1">
                {#each featureToggles as feat}
                  <div class="flex items-center justify-between px-2.5 py-1.5 rounded-lg hover:bg-(--color-bg)/50">
                    <div class="flex items-center gap-2">
                      <span class="text-[11px] font-mono font-medium text-(--color-text)">{feat.key}</span>
                      <span class="text-[9px] text-(--color-text-secondary)">{feat.label}</span>
                    </div>
                    <button
                      onclick={() => featureStore.toggle(feat.key)}
                      class="text-[10px] font-bold px-2 py-0.5 rounded-full cursor-pointer transition-colors {featureStore.isEnabled(feat.key) ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-600'}"
                    >
                      {featureStore.isEnabled(feat.key) ? "ON" : "OFF"}
                    </button>
                  </div>
                {/each}
              </div>
            </div>

            <!-- OPFS File Browser -->
            <div class="mt-4 pt-3 border-t border-(--color-border)">
              <div class="flex items-center justify-between mb-2">
                <span class="text-[11px] font-semibold text-(--color-text)">OPFS Files</span>
                <button
                  onclick={refreshOpfs}
                  class="text-[10px] font-medium text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1.5 py-0.5 rounded hover:bg-(--color-bg) transition-colors"
                >
                  refresh
                </button>
              </div>
              {#if opfsLoading}
                <div class="py-3 text-center text-xs text-(--color-text-secondary)">Loading...</div>
              {:else if opfsFiles.length === 0}
                <div class="py-3 text-center text-xs text-(--color-text-secondary)">No OPFS files</div>
              {:else}
                <div class="rounded-xl border border-(--color-border) overflow-hidden divide-y divide-(--color-border)/50">
                  {#each opfsFiles as file}
                    <div class="px-2.5 py-1.5 flex items-center justify-between gap-1.5 bg-(--color-card)">
                      <div class="flex items-center gap-2 min-w-0">
                        <span class="text-[11px] font-mono font-medium text-(--color-text) truncate">{file.name}</span>
                        {#if file.size >= 0}
                          <span class="text-[9px] text-(--color-text-secondary) shrink-0">
                            {file.size < 1024 ? `${file.size}B` : file.size < 1048576 ? `${(file.size / 1024).toFixed(1)}KB` : `${(file.size / 1048576).toFixed(1)}MB`}
                          </span>
                        {:else}
                          <span class="text-[9px] text-(--color-text-secondary) shrink-0">dir</span>
                        {/if}
                      </div>
                      {#if file.size >= 0}
                        <div class="flex items-center gap-1 shrink-0">
                          <button
                            onclick={() => downloadOpfsFile(file.name)}
                            class="text-[9px] text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1"
                            aria-label="Download {file.name}"
                          >dl</button>
                          <button
                            onclick={() => deleteOpfsFile(file.name)}
                            class="text-[9px] text-red-400 hover:text-red-600 cursor-pointer px-1"
                            aria-label="Delete {file.name}"
                          >del</button>
                        </div>
                      {/if}
                    </div>
                  {/each}
                </div>
              {/if}
            </div>

            <!-- localStorage Inspector -->
            <div class="mt-4 pt-3 border-t border-(--color-border)">
              <div class="flex items-center justify-between mb-2">
                <span class="text-[11px] font-semibold text-(--color-text)">localStorage</span>
                <div class="flex items-center gap-1">
                  <span class="text-[9px] text-(--color-text-secondary)">{lsEntries.length} keys</span>
                  <button
                    onclick={refreshLs}
                    class="text-[10px] font-medium text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1.5 py-0.5 rounded hover:bg-(--color-bg) transition-colors"
                  >
                    refresh
                  </button>
                </div>
              </div>
              {#if lsEntries.length > 0}
                <div class="rounded-xl border border-(--color-border) overflow-hidden divide-y divide-(--color-border)/50">
                  {#each lsEntries as entry}
                    <div class="px-2.5 py-1.5 bg-(--color-card)">
                      {#if lsEditKey === entry.key}
                        <div class="space-y-1.5">
                          <div class="text-[10px] font-bold font-mono text-(--color-text)">{entry.key}</div>
                          <textarea
                            bind:value={lsEditValue}
                            class="w-full text-[10px] font-mono bg-(--color-bg) text-(--color-text) border border-(--color-border) rounded px-2 py-1 resize-none focus:outline-none focus:ring-1 focus:ring-(--color-accent)"
                            rows="3"
                          ></textarea>
                          <div class="flex gap-1.5">
                            <button
                              onclick={saveLsEdit}
                              class="text-[9px] font-bold text-white bg-(--color-accent) hover:bg-(--color-accent-hover) px-2 py-0.5 rounded cursor-pointer transition-colors"
                            >Save</button>
                            <button
                              onclick={() => { lsEditKey = null; }}
                              class="text-[9px] font-medium text-(--color-text-secondary) hover:text-(--color-text) px-2 py-0.5 rounded cursor-pointer transition-colors"
                            >Cancel</button>
                          </div>
                        </div>
                      {:else}
                        <div class="flex items-start justify-between gap-1.5">
                          <div class="min-w-0 flex-1">
                            <div class="text-[10px] font-bold font-mono text-(--color-text) truncate">{entry.key}</div>
                            <div class="text-[9px] font-mono text-(--color-text-secondary) truncate mt-0.5">{entry.value.length > 80 ? entry.value.slice(0, 80) + "..." : entry.value}</div>
                          </div>
                          <div class="flex items-center gap-1 shrink-0 mt-0.5">
                            <span class="text-[8px] text-(--color-text-secondary)">{entry.size}B</span>
                            <button
                              onclick={() => { lsEditKey = entry.key; lsEditValue = entry.value; }}
                              class="text-[9px] text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer px-1"
                              aria-label="Edit {entry.key}"
                            >edit</button>
                            <button
                              onclick={() => deleteLsKey(entry.key)}
                              class="text-[9px] text-red-400 hover:text-red-600 cursor-pointer px-1"
                              aria-label="Delete {entry.key}"
                            >del</button>
                          </div>
                        </div>
                      {/if}
                    </div>
                  {/each}
                </div>
              {:else}
                <div class="py-3 text-center text-xs text-(--color-text-secondary)">No localStorage entries</div>
              {/if}
            </div>

            <!-- State Snapshots -->
            <div class="mt-4 pt-3 border-t border-(--color-border)">
              <span class="text-[11px] font-semibold text-(--color-text)">State Snapshots</span>
              <div class="mt-2 flex gap-2">
                <button
                  onclick={saveStateSnapshot}
                  class="flex-1 text-[10px] font-bold text-white bg-(--color-accent) hover:bg-(--color-accent-hover) px-3 py-1.5 rounded-lg cursor-pointer transition-colors text-center"
                >
                  Save snapshot
                </button>
                <label
                  class="flex-1 text-[10px] font-bold text-(--color-accent) border border-(--color-accent) hover:bg-(--color-accent)/10 px-3 py-1.5 rounded-lg cursor-pointer transition-colors text-center"
                >
                  Restore
                  <input
                    type="file"
                    accept=".json"
                    class="hidden"
                    onchange={(e) => {
                      const file = (e.currentTarget as HTMLInputElement).files?.[0];
                      if (file) restoreStateSnapshot(file);
                    }}
                  />
                </label>
              </div>
              <p class="text-[9px] text-(--color-text-secondary) mt-1.5">Downloads OPFS + localStorage as JSON. Restore replaces everything and reloads.</p>
            </div>

            <!-- Danger Zone -->
            <div class="mt-4 pt-3 border-t border-red-200">
              <span class="text-[10px] font-bold text-red-500 tracking-wide uppercase">Danger Zone</span>
              <div class="mt-2 space-y-1.5">
                {#if confirmAction}
                  <div class="rounded-xl bg-red-50 p-3">
                    <p class="text-[11px] text-red-700 font-medium mb-2">
                      {confirmAction === "opfs" ? "Delete OPFS database? (wimg.db)" :
                       confirmAction === "ls" ? "Clear all localStorage?" :
                       "Full reset? (OPFS + localStorage + sync key)"}
                    </p>
                    <div class="flex gap-2">
                      <button
                        onclick={() => {
                          if (confirmAction === "opfs") clearOpfs();
                          else if (confirmAction === "ls") clearLocalStorage();
                          else fullReset();
                        }}
                        class="text-[10px] font-bold text-white bg-red-500 hover:bg-red-600 px-3 py-1 rounded-lg cursor-pointer transition-colors"
                      >
                        Confirm
                      </button>
                      <button
                        onclick={() => { confirmAction = null; }}
                        class="text-[10px] font-medium text-(--color-text-secondary) hover:text-(--color-text) px-3 py-1 rounded-lg cursor-pointer transition-colors"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                {:else}
                  <button
                    onclick={() => { confirmAction = "opfs"; }}
                    class="w-full text-left text-[11px] font-medium text-red-600 hover:bg-red-50 px-2.5 py-1.5 rounded-lg cursor-pointer transition-colors"
                  >
                    Clear OPFS <span class="text-(--color-text-secondary)">(wimg.db)</span>
                  </button>
                  <button
                    onclick={() => { confirmAction = "ls"; }}
                    class="w-full text-left text-[11px] font-medium text-red-600 hover:bg-red-50 px-2.5 py-1.5 rounded-lg cursor-pointer transition-colors"
                  >
                    Clear localStorage <span class="text-(--color-text-secondary)">(settings, sync key, flags)</span>
                  </button>
                  <button
                    onclick={() => { confirmAction = "full"; }}
                    class="w-full text-left text-[11px] font-medium text-red-600 hover:bg-red-50 px-2.5 py-1.5 rounded-lg cursor-pointer transition-colors"
                  >
                    Full reset <span class="text-(--color-text-secondary)">(everything)</span>
                  </button>
                {/if}
              </div>
            </div>
          </div>
        {:else if devtoolsStore.activeTab === "sql"}
          <div class="p-3 space-y-2">
            <!-- Schema Inspector -->
            <div class="rounded-xl border border-(--color-border) overflow-hidden">
              <button
                onclick={() => { schemaOpen = !schemaOpen; if (schemaOpen && schemaData.length === 0) loadSchema(); }}
                class="w-full flex items-center justify-between px-3 py-2 bg-(--color-bg)/50 hover:bg-(--color-bg) cursor-pointer transition-colors"
              >
                <span class="text-[11px] font-semibold text-(--color-text)">Schema</span>
                <div class="flex items-center gap-2">
                  {#if schemaData.length > 0}
                    <span class="text-[9px] text-(--color-text-secondary)">{schemaData.length} tables</span>
                  {/if}
                  <svg class="w-3 h-3 text-(--color-text-secondary) transition-transform {schemaOpen ? 'rotate-180' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </button>
              {#if schemaOpen}
                <div class="divide-y divide-(--color-border)/50">
                  {#each schemaData as table}
                    <div>
                      <button
                        onclick={() => { expandedTable = expandedTable === table.name ? null : table.name; }}
                        class="w-full flex items-center justify-between px-3 py-1.5 hover:bg-(--color-bg)/30 cursor-pointer transition-colors"
                      >
                        <div class="flex items-center gap-2">
                          <svg class="w-2.5 h-2.5 text-(--color-text-secondary) transition-transform {expandedTable === table.name ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                          <span class="text-[11px] font-mono font-medium text-(--color-text)">{table.name}</span>
                        </div>
                        <span class="text-[9px] text-(--color-text-secondary)">{table.rowCount} rows</span>
                      </button>
                      {#if expandedTable === table.name}
                        <div class="px-3 pb-2">
                          <pre class="text-[9px] font-mono text-(--color-text-secondary) whitespace-pre-wrap bg-(--color-bg) rounded-lg px-2.5 py-2 overflow-x-auto">{table.sql}</pre>
                          <button
                            onclick={() => { sqlInput = `SELECT * FROM "${table.name}" LIMIT 20`; schemaOpen = false; }}
                            class="mt-1.5 text-[9px] font-medium text-(--color-accent) hover:text-(--color-accent-hover) cursor-pointer"
                          >
                            Query this table
                          </button>
                        </div>
                      {/if}
                    </div>
                  {/each}
                </div>
                {#if schemaData.length > 0}
                  <div class="px-3 py-1.5 border-t border-(--color-border)/50">
                    <button
                      onclick={loadSchema}
                      class="text-[9px] font-medium text-(--color-text-secondary) hover:text-(--color-text) cursor-pointer"
                    >
                      Refresh schema
                    </button>
                  </div>
                {/if}
              {/if}
            </div>

            <textarea
              bind:value={sqlInput}
              onkeydown={(e) => {
                if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
                  e.preventDefault();
                  addToHistory(sqlInput);
                  runSql();
                }
              }}
              class="w-full text-[11px] font-mono bg-(--color-bg) text-(--color-text) border border-(--color-border) rounded-lg px-3 py-2 resize-none focus:outline-none focus:ring-1 focus:ring-(--color-accent)"
              rows="3"
              placeholder="SELECT * FROM ..."
              spellcheck="false"
            ></textarea>

            <div class="flex items-center gap-2">
              <button
                onclick={() => { addToHistory(sqlInput); runSql(); }}
                disabled={sqlRunning}
                class="text-[10px] font-bold text-white bg-(--color-accent) hover:bg-(--color-accent-hover) px-3 py-1 rounded-lg cursor-pointer transition-colors disabled:opacity-50"
              >
                {sqlRunning ? "Running..." : "Run (Cmd+Enter)"}
              </button>
              {#if sqlHistory.length > 0}
                <select
                  onchange={(e) => { const t = e.currentTarget; sqlInput = t.value; t.selectedIndex = 0; }}
                  class="text-[10px] bg-(--color-bg) text-(--color-text-secondary) border border-(--color-border) rounded-lg px-1.5 py-1 cursor-pointer"
                >
                  <option value="" disabled selected>History</option>
                  {#each sqlHistory as query}
                    <option value={query}>{query.length > 50 ? query.slice(0, 50) + "..." : query}</option>
                  {/each}
                </select>
              {/if}
            </div>

            {#if sqlError}
              <div class="text-[11px] text-red-600 bg-red-50 rounded-lg px-3 py-2 font-mono break-all">
                {sqlError}
              </div>
            {/if}

            {#if sqlResult}
              <div class="text-[9px] text-(--color-text-secondary) flex gap-3">
                <span>{sqlResult.count} row{sqlResult.count !== 1 ? "s" : ""}</span>
                <span>{sqlResult.columns.length} col{sqlResult.columns.length !== 1 ? "s" : ""}</span>
                {#if sqlResult.truncated}
                  <span class="text-amber-600 font-semibold">truncated (max 500)</span>
                {/if}
              </div>
              {#if sqlResult.columns.length > 0}
                <div class="overflow-x-auto rounded-lg border border-(--color-border)">
                  <table class="w-full text-[10px]">
                    <thead>
                      <tr class="bg-(--color-bg)">
                        {#each sqlResult.columns as col}
                          <th class="px-2 py-1.5 text-left font-bold text-(--color-text) whitespace-nowrap border-b border-(--color-border)">{col}</th>
                        {/each}
                      </tr>
                    </thead>
                    <tbody>
                      {#each sqlResult.rows as row}
                        <tr class="border-b border-(--color-border)/30 hover:bg-(--color-bg)/50">
                          {#each row as cell}
                            <td class="px-2 py-1 text-(--color-text) font-mono whitespace-nowrap max-w-[12rem] overflow-hidden text-ellipsis">
                              {#if cell === null}
                                <span class="text-(--color-text-secondary) italic">NULL</span>
                              {:else}
                                {cell}
                              {/if}
                            </td>
                          {/each}
                        </tr>
                      {/each}
                    </tbody>
                  </table>
                </div>
              {/if}
            {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}
