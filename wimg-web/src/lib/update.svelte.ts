import { APP_VERSION, CHANGELOG } from "./version";
import type { ChangelogEntry } from "./version";

const VERSION_KEY = "wimg-last-version";

let showBanner = $state(false);
let waitingSW: ServiceWorker | null = $state(null);
let newEntries: ChangelogEntry[] = $state([]);
let hasBreaking = $state(false);

function getLastVersion(): string | null {
  return localStorage.getItem(VERSION_KEY);
}

function setLastVersion(version: string) {
  localStorage.setItem(VERSION_KEY, version);
}

function getNewEntries(lastVersion: string | null): ChangelogEntry[] {
  if (!lastVersion) return [];
  return CHANGELOG.filter((entry) => entry.version > lastVersion);
}

function trackWaitingSW(sw: ServiceWorker) {
  waitingSW = sw;
  const entries = getNewEntries(getLastVersion());
  newEntries = entries.length > 0 ? entries : CHANGELOG.slice(0, 1);
  hasBreaking = newEntries.some((e) => e.breaking);
  showBanner = true;
}

export const updateStore = {
  get showBanner() {
    return showBanner;
  },
  get newEntries() {
    return newEntries;
  },
  get hasBreaking() {
    return hasBreaking;
  },
  get targetVersion() {
    return APP_VERSION;
  },

  init() {
    if (typeof window === "undefined" || !("serviceWorker" in navigator)) {
      return;
    }

    const lastVersion = getLastVersion();
    if (!lastVersion) {
      setLastVersion(APP_VERSION);
    }

    navigator.serviceWorker.ready.then((registration) => {
      if (registration.waiting) {
        trackWaitingSW(registration.waiting);
      }

      registration.addEventListener("updatefound", () => {
        const installing = registration.installing;
        if (!installing) return;

        installing.addEventListener("statechange", () => {
          if (installing.state === "installed" && navigator.serviceWorker.controller) {
            trackWaitingSW(installing);
          }
        });
      });
    });

    navigator.serviceWorker.addEventListener("controllerchange", () => {
      setLastVersion(APP_VERSION);
      window.location.reload();
    });
  },

  activateUpdate() {
    if (!waitingSW) return;
    waitingSW.postMessage({ type: "SKIP_WAITING" });
  },

  dismiss() {
    showBanner = false;
  },

  async clearData() {
    const root = await navigator.storage.getDirectory();
    try {
      await root.removeEntry("wimg.db");
    } catch {
      // File may not exist
    }
  },

  async clearDataAndUpdate() {
    await updateStore.clearData();
    updateStore.activateUpdate();
  },
};
