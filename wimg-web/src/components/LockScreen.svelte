<script module lang="ts">
  // Module-scoped flag: only auto-trigger the passkey sheet on the FIRST
  // lock since page load. Subsequent re-mounts (returning to the tab after
  // visibility-change re-lock, manual Cmd+Shift+L) require an explicit
  // fingerprint-button tap.
  // Why: the auto-trigger fires `navigator.credentials.get(...)`, which
  // browser-side credential providers (Bitwarden, 1Password) hook into and
  // pop their own sheet — extremely noisy when the user is just tabbing
  // back and forth. First-load auto-trigger is still useful because the
  // user just opened the app and most likely wants to unlock immediately.
  let autoTriedThisSession = false;
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { lock } from "$lib/lock.svelte";
  import { clearSyncKey } from "$lib/sync";
  import { clearDemoFlag } from "$lib/demo";
  import { LS_ONBOARDING_COMPLETED } from "$lib/config";

  let pin = $state("");
  let error = $state(false);
  let busy = $state(false);
  let shake = $state(false);
  let forgotMode = $state(false);
  let resetting = $state(false);
  // Trigger reactive ticks so the cooldown countdown updates each second
  // even though `lock.cooldownSecondsRemaining` is a getter on Date.now().
  let tick = $state(0);
  let cooldownInterval: ReturnType<typeof setInterval> | null = null;

  let cooldownSec = $derived.by(() => {
    void tick; // depend on the ticker
    return lock.cooldownSecondsRemaining;
  });
  let isCooldown = $derived(cooldownSec > 0);

  onMount(() => {
    cooldownInterval = setInterval(() => {
      tick++;
    }, 1000);

    // Lock body scroll so the underlying app can't be scrolled past the
    // overlay (rubber-band on iOS, arrow-keys / spacebar on desktop).
    const prevOverflow = document.body.style.overflow;
    const prevOverscroll = document.body.style.overscrollBehavior;
    document.body.style.overflow = "hidden";
    document.body.style.overscrollBehavior = "contain";

    // If a passkey is registered AND this is the first lock since page load,
    // prompt the biometric sheet automatically so the user doesn't have to
    // tap the fingerprint button. Cancellation falls through silently — the
    // PIN pad stays available. Re-locks within the same session require an
    // explicit tap (see autoTriedThisSession above).
    if (lock.hasPasskey && !isCooldown && !autoTriedThisSession) {
      autoTriedThisSession = true;
      // Defer one frame so the DOM is painted before the OS sheet appears.
      requestAnimationFrame(() => {
        if (!busy && !isCooldown) void autoTryPasskey();
      });
    }

    // Physical keyboard input — digits append, Backspace deletes, Enter
    // tries the passkey when no PIN typed yet (banking-app convention).
    const onKey = (e: KeyboardEvent) => {
      if (busy || isCooldown) return;
      // Don't swallow modifier shortcuts (Cmd+R, Ctrl+L, etc.).
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key >= "0" && e.key <= "9") {
        e.preventDefault();
        void append(e.key);
      } else if (e.key === "Backspace" || e.key === "Delete") {
        e.preventDefault();
        backspace();
      } else if (e.key === "Enter" && lock.hasPasskey && pin.length === 0) {
        e.preventDefault();
        void tryPasskey();
      }
    };
    window.addEventListener("keydown", onKey);

    return () => {
      if (cooldownInterval) clearInterval(cooldownInterval);
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
      document.body.style.overscrollBehavior = prevOverscroll;
    };
  });

  // iOS-style fixed 4-digit PIN. The lock store still accepts variable
  // length, but new setups are constrained to 4 digits in the Settings
  // wizard so this matches.
  const PIN_LEN = 4;

  async function append(d: string) {
    if (busy || isCooldown) return;
    if (pin.length >= PIN_LEN) return;
    pin = pin + d;
    error = false;
    if (pin.length === PIN_LEN) {
      busy = true;
      const ok = await lock.verifyPin(pin);
      if (!ok) {
        error = true;
        shake = true;
        setTimeout(() => {
          pin = "";
          shake = false;
        }, 350);
      }
      busy = false;
    }
  }

  function backspace() {
    if (busy || isCooldown) return;
    pin = pin.slice(0, -1);
    error = false;
  }

  async function tryPasskey() {
    if (busy || isCooldown) return;
    busy = true;
    const ok = await lock.verifyPasskey();
    if (!ok) error = true;
    busy = false;
  }

  // Like tryPasskey but quiet on cancel — used by the on-mount auto-prompt
  // where a "Cancel" tap shouldn't flash the red error state at the user.
  async function autoTryPasskey() {
    if (busy || isCooldown) return;
    busy = true;
    await lock.verifyPasskey();
    busy = false;
  }

  // PIN-forgotten escape hatch. The lock gates the UI but doesn't encrypt
  // OPFS, so the only honest "reset" is a factory wipe: clear local DB +
  // sync key + onboarding flags, then reload. Sync users can re-link by
  // entering their sync key again; non-sync users start fresh. Mirrors the
  // Settings → Danger Zone reset so the lock has the same teeth either way.
  async function handleReset() {
    if (resetting) return;
    resetting = true;
    try {
      const root = await navigator.storage.getDirectory();
      await root.removeEntry("wimg.db").catch(() => {});
      lock.disable();
      clearSyncKey();
      localStorage.removeItem("wimg_sync_last_ts");
      clearDemoFlag();
      localStorage.removeItem(LS_ONBOARDING_COMPLETED);
      window.location.reload();
    } catch {
      resetting = false;
    }
  }
</script>

