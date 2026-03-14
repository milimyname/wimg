/**
 * Reactive data store over libwimg WASM.
 * Methods auto-invalidate when bump() is called (sync receive or local mutations).
 * Pages use: `let txns = $derived(data.transactions(account))` — no void hacks.
 */
import {
  getTransactions,
  getTransactionsFiltered,
  getSummaryFiltered,
  getDebts,
  getGoals,
  getRecurring,
  type Transaction,
  type MonthlySummary,
  type Debt,
  type Goal,
  type RecurringPattern,
} from "./wasm";

// oxlint-disable no-unused-expressions, no-unused-private-class-members -- #v read triggers Svelte reactivity
class DataStore {
  #v = $state(0);

  bump() {
    this.#v++;
  }

  transactions(account?: string | null): Transaction[] {
    this.#v;
    return getTransactionsFiltered(account);
  }

  allTransactions(): Transaction[] {
    this.#v;
    return getTransactions();
  }

  hasAnyData(): boolean {
    this.#v;
    try {
      return getTransactions().length > 0;
    } catch {
      return false;
    }
  }

  summary(year: number, month: number, account?: string | null): MonthlySummary {
    this.#v;
    return getSummaryFiltered(year, month, account);
  }

  debts(): Debt[] {
    this.#v;
    return getDebts();
  }

  goals(): Goal[] {
    this.#v;
    return getGoals();
  }

  recurring(): RecurringPattern[] {
    this.#v;
    return getRecurring();
  }
}
// oxlint-enable no-unused-expressions, no-unused-private-class-members

export const data = new DataStore();
