# How wimg Keeps Your Financial Data Private — A Technical Deep Dive

Most personal finance apps ask you to trust them with your most sensitive data: your bank transactions, your salary, your spending habits. They store it on their servers, pipe it through analytics, and hand it to third-party aggregators who see everything in plaintext.

wimg takes a different approach. Your financial data never leaves your device unless you explicitly choose to sync — and even then, the server only sees ciphertext. No accounts. No passwords. No telemetry. No intermediaries.

This post explains the technical architecture that makes this possible.

---

## 1. Local-First: SQLite Compiled Into the Binary

wimg is built around a single Zig library called **libwimg**. SQLite 3.52.0 is compiled directly into the library as an amalgamation — no external database dependency, no network calls, no ORM layer.

```
libwimg (Zig)
├── sqlite3.c (amalgamation, compiled in)
├── parser.zig    — CSV parsing
├── categories.zig — keyword-based categorization
├── summary.zig   — calculations
├── db.zig        — SQLite wrapper + schema + migrations
└── root.zig      — C ABI exports
```

On **web**, the database lives in [OPFS](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system) (Origin Private File System) — a browser-native storage mechanism that gives SQLite a real file to write to, entirely offline. No IndexedDB hacks, no server round-trips.

On **iOS**, it's a plain SQLite file at `~/Documents/wimg.db`.

The key insight: **the app works with zero network connectivity**. You can import CSV bank statements, categorize transactions, view summaries, track debts, and calculate tax deductions — all without the device ever making a single HTTP request. The network is an enhancement (sync), never a requirement.

Both the web app (compiled to WASM) and the iOS app (linked as a static library) call the exact same C ABI functions:

```zig
export fn wimg_init(db_path: [*:0]const u8) i32
export fn wimg_get_transactions() i32
export fn wimg_set_category(id: [*]const u8, id_len: usize, cat: u8) i32
export fn wimg_get_summary(year: i32, month: i32) i32
```

Same parser. Same categorization logic. Same queries. One codebase. No logic duplication between platforms means no platform-specific data leaks to worry about.

---

## 2. No Accounts, No Passwords, No User Database

There is no sign-up flow. There is no user table. There is no password hash stored anywhere.

When you enable sync, the app generates a UUID:

```
a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

That's your **sync key**. It is simultaneously your identity, your authentication token, and the seed for your encryption key. If you have the sync key, you can access the data. If you don't, nobody can — not even the server operator.

This eliminates entire categories of vulnerabilities:
- No credential database to breach
- No password reset flow to phish
- No session tokens to steal
- No OAuth providers to trust

The trade-off is explicit: lose the sync key, lose access to the synced data. But the canonical copy always lives on your device.

---

## 3. End-to-End Encryption for Sync

When sync is enabled, data flows through Cloudflare Durable Objects and R2 storage. But the server never sees plaintext. Here's the encryption flow:

```
sync_key (UUID)
    │
    ▼
HKDF-SHA256(sync_key, salt="wimg-e2e", info="encryption")
    │
    ▼
256-bit encryption key
    │
    ▼
XChaCha20-Poly1305(plaintext_rows) → ciphertext + nonce + tag
    │
    ▼
POST /sync/:key → Durable Object merges → R2 stores ciphertext
```

**HKDF-SHA256** derives a proper 256-bit key from the sync key. **XChaCha20-Poly1305** provides authenticated encryption — the 24-byte nonce means no nonce reuse concerns even at high sync frequency, and the Poly1305 tag ensures tamper detection.

The sync protocol is row-level, last-write-wins:

```
POST /sync/:key          — push encrypted changed rows
GET  /sync/:key?since=ts — pull rows newer than timestamp
GET  /ws/:key            — WebSocket for real-time sync
```

Each row carries an `updated_at` timestamp. The Durable Object merges by timestamp — whoever saved last wins. This is intentionally simple: one person, two devices. CRDTs would be engineering overhead for a problem that doesn't exist at this scale.

Real-time sync happens over WebSocket with the Hibernation API, so idle connections cost nothing. A change on your phone appears on your laptop within 1–2 seconds. Echo suppression (2-second window after push) prevents a device from applying its own changes back.

What the server stores: `r2://wimg-sync/{sync-key}/changes.json` — one encrypted JSON blob. What the server can read: nothing.

---

## 4. FinTS: Direct Bank Connection, No Intermediary

Most "open banking" apps use PSD2 aggregators (AISPs) like GoCardless, Tink, or finAPI. These services sit between you and your bank. They must decrypt your transaction data to normalize it, categorize merchants, and standardize formats. Your financial history exists in plaintext on their servers.

