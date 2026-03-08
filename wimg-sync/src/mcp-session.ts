/**
 * McpSession — Durable Object that keeps WASM warm for MCP requests.
 *
 * Each sync key maps to one McpSession DO. The DO:
 * 1. Instantiates libwimg.wasm on first request
 * 2. Pulls data from R2 (via SyncRoom DO)
 * 3. Decrypts + applies to in-memory SQLite
 * 4. Handles MCP JSON-RPC requests (tools/list, tools/call)
 * 5. For write tools: syncs changes back to SyncRoom → R2 + WS broadcast
 */

import { WasmInstance, type SyncRow } from "./mcp-wasm";
import { getToolDefinitions, WRITE_TOOL_NAMES } from "./mcp-tools";

interface Env {
  BUCKET: R2Bucket;
  SYNC_ROOM: DurableObjectNamespace;
}

interface JsonRpcRequest {
  jsonrpc: "2.0";
  id?: number | string;
  method: string;
  params?: Record<string, unknown>;
}

interface JsonRpcResponse {
  jsonrpc: "2.0";
  id?: number | string | null;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

const REFRESH_INTERVAL_MS = 60_000; // Re-pull from R2 every 60s on read

export class McpSession implements DurableObject {
  private syncKey: string | null = null;
  private wasm: WasmInstance | null = null;
  private encryptionKey: Uint8Array | null = null;
  private lastRefreshTs = 0;
  private lastSyncTs = 0;

  constructor(
    private state: DurableObjectState,
    private env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method === "DELETE") {
      // Evict: close WASM, clear state
      this.wasm?.close();
      this.wasm = null;
      this.encryptionKey = null;
      this.syncKey = null;
      this.lastRefreshTs = 0;
      this.lastSyncTs = 0;
      return new Response("OK");
    }

    if (request.method !== "POST") {
      return Response.json(
        { jsonrpc: "2.0", error: { code: -32600, message: "Method not allowed" } },
        { status: 405 },
      );
    }

    // Extract sync key from header
    const key = request.headers.get("X-Sync-Key");
    if (!key) {
      return Response.json(
        { jsonrpc: "2.0", error: { code: -32600, message: "Missing sync key" } },
        { status: 401 },
      );
    }

    // Initialize WASM + load data if needed
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

    // Parse JSON-RPC
    let rpc: JsonRpcRequest;
    try {
      rpc = (await request.json()) as JsonRpcRequest;
    } catch {
      return Response.json({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32700, message: "Parse error" },
      });
    }

    // Refresh data periodically on reads
    if (!WRITE_TOOL_NAMES.has(rpc.params?.name as string)) {
      const now = Date.now();
      if (now - this.lastRefreshTs > REFRESH_INTERVAL_MS) {
        try {
          await this.pullFromSync();
          this.lastRefreshTs = now;
        } catch {
          // Continue with stale data rather than failing
        }
      }
    }

