# Changelog

## v0.6.21 (2026-03-19)

- fix: fetch tags and exclude version-bump files in CI change detection

## v0.6.20 (2026-03-19)

- Version bump

## v0.6.19 (2026-03-19)

- fix: resolve double-tap required for navigation in iOS views

## v0.6.18 (2026-03-19)

- Version bump

## v0.6.17 (2026-03-19)

- fix: map label-only 3920 TAN methods for Comdirect
- perf: debounce search and fix DateFormatter allocation in iOS views
- fix: use Array wrapper for Data in fintsSetTanMedium Swift call
- refactor: rewrite FinTS scripts from Python to Bun, remove one-off tests
- feat: harden FinTS TAN medium flow and bank support tooling
- feat: improve top-bank matrix diagnostics and reporting
- fix: harden touchdown token parsing from 3040 responses
- fix: harden CAMT parsing for multi-Ustrd and currency attribute
- feat: add FinTS decoupled TAN and CAMT fallback support
- feat: improve mobile UX and privacy visibility

## v0.6.16 (2026-03-18)

- docs: add TestFlight guide and auto-reset build number in release.sh

## v0.6.15 (2026-03-18)

- docs: add FinTS technical runbook and phase 6.7 plan
- fix: harden FinTS TAN flow and paginated statement import

## v0.6.14 (2026-03-17)

- fix: CI svelte-check errors — exclude test files, a11y fixes, toSorted

## v0.6.13 (2026-03-17)

- docs: add PSD2/PSD3 banking aggregators research
- fix: FinTS dialog ID extraction from HNHBK response + envelope size test fix
- docs: add FinTS protocol learnings to decisions log and phases
- fix: FinTS protocol — HNHBK size patch, HKIDN DEG, segment numbering, Base64
- fix: FinTS protocol — HNHBK size patch off-by-one, segment numbering, no envelope
- fix: FinTS Base64 newline stripping, HKIDN DEG format, Subsembly bank

## v0.6.12 (2026-03-17)

- refactor: remove DrawerIndent page scale effect

## v0.6.11 (2026-03-17)

- fix: feedback verbose errors, full-height snap, selected icon swap
- docs: update CLAUDE.md with Drawer, feedback, bun test, stacked toasts
- fix: feedback triage OIDC permissions and token rename
- refactor: migrate tests from vitest to bun test
- fix: sheet-active class cleanup and BottomNav fly-in transition
- feat: Sonner-style stacked toasts with hover-to-pause and swipe

## v0.6.10 (2026-03-17)

- feat: drawer test page for stacking validation
- fix: theme-color from blue to app background
- feat: in-app feedback → GitHub Issue with rate limiting
- feat: Drawer component with stacking, indent, and portal support

## v0.6.9 (2026-03-16)

- docs: add Sparquote + Heatmap FAQ entries, update project docs
- feat: spending heatmap on analysis page
- feat: Sparquote savings rate card on dashboard

## v0.6.8 (2026-03-14)

- feat: updated onboarding cards + bank nav link in search
- fix: NaN in iOS donut charts from negative expense amounts
- feat: FinTS HTTP callback + deadlock fix + error messages
- feat: iOS dark mode with theme picker

## v0.6.7 (2026-03-14)

- feat: iOS search nav links + FAQ deep-link scroll
- feat: iOS parity — search tab, advanced filters, FAQ sync
- refactor: align iOS tabs with web — 3 tabs, Analyse in More
- docs: fix feature parity — iOS search already implemented
- fix: goals undo/redo, iOS TaxView compile, vitest in CI
- feat: iOS parity — savings goals, tax helper, net worth chart

## v0.6.6 (2026-03-14)

- feat: add vitest tests, custom tax keywords, and extract tax logic
- docs: update CLAUDE.md and rules for Phase 6.3 completion

## v0.6.5 (2026-03-14)

- feat: add Steuern FAQ entry with palette deep-link
- feat: Phase 6.3 — Anlage N tax helper page

