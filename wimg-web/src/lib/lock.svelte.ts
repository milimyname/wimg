/**
 * App-lock store — web equivalent of iOS/Android biometric lock.
 *
 * Two layers:
 * 1. PIN gate. Hash with PBKDF2-SHA256 (100k iterations) and store the hash
 *    + salt in localStorage. Unlock state in sessionStorage so closing the
 *    tab re-locks.
 * 2. Optional WebAuthn passkey on top. After PIN is set, the user can
 *    enroll a passkey which fires Face ID / Touch ID / Windows Hello via
 *    the OS keystore on subsequent unlocks. Skipped if the browser /
 *    device doesn't expose `userVerification: 'required'`.
 *
 * Browsers have no equivalent to iOS scenePhase or Android FLAG_SECURE.
 * The closest is `visibilitychange` — handled separately by
 * `PrivacyOverlay.svelte`. Combined, this matches the native UX as far
 * as the web sandbox allows.
 */

const PIN_HASH_KEY = "wimg_pin_hash";
const PIN_SALT_KEY = "wimg_pin_salt";
const PASSKEY_ID_KEY = "wimg_passkey_id";
const UNLOCKED_KEY = "wimg_unlocked";
const AUTOLOCK_MINUTES_KEY = "wimg_autolock_minutes";
const FAIL_COUNT_KEY = "wimg_lock_fail_count";
const COOLDOWN_UNTIL_KEY = "wimg_lock_cooldown_until";

/** Auto-lock options shown in Settings. 0 = never. */
export const AUTOLOCK_OPTIONS = [0, 1, 5, 15, 60] as const;
export type AutoLockMinutes = (typeof AUTOLOCK_OPTIONS)[number];

/** Wrong-PIN attempts before the first cooldown. */
const FAIL_THRESHOLD = 5;
/** Base cooldown in ms — doubles every additional FAIL_THRESHOLD attempts. */
const BASE_COOLDOWN_MS = 30_000;

class LockStore {
  #locked = $state(false);
  #pinHash = $state<string | null>(null);
  #salt = $state<string | null>(null);
  #passkeyId = $state<string | null>(null);
  #ready = $state(false);
  #autoLockMinutes = $state<AutoLockMinutes>(5);
  #failCount = $state(0);
  #cooldownUntil = $state(0);
  #idleTimer: ReturnType<typeof setTimeout> | null = null;
  /** Unix ms when the current idle timer was armed. 0 if no timer active. */
  #idleArmedAt = $state(0);

  /** True when the gate is up and the main UI should be hidden. */
  get isLocked(): boolean {
    return this.#locked;
  }

  /** True when the user has configured a PIN. */
  get isEnabled(): boolean {
    return this.#pinHash !== null;
  }

  /** True when a passkey is registered (biometric unlock available). */
  get hasPasskey(): boolean {
    return this.#passkeyId !== null;
  }

  /** Browser supports WebAuthn with userVerification. */
  get supportsPasskey(): boolean {
    return typeof window !== "undefined" && typeof window.PublicKeyCredential !== "undefined";
  }

  /** Hydrated from storage — UI shouldn't render until this is true. */
  get isReady(): boolean {
    return this.#ready;
  }

  /** Current auto-lock setting (minutes). 0 = never. */
  get autoLockMinutes(): AutoLockMinutes {
    return this.#autoLockMinutes;
  }

  /** Unix ms timestamp when cooldown ends. 0 if not in cooldown. */
  get cooldownUntil(): number {
    return this.#cooldownUntil;
  }

  /** True if a wrong-PIN cooldown is currently active. */
  get isCooldownActive(): boolean {
    return Date.now() < this.#cooldownUntil;
  }

  /** Remaining seconds in the current cooldown, rounded up. */
  get cooldownSecondsRemaining(): number {
    const ms = this.#cooldownUntil - Date.now();
    return ms > 0 ? Math.ceil(ms / 1000) : 0;
  }

  /** Wrong-PIN attempts since last successful unlock. */
  get failCount(): number {
    return this.#failCount;
  }

