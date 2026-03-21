import { LS_COACHMARK_PREFIX } from "./config";

class CoachmarkStore {
  #dismissed = $state<Record<string, boolean>>({});

  constructor() {
    if (typeof window === "undefined") return;
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith(LS_COACHMARK_PREFIX)) {
        this.#dismissed[key.slice(LS_COACHMARK_PREFIX.length)] = true;
      }
    }
  }

  shouldShow(key: string): boolean {
    return !this.#dismissed[key];
  }

  dismiss(key: string): void {
    this.#dismissed[key] = true;
    localStorage.setItem(LS_COACHMARK_PREFIX + key, "1");
  }
}

export const coachmarkStore = new CoachmarkStore();
