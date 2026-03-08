/**
 * Sync service — orchestrates push/pull with the Cloudflare Worker API.
 * Now also manages real-time WebSocket connection for live sync.
 *
 * Dev:  http://localhost:8787 (wrangler dev)
 * Prod: https://wimg-sync.mili-my.name
 */

import { getChanges, applyChanges, opfsSave, setOnMutate, type SyncRow } from "./wasm";
import { accountStore } from "./account.svelte";
import { syncWS } from "./sync-ws.svelte";
import { SYNC_API_URL, LS_SYNC_KEY, LS_SYNC_LAST_TS } from "./config";

export function getSyncKey(): string | null {
  return localStorage.getItem(LS_SYNC_KEY);
}

export function setSyncKey(key: string): void {
  localStorage.setItem(LS_SYNC_KEY, key);
}

export function clearSyncKey(): void {
  localStorage.removeItem(LS_SYNC_KEY);
  localStorage.removeItem(LS_SYNC_LAST_TS);
  disconnectSync();
}

export function getLastSyncTimestamp(): number {
  return Number(localStorage.getItem(LS_SYNC_LAST_TS) || "0");
}

function setLastSyncTimestamp(ts: number): void {
  localStorage.setItem(LS_SYNC_LAST_TS, String(ts));
}

export function isSyncEnabled(): boolean {
  return !!getSyncKey();
}

export async function syncPush(syncKey: string): Promise<number> {
  const lastSync = getLastSyncTimestamp();
  const changes: SyncRow[] = getChanges(lastSync);
  if (changes.length === 0) return 0;

  // Suppress echo: the DO will broadcast our push back to us via WS
  syncWS.suppressEcho();

  const res = await fetch(`${SYNC_API_URL}/sync/${syncKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ rows: changes }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Sync push failed: ${res.status} ${body}`);
  }

  const result = (await res.json()) as { merged: number };

  // DO's HTTP push handler already broadcasts to all WS clients
  // No need to also push via WS — that would cause duplicate broadcasts

  setLastSyncTimestamp(Date.now());
  return result.merged;
}

export async function syncPull(syncKey: string): Promise<number> {
  const lastSync = getLastSyncTimestamp();

  const res = await fetch(`${SYNC_API_URL}/sync/${syncKey}?since=${lastSync}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Sync pull failed: ${res.status} ${body}`);
  }

  const { rows } = (await res.json()) as { rows: SyncRow[] };
  if (!rows.length) return 0;

  const applied = applyChanges(rows);
  await opfsSave();
  setLastSyncTimestamp(Date.now());
  accountStore.reload();
  window.dispatchEvent(new CustomEvent("wimg:sync-received"));
  return applied;
}

export async function syncFull(syncKey: string): Promise<{ pushed: number; pulled: number }> {
  const pushed = await syncPush(syncKey);
  const pulled = await syncPull(syncKey);
  setLastSyncTimestamp(Date.now());
  return { pushed, pulled };
}

/** Connect WebSocket for real-time sync + register onMutate callback */
export function connectSync(): void {
  const key = getSyncKey();
  if (!key) return;

  syncWS.connect(key);

  // Auto-push on every local mutation
  setOnMutate(() => {
    const syncKey = getSyncKey();
    if (syncKey) {
      syncPush(syncKey).catch((err) => {
        console.error("[wimg-sync] Auto-push failed:", err);
      });
    }
  });
}

/** Disconnect WebSocket and remove onMutate callback */
export function disconnectSync(): void {
  syncWS.disconnect();
  setOnMutate(null);
}
