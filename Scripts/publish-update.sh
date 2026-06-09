#!/usr/bin/env bash
#
# publish-update.sh — publish a release to GitHub Releases (the default update host).
#
# Uploads the DMG (first install), the Sparkle .zip (update archive), appcast.xml, and the
# SHA-256 sidecars to a `mac-v<version>` release/tag. The Sparkle SUFeedURL points at the
# repo's latest release appcast, so existing installs see the update automatically.
#
# Requires the `gh` CLI authenticated for the Mac repo (set GH_REPO or run inside the repo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(grep -m1 'MARKETING_VERSION' "$ROOT/project.yml" | sed -E 's/.*: *"?([0-9A-Za-z.\-]+)"?.*/\1/')"
TAG="mac-v${VERSION}"
NOTES="$DIST/release-notes-${VERSION}.md"

command -v gh >/dev/null || { echo "✗ GitHub CLI (gh) not installed."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ gh is not authenticated (gh auth login)."; exit 1; }
[ -f "$DIST/appcast.xml" ] || { echo "✗ appcast.xml missing — run generate-appcast.sh first."; exit 1; }

[ -f "$NOTES" ] || printf "# Foundry %s\n\n- Maintenance update.\n" "$VERSION" > "$NOTES"

shopt -s nullglob
ASSETS=( "$DIST"/*.dmg "$DIST"/*.zip "$DIST"/appcast.xml "$DIST"/*.sha256 )

echo "▸ Publishing $TAG with ${#ASSETS[@]} assets…"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "${ASSETS[@]}" --clobber
else
  gh release create "$TAG" "${ASSETS[@]}" --title "Foundry $VERSION" --notes-file "$NOTES"
fi
echo "✓ Published $TAG. Sparkle clients will pick up appcast.xml on their next check."
