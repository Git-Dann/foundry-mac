#!/usr/bin/env bash
#
# generate-appcast.sh — produce dist/appcast.xml with EdDSA signatures for the update archives.
#
# Uses Sparkle's own `generate_appcast` (resolved from the SwiftPM checkout). It signs every
# archive in dist/ with the EdDSA private key stored in your login Keychain by `generate_keys`,
# and emits the matching public key — copy that into Info.plist's SUPublicEDKey.
#
# First-time key setup (run ONCE, keep the private key in the Keychain, NEVER commit it):
#   <sparkle>/bin/generate_keys
# CI provides the private key via the SPARKLE_EDDSA_PRIVATE_KEY secret (see the workflow).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
mkdir -p "$DIST"

find_tool() {
  local name="$1"
  # 1) on PATH  2) Sparkle SwiftPM artifacts in DerivedData
  command -v "$name" 2>/dev/null && return 0
  find "${HOME}/Library/Developer/Xcode/DerivedData" -type f -name "$name" 2>/dev/null | head -1
}

GENERATE_APPCAST="$(find_tool generate_appcast || true)"
if [[ -z "${GENERATE_APPCAST:-}" ]]; then
  echo "✗ Sparkle's generate_appcast not found."
  echo "  Build the app once (so SwiftPM resolves Sparkle), or download the Sparkle tools from"
  echo "  https://github.com/sparkle-project/Sparkle/releases and put bin/ on your PATH."
  exit 1
fi
echo "▸ Using: $GENERATE_APPCAST"

# Private key: prefer the Keychain (generate_keys). CI may pass it via env → write a temp file.
KEY_ARGS=()
if [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  TMPKEY="$(mktemp)"; trap 'rm -f "$TMPKEY"' EXIT
  printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$TMPKEY"
  KEY_ARGS=(--ed-key-file "$TMPKEY")
fi

# Sparkle indexes ONE archive per version. The DMG is first-install only, so feed
# generate_appcast just the Sparkle update .zip(s) via a staging dir; the appcast lands in dist/.
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/Git-Dann/foundry-mac/releases/latest/download/}"
STAGE="$DIST/.appcast-staging"
rm -rf "$STAGE"; mkdir -p "$STAGE"
shopt -s nullglob
zips=( "$DIST"/*.zip )
[[ ${#zips[@]} -gt 0 ]] || { echo "✗ No update .zip in $DIST — run make-dmg.sh first."; exit 1; }
cp "${zips[@]}" "$STAGE"/
[[ -f "$DIST/appcast.xml" ]] && cp "$DIST/appcast.xml" "$STAGE"/  # update existing feed if present

echo "▸ Generating appcast from ${#zips[@]} archive(s)…"
"$GENERATE_APPCAST" "${KEY_ARGS[@]}" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$STAGE"

if [[ -f "$STAGE/appcast.xml" ]]; then
  mv "$STAGE/appcast.xml" "$DIST/appcast.xml"
  rm -rf "$STAGE"
  echo "✓ $DIST/appcast.xml"
  echo "▸ Signature entries:"
  grep -o 'sparkle:edSignature="[^"]\{6\}' "$DIST/appcast.xml" | sed 's/$/…/' || true
else
  echo "✗ appcast.xml was not produced."
  exit 1
fi