## v0.6.4 (2026-03-14)

- fix: show current release notes when version is latest
- docs: defer Phase 6.1 Annual Review to end of year

## v0.6.3 (2026-03-14)

- feat: add savings goals MCP tools + expand FAQ to 19 entries

## v0.6.2 (2026-03-14)

- feat: expand FAQ to 19 entries with palette deep-links

## v0.6.1 (2026-03-14)

- refactor: remove layerchart, improve changelog and palette UX
- feat: add FAQ and MCP help actions to Command Palette

## v0.6.0 (2026-03-14)

- fix: use toSorted() instead of spread+sort in NetWorthChart
- feat: Phase 6.2 — net worth over time chart in analysis page

## v0.5.23 (2026-03-14)

- feat: Phase 6.4 — savings goals
- refactor: remove standalone renewals page
- fix: recurring patterns persist to OPFS, auto-detect on import
- feat: Phase 5.4 — annual renewals calendar

## v0.5.22 (2026-03-14)

- fix: replace afterNavigate with reactive scroll-to-top

## v0.5.21 (2026-03-14)

- fix: scroll to top on page navigation
- fix: scroll lock on navigation, rename dashboard to home
- fix: recurring cards overflow on mobile
- fix: anomaly cards visible in dark mode
- fix: dashboard avatar circle visible in dark mode
- fix: debts header row-wrap on narrow screens
- fix: compact format for large amounts, overflow prevention
- fix: about page hero icon visible in dark mode
- fix: link device input overflow on mobile
- fix: avatar circle stays dark, emerald privacy card dark mode
- fix: primary buttons (bg-text + text-white) invert in dark mode
- fix: accent buttons always show dark text in dark mode
- fix: accent hero cards readable in dark mode
- fix: donut chart center text overflow with compact format
- fix: Toast countdown ring visibility in dark mode
- fix: dark mode hover and selection states
- fix: unify checkbox toggle style across filter sheet and settings
- fix: dark mode for transaction pills, segmented control, filter sheet
- fix: dark mode checkbox toggle contrast, update docs for Phase 5.7b
- fix: dark mode for BottomSheet, Toast, CommandPalette, alerts
- fix: premium dark mode theme matching fintech design
- feat: Phase 5.7b — command palette refinement

## v0.5.20 (2026-03-14)

- fix: Swift argument order and remove unnecessary await
- fix: UpdateBanner shows all missed releases, analysis back icon, Swift type-check

## v0.5.19 (2026-03-14)

- fix: revert Vite+ migration, restore bun + oxfmt/oxlint

## v0.5.18 (2026-03-14)

- feat: add in-app changelog and migrate to Vite+
- fix changelog

## v0.5.17 (2026-03-14)

- Added Phase 5.11: In-App Changelog with a new `/changelog` page that fetches data from the GitHub Releases API, featuring a timeline UI with version badges and commit descriptions.
- Updated UpdateBanner to show inline changelog and modified "Was ist neu?" links to direct to the new `/changelog`.
- Enhanced localStorage caching for offline access after the first fetch.
- Upgraded GitHub Actions from v4 to v6 for checkout and from v4 to v7/v8 for artifact upload/download, improving workflow stability and performance.
- Refactored data clearing functions to remove both "wimg.db" and "e5-small-q8-v7.gguf" files, ensuring a more comprehensive cleanup.

## v0.5.16 (2026-03-14)

- Enhance categorization and UI components

## v0.5.15 (2026-03-14)

- Refactor categorization and remove embedding functionality

## v0.5.14 (2026-03-12)

- Fix tokenizer: replace greedy BPE with Viterbi for Unigram model

## v0.5.13 (2026-03-10)

- Enhance BottomSheet component with improved wheel and touch handling

## v0.5.12 (2026-03-10)

- Refactor tokenizer tests to use helper functions for state reset

## v0.5.11 (2026-03-10)

- Enhance embedding functionality and update documentation

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
