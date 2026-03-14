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

class DevToolsStore {
  #wasmCalls = $state<WasmCall[]>([]);
  #syncEvents = $state<SyncEvent[]>([]);
  #actions = $state<ActionEntry[]>([]);
  #syncDiffs = $state<SyncDiff[]>([]);
  #open = $state(false);
  #activeTab = $state<"wasm" | "memory" | "sync" | "data" | "sql">("wasm");
  #panelWidth = $state(384);
  #panelHeight = $state(448);

  get wasmCalls() {
    return this.#wasmCalls;
  }

  get syncEvents() {
    return this.#syncEvents;
  }

  get actions() {
    return this.#actions;
  }

  get syncDiffs() {
    return this.#syncDiffs;
  }

  get open() {
    return this.#open;
  }

  set open(v: boolean) {
    if (v && typeof window !== "undefined") {
      // Clamp to viewport on open
      this.#panelWidth = Math.min(this.#panelWidth, window.innerWidth - 24);
      this.#panelHeight = Math.min(this.#panelHeight, window.innerHeight - 120);
    }
    this.#open = v;
  }

  get activeTab() {
    return this.#activeTab;
  }

  set activeTab(v: "wasm" | "memory" | "sync" | "data" | "sql") {
    this.#activeTab = v;
  }

  get panelWidth() {
    return this.#panelWidth;
  }

  set panelWidth(v: number) {
    this.#panelWidth = v;
  }

  get panelHeight() {
    return this.#panelHeight;
  }

  set panelHeight(v: number) {
    this.#panelHeight = v;
  }

  logWasmCall(name: string, duration: number): void {
    this.#wasmCalls = [{ name, duration, timestamp: Date.now() }, ...this.#wasmCalls].slice(
      0,
      MAX_WASM_CALLS,
    );
  }

  logSyncEvent(type: SyncEvent["type"], details: string): void {
    this.#syncEvents = [{ type, timestamp: Date.now(), details }, ...this.#syncEvents].slice(
      0,
      MAX_SYNC_EVENTS,
    );
  }

  logAction(action: string, details: string): void {
    this.#actions = [{ action, details, timestamp: Date.now() }, ...this.#actions].slice(
      0,
      MAX_ACTIONS,
    );
  }

  logSyncDiff(direction: SyncDiff["direction"], rows: SyncDiff["rows"]): void {
    this.#syncDiffs = [{ direction, timestamp: Date.now(), rows }, ...this.#syncDiffs].slice(
      0,
      MAX_SYNC_DIFFS,
    );
  }

  get aggregateStats(): WasmStats[] {
    const map = new Map<string, { count: number; totalMs: number }>();
    for (const call of this.#wasmCalls) {
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
      .toSorted((a, b) => b.totalMs - a.totalMs);
  }

  /** Sparkline data: call counts per second for the last 60 seconds */
  get sparklineData(): number[] {
    const now = Date.now();
    const buckets = Array.from({ length: 60 }, () => 0);
    for (const call of this.#wasmCalls) {
      const age = Math.floor((now - call.timestamp) / 1000);
      if (age >= 0 && age < 60) buckets[59 - age]++;
    }
    return buckets;
  }

  clear(): void {
    this.#wasmCalls = [];
    this.#syncEvents = [];
    this.#actions = [];
    this.#syncDiffs = [];
  }

  toggle(): void {
    this.#open = !this.#open;
  }

  enable(): void {
    devtoolsEnabled = true;
  }
}

export const devtoolsStore = new DevToolsStore();
