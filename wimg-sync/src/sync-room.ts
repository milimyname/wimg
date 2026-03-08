/**
 * SyncRoom — Durable Object with WebSocket Hibernation API.
 *
 * One DO instance per sync key. Holds all WebSocket connections for that key.
 * When device A pushes changes, the DO merges into R2 and broadcasts to all
 * other connected devices via WebSocket.
 */

interface Env {
  BUCKET: R2Bucket;
}

interface Row {
  table: string;
  id: string;
  data: Record<string, unknown>;
  updated_at: number;
}

interface SyncData {
  rows: Row[];
}

interface WSMessage {
  type: string;
  rows?: Row[];
  since?: number;
}

const MAX_SIZE_BYTES = 100 * 1024 * 1024; // 100MB per key
const PING_INTERVAL_MS = 30_000;

export class SyncRoom implements DurableObject {
  private syncKey: string | null = null;

  constructor(
    private state: DurableObjectState,
    private env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // Extract sync key from header (set by Worker router)
    this.syncKey = request.headers.get("X-Sync-Key") ?? url.pathname.split("/").pop() ?? null;

    if (url.pathname.endsWith("/ws")) {
      // WebSocket upgrade
      const pair = new WebSocketPair();
      const [client, server] = [pair[0], pair[1]];

      this.state.acceptWebSocket(server);
      this.schedulePing();

      return new Response(null, { status: 101, webSocket: client });
    }

    if (request.method === "POST") {
      return this.handlePush(request);
    }

    if (request.method === "GET") {
      return this.handlePull(url);
    }

    return new Response("Method not allowed", { status: 405 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;

    try {
      const msg = JSON.parse(message) as WSMessage;

      if (msg.type === "pong") {
        // Heartbeat response — client is alive
        return;
      }

      if (msg.type === "push" && msg.rows?.length) {
        // Push via WebSocket: merge to R2 + broadcast to others
        const merged = await this.mergeToR2(msg.rows);
        this.broadcast({ type: "changes", rows: msg.rows }, ws);
        ws.send(JSON.stringify({ type: "push_ack", merged }));
        return;
      }

      if (msg.type === "pull") {
        // Pull via WebSocket
        const since = msg.since ?? 0;
        const rows = await this.getRowsSince(since);
        ws.send(JSON.stringify({ type: "pull_result", rows }));
        return;
      }
    } catch {
      // Ignore malformed messages
    }
  }

  async webSocketClose(
    _ws: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean,
  ): Promise<void> {
    // WebSocket already closed by runtime — nothing to do.
    // Hibernation API auto-removes it from getWebSockets().
  }

  async webSocketError(_ws: WebSocket, _error: unknown): Promise<void> {
    // WebSocket already errored — runtime handles cleanup.
  }

  async alarm(): Promise<void> {
    // Ping all connected clients
    const sockets = this.state.getWebSockets();
    if (sockets.length === 0) return;

    const ping = JSON.stringify({ type: "ping" });
    for (const ws of sockets) {
      try {
        ws.send(ping);
      } catch {
        // Socket dead, will be cleaned up by webSocketClose/webSocketError
      }
    }

    this.schedulePing();
  }

  private schedulePing(): void {
    // Schedule alarm for next ping — Hibernation API keeps DO alive only when needed
    this.state.storage.setAlarm(Date.now() + PING_INTERVAL_MS);
  }

  private async handlePush(request: Request): Promise<Response> {
    const incoming = (await request.json()) as SyncData;

    if (!incoming.rows?.length) {
      return Response.json({ error: "No rows provided" }, { status: 400 });
    }

    const merged = await this.mergeToR2(incoming.rows);

    // Broadcast to all WebSocket clients
    this.broadcast({ type: "changes", rows: incoming.rows });

    return Response.json({ merged });
  }

  private async handlePull(url: URL): Promise<Response> {
    const since = Number(url.searchParams.get("since") || "0");
    const rows = await this.getRowsSince(since);
    return Response.json({ rows });
  }

  private async mergeToR2(incomingRows: Row[]): Promise<number> {
    const key = this.syncKey;
    if (!key) throw new Error("No sync key");

    const objectKey = `${key}/changes.json`;
    const existing = await this.env.BUCKET.get(objectKey);

    let stored: SyncData = { rows: [] };
    if (existing) {
      stored = (await existing.json()) as SyncData;
    }

    // Merge: last-write-wins per table+id
    const index = new Map<string, number>();
    for (let i = 0; i < stored.rows.length; i++) {
      const row = stored.rows[i];
      index.set(`${row.table}:${row.id}`, i);
    }

    for (const row of incomingRows) {
      const rowKey = `${row.table}:${row.id}`;
      const existingIdx = index.get(rowKey);

      if (existingIdx !== undefined) {
        if (row.updated_at > stored.rows[existingIdx].updated_at) {
          stored.rows[existingIdx] = row;
        }
      } else {
        index.set(rowKey, stored.rows.length);
        stored.rows.push(row);
      }
    }

    const body = JSON.stringify(stored);

    if (body.length > MAX_SIZE_BYTES) {
      throw new Error("Storage limit exceeded (100MB)");
    }

    await this.env.BUCKET.put(objectKey, body, {
      httpMetadata: { contentType: "application/json" },
    });

    return stored.rows.length;
  }

  private async getRowsSince(since: number): Promise<Row[]> {
    const key = this.syncKey;
    if (!key) return [];

    const existing = await this.env.BUCKET.get(`${key}/changes.json`);
    if (!existing) return [];

    const stored = (await existing.json()) as SyncData;
    return stored.rows.filter((r) => r.updated_at > since);
  }

  private broadcast(msg: Record<string, unknown>, exclude?: WebSocket): void {
    const payload = JSON.stringify(msg);
    for (const ws of this.state.getWebSockets()) {
      if (ws === exclude) continue;
      try {
        ws.send(payload);
      } catch {
        // Dead socket — will be cleaned up
      }
    }
  }
}
