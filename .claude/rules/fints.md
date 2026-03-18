# FinTS 3.0 Technical Notes

Purpose: protocol-level reference for `libwimg` FinTS implementation.
Audience: engineers touching `libwimg/src/fints.zig`, `root.zig`, `mt940.zig`.

## Scope

- Native-only FinTS (`iOS`), no WASM transport.
- Protocol implemented in Zig, transport provided by iOS callback (`URLSession`).
- Current verified bank: Comdirect (`BLZ 20041177`).

## End-to-End Flow (Current)

1. Sync init (bootstrap, sec func `999`), parse BPD/UPD/HITANS.
2. Select TAN mechanism from `3920` (prefer two-step, e.g. `902`).
3. Auth init (HKTAN process-4 for `HKIDN` when two-step mode).
4. If challenge:
   - `nochallenge`/empty -> continue automatically.
   - photoTAN/TAN challenge -> return to UI.
5. Fetch statements (`HKKAZ` + process-4 `HKTAN`).
6. If TAN required for fetch:
   - Submit via HKTAN process-2 with `task_reference`.
7. Parse `HIKAZ` response(s), assemble MT940, insert transactions.
8. Follow touchdown pagination via `3040` token until exhaustion.
9. End dialog (`HKEND`), clear sensitive state.

## Critical Wire-Format Rules

- `HNHBK` size must match final message length exactly.
- `dialog_id`/`system_id` must be preserved across recursive `HNVSD` parsing.
- Segment numbering must be contiguous.
- DEG colons in account/group fields must remain structural (`:`), not escaped.
- FinTS binary fields are `@len@<raw-bytes>` and may contain delimiters.
  Parsers must be length-aware, not delimiter-only.
- `HITANS` and `HITAN` must be dispatched separately (`HITANS:` first).

## TAN-Specific Rules

- `HKTAN` process-2 (submit) must include `task_reference` from prior `HITAN`.
- Wrong/missing reference typically yields `9120`/`9110`.
- TAN submit request must still include correct signature footer content
  (`PIN:TAN` shape as required by current envelope/signature builder).
- On successful response with statement payload, clear stale TAN state immediately.

## HKKAZ and Paging

- Use real account connection (from `HIUPD`), not login user id fallback when available.
- `3040` means more data is available and includes continuation (touchdown) token.
- Continue requesting `HKKAZ` with touchdown field until no `3040` token remains.
- Single page often returns around 100 transactions; this is not "all history".

## MT940 Parsing Learnings

- Banks may split `HIKAZ` across multiple segments; concatenate booked streams.
- Normalize parser input:
  - `@@` -> `\r\n`
  - `-0000` -> `+0000`
- Handle mixed line endings (`\n`, `\r\n`, `\r`).
- `:61:` supports optional funds code char after debit/credit marker.
- Parse should tolerate bank-specific variants before classifying payload as invalid.

## Error Code Cheat Sheet (Observed)

- `0020`: request executed / dialog initialized (context dependent).
- `0030`: TAN required.
- `3040`: additional information/continuation available (touchdown).
- `3050`: UPD out of date (usually informational).
- `3060`: warnings present.
- `3076`: strong customer authentication not required.
- `3920`: available TAN methods listed.
- `9010`: order not processed due to general message errors.
- `9050`: message contains errors.
- `9110`: invalid order message / unknown structure.
- `9120`: invalid order message / initialization missing.
- `9800`: dialog aborted.

## Debugging Playbook

When something fails, log all of:

- Outgoing request preview (`auth`, `fetch`, `send_tan`).
- Response code list (`HIRMG`/`HIRMS`) with text.
- `dialog_id`, `system_id`, `msg_num`.
- TAN state (`has_pending_tan`, challenge len, hhduc len, task_reference).
- `HIKAZ` extraction sizes (`mt940_len`, parsed count, parse errors).
- MT940 preview bytes (first 150-200 chars) after extraction.

If a bank says `9110`:

1. Compare failing message against a known-good library (python-fints).
2. Validate envelope size and segment numbering.
3. Validate TAN segment version/arity and mandatory empty placeholders.
4. Verify binary field parsing is not truncating payloads.

## Background Fetch Constraints (iOS)

- Works automatically only when no interactive TAN is needed (`3076`/`nochallenge`).
- If TAN/photoTAN is required, user interaction is mandatory.
- BG tasks are time-limited; multi-page imports can be interrupted.
- Recommended UX:
  - attempt scheduled background fetch,
  - auto-import if no TAN required,
  - persist pending challenge state and notify user if TAN required.
