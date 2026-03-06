/**
 * Claude API integration for transaction categorization.
 *
 * Since WASM can't make HTTP calls, categorization via Claude API
 * happens on the JS/TS side. Uncategorized transactions are sent
 * to Claude in batches, and results are written back via wimg_set_category.
 */

import { CATEGORIES, type Transaction, setCategory } from "./wasm";
import { CLAUDE_API_URL, CLAUDE_MODEL, CLAUDE_BATCH_SIZE, LS_CLAUDE_API_KEY } from "./config";

export function getApiKey(): string | null {
  return localStorage.getItem(LS_CLAUDE_API_KEY);
}

export function setApiKey(key: string): void {
  localStorage.setItem(LS_CLAUDE_API_KEY, key);
}

export function removeApiKey(): void {
  localStorage.removeItem(LS_CLAUDE_API_KEY);
}

/** Build category name→id map for Claude's response parsing. */
function categoryNameToId(): Record<string, number> {
  const map: Record<string, number> = {};
  for (const [id, cat] of Object.entries(CATEGORIES)) {
    map[cat.name.toLowerCase()] = Number(id);
  }
  return map;
}

/** Build the category list string for the prompt. */
function categoryList(): string {
  return Object.entries(CATEGORIES)
    .filter(([id]) => Number(id) !== 0 && Number(id) !== 255)
    .map(([id, cat]) => `${id}: ${cat.name}`)
    .join("\n");
}

interface CategorizeResult {
  categorized: number;
  errors: string[];
}

/**
 * Categorize uncategorized transactions via Claude API.
 * Sends descriptions in batches and maps responses back to category IDs.
 */
export async function categorizeWithClaude(transactions: Transaction[]): Promise<CategorizeResult> {
  const apiKey = getApiKey();
  if (!apiKey) {
    return { categorized: 0, errors: ["No API key configured"] };
  }

  const uncategorized = transactions.filter((tx) => tx.category === 0);
  if (uncategorized.length === 0) {
    return { categorized: 0, errors: [] };
  }

  const nameToId = categoryNameToId();
  let categorized = 0;
  const errors: string[] = [];

  for (let i = 0; i < uncategorized.length; i += CLAUDE_BATCH_SIZE) {
    const batch = uncategorized.slice(i, i + CLAUDE_BATCH_SIZE);
    const descriptions = batch
      .map(
        (tx, idx) =>
          `${idx + 1}. "${tx.description}" (${tx.amount > 0 ? "+" : ""}${tx.amount.toFixed(2)}€)`,
      )
      .join("\n");

    const prompt = `You are a personal finance categorizer for a German bank account. Categorize each transaction into exactly one category.

Available categories:
${categoryList()}

Transactions to categorize:
${descriptions}

Respond with ONLY a JSON array of objects, one per transaction, in order:
[{"index": 1, "category": "Category Name"}, ...]

Use the exact category names from the list above. If unsure, use "Other".`;

    try {
      const response = await fetch(CLAUDE_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "anthropic-dangerous-direct-browser-access": "true",
        },
        body: JSON.stringify({
          model: CLAUDE_MODEL,
          max_tokens: 1024,
          messages: [{ role: "user", content: prompt }],
        }),
      });

      if (!response.ok) {
        const text = await response.text();
        if (response.status === 401) {
          errors.push("Invalid API key");
          break;
        }
        errors.push(`API error ${response.status}: ${text.slice(0, 100)}`);
        continue;
      }

      const data = await response.json();
      const content = data.content?.[0]?.text ?? "";

      // Extract JSON array from response
      const jsonMatch = content.match(/\[[\s\S]*\]/);
      if (!jsonMatch) {
        errors.push(`Could not parse response for batch ${Math.floor(i / CLAUDE_BATCH_SIZE) + 1}`);
        continue;
      }

      const results = JSON.parse(jsonMatch[0]) as Array<{
        index: number;
        category: string;
      }>;

      for (const result of results) {
        const txIdx = result.index - 1;
        if (txIdx < 0 || txIdx >= batch.length) continue;

        const categoryId = nameToId[result.category.toLowerCase()];
        if (categoryId !== undefined && categoryId !== 0) {
          await setCategory(batch[txIdx].id, categoryId);
          categorized++;
        }
      }
    } catch (e) {
      errors.push(
        `Batch ${Math.floor(i / CLAUDE_BATCH_SIZE) + 1} failed: ${e instanceof Error ? e.message : "Unknown error"}`,
      );
    }
  }

  return { categorized, errors };
}
