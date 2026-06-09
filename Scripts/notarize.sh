#!/usr/bin/env bash
#
# notarize.sh — submit the DMG to Apple's notary service, then staple + verify.
#
# Credentials (either a stored notarytool profile OR Apple ID env vars):
#   NOTARY_PROFILE                          name of a `xcrun notarytool store-credentials` profile
#   — or —
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
#
# Usage: Scripts/notarize.sh [path-to-dmg]   (defaults to the newest dist/*.dmg)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DMG="${1:-$(ls -t "$ROOT"/dist/*.dmg 2>/dev/null | head -1 || true)}"
[ -n "${DMG:-}" ] && [ -f "$DMG" ] || { echo "✗ No DMG found. Run make-dmg.sh first."; exit 1; }

if [[ "$DMG" == *unsigned-internal* ]]; then
  echo "✗ $DMG is an UNSIGNED internal build and cannot be notarized."
  echo "  Provide a Developer ID Application certificate, rebuild, then retry."
  exit 1
fi

# Build the notarytool auth args from whichever credentials are present.
AUTH=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
else
  echo "✗ Notarization credentials missing."
  echo "  Set NOTARY_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD."
  exit 1
fi

echo "▸ Submitting $DMG to notary service…"
xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait

echo "▸ Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "▸ Gatekeeper assessment:"
spctl -a -vv -t open --context context:primary-signature "$DMG" || true
echo "✓ Notarized + stapled: $DMG"
