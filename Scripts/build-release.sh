#!/usr/bin/env bash
#
# build-release.sh — archive + export Foundry.app for distribution.
#
# Produces a universal (arm64 + x86_64), hardened-runtime app in dist/Foundry.app.
# If a "Developer ID Application" identity is present it signs with it (ready to notarize);
# otherwise it builds an ad-hoc UNSIGNED app and says so (see docs/macos-release.md).
#
# Env:
#   APPLE_TEAM_ID   (optional) team id for Developer ID signing
#   DEVELOPER_DIR   (optional) defaults to /Applications/Xcode.app/Contents/Developer
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SCHEME="Foundry"
CONFIG="Release"
ARCHIVE="$ROOT/build/Foundry.xcarchive"
DIST="$ROOT/dist"
APP="$DIST/Foundry.app"

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*: *"?([0-9A-Za-z.\-]+)"?.*/\1/')"
echo "▸ Foundry $VERSION — release build"

mkdir -p "$DIST" build
rm -rf "$ARCHIVE" "$APP" "$DIST"/Foundry.app

echo "▸ Generating Xcode project…"
xcodegen generate >/dev/null

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)".*/\1/' || true)"

if [[ -n "$SIGN_ID" ]]; then
  echo "▸ Archiving (Developer ID: $SIGN_ID)…"
  xcodebuild archive \
    -project Foundry.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ${APPLE_TEAM_ID:+DEVELOPMENT_TEAM="$APPLE_TEAM_ID"} \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  ${APPLE_TEAM_ID:+<key>teamID</key><string>$APPLE_TEAM_ID</string>}
</dict></plist>
PLIST

  echo "▸ Exporting signed app…"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST" \
    -exportOptionsPlist build/ExportOptions.plist
  echo "✓ Signed app: $APP"
else
  echo "▸ No 'Developer ID Application' identity found — building UNSIGNED (ad-hoc)."
  echo "  This produces an internal build only; notarization is skipped."
  xcodebuild archive \
    -project Foundry.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
  cp -R "$ARCHIVE/Products/Applications/Foundry.app" "$APP"
  echo "✓ Unsigned app: $APP"
fi

# Strip disallowed extended attributes (e.g. com.apple.FinderInfo that the SwiftPM Sparkle
# artifact can carry) so codesign/notarization don't reject the bundle.
xattr -cr "$APP" 2>/dev/null || true

echo "▸ codesign summary:"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|Identifier|Runtime' || true
echo "Done. Next: Scripts/make-dmg.sh"
