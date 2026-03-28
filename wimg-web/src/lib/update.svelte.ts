import { APP_VERSION, RELEASES_URL, IS_BREAKING } from "./version";
import { LS_LAST_VERSION } from "./config";
import { updated } from "$app/stores";

function getLastVersion(): string | null {
  return localStorage.getItem(LS_LAST_VERSION);
}

function setLastVersion(version: string) {
  localStorage.setItem(LS_LAST_VERSION, version);
}

class UpdateStore {
  #showBanner = $state(false);
  #sheetOpen = $state(false);
  #waitingSW: ServiceWorker | null = $state(null);

  get showBanner() {
    return this.#showBanner;
  }

  get hasBreaking() {
    return IS_BREAKING;
  }

  get targetVersion() {
    return APP_VERSION;
  }

  get releasesUrl() {
    return RELEASES_URL;
  }

  get sheetOpen() {
    return this.#sheetOpen;
  }

  set sheetOpen(v: boolean) {
    this.#sheetOpen = v;
  }

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
        this.#trackWaitingSW(registration.waiting);
      }

      registration.addEventListener("updatefound", () => {
        const installing = registration.installing;
        if (!installing) return;

        installing.addEventListener("statechange", () => {
          if (installing.state === "installed" && navigator.serviceWorker.controller) {
            this.#trackWaitingSW(installing);
          }
        });
      });
    });

    // SvelteKit version polling: detects new deployments every 5 minutes
    // When detected, trigger SW update check so the waiting worker is ready
    updated.subscribe((isUpdated) => {
      if (isUpdated) {
        this.#showBanner = true;
        // Kick SW to check for the new version
        navigator.serviceWorker.ready.then((reg) => reg.update());
      }
    });

    navigator.serviceWorker.addEventListener("controllerchange", () => {
      setLastVersion(APP_VERSION);
      this.#fadeAndReload();
    });
  }

  #trackWaitingSW(sw: ServiceWorker) {
    this.#waitingSW = sw;
    this.#showBanner = true;
  }

  activateUpdate() {
    if (this.#waitingSW) {
      // eslint-disable-next-line unicorn/require-post-message-target-origin -- Worker.postMessage has no targetOrigin
      this.#waitingSW.postMessage({ type: "SKIP_WAITING" });
      return;
    }
    // SvelteKit detected update but SW hasn't installed yet — wait for it
    navigator.serviceWorker.ready.then((reg) => {
      if (reg.waiting) {
        reg.waiting.postMessage({ type: "SKIP_WAITING" });
        return;
      }
      // SW still installing — listen for it to finish
      const installing = reg.installing;
      if (installing) {
        installing.addEventListener("statechange", () => {
          if (installing.state === "installed") {
            installing.postMessage({ type: "SKIP_WAITING" });
          }
        });
        return;
      }
      // Fallback: fade out then reload
      this.#fadeAndReload();
    });
  }

  #fadeAndReload() {
    const overlay = document.createElement("div");
    overlay.style.cssText =
      "position:fixed;inset:0;z-index:9999;background:var(--color-bg,#faf9f6);opacity:0;transition:opacity 300ms ease";
    document.body.appendChild(overlay);
    requestAnimationFrame(() => {
      overlay.style.opacity = "1";
      overlay.addEventListener("transitionend", () => window.location.reload());
      setTimeout(() => window.location.reload(), 400);
    });
  }

  dismiss() {
    this.#showBanner = false;
  }

  async clearData() {
    const root = await navigator.storage.getDirectory();
    await Promise.allSettled(["wimg.db", "e5-small-q8-v7.gguf"].map((n) => root.removeEntry(n)));
  }

  async clearDataAndUpdate() {
    await this.clearData();
    this.activateUpdate();
  }
}

export const updateStore = new UpdateStore();
