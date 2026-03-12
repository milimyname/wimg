import { APP_VERSION, RELEASES_URL, IS_BREAKING } from "./version";
import { LS_LAST_VERSION } from "./config";
import { updated } from "$app/stores";

let showBanner = $state(false);
let sheetOpen = $state(false);
let waitingSW: ServiceWorker | null = $state(null);

function getLastVersion(): string | null {
  return localStorage.getItem(LS_LAST_VERSION);
}

function setLastVersion(version: string) {
  localStorage.setItem(LS_LAST_VERSION, version);
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

    // SvelteKit version polling: detects new deployments every 5 minutes
    // When detected, trigger SW update check so the waiting worker is ready
    updated.subscribe((isUpdated) => {
      if (isUpdated) {
        showBanner = true;
        // Kick SW to check for the new version
        navigator.serviceWorker.ready.then((reg) => reg.update());
      }
    });

    navigator.serviceWorker.addEventListener("controllerchange", () => {
      setLastVersion(APP_VERSION);
      // Smooth fade-out before reload to avoid white flash
      const overlay = document.createElement("div");
      overlay.style.cssText =
        "position:fixed;inset:0;z-index:9999;background:var(--color-bg,#faf9f6);opacity:0;transition:opacity 300ms ease";
      document.body.appendChild(overlay);
      requestAnimationFrame(() => {
        overlay.style.opacity = "1";
        overlay.addEventListener("transitionend", () => window.location.reload());
        // Fallback if transition doesn't fire
        setTimeout(() => window.location.reload(), 400);
      });
    });
  },

  activateUpdate() {
    if (!waitingSW) {
      // SvelteKit detected update but SW hasn't installed yet — hard reload
      window.location.reload();
      return;
    }
    // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker.postMessage has no targetOrigin
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
