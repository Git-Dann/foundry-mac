#!/usr/bin/env bash
# Build Foundry (Release) and install it to /Applications on this Mac.
#
#   Scripts/install-local.sh                  ad-hoc signed; the widget can't read app data
#   TEAM=B27Y4M6S3Y Scripts/install-local.sh  signed with your team (needs your Apple ID in
#                                             Xcode → Settings → Accounts); widget works
#
# The existing /Applications/Foundry.app is moved to the Trash, not deleted.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
DD=build/local
rm -rf "$DD/Build/Products/Release/Foundry.app"

if [ -n "${TEAM:-}" ]; then
  echo "▸ Building Release signed with team $TEAM"
  xcodebuild -project Foundry.xcodeproj -scheme Foundry -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DD" -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" \
    build -quiet
else
  echo "▸ Building Release, signed ad hoc for this Mac"
  xcodebuild -project Foundry.xcodeproj -scheme Foundry -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DD" \
    -xcconfig Scripts/local-adhoc.xcconfig ENABLE_HARDENED_RUNTIME=NO build -quiet
fi

APP="$DD/Build/Products/Release/Foundry.app"
codesign --verify --deep --strict "$APP"

osascript -e 'tell application "Foundry" to quit' >/dev/null 2>&1 || true
sleep 1
if [ -d /Applications/Foundry.app ]; then
  osascript -e 'tell application "Finder" to delete POSIX file "/Applications/Foundry.app"' >/dev/null
  echo "▸ Moved the old Foundry.app to the Trash"
fi
ditto "$APP" /Applications/Foundry.app
echo "▸ Installed $(defaults read /Applications/Foundry.app/Contents/Info CFBundleShortVersionString) to /Applications"
open /Applications/Foundry.app
