import { Hono } from "hono";
import { cors } from "hono/cors";

export { SyncRoom } from "./sync-room";

type Bindings = {
  BUCKET: R2Bucket;
  SYNC_ROOM: DurableObjectNamespace;
};

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
      if (!origin) return "*";
      if (ALLOWED_ORIGINS.includes(origin)) return origin;
      if (origin.endsWith(".pages.dev")) return origin;
      // Allow private network origins for local dev (192.168.x.x, 10.x.x, 172.16-31.x.x)
      if (/^https?:\/\/(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.|localhost)/.test(origin))
        return origin;
      return "";
    },
    allowMethods: ["GET", "POST", "OPTIONS"],
    allowHeaders: ["Content-Type"],
  }),
);

/** Get the DO stub for a sync key */
function getSyncRoom(env: Bindings, key: string) {
  const id = env.SYNC_ROOM.idFromName(key);
  return env.SYNC_ROOM.get(id);
}

// WebSocket upgrade — route to DO
app.get("/ws/:key", async (c) => {
  const key = c.req.param("key");
  const upgradeHeader = c.req.header("Upgrade");

  if (!upgradeHeader || upgradeHeader.toLowerCase() !== "websocket") {
    return c.text("Expected WebSocket upgrade", 426);
  }

  const stub = getSyncRoom(c.env, key);
  const url = new URL(c.req.url);
  url.pathname = "/ws";

  return stub.fetch(
    new Request(url.toString(), {
      headers: {
        Upgrade: "websocket",
        "X-Sync-Key": key,
      },
    }),
  );
});

// Push changed rows — route to DO
app.post("/sync/:key", async (c) => {
  const key = c.req.param("key");
  const stub = getSyncRoom(c.env, key);

  return stub.fetch(
    new Request(c.req.url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Sync-Key": key },
      body: c.req.raw.body,
    }),
  );
});

// Pull rows newer than `since` — route to DO
app.get("/sync/:key", async (c) => {
  const key = c.req.param("key");
  const stub = getSyncRoom(c.env, key);

  const url = new URL(c.req.url);
  return stub.fetch(
    new Request(url.toString(), {
      headers: { "X-Sync-Key": key },
    }),
  );
});

export default app;
