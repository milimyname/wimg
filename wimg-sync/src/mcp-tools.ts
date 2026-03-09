/**
 * MCP tool definitions for remote wimg server.
 * 9 read tools + 9 write tools = 18 total.
 */

import { z } from "zod/v4";
import type { WasmInstance, CategoryInfo } from "./mcp-wasm";

function formatAmount(euros: number): string {
  // WASM already returns amounts in euros (Zig formatAmount converts cents → euros)
  return euros.toFixed(2);
}

/**
 * Strip personally identifiable information from transaction descriptions.
 * Keeps merchant names (REWE, SPOTIFY, etc.) but removes:
 * - IBANs (e.g. DE89 3704 0044 0532 0130 00)
 * - BICs/SWIFT codes (e.g. COBADEFFXXX)
 * - Card numbers (4×4 digit groups)
 * - Structured reference fields: EREF+, MREF+, CRED+, KREF+, ABWA+ (names)
 */
function stripPII(description: string): string {
  return (
    description
      // IBANs: 2-letter country code + 2 check digits + up to 30 alphanumeric (with optional spaces)
      .replace(/\b[A-Z]{2}\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{0,4}\s?\d{0,2}\b/g, "***")
      // BIC/SWIFT: 8 or 11 chars (4 bank + 2 country + 2 location + optional 3 branch)
      .replace(/\bBIC\+[A-Z0-9]{8,11}\b/g, "BIC+***")
      // Card numbers: 4×4 digit groups
      .replace(/\b\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\b/g, "***")
      // Structured fields containing references or personal data
      .replace(/\bEREF\+\S+/g, "EREF+***")
      .replace(/\bMREF\+\S+/g, "MREF+***")
      .replace(/\bCRED\+\S+/g, "CRED+***")
      .replace(/\bKREF\+\S+/g, "KREF+***")
      .replace(/\bIBAN\+\S+/g, "IBAN+***")
      // ABWA+ (abweichender Auftraggeber/Empfänger — contains personal names)
      .replace(/\bABWA\+[^+]+/g, "ABWA+***")
      // Collapse multiple spaces
      .replace(/\s{2,}/g, " ")
      .trim()
  );
}

function categoryName(categories: Record<number, CategoryInfo>, id: number): string {
  return categories[id]?.name ?? `Unknown (${id})`;
}

/** Map of aliases → canonical German category name (lowercase keys) */
const CATEGORY_ALIASES: Record<string, string> = {
  // English → German
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
  // Common German short forms
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

  // 1. Exact match on German name (canonical)
  const exact = Object.values(categories).find((c) => c.name.toLowerCase() === lower);
  if (exact) return exact.id;

  // 2. Alias lookup
  const aliasTarget = CATEGORY_ALIASES[lower];
  if (aliasTarget) {
    const aliased = Object.values(categories).find((c) => c.name.toLowerCase() === aliasTarget);
    if (aliased) return aliased.id;
  }

  // 3. Substring match (e.g. "leben" matches "Lebensmittel")
  const partial = Object.values(categories).find((c) => c.name.toLowerCase().includes(lower) || lower.includes(c.name.toLowerCase()));
  if (partial) return partial.id;

  return undefined;
}

function validCategoryNames(categories: Record<number, CategoryInfo>): string {
  return Object.values(categories)
    .map((c) => c.name)
    .join(", ");
}

interface ToolDef {
  name: string;
  description: string;
  schema: Record<string, z.ZodType>;
  handler: (args: Record<string, unknown>, wasm: WasmInstance) => { text: string };
}