    const response = this.handleRpc(rpc);
    return Response.json(response);
  }

  private async initialize(syncKey: string): Promise<void> {
    this.syncKey = syncKey;

    // Create fresh WASM instance
    this.wasm = await WasmInstance.create();

    // Derive encryption key from sync key
    this.encryptionKey = this.wasm.deriveEncryptionKey(syncKey);

    // Pull all data from R2 via SyncRoom
    await this.pullFromSync();
    this.lastRefreshTs = Date.now();
  }

  private async pullFromSync(): Promise<void> {
    if (!this.syncKey || !this.wasm || !this.encryptionKey) return;

    const stub = this.getSyncRoomStub();
    const url = `https://internal/sync/${this.syncKey}?since=${this.lastSyncTs}`;
    const res = await stub.fetch(new Request(url, {
      headers: { "X-Sync-Key": this.syncKey },
    }));

    if (!res.ok) return;

    const { rows } = (await res.json()) as { rows: SyncRow[] };
    if (!rows.length) return;

    const decrypted = this.wasm.decryptRows(rows, this.encryptionKey);
    this.wasm.applyChanges(decrypted);

    // Track latest timestamp for incremental pulls
    const maxTs = rows.reduce((max, r) => Math.max(max, r.updated_at), this.lastSyncTs);
    this.lastSyncTs = maxTs;
  }

  private async pushToSync(): Promise<void> {
    if (!this.syncKey || !this.wasm || !this.encryptionKey) return;

    const rows = this.wasm.getChanges(this.lastSyncTs);
    if (!rows.length) return;

    // Encrypt each row's data
    const encrypted: SyncRow[] = rows.map((row) => ({
      ...row,
      data: this.wasm!.encryptField(
        JSON.stringify(row.data),
        this.encryptionKey!,
      ) as unknown as Record<string, unknown>,
    }));

    // Push to SyncRoom DO → R2 + WebSocket broadcast
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

    // Update timestamp
    const maxTs = rows.reduce((max, r) => Math.max(max, r.updated_at), this.lastSyncTs);
    this.lastSyncTs = maxTs;
  }

  private getSyncRoomStub() {
    const id = this.env.SYNC_ROOM.idFromName(this.syncKey!);
    return this.env.SYNC_ROOM.get(id);
  }

  private handleRpc(rpc: JsonRpcRequest): JsonRpcResponse {
    const { method, params, id } = rpc;

    switch (method) {
      case "initialize":
        return {
          jsonrpc: "2.0",
          id,
          result: {
            protocolVersion: "2024-11-05",
            capabilities: { tools: {} },
            serverInfo: { name: "wimg", version: "0.1.0" },
          },
        };

      case "notifications/initialized":
        // Client ack — no response needed for notifications
        return { jsonrpc: "2.0", id, result: {} };

      case "tools/list":
        return {
          jsonrpc: "2.0",
          id,
          result: {
            tools: getToolDefinitions().map((t) => ({
              name: t.name,
              description: t.description,
              inputSchema: {
                type: "object",
                properties: this.zodSchemasToJsonSchema(t.schema),
              },
            })),
          },
        };

      case "tools/call":
        return this.handleToolCall(id, params as { name: string; arguments?: Record<string, unknown> });

      case "ping":
        return { jsonrpc: "2.0", id, result: {} };

      default:
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: `Method not found: ${method}` },
        };
    }
  }

  private handleToolCall(
    id: number | string | undefined,
    params: { name: string; arguments?: Record<string, unknown> },
  ): JsonRpcResponse {
    const tools = getToolDefinitions();
    const tool = tools.find((t) => t.name === params.name);
    if (!tool) {
      return {
        jsonrpc: "2.0",
        id,
        error: { code: -32602, message: `Unknown tool: ${params.name}` },
      };
    }

    try {
      const result = tool.handler(params.arguments ?? {}, this.wasm!);

      // If this was a write tool, sync changes back
      if (WRITE_TOOL_NAMES.has(params.name)) {
        // Fire-and-forget push — don't block the response
        this.state.waitUntil(this.pushToSync());
      }

      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: result.text }],
        },
      };
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Tool execution failed";
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ error: msg }) }],
          isError: true,
        },
      };
    }
  }

  /** Convert Zod schemas to JSON Schema for tools/list response */
  private zodSchemasToJsonSchema(
    schemas: Record<string, unknown>,
  ): Record<string, { type: string; description?: string }> {
    const result: Record<string, { type: string; description?: string }> = {};
    for (const [key, zodSchema] of Object.entries(schemas)) {
      const z = zodSchema as { _def?: { typeName?: string; description?: string } };
      let type = "string";
      if (z._def?.typeName === "ZodNumber") type = "number";
      if (z._def?.typeName === "ZodBoolean") type = "boolean";
      result[key] = { type, description: z._def?.description };
    }
    return result;
  }
}
