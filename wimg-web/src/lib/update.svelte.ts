import { APP_VERSION, RELEASES_URL, IS_BREAKING } from "./version";

const VERSION_KEY = "wimg-last-version";

let showBanner = $state(false);
let sheetOpen = $state(false);
let waitingSW: ServiceWorker | null = $state(null);

function getLastVersion(): string | null {
  return localStorage.getItem(VERSION_KEY);
}

function setLastVersion(version: string) {
  localStorage.setItem(VERSION_KEY, version);
}

function trackWaitingSW(sw: ServiceWorker) {
  waitingSW = sw;
  showBanner = true;
}

export const updateStore = {
  get showBanner() {
    return showBanner;
  },
  get hasBreaking() {
    return IS_BREAKING;
  },
  get targetVersion() {
    return APP_VERSION;
  },
  get releasesUrl() {
    return RELEASES_URL;
  },
  get sheetOpen() {
    return sheetOpen;
  },
  set sheetOpen(v: boolean) {
    sheetOpen = v;
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
