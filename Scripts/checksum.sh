#!/usr/bin/env bash
#
# checksum.sh — write SHA-256 sidecar files for every artifact in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
cd "$DIST"

shopt -s nullglob
artifacts=( *.dmg *.zip )
if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "✗ No artifacts in $DIST — run build-release.sh + make-dmg.sh first."
  exit 1
fi

for f in "${artifacts[@]}"; do
  shasum -a 256 "$f" | tee "$f.sha256"
done
echo "✓ Checksums written to $DIST/*.sha256"
