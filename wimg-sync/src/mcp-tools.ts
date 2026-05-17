/**
 * MCP tool definitions for the wimg remote server.
 *
 * Intentionally minimal: only the two primitives Code Mode can't compose
 * away. Everything else (search, filter, group, batch, undo, recurring
 * detection, etc.) lives inside LLM-written code that the Code Mode
 * sandbox runs against these tools.
 *
 *   query(sql)                      — read-only SQL against the live SQLite
 *   set_category(transaction_id, category) — the only write
 *
 * Write coalescing: `set_category` calls `onWrite`, the DO flips its
 * `dirty` flag, and a single `pushToSync()` fires after the MCP request
 * regardless of how many writes the sandbox made.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { WasmInstance, CategoryInfo } from "./mcp-wasm";

/**
 * Strip personally identifiable information from transaction descriptions.
 * Keeps merchant names (REWE, SPOTIFY, etc.) but removes:
 * - IBANs (e.g. DE89 3704 0044 0532 0130 00)
 * - BICs/SWIFT codes (e.g. COBADEFFXXX)
 * - Card numbers (4×4 digit groups)
 * - Structured reference fields: EREF+, MREF+, CRED+, KREF+, ABWA+ (names)
 */
export function stripPII(description: string): string {
  return (
    description
      .replace(/\b[A-Z]{2}\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{0,4}\s?\d{0,2}\b/g, "***")
      .replace(/\bBIC\+[A-Z0-9]{8,11}\b/g, "BIC+***")
      .replace(/\b\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\b/g, "***")
      .replace(/\bEREF\+\S+/g, "EREF+***")
      .replace(/\bMREF\+\S+/g, "MREF+***")
      .replace(/\bCRED\+\S+/g, "CRED+***")
      .replace(/\bKREF\+\S+/g, "KREF+***")
      .replace(/\bIBAN\+\S+/g, "IBAN+***")
      .replace(/\bABWA\+[^+]+/g, "ABWA+***")
      .replace(/\s{2,}/g, " ")
      .trim()
  );
}

/** Map of aliases → canonical German category name (lowercase keys) */
const CATEGORY_ALIASES: Record<string, string> = {
  uncategorized: "unkategorisiert",
  groceries: "lebensmittel",
  food: "lebensmittel",
  dining: "essen gehen",
  restaurant: "essen gehen",
  restaurants: "essen gehen",
  "eating out": "essen gehen",
  transport: "transport",
  transportation: "transport",
  housing: "wohnen",
  rent: "wohnen",
  utilities: "nebenkosten",
  bills: "nebenkosten",
  entertainment: "unterhaltung",
  shopping: "shopping",
  health: "gesundheit",
  healthcare: "gesundheit",
  pharmacy: "gesundheit",
  insurance: "versicherung",
  income: "einkommen",
  salary: "einkommen",
  gehalt: "einkommen",
  transfer: "umbuchung",
  transfers: "umbuchung",
  cash: "bargeld",
  subscriptions: "abonnements",
  abos: "abonnements",
  subs: "abonnements",
  travel: "reisen",
  education: "bildung",
  other: "sonstiges",
  misc: "sonstiges",
  telefon: "nebenkosten",
  drogerie: "shopping",
  baumarkt: "shopping",
  freizeit: "unterhaltung",
  fitness: "gesundheit",
};

/**
 * Resolve a category name (English, German, or alias) to a category ID.
 * Returns undefined if no match found.
 */
function resolveCategoryId(
  categories: Record<number, CategoryInfo>,
  input: string,
): number | undefined {
  const lower = input.toLowerCase().trim();

  const exact = Object.values(categories).find((c) => c.name.toLowerCase() === lower);
  if (exact) return exact.id;

  const aliasTarget = CATEGORY_ALIASES[lower];
  if (aliasTarget) {
    const aliased = Object.values(categories).find((c) => c.name.toLowerCase() === aliasTarget);
    if (aliased) return aliased.id;
  }

  const partial = Object.values(categories).find(
    (c) => c.name.toLowerCase().includes(lower) || lower.includes(c.name.toLowerCase()),
  );
  if (partial) return partial.id;

  return undefined;
}

function validCategoryNames(categories: Record<number, CategoryInfo>): string {
  return Object.values(categories)
    .map((c) => c.name)
    .join(", ");
}

/**
 * Column names whose values get run through stripPII() before leaving
 * `wimg.query()`. Conservative — better to strip too much than leak.
 */
const PII_COLUMNS = /^(desc|description|raw|note|reference|pattern|payee|merchant)$/i;

/** True for `SELECT ...` or `WITH ... SELECT ...` (CTEs). */
function isReadOnlySql(sql: string): boolean {
  const trimmed = sql.trim().replace(/^--.*$/gm, "").trim();
  return /^(select|with)\b/i.test(trimmed);
}

/** Shorthand for MCP text-content response */
function text(payload: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: typeof payload === "string" ? payload : JSON.stringify(payload, null, 2),
      },
    ],
  };
}

