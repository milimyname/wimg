#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/wimg-web/package.json"
YML="$ROOT/wimg-ios/project.yml"
CHANGELOG="$ROOT/CHANGELOG.md"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "error: $1" >&2; exit 1; }

usage() {
  echo "Usage: $0 <patch|minor|major|X.Y.Z>"
  echo ""
  echo "Examples:"
  echo "  $0 patch   # 0.4.2 → 0.4.3"
  echo "  $0 minor   # 0.4.2 → 0.5.0"
  echo "  $0 major   # 0.4.2 → 1.0.0"
  echo "  $0 1.0.0   # explicit version"
  exit 1
}

current_version() {
  grep '"version"' "$PKG" | head -1 | sed 's/.*"\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/'
}

bump_version() {
  local cur="$1" type="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$cur"

  case "$type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *)     die "unknown bump type: $type" ;;
  esac
}

# ── args ─────────────────────────────────────────────────────────────────────

[[ $# -eq 1 ]] || usage

OLD=$(current_version)
[[ -n "$OLD" ]] || die "could not read version from $PKG"

case "$1" in
  patch|minor|major) NEW=$(bump_version "$OLD" "$1") ;;
  [0-9]*.[0-9]*.[0-9]*) NEW="$1" ;;
  *) usage ;;
esac

[[ "$OLD" != "$NEW" ]] || die "new version ($NEW) is same as current ($OLD)"

echo "Bumping $OLD → $NEW"

# ── update package.json ──────────────────────────────────────────────────────

sed -i '' "s/\"version\": \"$OLD\"/\"version\": \"$NEW\"/" "$PKG"
echo "  updated $PKG"

# ── update project.yml ───────────────────────────────────────────────────────

sed -i '' "s/MARKETING_VERSION: \"$OLD\"/MARKETING_VERSION: \"$NEW\"/" "$YML"
echo "  updated $YML"

# ── generate changelog entry ─────────────────────────────────────────────────

PREV_TAG=$(git tag -l --sort=-v:refname | head -1 2>/dev/null || true)
DATE=$(date +%Y-%m-%d)

if [[ -n "$PREV_TAG" ]]; then
  COMMITS=$(git log --pretty=format:"- %s" --no-merges "$PREV_TAG"..HEAD)
else
  COMMITS=$(git log --pretty=format:"- %s" --no-merges)
fi

if [[ -z "$COMMITS" ]]; then
  COMMITS="- Version bump"
fi

ENTRY="## v${NEW} (${DATE})

${COMMITS}"

if [[ -f "$CHANGELOG" ]]; then
  # insert new entry after the first line (# Changelog)
  TMPFILE=$(mktemp)
  head -1 "$CHANGELOG" > "$TMPFILE"
  echo "" >> "$TMPFILE"
  echo "$ENTRY" >> "$TMPFILE"
  tail -n +2 "$CHANGELOG" >> "$TMPFILE"
  mv "$TMPFILE" "$CHANGELOG"
else
  cat > "$CHANGELOG" <<EOF
# Changelog

$ENTRY
EOF
fi

echo "  updated $CHANGELOG"

# ── commit + tag ─────────────────────────────────────────────────────────────

git add "$PKG" "$YML" "$CHANGELOG"
git commit -m "release: v${NEW}"
git tag "v${NEW}"

echo ""
echo "Done! Created commit and tag v${NEW}."
echo ""
echo "To publish:"
echo "  git push && git push origin v${NEW}"
