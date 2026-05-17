/**
 * McpSession — Durable Object that keeps WASM warm for MCP requests.
 *
 * Each sync key maps to one McpSession DO. The DO:
 * 1. Instantiates libwimg.wasm on first request
 * 2. Pulls data from SyncRoom DO (DO SQLite storage) on init + when stale
 * 3. Decrypts + applies to in-memory SQLite
 * 4. Builds a fresh McpServer per request — the SDK requires stateless
 *    construction (it errors "Server is already connected to transport"
 *    when reused). Each server's `onWrite` callback closes over `this` and
 *    increments a SHARED `this.writeCount` on the DO, so even closures from
 *    earlier requests that complete late (sandbox RPCs queued in the
 *    Dynamic Worker isolate) still register their writes against the same
 *    counter.
 * 5. After each request, if `writeCount` advanced past the last push
 *    watermark, coalesces all pending mutations into one pushToSync().
 */

import { createMcpHandler } from "agents/mcp";
import { WasmInstance, type SyncRow } from "./mcp-wasm";
import { buildMcpServer } from "./mcp-tools";
import { wrapWithCodeMode } from "./code-runner";

interface Env {
  SYNC_ROOM: DurableObjectNamespace;
  LOADER: WorkerLoader;
}

const REFRESH_INTERVAL_MS = 60_000;
// Grace period after handler returns to let any queued sandbox RPCs complete
// (Code Mode dispatches tool calls via Workers RPC, which may settle slightly
// after `await handler(...)` resolves).
const POST_HANDLER_GRACE_MS = 100;

export class McpSession implements DurableObject {
  private syncKey: string | null = null;
  private wasm: WasmInstance | null = null;
  private encryptionKey: Uint8Array | null = null;
  private lastRefreshTs = 0;
  private lastSyncTs = 0;
  /** Total writes seen since this DO instance started. Monotonic. */
  private writeCount = 0;
  /** Highest writeCount we've already pushed to SyncRoom. */
  private pushedUpTo = 0;

  constructor(
    private state: DurableObjectState,
    private env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method === "DELETE") {
      this.wasm?.close();
      this.wasm = null;
      this.encryptionKey = null;
      this.syncKey = null;
      this.lastRefreshTs = 0;
      this.lastSyncTs = 0;
      this.writeCount = 0;
      this.pushedUpTo = 0;
      return new Response("OK");
    }

    const key = request.headers.get("X-Sync-Key");
    if (!key) {
      return Response.json(
        { jsonrpc: "2.0", error: { code: -32600, message: "Missing sync key" } },
        { status: 401 },
      );
    }

    if (!this.wasm || this.syncKey !== key) {
      try {
        await this.initialize(key);
      } catch (err) {
        const msg = err instanceof Error ? err.message : "Initialization failed";
        return Response.json(
          { jsonrpc: "2.0", error: { code: -32603, message: msg } },
          { status: 500 },
        );
      }
    }

    // Best-effort refresh from SyncRoom when stale.
    const now = Date.now();
    if (now - this.lastRefreshTs > REFRESH_INTERVAL_MS) {
      try {
        await this.pullFromSync();
        this.lastRefreshTs = now;
      } catch {
        // continue with stale data
      }
    }

    // Per-request server: SDK requires fresh McpServer per call (transport
    // state can't be reused). onWrite closes over `this` so every closure —
    // current or leaked from prior requests — mutates the same counter.
    const baseServer = buildMcpServer({
      wasm: this.wasm!,
      onWrite: () => {
        this.writeCount++;
      },
    });
    const wrapped = await wrapWithCodeMode({
      server: baseServer,
      loader: this.env.LOADER,
    });
    const handler = createMcpHandler(wrapped, { route: "/mcp" });

    // DOs don't get a real ExecutionContext; expose one that proxies waitUntil
    // back to the DO state so createMcpHandler can schedule background work.
    const ctx = {
      waitUntil: (promise: Promise<unknown>) => this.state.waitUntil(promise),
      passThroughOnException: () => {
        /* no-op in DO context */
      },
    } as unknown as ExecutionContext;

    const response = await handler(request, this.env, ctx);

    // Brief grace period for queued sandbox RPCs to land their onWrite.
    await new Promise((r) => setTimeout(r, POST_HANDLER_GRACE_MS));

    if (this.writeCount > this.pushedUpTo) {
      const upTo = this.writeCount;
      this.pushedUpTo = upTo;
      this.state.waitUntil(this.pushToSync());
    }

    return response;
  }

  private async initialize(syncKey: string): Promise<void> {
    this.syncKey = syncKey;
    this.wasm = await WasmInstance.create();
    this.encryptionKey = this.wasm.deriveEncryptionKey(syncKey);
    await this.pullFromSync();
    this.lastRefreshTs = Date.now();
  }

  private async pullFromSync(): Promise<void> {
    if (!this.syncKey || !this.wasm || !this.encryptionKey) return;

    const stub = this.getSyncRoomStub();
    const url = `https://internal/sync/${this.syncKey}?since=${this.lastSyncTs}`;
    const res = await stub.fetch(
      new Request(url, {
        headers: { "X-Sync-Key": this.syncKey },
      }),
    );

    if (!res.ok) return;

    const { rows } = (await res.json()) as { rows: SyncRow[] };
    if (!rows.length) return;

    const decrypted = this.wasm.decryptRows(rows, this.encryptionKey);
    this.wasm.applyChanges(decrypted);

    const maxTs = rows.reduce((max, r) => Math.max(max, r.updated_at), this.lastSyncTs);
    this.lastSyncTs = maxTs;
  }

  private async pushToSync(): Promise<void> {
    if (!this.syncKey || !this.wasm || !this.encryptionKey) return;

    const rows = this.wasm.getChanges(this.lastSyncTs);
    if (!rows.length) return;

    const encrypted: SyncRow[] = rows.map((row) => ({
      ...row,
      data: this.wasm!.encryptField(
        JSON.stringify(row.data),
        this.encryptionKey!,
      ) as unknown as Record<string, unknown>,
    }));

    const stub = this.getSyncRoomStub();
    const res = await stub.fetch(
      new Request(`https://internal/sync/${this.syncKey}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Sync-Key": this.syncKey,
        },
        body: JSON.stringify({ rows: encrypted }),
      }),
    );

    if (!res.ok) {
      throw new Error(`Sync push failed: ${res.status}`);
    }

    const maxTs = rows.reduce((max, r) => Math.max(max, r.updated_at), this.lastSyncTs);
    this.lastSyncTs = maxTs;
  }

  private getSyncRoomStub() {
    const id = this.env.SYNC_ROOM.idFromName(this.syncKey!);
    return this.env.SYNC_ROOM.get(id);
  }
}
