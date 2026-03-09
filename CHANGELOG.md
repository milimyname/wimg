# Changelog

## v0.5.10 (2026-03-09)

- Implement PII stripping in transaction descriptions and enhance transaction filtering

## v0.5.9 (2026-03-09)

- Refactor notifications and enhance category handling in MCP tools

## v0.5.8 (2026-03-09)

- Update release workflow to use the correct path for WASM artifact in GitHub Actions

## v0.5.7 (2026-03-09)

- Enhance WASM build process and add raw SQL query support

## v0.5.6 (2026-03-09)

- Refactor category handling in MCP tools and enhance input fields in settings

## v0.5.5 (2026-03-09)

- Enhance TransactionCard and AboutView components; add MCP connection guide

## v0.5.4 (2026-03-09)

- Optimize WASM memory management for Cloudflare Workers
- Implement monthly snapshots and data export features

## v0.5.3 (2026-03-08)

- Fix migration configuration in wrangler.toml to use new_sqlite_classes for McpSession

## v0.5.2 (2026-03-08)

- Implement feature flags for enhanced user control

## v0.5.1 (2026-03-08)

- Enhance MCP server functionality and UI updates

## v0.5.0 (2026-03-08)

- Implement recurring pattern detection

## v0.4.26 (2026-03-08)

- Add body overflow control in OnboardingOverlay component

## v0.4.25 (2026-03-08)

- Enhance user experience with onboarding and multi-file CSV import features

## v0.4.24 (2026-03-08)

- Enhance encryption and migration features, update transaction handling

## v0.4.23 (2026-03-08)

- Implement Command Palette and enhance encryption features

## v0.4.22 (2026-03-08)

- Fix minor issues in SettingsView and enhance sync functionality

## v0.4.21 (2026-03-08)

- Implement catch-up mechanism for WebSocket reconnections

## v0.4.20 (2026-03-08)

- Enhance database schema and implement soft-delete functionality

## v0.4.19 (2026-03-08)

- Update wrangler.toml to rename 'new_classes' to 'new_sqlite_classes' for clarity in migration configuration

## v0.4.18 (2026-03-08)

- Refactor release workflow to remove conditional steps for wimg-sync changes

## v0.4.17 (2026-03-08)

- Add Phase 6: Financial Clarity features to CLAUDE.md

## v0.4.16 (2026-03-08)

- Implement real-time sync with Cloudflare Durable Objects and WebSocket support

## v0.4.15 (2026-03-07)

- Refactor release workflow to enhance SQLite handling and streamline deployment

## v0.4.14 (2026-03-06)

- Refactor release workflow to streamline SQLite file handling and improve caching

## v0.4.13 (2026-03-06)

- Enhance release workflow by caching SQLite amalgamation and Zig build artifacts

## v0.4.12 (2026-03-06)

- Refactor API key and URL management to use centralized configuration

## v0.4.11 (2026-03-06)

- Enhance file import functionality and update deployment configuration

## v0.4.10 (2026-03-06)

- Add settings, sync worker, JSON unescape fix, and UI improvements

## v0.4.9 (2026-03-06)

- Update Zig test command in release workflow to remove optimization flag for improved consistency

## v0.4.8 (2026-03-06)

- Refactor release process and enhance service worker caching

## v0.4.7 (2026-03-06)

- Enhance release workflow and script with pre-flight checks and Cloudflare Pages project creation

## v0.4.6 (2026-03-06)

- fix svelte-check: add @types/node, a11y labels, empty CSS rule
- release: v0.4.5
- fix oxfmt formatting

## v0.4.5 (2026-03-06)

- fix oxfmt formatting

## v0.4.4 (2026-03-06)

- add release script, changelog, and fix CI sqlite download
- release: v0.4.3
- add release script and changelog

## v0.4.3 (2026-03-06)

- add release script and changelog

## v0.4.2 (2026-03-06)

- Update lefthook configuration and version numbers for iOS and web projects

## v0.4.1 (2026-03-06)

- phase 4A: pure Zig FinTS client + MT940 parser + CI deploy fix

## v0.4.0 (2026-03-06)

- Fix Cloudflare Pages deployment project name in release workflow
- Add Cloudflare Pages deployment to release workflow and update dependencies
- Friendly Finance UI redesign (web + iOS) + Cloudflare Pages deployment
- add landing page at / using SvelteKit layout groups
- phase 3.5: multi-account support + batch CSV processing + emoji fix
- phase 3 complete: iOS app, build scripts, undo/redo, roadmap update
- phase 2 finale: offline SW, CSV preview, CI, bun migration
- phase 3
- phase 1 done
