/**
 * DevTools store — tracks WASM call performance, sync events, actions, and panel state.
 * Enabled in dev mode or via ?devtools URL param in production.
 */

/** Global flag — set to true when DevTools is active. Checked by instrumentation. */
export let devtoolsEnabled = false;

export interface WasmCall {
  name: string;
  duration: number; // ms
  timestamp: number; // Date.now()
}

export interface WasmStats {
  name: string;
  count: number;
  totalMs: number;
}

export interface SyncEvent {
  type: "push" | "pull" | "ws-connect" | "ws-disconnect" | "ws-message";
  timestamp: number;
  details: string;
}

export interface ActionEntry {
  action: string; // "setCategory", "importCsv", "addDebt", etc.
  details: string; // human-readable summary
  timestamp: number;
}

export interface SyncDiff {
  direction: "push" | "pull" | "ws";
  timestamp: number;
  rows: { table: string; id: string; fields: string[] }[];
}

const MAX_WASM_CALLS = 200;
const MAX_SYNC_EVENTS = 100;
const MAX_ACTIONS = 100;
const MAX_SYNC_DIFFS = 50;

let wasmCalls = $state<WasmCall[]>([]);
let syncEvents = $state<SyncEvent[]>([]);
let actions = $state<ActionEntry[]>([]);
let syncDiffs = $state<SyncDiff[]>([]);
let open = $state(false);
let activeTab = $state<"wasm" | "memory" | "sync" | "data" | "sql">("wasm");
let panelWidth = $state(384);
let panelHeight = $state(448);

export const devtoolsStore = {
  get wasmCalls() {
    return wasmCalls;
  },
  get syncEvents() {
    return syncEvents;
  },
  get actions() {
    return actions;
  },
  get syncDiffs() {
    return syncDiffs;
  },
  get open() {
    return open;
  },
  set open(v: boolean) {
    if (v && typeof window !== "undefined") {
      // Clamp to viewport on open
      panelWidth = Math.min(panelWidth, window.innerWidth - 24);
      panelHeight = Math.min(panelHeight, window.innerHeight - 120);
    }
    open = v;
  },
  get activeTab() {
    return activeTab;
  },
  set activeTab(v: "wasm" | "memory" | "sync" | "data" | "sql") {
    activeTab = v;
  },
  get panelWidth() {
    return panelWidth;
  },
  set panelWidth(v: number) {
    panelWidth = v;
  },
  get panelHeight() {
    return panelHeight;
  },
  set panelHeight(v: number) {
    panelHeight = v;
  },

  logWasmCall(name: string, duration: number): void {
    wasmCalls = [{ name, duration, timestamp: Date.now() }, ...wasmCalls].slice(0, MAX_WASM_CALLS);
  },

  logSyncEvent(type: SyncEvent["type"], details: string): void {
    syncEvents = [{ type, timestamp: Date.now(), details }, ...syncEvents].slice(
      0,
      MAX_SYNC_EVENTS,
    );
  },

  logAction(action: string, details: string): void {
    actions = [{ action, details, timestamp: Date.now() }, ...actions].slice(0, MAX_ACTIONS);
  },

  logSyncDiff(direction: SyncDiff["direction"], rows: SyncDiff["rows"]): void {
    syncDiffs = [{ direction, timestamp: Date.now(), rows }, ...syncDiffs].slice(0, MAX_SYNC_DIFFS);
  },

  get aggregateStats(): WasmStats[] {
    const map = new Map<string, { count: number; totalMs: number }>();
    for (const call of wasmCalls) {
      const existing = map.get(call.name);
      if (existing) {
        existing.count++;
        existing.totalMs += call.duration;
      } else {
        map.set(call.name, { count: 1, totalMs: call.duration });
      }
    }
    return [...map.entries()]
      .map(([name, stats]) => ({ name, ...stats }))
      .sort((a, b) => b.totalMs - a.totalMs);
  },

  /** Sparkline data: call counts per second for the last 60 seconds */
  get sparklineData(): number[] {
    const now = Date.now();
    const buckets = Array.from({ length: 60 }, () => 0);
    for (const call of wasmCalls) {
      const age = Math.floor((now - call.timestamp) / 1000);
      if (age >= 0 && age < 60) buckets[59 - age]++;
    }
    return buckets;
  },

  clear(): void {
    wasmCalls = [];
    syncEvents = [];
    actions = [];
    syncDiffs = [];
  },

  toggle(): void {
    open = !open;
  },

  enable(): void {
    devtoolsEnabled = true;
  },
};
