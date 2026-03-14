# Release Process

## Quick Release

```bash
# 1. Commit changes (conventional format enforced by lefthook)
git add <files> && git commit -m "feat: add changelog page"

# 2. Release + push
./scripts/release.sh patch --push
```

## What `release.sh` Does

1. Bumps version in `package.json` + `project.yml`
2. Generates `CHANGELOG.md` entry from commits (filters out `release/chore/ci/build`)
3. Commits as `release: v0.5.18`
4. Creates git tag `v0.5.18`
5. With `--push`: pushes code + tag → CI builds + deploys

## Bump Types

```bash
./scripts/release.sh patch          # 0.5.17 → 0.5.18
./scripts/release.sh minor          # 0.5.17 → 0.6.0
./scripts/release.sh major          # 0.5.17 → 1.0.0
./scripts/release.sh 2.0.0          # explicit version
./scripts/release.sh patch --push   # bump + push in one step
```

## Commit Message Format

Enforced by lefthook `commit-msg` hook:

```
type: description
```

| Type       | When                                      |
| ---------- | ----------------------------------------- |
| `feat`     | New feature or functionality              |
| `fix`      | Bug fix                                   |
| `refactor` | Code restructuring, no behavior change    |
| `docs`     | Documentation only                        |
| `style`    | Formatting, no code change                |
| `perf`     | Performance improvement                   |
| `test`     | Adding or fixing tests                    |
| `chore`    | Dependencies, config, tooling             |
| `build`    | Build system changes                      |
| `ci`       | CI/CD pipeline changes                    |

**Filtered from changelog:** `release`, `chore`, `ci`, `build` — these don't appear
in GitHub Releases or the in-app changelog.

**Tip:** Write commit messages for users, not developers. The message becomes the
changelog entry. `feat: add monthly spending chart` reads better than
`feat: implement BarChart component in AnalysisView`.

## CI Pipeline (`.github/workflows/release.yml`)

Triggered on tag push (`v*`):

```
check        → zig fmt, zig test, vp fmt, vp lint, svelte-check, tsc
  ↓
build-web    → WASM build, SvelteKit build, deploy to CF Pages
build-ios    → XCFramework build
deploy-sync  → CF Worker deploy (after web, uses compact WASM)
  ↓
release      → GitHub Release with WASM + XCFramework artifacts
```

## Breaking Releases

If a release includes schema changes that require OPFS clear:

1. Set `IS_BREAKING = true` in `wimg-web/src/lib/version.ts`
2. The UpdateBanner will show a warning and "Daten löschen & aktualisieren" button
3. Reset `IS_BREAKING = false` in the next release
