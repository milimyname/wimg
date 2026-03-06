/**
 * Sync service — orchestrates push/pull with the Cloudflare Worker API.
 *
 * Dev:  http://localhost:8787 (wrangler dev)
 * Prod: https://wimg-sync.mili-my.name
 */

import { getChanges, applyChanges, opfsSave, type SyncRow } from "./wasm";
import { accountStore } from "./account.svelte";

const SYNC_API =
  typeof window !== "undefined" && window.location.hostname === "localhost"
    ? "http://localhost:8787"
    : "https://wimg-sync.mili-my.name";

const LS_KEY_SYNC = "wimg_sync_key";
const LS_KEY_LAST_SYNC = "wimg_sync_last_ts";

export function getSyncKey(): string | null {
  return localStorage.getItem(LS_KEY_SYNC);
}

export function setSyncKey(key: string): void {
  localStorage.setItem(LS_KEY_SYNC, key);
}

export function clearSyncKey(): void {
  localStorage.removeItem(LS_KEY_SYNC);
  localStorage.removeItem(LS_KEY_LAST_SYNC);
}

export function getLastSyncTimestamp(): number {
  return Number(localStorage.getItem(LS_KEY_LAST_SYNC) || "0");
}

function setLastSyncTimestamp(ts: number): void {
  localStorage.setItem(LS_KEY_LAST_SYNC, String(ts));
}

export function isSyncEnabled(): boolean {
  return !!getSyncKey();
}

export async function syncPush(syncKey: string): Promise<number> {
  const lastSync = getLastSyncTimestamp();
  const changes: SyncRow[] = getChanges(lastSync);
  if (changes.length === 0) return 0;

  const res = await fetch(`${SYNC_API}/sync/${syncKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ rows: changes }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Sync push failed: ${res.status} ${body}`);
  }

  const result = (await res.json()) as { merged: number };
  return result.merged;
}

export async function syncPull(syncKey: string): Promise<number> {
  const lastSync = getLastSyncTimestamp();

  const res = await fetch(`${SYNC_API}/sync/${syncKey}?since=${lastSync}`);
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
  return applied;
}

export async function syncFull(syncKey: string): Promise<{ pushed: number; pulled: number }> {
  const pushed = await syncPush(syncKey);
  const pulled = await syncPull(syncKey);
  setLastSyncTimestamp(Date.now());
  return { pushed, pulled };
}