export interface BuildMcpServerDeps {
  wasm: WasmInstance;
  /** Called by every write tool after a successful mutation. */
  onWrite?: () => void;
}

export function buildMcpServer({ wasm, onWrite }: BuildMcpServerDeps): McpServer {
  const server = new McpServer({ name: "wimg", version: "0.3.0" });

  // ===== query — universal read =====

  server.registerTool(
    "query",
    {
      description: [
        "Run a read-only SQL query against the local wimg SQLite. Only `SELECT` / `WITH` allowed — `INSERT/UPDATE/DELETE/DROP` are rejected.",
        "Description-like columns (description, raw, note, reference, pattern, payee, merchant) are scrubbed for PII (IBAN/BIC/card/reference numbers) before return.",
        "",
        "Schema:",
        "  transactions(id TEXT, date TEXT, description TEXT, amount INTEGER /* cents, signed */, currency TEXT, category INTEGER, account TEXT, raw TEXT, excluded INTEGER, updated_at INTEGER)",
        "  accounts(id TEXT, name TEXT, type TEXT, currency TEXT, owner TEXT, color TEXT, updated_at INTEGER)",
        "  rules(pattern TEXT, category INTEGER, priority INTEGER, updated_at INTEGER)",
        "  snapshots(id TEXT, date TEXT, net_worth INTEGER, income INTEGER, expenses INTEGER, tx_count INTEGER, breakdown TEXT /* JSON */, updated_at INTEGER)",
        "  meta(key TEXT, value TEXT)",
        "",
        "Categories are NOT a SQLite table — they're a static list. Map between category ID and name by reference: 0=Unkategorisiert, 1=Lebensmittel, 2=Essen gehen, 3=Transport, 4=Wohnen, 5=Nebenkosten, 6=Unterhaltung, 7=Shopping, 8=Gesundheit, 9=Versicherung, 10=Einkommen, 11=Umbuchung, 12=Bargeld, 13=Abonnements, 14=Reisen, 15=Bildung, 255=Sonstiges.",
        "",
        "Amounts in `transactions.amount` are integer cents (negative = expense). Divide by 100 for euros. Snapshot amounts are also cents.",
      ].join("\n"),
      inputSchema: {
        sql: z
          .string()
          .describe(
            "SQL SELECT or WITH statement. Use LIMIT for paging. Use sqlite_master for schema introspection.",
          ),
      },
    },
    async ({ sql }) => {
      if (!isReadOnlySql(sql)) {
        throw new Error(
          "wimg.query: only SELECT / WITH statements allowed. Use set_category for category writes; other mutations aren't exposed via MCP.",
        );
      }
      const result = wasm.query(sql);
      const piiColIdx = result.columns
        .map((name, idx) => (PII_COLUMNS.test(name) ? idx : -1))
        .filter((idx) => idx >= 0);
      if (piiColIdx.length > 0) {
        for (const row of result.rows) {
          for (const idx of piiColIdx) {
            const v = row[idx];
            if (typeof v === "string") row[idx] = stripPII(v);
          }
        }
      }
      return text(result);
    },
  );

  // ===== set_category — the only write =====

  server.registerTool(
    "set_category",
    {
      description: [
        "Set the category of a single transaction by ID. The only write operation exposed via MCP.",
        "",
        "Category names accepted as German canonical (e.g. 'Lebensmittel'), English (e.g. 'Groceries'), or alias (e.g. 'Food'). Valid category IDs: 0=Unkategorisiert, 1=Lebensmittel, 2=Essen gehen, 3=Transport, 4=Wohnen, 5=Nebenkosten, 6=Unterhaltung, 7=Shopping, 8=Gesundheit, 9=Versicherung, 10=Einkommen, 11=Umbuchung, 12=Bargeld, 13=Abonnements, 14=Reisen, 15=Bildung, 255=Sonstiges.",
        "",
        "Side effects: also creates a low-priority `rules` row (auto-learn) so future transactions with the same merchant keyword get the same category.",
        "",
        "For bulk categorization, call this in a loop inside the Code Mode sandbox — the DO coalesces all writes from one MCP request into a single push to sync.",
      ].join("\n"),
      inputSchema: {
        transaction_id: z.string().describe("Transaction ID (the `id` column in `transactions`)."),
        category: z
          .string()
          .describe(
            "Category name — German, English, or alias. Examples: 'Lebensmittel', 'Groceries', 'Food', 'Abonnements', 'Subscriptions'.",
          ),
      },
    },
    async ({ transaction_id, category }) => {
      const catId = resolveCategoryId(wasm.categories, category);
      if (catId === undefined) {
        throw new Error(
          `Unknown category: '${category}'. Valid categories: ${validCategoryNames(wasm.categories)}`,
        );
      }
      wasm.setCategory(transaction_id, catId);
      onWrite?.();
      return text({
        success: true,
        transaction_id,
        category: wasm.categories[catId]?.name ?? `Unknown (${catId})`,
      });
    },
  );

  return server;
}
