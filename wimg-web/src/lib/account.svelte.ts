import { getAccounts, type Account } from "$lib/wasm";

class AccountStore {
  #selectedId = $state<string | null>(null);
  #accounts = $state<Account[]>([]);

  get selected() {
    return this.#selectedId;
  }

  get accounts() {
    return this.#accounts;
  }

  get selectedAccount(): Account | null {
    if (!this.#selectedId) return null;
    return this.#accounts.find((a) => a.id === this.#selectedId) ?? null;
  }

  select(id: string | null) {
    this.#selectedId = id;
  }

  reload() {
    this.#accounts = getAccounts();
  }
}

export const accountStore = new AccountStore();