  /** Read from storage on first client call. SSR-safe (no-op on server). */
  hydrate() {
    if (typeof localStorage === "undefined") return;
    this.#pinHash = localStorage.getItem(PIN_HASH_KEY);
    this.#salt = localStorage.getItem(PIN_SALT_KEY);
    this.#passkeyId = localStorage.getItem(PASSKEY_ID_KEY);
    const minutes = Number(localStorage.getItem(AUTOLOCK_MINUTES_KEY) ?? "5");
    this.#autoLockMinutes = (AUTOLOCK_OPTIONS as readonly number[]).includes(minutes)
      ? (minutes as AutoLockMinutes)
      : 5;
    this.#failCount = Number(localStorage.getItem(FAIL_COUNT_KEY) ?? "0");
    this.#cooldownUntil = Number(localStorage.getItem(COOLDOWN_UNTIL_KEY) ?? "0");
    // Locked on cold load if enabled and not already unlocked this session.
    const unlocked = sessionStorage.getItem(UNLOCKED_KEY) === "1";
    this.#locked = this.isEnabled && !unlocked;
    this.#ready = true;
  }

  /** Create or replace the PIN. Engages the lock immediately. */
  async setupPin(pin: string): Promise<void> {
    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    const hash = await this.#hashPin(pin, saltBytes);
    const saltStr = b64encode(saltBytes);
    localStorage.setItem(PIN_HASH_KEY, hash);
    localStorage.setItem(PIN_SALT_KEY, saltStr);
    this.#pinHash = hash;
    this.#salt = saltStr;
    this.#locked = true;
    sessionStorage.removeItem(UNLOCKED_KEY);
  }

