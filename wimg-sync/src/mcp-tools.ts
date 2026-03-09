/**
 * MCP tool definitions for remote wimg server.
 * 8 read tools + 9 write tools = 17 total.
 */

import { z } from "zod/v4";
import type { WasmInstance } from "./mcp-wasm";

function formatAmount(euros: number): string {
  // WASM already returns amounts in euros (Zig formatAmount converts cents → euros)
  return euros.toFixed(2);
}

function categoryName(categories: Record<number, { name: string }>, id: number): string {
  return categories[id]?.name ?? `Unknown (${id})`;
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
      name: "get_transactions",
      description: "Get recent transactions, optionally filtered by account",
      schema: {
        account: z.string().optional().describe("Account ID to filter by (omit for all)"),
        limit: z.number().int().positive().default(50).describe("Max transactions to return (default 50)"),
        offset: z.number().int().min(0).default(0).describe("Skip first N transactions for pagination (default 0)"),
      },
      handler: (args, wasm) => {
        const txs = wasm.getTransactionsFiltered(args.account as string | undefined);
        const offset = (args.offset as number) || 0;
        const limit = (args.limit as number) || 50;
        const page = txs.slice(offset, offset + limit);
        const hasMore = offset + limit < txs.length;
        const formatted = page.map((tx) => ({
          id: tx.id,
          date: tx.date,
          description: tx.description,
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
          description: tx.description,
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
      name: "get_spending_by_category",
      description: "Get spending for a specific category over multiple months",
      schema: {
        category: z.string().describe("Category name (e.g. 'Food', 'Transport', 'Entertainment')"),
        months: z.number().int().positive().default(6).describe("Number of months to look back"),
      },
      handler: (args, wasm) => {
        const now = new Date();
        const results: Array<{ year: number; month: number; amount: string; count: number }> = [];
        const catLower = (args.category as string).toLowerCase();
        const catId = Object.values(wasm.categories).find(
          (c) => c.name.toLowerCase() === catLower,
        )?.id;

        for (let i = 0; i < (args.months as number); i++) {
          const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
          const summary = wasm.getSummaryFiltered(d.getFullYear(), d.getMonth() + 1);
          const match = summary.by_category.find((c) =>
            catId !== undefined ? c.id === catId : c.name.toLowerCase() === catLower,
          );
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
          text: JSON.stringify({ category: args.category, months: results }, null, 2),
        };
      },
    },

    // ===== WRITE TOOLS =====

    {
      name: "set_category",
      description:
        "Set the category of a transaction. Use get_transactions or search_transactions first to find the transaction ID.",
      schema: {
        transaction_id: z.string().describe("Transaction ID"),
        category: z
          .string()
          .describe("Category name (e.g. 'Food', 'Lebensmittel', 'Transport', 'Shopping', 'Subscriptions')"),
      },
      handler: (args, wasm) => {
        const catName = (args.category as string).toLowerCase();
        const catId = Object.values(wasm.categories).find(
          (c) => c.name.toLowerCase() === catName,
        )?.id;
        if (catId === undefined) {
          throw new Error(`Unknown category: ${args.category}`);
        }
        wasm.setCategory(args.transaction_id as string, catId);
        return { text: JSON.stringify({ success: true, transaction_id: args.transaction_id, category: args.category }) };
      },
    },

    {
      name: "batch_set_category",
      description:
        "Set categories for multiple transactions at once. Much faster than calling set_category individually. Use get_transactions or search_transactions first to find transaction IDs.",
      schema: {
        updates: z
          .union([
            z.array(
              z.object({
                transaction_id: z.string().describe("Transaction ID"),
                category: z.string().describe("Category name"),
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
        const results: Array<{ transaction_id: string; category: string; success: boolean; error?: string }> = [];

        for (const u of updates) {
          const catName = u.category.toLowerCase();
          const catId = Object.values(wasm.categories).find((c) => c.name.toLowerCase() === catName)?.id;
          if (catId === undefined) {
            results.push({ transaction_id: u.transaction_id, category: u.category, success: false, error: `Unknown category: ${u.category}` });
            continue;
          }
          try {
            wasm.setCategory(u.transaction_id, catId);
            results.push({ transaction_id: u.transaction_id, category: u.category, success: true });
          } catch (e) {
            results.push({ transaction_id: u.transaction_id, category: u.category, success: false, error: String(e) });
          }
        }

        const succeeded = results.filter((r) => r.success).length;
        return {
          text: JSON.stringify({ total: updates.length, succeeded, failed: updates.length - succeeded, results }, null, 2),
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
