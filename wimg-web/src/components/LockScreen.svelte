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

  let pin = $state("");
  let error = $state(false);
  let busy = $state(false);
  let shake = $state(false);
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

  async function append(d: string) {
    if (busy || isCooldown) return;
    if (pin.length >= 6) return;
    pin = pin + d;
    error = false;
    // Submit at 4 minimum on next "Enter" — for now just at 6 like before
    if (pin.length === 6) {
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
</script>

<div class="fixed inset-0 z-100 bg-bg flex flex-col items-center justify-center px-8">
  <!-- Mark -->
  <div class="w-24 h-24 rounded-full bg-accent/20 flex items-center justify-center mb-6">
    <svg class="w-10 h-10 text-(--color-text)/80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8"
        d="M12 11a3 3 0 100-6 3 3 0 000 6zm-6 8a6 6 0 1112 0H6z" />
    </svg>
  </div>

  <h1 class="text-3xl font-display font-black mb-1">wimg</h1>
  {#if isCooldown}
    <p class="text-sm text-rose-600 mb-8">
      Zu viele falsche Versuche. Erneut versuchen in {cooldownSec}s
    </p>
  {:else}
    <p class="text-sm text-text-secondary mb-8">App ist gesperrt</p>
  {/if}

  <!-- PIN dots -->
  <div
    class="flex gap-3 mb-10 transition-transform"
    class:animate-shake={shake}
  >
    {#each Array(6) as _, i}
      {@const cls = error
        ? "bg-rose-500"
        : i < pin.length
          ? "bg-(--color-text)"
          : "bg-(--color-text)/15"}
      <span class="w-3.5 h-3.5 rounded-full transition-colors {cls}"></span>
    {/each}
  </div>

  <!-- Number pad -->
  <div class="grid grid-cols-3 gap-3 w-full max-w-[280px]">
    {#each ["1", "2", "3", "4", "5", "6", "7", "8", "9"] as n}
      <button
        type="button"
        onclick={() => append(n)}
        disabled={busy}
        class="aspect-square rounded-full bg-(--color-card-bg) text-2xl font-display font-semibold active:scale-95 transition-transform disabled:opacity-50"
      >{n}</button>
    {/each}

    <!-- Bottom row: passkey | 0 | backspace -->
    {#if lock.hasPasskey}
      <button
        type="button"
        onclick={tryPasskey}
        disabled={busy}
        aria-label="Mit Face ID / Touch ID entsperren"
        class="aspect-square rounded-full flex items-center justify-center active:scale-95 transition-transform disabled:opacity-50"
      >
        <svg class="w-7 h-7 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6"
            d="M7 11V8a5 5 0 0110 0v3m-9 0a2 2 0 00-2 2v6a2 2 0 002 2h8a2 2 0 002-2v-6a2 2 0 00-2-2H8z" />
        </svg>
      </button>
    {:else}
      <span></span>
    {/if}

    <button
      type="button"
      onclick={() => append("0")}
      disabled={busy}
      class="aspect-square rounded-full bg-(--color-card-bg) text-2xl font-display font-semibold active:scale-95 transition-transform disabled:opacity-50"
    >0</button>

    <button
      type="button"
      onclick={backspace}
      disabled={busy || pin.length === 0}
      aria-label="Löschen"
      class="aspect-square rounded-full flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30"
    >
      <svg class="w-7 h-7 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8"
          d="M3 12l4-7h13a1 1 0 011 1v12a1 1 0 01-1 1H7l-4-7zm7-3l4 6m0-6l-4 6" />
      </svg>
    </button>
  </div>
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
