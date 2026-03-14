/**
 * Theme store — light/dark/system mode with localStorage persistence.
 */

const LS_KEY = "wimg_theme";

type Mode = "light" | "dark" | "system";

function readStored(): Mode {
  if (typeof window === "undefined") return "system";
  const v = localStorage.getItem(LS_KEY);
  if (v === "light" || v === "dark") return v;
  return "system";
}

class ThemeStore {
  #mode = $state<Mode>(readStored());

  get mode() {
    return this.#mode;
  }

  get resolved(): "light" | "dark" {
    if (this.#mode !== "system") return this.#mode;
    if (typeof window === "undefined") return "light";
    return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  get isDark() {
    return this.resolved === "dark";
  }

  set(mode: Mode) {
    this.#mode = mode;
    localStorage.setItem(LS_KEY, mode);
    this.#apply();
  }

  toggle() {
    const order: Mode[] = ["light", "dark", "system"];
    const idx = order.indexOf(this.#mode);
    this.set(order[(idx + 1) % order.length]);
  }

  init() {
    this.#apply();
    // Listen for system preference changes when in "system" mode
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (this.#mode === "system") this.#apply();
    });
  }

  #apply() {
    const dark = this.resolved === "dark";
    document.documentElement.classList.toggle("dark", dark);
    // Update theme-color meta for mobile browsers
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", dark ? "#1a1a1a" : "#faf9f6");
  }
}

export const themeStore = new ThemeStore();
