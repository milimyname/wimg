/**
 * Centralized configuration — all URLs, keys, and constants in one place.
 */

// --- Sync API ---
export const SYNC_API_URL =
  typeof window !== "undefined" && window.location.hostname === "localhost"
    ? "http://localhost:8787"
    : "https://wimg-sync.mili-my.name";

// --- Claude API ---
export const CLAUDE_API_URL = "https://api.anthropic.com/v1/messages";
export const CLAUDE_MODEL = "claude-haiku-4-5-20251001";
export const CLAUDE_BATCH_SIZE = 50;

// --- GitHub ---
export const RELEASES_URL = "https://github.com/milimyname/wimg/releases";

// --- LocalStorage keys ---
export const LS_CLAUDE_API_KEY = "wimg_claude_api_key";
export const LS_SYNC_KEY = "wimg_sync_key";
export const LS_SYNC_LAST_TS = "wimg_sync_last_ts";
export const LS_LAST_VERSION = "wimg-last-version";