export function getToolDefinitions(): ToolDef[] {
  return [
    // ===== READ TOOLS =====

    {
      name: "get_monthly_summary",
      description: "Get income, expenses, and spending by category for a given month",
      schema: {
        year: z.number().int().describe("Year (e.g. 2026)"),
        month: z.number().int().min(1).max(12).describe("Month (1-12)"),
        account: z.string().optional().describe("Account ID to filter by (omit for all)"),
      },
      handler: (args, wasm) => {
        const summary = wasm.getSummaryFiltered(
          args.year as number,
          args.month as number,
          args.account as string | undefined,
        );
        const breakdown = summary.by_category.map((c) => ({
          category: categoryName(wasm.categories, c.id),
          amount: formatAmount(c.amount),
          count: c.count,
        }));
        return {
          text: JSON.stringify(
            {
              year: summary.year,
              month: summary.month,
              income: formatAmount(summary.income),
              expenses: formatAmount(summary.expenses),
              available: formatAmount(summary.available),
              transaction_count: summary.tx_count,
              by_category: breakdown,
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "list_categories",
      description:
        "List all valid categories with their IDs, German names, colors, and icons. Call this before set_category to see valid category names.",
      schema: {},
      handler: (_args, wasm) => {
        const cats = Object.values(wasm.categories).map((c) => ({
          id: c.id,
          name: c.name,
          color: c.color,
          icon: c.icon,
        }));
        return {
          text: JSON.stringify(
            {
              count: cats.length,
              categories: cats,
              note: "Use the 'name' field when calling set_category or batch_set_category. English names and common aliases are also accepted.",
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "get_transactions",
      description: "Get transactions, optionally filtered by account, date, and/or category",
      schema: {
        account: z.string().optional().describe("Account ID to filter by (omit for all)"),
        year: z.number().int().optional().describe("Filter by year (e.g. 2025)"),
        month: z.number().int().min(1).max(12).optional().describe("Filter by month (1-12, requires year)"),
        category: z.string().optional().describe("Filter by category name (German, English, or alias). Use 'Unkategorisiert' or 'uncategorized' for uncategorized transactions."),
        limit: z.number().int().positive().default(50).describe("Max transactions to return (default 50)"),
        offset: z.number().int().min(0).default(0).describe("Skip first N transactions for pagination (default 0)"),
      },
      handler: (args, wasm) => {
        let txs = wasm.getTransactionsFiltered(args.account as string | undefined);
        const year = args.year as number | undefined;
        const month = args.month as number | undefined;
        const categoryFilter = args.category as string | undefined;
        if (year) {
          txs = txs.filter((tx) => {
            const [ty, tm] = tx.date.split("-").map(Number);
            return ty === year && (month ? tm === month : true);
          });
        }
        if (categoryFilter) {
          const catId = resolveCategoryId(wasm.categories, categoryFilter);
          if (catId === undefined) {
            throw new Error(
              `Unknown category: '${categoryFilter}'. Valid categories: ${validCategoryNames(wasm.categories)}`,
            );
          }
          txs = txs.filter((tx) => tx.category === catId);
        }
        const offset = (args.offset as number) || 0;
        const limit = (args.limit as number) || 50;
        const page = txs.slice(offset, offset + limit);
        const hasMore = offset + limit < txs.length;
        const formatted = page.map((tx) => ({
          id: tx.id,
          date: tx.date,
          description: stripPII(tx.description),
          amount: formatAmount(tx.amount),
          currency: tx.currency,
          category: categoryName(wasm.categories, tx.category),
          account: tx.account,
          excluded: tx.excluded === 1,
        }));
        return {
          text: JSON.stringify(
            {
              total: txs.length,
              offset,
              showing: page.length,
              has_more: hasMore,
              ...(hasMore ? { next_offset: offset + limit } : {}),
              ...(year ? { filter: { year, ...(month ? { month } : {}) } } : {}),
              transactions: formatted,
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "search_transactions",
      description: "Search transactions by description (case-insensitive substring match)",
      schema: {
        query: z.string().describe("Search term to match against transaction descriptions"),
        account: z.string().optional().describe("Account ID to filter by (omit for all)"),
        limit: z.number().int().positive().default(20).describe("Max results (default 20)"),
        offset: z.number().int().min(0).default(0).describe("Skip first N matches for pagination (default 0)"),
      },
      handler: (args, wasm) => {
        const txs = wasm.getTransactionsFiltered(args.account as string | undefined);
        const q = (args.query as string).toLowerCase();
        const matches = txs.filter((tx) => tx.description.toLowerCase().includes(q));
        const offset = (args.offset as number) || 0;
        const limit = (args.limit as number) || 20;
        const page = matches.slice(offset, offset + limit);
        const hasMore = offset + limit < matches.length;
        const formatted = page.map((tx) => ({
          id: tx.id,
          date: tx.date,
          description: stripPII(tx.description),
          amount: formatAmount(tx.amount),
          currency: tx.currency,
          category: categoryName(wasm.categories, tx.category),
          account: tx.account,
        }));
        return {
          text: JSON.stringify(
            {
              query: args.query,
              total_matches: matches.length,
              offset,
              showing: page.length,
              has_more: hasMore,
              ...(hasMore ? { next_offset: offset + limit } : {}),
              transactions: formatted,
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "get_recurring_payments",
      description:
        "Get detected recurring payments (subscriptions, regular charges) with price change alerts",
      schema: {},
      handler: (_args, wasm) => {
        const patterns = wasm.getRecurring();
        const formatted = patterns.map((p) => ({
          merchant: p.merchant,
          amount: formatAmount(p.amount),
          interval: p.interval,
          category: categoryName(wasm.categories, p.category),
          last_seen: p.last_seen,
          next_due: p.next_due,
          active: p.active === 1,
          price_change: p.price_change
            ? { previous: formatAmount(p.prev_amount!), change: formatAmount(p.price_change) }
            : null,
        }));
        return {
          text: JSON.stringify({ count: patterns.length, recurring: formatted }, null, 2),
        };
      },
    },

    {
      name: "get_debt_status",
      description: "Get all debts with progress (total, paid, remaining, percentage)",
      schema: {},
      handler: (_args, wasm) => {
        const debts = wasm.getDebts();
        const formatted = debts.map((d) => ({
          id: d.id,
          name: d.name,
          total: formatAmount(d.total),
          paid: formatAmount(d.paid),
          remaining: formatAmount(d.total - d.paid),
          progress_pct: d.total > 0 ? Math.round((d.paid / d.total) * 100) : 0,
          monthly_payment: d.monthly ? formatAmount(d.monthly) : null,
        }));
        const totalDebt = debts.reduce((s, d) => s + d.total, 0);
        const totalPaid = debts.reduce((s, d) => s + d.paid, 0);
        return {
          text: JSON.stringify(
            {
              count: debts.length,
              total_debt: formatAmount(totalDebt),
              total_paid: formatAmount(totalPaid),
              total_remaining: formatAmount(totalDebt - totalPaid),
              debts: formatted,
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "get_accounts",
      description: "Get all bank accounts",
      schema: {},
      handler: (_args, wasm) => {
        const accounts = wasm.getAccounts();
        return {
          text: JSON.stringify({ count: accounts.length, accounts }, null, 2),
        };
      },
    },

    {
      name: "detect_recurring",
      description: "Re-scan transactions to detect recurring payment patterns",
      schema: {},
      handler: (_args, wasm) => {
        const count = wasm.detectRecurring();
        return { text: JSON.stringify({ patterns_detected: count }, null, 2) };
      },
    },

    {
      name: "get_uncategorized_transactions",
      description:
        "Get all uncategorized transactions, grouped by merchant/description pattern. Use this FIRST before categorizing — it shows everything that needs categorization in one call. Then use batch_set_category to categorize them all at once.",
      schema: {
        account: z.string().optional().describe("Account ID to filter by (omit for all)"),
      },
      handler: (args, wasm) => {
        const txs = wasm.getTransactionsFiltered(args.account as string | undefined);
        const uncategorized = txs.filter((tx) => tx.category === 0);

        // Group by normalized description (lowercase, trim numbers/dates)
        const groups: Record<string, Array<{ id: string; date: string; description: string; amount: string }>> = {};
        for (const tx of uncategorized) {
          // Normalize: lowercase, remove dates, trailing numbers, card numbers
          const key = tx.description
            .toLowerCase()
            .replace(/\d{2}\.\d{2}\.\d{2,4}/g, "")
            .replace(/\d{4}\s?\d{4}\s?\d{4}/g, "")
            .replace(/\s+/g, " ")
            .trim();
          if (!groups[key]) groups[key] = [];
          groups[key].push({
            id: tx.id,
            date: tx.date,
            description: stripPII(tx.description),
            amount: formatAmount(tx.amount),
          });
        }

        // Sort groups by count (most common first)
        const sorted = Object.entries(groups)
          .sort((a, b) => b[1].length - a[1].length)
          .map(([pattern, txns]) => ({
            pattern,
            count: txns.length,
            total: formatAmount(txns.reduce((s, t) => s + parseFloat(t.amount), 0)),
            transactions: txns,
          }));

        return {
          text: JSON.stringify(
            {
              total_uncategorized: uncategorized.length,
              groups: sorted.length,
              by_merchant: sorted,
              tip: "Use batch_set_category with the transaction IDs and category names to categorize them all at once.",
            },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "get_spending_by_category",
      description:
        "Get spending for a specific category over multiple months. Accepts English names, German names, or aliases.",
      schema: {
        category: z
          .string()
          .describe("Category name (e.g. 'Lebensmittel', 'Groceries', 'Food', 'Transport', 'Shopping')"),
        months: z.number().int().positive().default(6).describe("Number of months to look back"),
      },
      handler: (args, wasm) => {
        const catId = resolveCategoryId(wasm.categories, args.category as string);
        if (catId === undefined) {
          throw new Error(
            `Unknown category: '${args.category}'. Valid categories: ${validCategoryNames(wasm.categories)}`,
          );
        }

        const now = new Date();
        const results: Array<{ year: number; month: number; amount: string; count: number }> = [];

        for (let i = 0; i < (args.months as number); i++) {
          const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
          const summary = wasm.getSummaryFiltered(d.getFullYear(), d.getMonth() + 1);
          const match = summary.by_category.find((c) => c.id === catId);
          if (match) {
            results.push({
              year: d.getFullYear(),
              month: d.getMonth() + 1,
              amount: formatAmount(match.amount),
              count: match.count,
            });
          }
        }

        return {
          text: JSON.stringify(
            { category: categoryName(wasm.categories, catId), months: results },
            null,
            2,
          ),
        };
      },
    },

    // ===== WRITE TOOLS =====

    {
      name: "set_category",
      description:
        "Set the category of a transaction. Accepts German names, English names, or aliases. Call list_categories first to see valid names.",
      schema: {
        transaction_id: z.string().describe("Transaction ID"),
        category: z
          .string()
          .describe(
            "Category name — German (e.g. 'Lebensmittel', 'Essen gehen', 'Abonnements'), English (e.g. 'Groceries', 'Dining', 'Subscriptions'), or alias (e.g. 'Food', 'Restaurant', 'Abos')",
          ),
      },
      handler: (args, wasm) => {
        const catId = resolveCategoryId(wasm.categories, args.category as string);
        if (catId === undefined) {
          throw new Error(
            `Unknown category: '${args.category}'. Valid categories: ${validCategoryNames(wasm.categories)}`,
          );
        }
        wasm.setCategory(args.transaction_id as string, catId);
        const resolved = categoryName(wasm.categories, catId);
        return {
          text: JSON.stringify({ success: true, transaction_id: args.transaction_id, category: resolved }),
        };
      },
    },

    {
      name: "batch_set_category",
      description:
        "Set categories for multiple transactions at once. Accepts German names, English names, or aliases. Call list_categories first to see valid names.",
      schema: {
        updates: z
          .union([
            z.array(
              z.object({
                transaction_id: z.string().describe("Transaction ID"),
                category: z.string().describe("Category name (German, English, or alias)"),
              }),
            ),
            z.string().describe("JSON-encoded array of {transaction_id, category} objects"),
          ])
          .describe("Array of {transaction_id, category} pairs (max 100). Can be a JSON string or array."),
      },
      handler: (args, wasm) => {
        let updates: Array<{ transaction_id: string; category: string }>;
        const raw = args.updates;
        if (typeof raw === "string") {
          try {
            updates = JSON.parse(raw);
          } catch {
            throw new Error("updates must be valid JSON array of {transaction_id, category} objects");
          }
        } else if (Array.isArray(raw)) {
          updates = raw as Array<{ transaction_id: string; category: string }>;
        } else {
          throw new Error("updates must be an array of {transaction_id, category} objects");
        }
        if (!Array.isArray(updates) || updates.length === 0) {
          throw new Error("updates must be a non-empty array");
        }
        if (updates.length > 100) {
          throw new Error("Maximum 100 updates per batch");
        }
        const results: Array<{
          transaction_id: string;
          category: string;
          resolved?: string;
          success: boolean;
          error?: string;
        }> = [];

        for (const u of updates) {
          const catId = resolveCategoryId(wasm.categories, u.category);
          if (catId === undefined) {
            results.push({
              transaction_id: u.transaction_id,
              category: u.category,
              success: false,
              error: `Unknown category: '${u.category}'. Valid: ${validCategoryNames(wasm.categories)}`,
            });
            continue;
          }
          try {
            wasm.setCategory(u.transaction_id, catId);
            results.push({
              transaction_id: u.transaction_id,
              category: u.category,
              resolved: categoryName(wasm.categories, catId),
              success: true,
            });
          } catch (e) {
            results.push({ transaction_id: u.transaction_id, category: u.category, success: false, error: String(e) });
          }
        }

        const succeeded = results.filter((r) => r.success).length;
        return {
          text: JSON.stringify(
            { total: updates.length, succeeded, failed: updates.length - succeeded, results },
            null,
            2,
          ),
        };
      },
    },

    {
      name: "set_excluded",
      description: "Include or exclude a transaction from summaries and analysis",
      schema: {
        transaction_id: z.string().describe("Transaction ID"),
        excluded: z.boolean().describe("true to exclude, false to include"),
      },
      handler: (args, wasm) => {
        wasm.setExcluded(args.transaction_id as string, args.excluded as boolean);
        return {
          text: JSON.stringify({
            success: true,
            transaction_id: args.transaction_id,
            excluded: args.excluded,
          }),
        };
      },
    },

    {
      name: "add_debt",
      description: "Add a new debt to track (e.g. loan, installment, recurring bill)",
      schema: {
        name: z.string().describe("Name of the debt (e.g. 'FOM Studiengebühren', 'Klarna')"),
        total: z.number().positive().describe("Total amount in euros (e.g. 5000.00)"),
        monthly: z.number().positive().optional().describe("Monthly payment in euros (optional)"),
      },
      handler: (args, wasm) => {
        const totalCents = Math.round((args.total as number) * 100);
        const monthlyCents = args.monthly ? Math.round((args.monthly as number) * 100) : undefined;
        const id = wasm.addDebt(args.name as string, totalCents, monthlyCents);
        return {
          text: JSON.stringify({ success: true, id, name: args.name, total: args.total }),
        };
      },
    },

    {
      name: "mark_debt_paid",
      description: "Record a payment towards a debt. Use get_debt_status first to find the debt ID.",
      schema: {
        debt_id: z.string().describe("Debt ID"),
        amount: z.number().positive().describe("Payment amount in euros (e.g. 200.00)"),
      },
      handler: (args, wasm) => {
        const amountCents = Math.round((args.amount as number) * 100);
        wasm.markDebtPaid(args.debt_id as string, amountCents);
        return {
          text: JSON.stringify({ success: true, debt_id: args.debt_id, amount_paid: args.amount }),
        };
      },
    },

    {
      name: "add_account",
      description: "Add a new bank account for tracking",
      schema: {
        id: z.string().describe("Account ID (e.g. 'comdirect-main', 'tr-depot')"),
        name: z.string().describe("Display name (e.g. 'Comdirect Girokonto')"),
        color: z.string().optional().describe("Hex color (e.g. '#FFD700', default: '#6B7280')"),
      },
      handler: (args, wasm) => {
        wasm.addAccount(args.id as string, args.name as string, args.color as string | undefined);
        return {
          text: JSON.stringify({ success: true, id: args.id, name: args.name }),
        };
      },
    },

    {
      name: "update_account",
      description: "Update an existing bank account's name or color",
      schema: {
        id: z.string().describe("Account ID to update"),
        name: z.string().describe("New display name"),
        color: z.string().optional().describe("New hex color"),
      },
      handler: (args, wasm) => {
        wasm.updateAccount(
          args.id as string,
          args.name as string,
          args.color as string | undefined,
        );
        return {
          text: JSON.stringify({ success: true, id: args.id, name: args.name }),
        };
      },
    },

    {
      name: "undo",
      description: "Undo the last action (category change, debt payment, etc.)",
      schema: {},
      handler: (_args, wasm) => {
        const result = wasm.undo();
        if (!result) return { text: JSON.stringify({ success: false, reason: "Nothing to undo" }) };
        return { text: JSON.stringify({ success: true, undone: result }) };
      },
    },

    {
      name: "redo",
      description: "Redo the last undone action",
      schema: {},
      handler: (_args, wasm) => {
        const result = wasm.redo();
        if (!result) return { text: JSON.stringify({ success: false, reason: "Nothing to redo" }) };
        return { text: JSON.stringify({ success: true, redone: result }) };
      },
    },
  ];
}

/** Tools that mutate data and need sync write-back */
export const WRITE_TOOL_NAMES = new Set([
  "set_category",
  "batch_set_category",
  "set_excluded",
  "add_debt",
  "mark_debt_paid",
  "add_account",
  "update_account",
  "undo",
  "redo",
  "detect_recurring",
]);
