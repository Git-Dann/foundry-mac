#!/usr/bin/env bash
#
# make-dmg.sh — package dist/Foundry.app into:
#   • a first-install DMG (with an /Applications drop target)
#   • a Sparkle update .zip
#
# DMG name: Foundry-<version>-universal.dmg              (signed)
#           Foundry-<version>-universal-unsigned-internal.dmg  (unsigned)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="$ROOT/dist"
APP="$DIST/Foundry.app"
ARCH="universal"

[ -d "$APP" ] || { echo "✗ $APP not found — run Scripts/build-release.sh first."; exit 1; }

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*: *"?([0-9A-Za-z.\-]+)"?.*/\1/')"

if codesign -dvv "$APP" 2>&1 | grep -q 'Developer ID Application'; then
  SUFFIX=""
else
  SUFFIX="-unsigned-internal"
  echo "▸ App is not Developer ID signed — naming the DMG as an internal build."
fi

DMG="$DIST/Foundry-${VERSION}-${ARCH}${SUFFIX}.dmg"
ZIP="$DIST/Foundry-${VERSION}-${ARCH}.zip"

echo "▸ Building Sparkle update zip…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ $ZIP"

echo "▸ Building DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Foundry.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Foundry" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ $DMG"

echo "Done. Next: Scripts/checksum.sh  (and Scripts/notarize.sh for signed builds)"