  async verifyPin(pin: string): Promise<boolean> {
    if (!this.#pinHash || !this.#salt) return false;
    if (this.isCooldownActive) return false;
    const saltBytes = b64decode(this.#salt);
    const candidate = await this.#hashPin(pin, saltBytes);
    if (candidate !== this.#pinHash) {
      this.#registerFailedAttempt();
      return false;
    }
    this.#clearFailedAttempts();
    this.#unlock();
    return true;
  }

  /** Register a discoverable WebAuthn credential bound to this device. */
  async enablePasskey(): Promise<boolean> {
    if (!this.supportsPasskey) return false;
    try {
      const cred = await navigator.credentials.create({
        publicKey: {
          rp: { name: "wimg" },
          user: {
            id: crypto.getRandomValues(new Uint8Array(16)),
            name: "wimg",
            displayName: "wimg user",
          },
          pubKeyCredParams: [
            { type: "public-key", alg: -7 }, // ES256
            { type: "public-key", alg: -257 }, // RS256
          ],
          authenticatorSelection: {
            userVerification: "required",
            residentKey: "preferred",
          },
          challenge: crypto.getRandomValues(new Uint8Array(32)),
          timeout: 60_000,
        },
      });
      if (!cred) return false;
      // We don't validate the attestation server-side (no server). Storing
      // the credential ID gives us something to require by allowCredentials
      // on subsequent get() calls.
      const id = b64encode(new Uint8Array((cred as PublicKeyCredential).rawId));
      localStorage.setItem(PASSKEY_ID_KEY, id);
      this.#passkeyId = id;
      return true;
    } catch {
      return false;
    }
  }

  /** Verify the passkey — fires Face ID / Touch ID / Windows Hello. */
  async verifyPasskey(): Promise<boolean> {
    if (!this.#passkeyId || !this.supportsPasskey) return false;
    if (this.isCooldownActive) return false;
    try {
      const allowCredentials: PublicKeyCredentialDescriptor[] = [
        {
          type: "public-key",
          id: b64decode(this.#passkeyId).buffer as ArrayBuffer,
        },
      ];
      const got = await navigator.credentials.get({
        publicKey: {
          challenge: crypto.getRandomValues(new Uint8Array(32)),
          allowCredentials,
          userVerification: "required",
          timeout: 60_000,
        },
      });
      if (!got) return false;
      this.#clearFailedAttempts();
      this.#unlock();
      return true;
    } catch {
      return false;
    }
  }

  /** Update the idle auto-lock setting (persisted). */
  setAutoLockMinutes(minutes: AutoLockMinutes) {
    this.#autoLockMinutes = minutes;
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(AUTOLOCK_MINUTES_KEY, String(minutes));
    }
    this.armIdleTimer();
  }

  /**
   * Reset the idle timer. Wire this to user-activity events
   * (pointerdown, keydown) from the app shell.
   */
  armIdleTimer() {
    if (this.#idleTimer) {
      clearTimeout(this.#idleTimer);
      this.#idleTimer = null;
    }
    this.#idleArmedAt = 0;
    if (!this.isEnabled || this.#locked || this.#autoLockMinutes === 0) return;
    this.#idleArmedAt = Date.now();
    this.#idleTimer = setTimeout(() => this.lockNow(), this.#autoLockMinutes * 60_000);
  }

  /**
   * Seconds until the idle timer fires. Returns 0 when no timer is armed
   * (lock disabled, already locked, or "never" auto-lock). Read once per
   * second from a ticker — relies on Date.now() not on a Svelte state for
   * the countdown itself.
   */
  get idleSecondsRemaining(): number {
    if (this.#idleArmedAt === 0) return 0;
    const elapsedMs = Date.now() - this.#idleArmedAt;
    const totalMs = this.#autoLockMinutes * 60_000;
    const remaining = Math.ceil((totalMs - elapsedMs) / 1000);
    return remaining > 0 ? remaining : 0;
  }

  /** Tear everything down. */
  disable() {
    localStorage.removeItem(PIN_HASH_KEY);
    localStorage.removeItem(PIN_SALT_KEY);
    localStorage.removeItem(PASSKEY_ID_KEY);
    localStorage.removeItem(FAIL_COUNT_KEY);
    localStorage.removeItem(COOLDOWN_UNTIL_KEY);
    sessionStorage.removeItem(UNLOCKED_KEY);
    this.#pinHash = null;
    this.#salt = null;
    this.#passkeyId = null;
    this.#locked = false;
    this.#failCount = 0;
    this.#cooldownUntil = 0;
    if (this.#idleTimer) {
      clearTimeout(this.#idleTimer);
      this.#idleTimer = null;
    }
  }

  /** Drop just the passkey without disabling the PIN. */
  removePasskey() {
    localStorage.removeItem(PASSKEY_ID_KEY);
    this.#passkeyId = null;
  }

  /** Manually re-engage the lock (used by the "Sperren" menu action). */
  lockNow() {
    if (this.isEnabled) {
      this.#locked = true;
      sessionStorage.removeItem(UNLOCKED_KEY);
    }
  }

  #unlock() {
    this.#locked = false;
    sessionStorage.setItem(UNLOCKED_KEY, "1");
    this.armIdleTimer();
  }

  /**
   * Penalize a wrong PIN. Every FAIL_THRESHOLD attempts, double the
   * cooldown — 30 s → 60 s → 120 s and so on. Counters persist in
   * localStorage so closing the tab doesn't reset the penalty.
   */
  #registerFailedAttempt() {
    this.#failCount += 1;
    localStorage.setItem(FAIL_COUNT_KEY, String(this.#failCount));
    if (this.#failCount > 0 && this.#failCount % FAIL_THRESHOLD === 0) {
      const tier = Math.floor(this.#failCount / FAIL_THRESHOLD) - 1;
      const ms = BASE_COOLDOWN_MS * Math.pow(2, tier);
      this.#cooldownUntil = Date.now() + ms;
      localStorage.setItem(COOLDOWN_UNTIL_KEY, String(this.#cooldownUntil));
    }
  }

  #clearFailedAttempts() {
    this.#failCount = 0;
    this.#cooldownUntil = 0;
    localStorage.removeItem(FAIL_COUNT_KEY);
    localStorage.removeItem(COOLDOWN_UNTIL_KEY);
  }

  async #hashPin(pin: string, salt: Uint8Array): Promise<string> {
    const enc = new TextEncoder();
    const keyMaterial = await crypto.subtle.importKey(
      "raw",
      enc.encode(pin),
      { name: "PBKDF2" },
      false,
      ["deriveBits"],
    );
    const bits = await crypto.subtle.deriveBits(
      { name: "PBKDF2", salt: salt as BufferSource, iterations: 100_000, hash: "SHA-256" },
      keyMaterial,
      256,
    );
    return b64encode(new Uint8Array(bits));
  }
}

function b64encode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function b64decode(s: string): Uint8Array {
  const raw = atob(s);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

export const lock = new LockStore();
