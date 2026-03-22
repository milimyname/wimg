/**
 * i18n runtime — reactive locale with translation lookup.
 * German strings are keys. English translations loaded from map.
 * The Vite plugin replaces template text at compile time with __t$() calls.
 * Changing locale triggers Svelte reactivity — no page reload needed.
 */
import { LS_LOCALE } from "$lib/config";
import { en } from "$lib/translations/en";

function getInitialLocale(): string {
  if (typeof localStorage === "undefined") return "de";
  const stored = localStorage.getItem(LS_LOCALE) ?? navigator.language.slice(0, 2);
  return ["de", "en"].includes(stored) ? stored : "de";
}

class I18n {
  // Initialize immediately — before any component renders
  locale = $state(getInitialLocale());

  init() {
    // Re-read in case called after SSR hydration
    this.locale = getInitialLocale();
  }

  setLocale(locale: string) {
    if (locale === this.locale) return;
    this.locale = locale;
    localStorage.setItem(LS_LOCALE, locale);
  }

  /**
   * Translate a German key. Called by compiled templates.
   * Reads this.locale ($state) so Svelte tracks the dependency.
   */
  $ = (key: string): string => {
    if (this.locale === "de") return key;
    return en[key] ?? key;
  };
}

export const i18n = new I18n();
