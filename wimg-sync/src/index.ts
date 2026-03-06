import { Hono } from "hono";
import { cors } from "hono/cors";

type Bindings = { BUCKET: R2Bucket };

interface Row {
  table: string;
  id: string;
  data: Record<string, unknown>;
  updated_at: number;
}

interface SyncData {
  rows: Row[];
}

const MAX_SIZE_BYTES = 100 * 1024 * 1024; // 100MB per key

const ALLOWED_ORIGINS = [
  "https://wimg.pages.dev",
  "https://wimg-web.pages.dev",
  "https://wimg.mili-my.name",
  "http://localhost:5173",
  "http://localhost:4173",
];

const app = new Hono<{ Bindings: Bindings }>();

app.use(
  "*",
  cors({
    origin: (origin) => {
      // Allow requests with no Origin header (iOS native app, curl, etc.)
      if (!origin) return "*";
      // Allow known wimg web origins
      if (ALLOWED_ORIGINS.includes(origin)) return origin;
      // Allow any *.pages.dev subdomain for preview deployments
      if (origin.endsWith(".pages.dev")) return origin;
      return "";
    },
    allowMethods: ["GET", "POST", "OPTIONS"],
    allowHeaders: ["Content-Type"],
  }),
);

// Push changed rows
app.post("/sync/:key", async (c) => {
  const key = c.req.param("key");
  const incoming = await c.req.json<SyncData>();

  if (!incoming.rows?.length) {
    return c.json({ error: "No rows provided" }, 400);
  }

  const objectKey = `${key}/changes.json`;
  const existing = await c.env.BUCKET.get(objectKey);

  let stored: SyncData = { rows: [] };
  if (existing) {
    stored = await existing.json<SyncData>();
  }

  // Merge: last-write-wins per table+id
  const index = new Map<string, number>();
  for (let i = 0; i < stored.rows.length; i++) {
    const row = stored.rows[i];
    index.set(`${row.table}:${row.id}`, i);
  }

  for (const row of incoming.rows) {
    const rowKey = `${row.table}:${row.id}`;
    const existingIdx = index.get(rowKey);

    if (existingIdx !== undefined) {
      // Last-write-wins: only update if incoming is newer
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
    return c.json({ error: "Storage limit exceeded (100MB)" }, 413);
  }

  await c.env.BUCKET.put(objectKey, body, {
    httpMetadata: { contentType: "application/json" },
  });

  return c.json({ merged: stored.rows.length });
});

// Pull rows newer than `since`
app.get("/sync/:key", async (c) => {
  const key = c.req.param("key");
  const since = Number(c.req.query("since") || "0");

  const existing = await c.env.BUCKET.get(`${key}/changes.json`);
  if (!existing) {
    return c.json({ rows: [] });
  }

  const stored = await existing.json<SyncData>();
  const filtered = stored.rows.filter((r) => r.updated_at > since);

  return c.json({ rows: filtered });
});

export default app;
