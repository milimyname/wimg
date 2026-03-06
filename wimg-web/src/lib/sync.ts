/**
 * Sync service — orchestrates push/pull with the Cloudflare Worker API.
 *
 * Dev:  http://localhost:8787 (wrangler dev)
 * Prod: https://wimg-sync.mili-my.name
 */

import { getChanges, applyChanges, opfsSave, type SyncRow } from "./wasm";
import { accountStore } from "./account.svelte";
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
  return applied;
}

export async function syncFull(syncKey: string): Promise<{ pushed: number; pulled: number }> {
  const pushed = await syncPush(syncKey);
  const pulled = await syncPull(syncKey);
  setLastSyncTimestamp(Date.now());
  return { pushed, pulled };
}
