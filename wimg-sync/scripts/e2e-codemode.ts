#!/usr/bin/env bun
/**
 * End-to-end test for the Code Mode round-trip on wimg-sync.
 *
 * Flow:
 *   1. POST /sync/:key  → seed one fake `transactions` row (plaintext object —
 *                          SyncRoom stores it opaquely; McpSession's decryptRows
 *                          passes through any non-string `data` unchanged).
 *   2. POST /mcp `code` → sandbox calls codemode.set_category() to change the
 *                          seeded row's category. DO mutates WASM SQLite, flips
 *                          dirty flag, queues pushToSync via waitUntil.
 *   3. POST /mcp `code` → sandbox calls codemode.query() to read the row back.
 *                          DO is warm; query goes straight to wasm.query().
 *   4. POST /sync/:key  → pull to verify the mutation reached SyncRoom (data is
 *                          now a ciphertext string, since pushToSync encrypts).
 *
 * Requires `wrangler dev` running on http://localhost:8787 (or set WIMG_SYNC_URL).
 * Run: bun run wimg-sync/scripts/e2e-codemode.ts
 */

const BASE = process.env.WIMG_SYNC_URL ?? "http://localhost:8787";
const KEY = `e2e-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const TX_ID = "seed-tx-1";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(`ASSERT FAIL: ${msg}`);
}

async function seedTransaction(): Promise<void> {
  const tx = {
    id: TX_ID,
    date: "2026-05-17",
    description: "REWE SAGT DANKE. 17.05.2026 12:00 DE89370400440532013000",
    amount: -1234, // -12.34 EUR
    currency: "EUR",
    category: 0, // Unkategorisiert
    account: "test-account",
    excluded: 0,
  };
  const row = {
    table: "transactions",
    id: TX_ID,
    data: tx, // plaintext object — DO passes through (decryptRows checks typeof "string")
    // Seed clearly in the past so the WASM-side `js_time_ms` stamp on the
    // subsequent mutation is unambiguously greater. Without a gap,
    // `wimg_get_changes(since)` can miss the mutated row.
    updated_at: Date.now() - 60_000,
  };
  const res = await fetch(`${BASE}/sync/${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Sync-Key": KEY },
    body: JSON.stringify({ rows: [row] }),
  });
  if (!res.ok) throw new Error(`seed POST failed: ${res.status} ${await res.text()}`);
  const body = (await res.json()) as { merged: number };
  console.log(`✓ seeded — SyncRoom now has ${body.merged} row(s)`);
}

async function callCode(code: string): Promise<unknown> {
  const res = await fetch(`${BASE}/mcp`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${KEY}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "code", arguments: { code } },
    }),
  });
  if (!res.ok) throw new Error(`MCP POST failed: ${res.status} ${await res.text()}`);

  // SSE format: "event: message\ndata: {...}\n\n"
  const text = await res.text();
  const dataLine = text
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.startsWith("data: "));
  assert(dataLine, `no data line in SSE response: ${text}`);
  const envelope = JSON.parse(dataLine.slice("data: ".length)) as {
    result?: {
      content: Array<{ type: string; text: string }>;
      isError?: boolean;
    };
    error?: { message: string };
  };
  if (envelope.error) throw new Error(`MCP error: ${envelope.error.message}`);
  assert(envelope.result, `no result: ${JSON.stringify(envelope)}`);

  const content = envelope.result.content[0]?.text;
  assert(content !== undefined, "no content text");
  if (envelope.result.isError) {
    throw new Error(`Sandbox error: ${content}`);
  }
  // The handler returns text(payload) which JSON.stringifies the value.
  try {
    return JSON.parse(content);
  } catch {
    return content;
  }
}

async function main(): Promise<void> {
  console.log(`Server: ${BASE}`);
  console.log(`Sync key: ${KEY}`);
  console.log("");

  // 1. Seed
  await seedTransaction();

  // 2. Mutate via Code Mode
  const setRes = (await callCode(
    `async () => await codemode.set_category({ transaction_id: "${TX_ID}", category: "Groceries" })`,
  )) as { success?: boolean; category?: string };
  console.log("✓ set_category →", setRes);
  assert(setRes.success === true, "set_category did not return success=true");
  assert(
    setRes.category === "Lebensmittel",
    `expected category resolved to 'Lebensmittel', got ${setRes.category}`,
  );

  // 3. Read back via Code Mode (same DO, warm WASM)
  const queryRes = (await callCode(
    `async () => await codemode.query({ sql: "SELECT id, category, description, updated_at FROM transactions WHERE id = '${TX_ID}'" })`,
  )) as { columns: string[]; rows: unknown[][]; count: number };
  console.log("✓ query →", queryRes);
  assert(queryRes.count === 1, `expected 1 row, got ${queryRes.count}`);
  const row = queryRes.rows[0];
  assert(row[0] === TX_ID, `row id mismatch: ${row[0]}`);
  assert(row[1] === 1, `expected category=1 (Lebensmittel), got ${row[1]}`);
  // PII column-scrub assertion: description must have IBAN replaced with ***
  const desc = String(row[2]);
  assert(
    !/\bDE89/.test(desc) && /\*\*\*/.test(desc),
    `PII strip did not run on description: '${desc}'`,
  );
  console.log("✓ description PII-scrubbed:", desc);

  // 4. Verify the mutation propagated back to SyncRoom. pushToSync is
  //    fire-and-forget via waitUntil, so poll up to 3s for the row to flip
  //    from our plaintext seed (object) to the DO's encrypted push (string).
  let pulled: { data: unknown; updated_at: number } | undefined;
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const r = await fetch(`${BASE}/sync/${KEY}?since=0`, {
      headers: { "X-Sync-Key": KEY },
    });
    if (!r.ok) throw new Error(`pull failed: ${r.status}`);
    const body = (await r.json()) as {
      rows: Array<{ table: string; id: string; data: unknown; updated_at: number }>;
    };
    pulled = body.rows.find((row) => row.table === "transactions" && row.id === TX_ID);
    if (pulled && typeof pulled.data === "string") break;
    await new Promise((res) => setTimeout(res, 200));
  }
  assert(pulled, `transaction not present in SyncRoom after mutation`);
  assert(
    typeof pulled.data === "string",
    `expected encrypted (string) data after push, still got plaintext after 3s`,
  );
  console.log(`✓ SyncRoom row replaced with encrypted ciphertext (updated_at=${pulled.updated_at})`);

  console.log("");
  console.log("PASS");
}

main().catch((e) => {
  console.error("");
  console.error("FAIL:", e instanceof Error ? e.message : String(e));
  process.exit(1);
});
