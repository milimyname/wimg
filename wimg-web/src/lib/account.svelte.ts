import { getAccounts, type Account } from "$lib/wasm";

let selectedAccountId = $state<string | null>(null);
let accounts = $state<Account[]>([]);

export const accountStore = {
  get selected() {
    return selectedAccountId;
  },
  get accounts() {
    return accounts;
  },
  get selectedAccount(): Account | null {
    if (!selectedAccountId) return null;
    return accounts.find((a) => a.id === selectedAccountId) ?? null;
  },
  select(id: string | null) {
    selectedAccountId = id;
  },
  reload() {
    accounts = getAccounts();
  },
};