<div class="fixed inset-0 z-100 bg-(--color-bg) flex flex-col items-center justify-center px-6">
  <!-- Brand mark -->
  <div class="mb-8 flex flex-col items-center">
    <h1 class="text-4xl font-display font-black tracking-tight text-(--color-text)">wimg</h1>
    {#if forgotMode}
      <p class="mt-1.5 text-xs font-medium text-(--color-text-secondary)">
        PIN zurücksetzen
      </p>
    {:else if isCooldown}
      <p class="mt-1.5 text-xs font-medium text-rose-600">
        Zu viele falsche Versuche · {cooldownSec}s
      </p>
    {:else}
      <p class="mt-1.5 text-xs font-medium text-(--color-text-secondary)">
        PIN eingeben
      </p>
    {/if}
  </div>

  {#if forgotMode}
    <!-- Reset confirmation — replaces the keypad. -->
    <div class="w-full max-w-[320px] flex flex-col items-center">
      <div class="w-14 h-14 rounded-full bg-rose-500/10 flex items-center justify-center mb-4">
        <svg class="w-7 h-7 text-rose-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z" />
        </svg>
      </div>
      <h2 class="font-display font-extrabold text-lg text-(--color-text) text-center mb-1.5">
        Alle Daten löschen?
      </h2>
      <p class="text-[13px] leading-relaxed text-(--color-text-secondary) text-center mb-6">
        Die PIN lässt sich nicht wiederherstellen. Beim Zurücksetzen werden
        alle lokalen Daten gelöscht. Falls Sync aktiv war, kannst du deine
        Daten anschließend mit dem Sync-Schlüssel wiederherstellen.
      </p>

      <button
        type="button"
        onclick={handleReset}
        disabled={resetting}
        class="w-full py-3.5 rounded-2xl bg-rose-600 text-white font-bold text-sm transition-transform active:scale-[0.98] disabled:opacity-60 mb-2"
      >
        {resetting ? "Lösche…" : "Ja, alles löschen"}
      </button>
      <button
        type="button"
        onclick={() => (forgotMode = false)}
        disabled={resetting}
        class="w-full py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) hover:bg-(--color-text)/[0.06] transition-colors disabled:opacity-50"
      >
        Abbrechen
      </button>
    </div>
  {:else}

  <!-- PIN dots — iOS-style: ring when empty, filled when active -->
  <div
    class="flex gap-5 mb-12 transition-transform"
    class:animate-shake={shake}
  >
    {#each Array(PIN_LEN) as _, i}
      {@const filled = i < pin.length}
      <span
        class="w-3.5 h-3.5 rounded-full transition-all duration-150
          {error
            ? 'bg-rose-500 border-rose-500'
            : filled
              ? 'bg-(--color-text) border-(--color-text)'
              : 'bg-transparent border-(--color-text)/35'}
          border-[1.5px]"
      ></span>
    {/each}
  </div>

  <!-- Number pad — iOS layout: 3-col grid, large round buttons, subtle press -->
  <div class="grid grid-cols-3 gap-x-6 gap-y-4 w-full max-w-[260px]">
    {#each ["1", "2", "3", "4", "5", "6", "7", "8", "9"] as n}
      <button
        type="button"
        onclick={() => append(n)}
        disabled={busy}
        class="aspect-square rounded-full bg-(--color-text)/[0.06] hover:bg-(--color-text)/[0.10] active:bg-(--color-text)/[0.14] text-[28px] font-display font-light text-(--color-text) active:scale-[0.96] transition-all duration-100 disabled:opacity-50"
      >{n}</button>
    {/each}

    <!-- Bottom row: passkey | 0 | backspace -->
    {#if lock.hasPasskey}
      <button
        type="button"
        onclick={tryPasskey}
        disabled={busy}
        aria-label="Mit Face ID / Touch ID entsperren"
        class="aspect-square rounded-full flex items-center justify-center active:bg-(--color-text)/[0.08] transition-colors duration-100 disabled:opacity-50"
      >
        <svg class="w-7 h-7 text-(--color-text)" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round"
            d="M12 11v2m-5.5-6a5.5 5.5 0 0111 0M5 11v5a3 3 0 003 3h8a3 3 0 003-3v-5a3 3 0 00-3-3H8a3 3 0 00-3 3z" />
        </svg>
      </button>
    {:else}
      <span></span>
    {/if}

    <button
      type="button"
      onclick={() => append("0")}
      disabled={busy}
      class="aspect-square rounded-full bg-(--color-text)/[0.06] hover:bg-(--color-text)/[0.10] active:bg-(--color-text)/[0.14] text-[28px] font-display font-light text-(--color-text) active:scale-[0.96] transition-all duration-100 disabled:opacity-50"
    >0</button>

    <button
      type="button"
      onclick={backspace}
      disabled={busy || pin.length === 0}
      aria-label="Löschen"
      class="aspect-square rounded-full flex items-center justify-center active:bg-(--color-text)/[0.08] transition-colors duration-100 disabled:opacity-30"
    >
      <svg class="w-7 h-7 text-(--color-text)" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round"
          d="M22 6a2 2 0 00-2-2H10l-7 8 7 8h10a2 2 0 002-2V6zM18 9l-5 6m0-6l5 6" />
      </svg>
    </button>
  </div>

  <button
    type="button"
    onclick={() => (forgotMode = true)}
    disabled={busy}
    class="mt-8 text-xs font-medium text-(--color-text-secondary) hover:text-(--color-text) transition-colors disabled:opacity-50"
  >
    PIN vergessen?
  </button>
  {/if}
</div>

<style>
  @keyframes shake {
    0%, 100% { transform: translateX(0); }
    25% { transform: translateX(-8px); }
    50% { transform: translateX(8px); }
    75% { transform: translateX(-4px); }
  }
  :global(.animate-shake) {
    animation: shake 0.35s ease-in-out;
  }
</style>