wimg implements **FinTS 3.0 directly in Zig** — roughly 2,000 lines of protocol engine covering dialog initialization, PIN/TAN authentication, HKKAZ statement fetching, and MT940 parsing. The connection goes straight from the device to the bank's FinTS endpoint:

```
iPhone → (HTTPS) → Bank FinTS Server
                    ↓
              MT940 response
                    ↓
         libwimg parses → SQLite
```

No intermediary. No AISP. No third-party server sees your transactions. The HTTP transport is provided via a C ABI callback — iOS uses `URLSession`, keeping the protocol logic pure Zig while the transport stays platform-native.

This is iOS-only by design: browsers can't make direct FinTS requests due to CORS restrictions. But on native, it means your bank data travels directly from the bank to your device's local database and nowhere else.

For context, here's what the aggregator landscape looks like for German banks:

| Approach | Who sees your data | Cost |
|---|---|---|
| FinTS direct (wimg) | Nobody | Free |
| GoCardless | GoCardless servers | "Free" (you're the funnel) |
| finAPI | finAPI servers | €250+/month |
| Tink (Visa) | Tink servers | Opaque pricing |

PSD2 mandates that AISPs use QWAC/QSealC certificates for authentication and integrity — but not for confidentiality. The data is decrypted on the aggregator's servers. GDPR says minimize data sharing; PSD2 says mandate it. The regulations literally contradict each other.

---

## 5. PII Stripping for AI Features

wimg offers an MCP (Model Context Protocol) server that lets Claude interact with your financial data for analysis. But before any transaction description reaches the AI, it passes through `stripPII()`:

```
Input:  "SEPA ÜBERWEISUNG an Max Mustermann DE89370400440532013000
         BIC COBADEFFXXX Ref: 2026-03-001"

Output: "SEPA ÜBERWEISUNG an [NAME] [IBAN] BIC [BIC] Ref: [REF]"
```

The function removes:
- **IBANs** (DE/AT/CH patterns)
- **Card numbers** (partial or full)
- **BICs** (SWIFT codes)
- **Reference numbers**
- **Personal names** (common patterns in SEPA transactions)

Merchant names are preserved — Claude needs "REWE" or "Deutsche Bahn" to categorize transactions. But your neighbor's name from a shared dinner payment? Stripped.

The MCP server itself runs as a Cloudflare Durable Object with your sync key as Bearer authentication. It loads a compact WASM build of libwimg (53 MB memory budget vs. 209 MB for the web app), decrypts your data from R2, and serves 24 MCP tools. The WASM instance stays warm in the DO for fast subsequent requests.

---

## 6. Zero Telemetry

There is no analytics SDK in wimg. No Google Analytics. No Sentry. No Mixpanel. No Amplitude. No PostHog. No "anonymous" usage tracking.

The DevTools panel (a TanStack-style inspector with WASM call tracing, memory monitoring, sync event logs, and a SQL runner) exists for development. In production builds, the `devtoolsEnabled` boolean is `false`, and the entire panel is tree-shaken out. Zero runtime overhead. You can opt in with `?devtools` in the URL, but that's your choice for your debugging — nothing phones home.

Feature flags are stored in `localStorage` (web) or `UserDefaults` (iOS). They control UI visibility of optional features like debt tracking or tax helpers. They never leave the device.

---

## 7. The Architecture Enables the Privacy

This isn't privacy bolted onto a cloud app. The architecture makes most privacy violations structurally impossible:

- **No server for core features** → no server to breach
- **No user database** → no credentials to steal
- **E2E encryption** → compromised server reveals nothing
- **Direct bank connection** → no intermediary to trust
- **PII stripping** → AI features work without exposing personal data
- **No telemetry** → no behavioral data to sell or leak

The library-as-product approach (inspired by [libghostty](https://github.com/ghostty-org/ghostty)) means the Svelte web app and the SwiftUI iOS app are genuinely thin shells. They render what libwimg returns. The privacy guarantees live in the library, not in the UI layer, so they can't be accidentally bypassed by a frontend change.

The app's UI is in German (it's built for the German banking market — Comdirect, Trade Republic, Scalable Capital), but the architecture principles are universal. Every financial app could work this way. Most choose not to because cloud-first is easier to monetize.

wimg chose differently: your money, your data, your device.

---

*wimg is a local-first personal finance app built with Zig, Svelte 5, and SwiftUI. The sync infrastructure runs on Cloudflare Workers and Durable Objects. FinTS bank connectivity is available on iOS.*
