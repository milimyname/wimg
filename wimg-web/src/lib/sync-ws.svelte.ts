/**
 * Real-time sync via WebSocket to SyncRoom Durable Object.
 *
 * Connects to ws://.../ws/:key, receives broadcasts from other devices,
 * applies changes locally, and notifies all pages to refresh.
 *
 * On every (re)connect, triggers an HTTP pull to catch up on missed changes.
 */

import { applyChanges, opfsSave, type SyncRow } from "./wasm";
import { accountStore } from "./account.svelte";
import { SYNC_API_URL } from "./config";

interface WSMessage {
  type: string;
  rows?: SyncRow[];
  merged?: number;
}

/** Callback for catch-up pull on (re)connect */
type OnReconnectFn = () => void;

class SyncWS {
  private ws: WebSocket | null = null;
  private reconnectDelay = 1000;
  private syncKey: string | null = null;
  private closed = false;
  private suppressUntil = 0; // Ignore echo of own push
  private onReconnect: OnReconnectFn | null = null;
  connected = $state(false);

  connect(syncKey: string): void {
    this.syncKey = syncKey;
    this.closed = false;
    this.doConnect();
  }

  /** Register a callback that fires on every (re)connect — used for catch-up pull */
  setOnReconnect(cb: OnReconnectFn | null): void {
    this.onReconnect = cb;
  }

  private doConnect(): void {
    if (this.closed || !this.syncKey) return;

    const wsUrl = SYNC_API_URL.replace(/^http/, "ws") + `/ws/${this.syncKey}`;
    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      this.connected = true;
      this.reconnectDelay = 1000;
      console.log("[wimg-sync] WebSocket connected");

      // Catch up on any changes missed while disconnected
      this.onReconnect?.();
    };

    this.ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data) as WSMessage;

        if (msg.type === "changes" && msg.rows?.length) {
          // Ignore echo of own push (within 2s window)
          if (Date.now() < this.suppressUntil) {
            console.log(`[wimg-sync] Ignoring echo (${msg.rows.length} rows)`);
            return;
          }
          applyChanges(msg.rows);
          opfsSave();
          accountStore.reload();
          window.dispatchEvent(new CustomEvent("wimg:sync-received"));
          console.log(`[wimg-sync] Received ${msg.rows.length} changes`);
        }

        if (msg.type === "ping") {
          this.ws?.send(JSON.stringify({ type: "pong" }));
        }
      } catch {
        // Ignore malformed messages
      }
    };

    this.ws.onclose = () => {
      this.connected = false;
      if (!this.closed) {
        console.log(`[wimg-sync] Reconnecting in ${this.reconnectDelay}ms`);
        setTimeout(() => this.doConnect(), this.reconnectDelay);
        this.reconnectDelay = Math.min(this.reconnectDelay * 2, 30_000);
      }
    };

    this.ws.onerror = () => {
      // onclose will fire after this — handles reconnect
    };
  }

  /** Mark that we just pushed — suppress echo for 2 seconds */
  suppressEcho(): void {
    this.suppressUntil = Date.now() + 2000;
  }

  disconnect(): void {
    this.closed = true;
    this.onReconnect = null;
    this.ws?.close();
    this.ws = null;
    this.connected = false;
  }
}

export const syncWS = new SyncWS();
