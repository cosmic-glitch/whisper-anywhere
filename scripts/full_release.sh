#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DMG="$ROOT_DIR/dist/Whisper-Anywhere-unsigned.dmg"
WEB_DMG="$ROOT_DIR/website/downloads/Whisper-Anywhere-unsigned.dmg"

log() {
  echo "==> $*"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd swift
require_cmd shasum

log "Running test suite"
cd "$ROOT_DIR"
swift test

log "Building unsigned DMG"
"$ROOT_DIR/scripts/build_unsigned_dmg.sh"

[[ -f "$DIST_DMG" ]] || die "Missing built DMG: $DIST_DMG"

log "Syncing DMG to website downloads"
mkdir -p "$(dirname "$WEB_DMG")"
cp "$DIST_DMG" "$WEB_DMG"

DIST_HASH="$(shasum -a 256 "$DIST_DMG" | awk '{print $1}')"
WEB_HASH="$(shasum -a 256 "$WEB_DMG" | awk '{print $1}')"

if [[ "$DIST_HASH" != "$WEB_HASH" ]]; then
  die "DMG hash mismatch between dist and website copies."
fi

log "Release artifacts ready and in sync"
echo "dist:    $DIST_DMG"
echo "website: $WEB_DMG"
echo "sha256:  $DIST_HASH"
