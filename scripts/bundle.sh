#!/bin/bash
# Assemble build/Switchboard.app from the SPM binary. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
CONF="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${BIN:-$ROOT/.build/$CONF/Switchboard}"
APP="${APP:-$ROOT/build/Switchboard.app}"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Switchboard"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# LESSON-BUILD-002: sign with a stable certificate so TCC grants survive rebuilds: an ad-hoc signature's
# designated requirement is its cdhash, which changes every build and silently drops grants.
# Override with SIGN_ID=...; ad-hoc only when no Apple Development certificate exists (CI).
SIGN_ID="${SIGN_ID:-Apple Development}"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
  echo "warning: no '$SIGN_ID' identity; signing ad hoc (TCC grants will not persist)" >&2
  SIGN_ID="-"
fi
codesign --force --sign "$SIGN_ID" --entitlements "$ROOT/Resources/Switchboard.entitlements" "$APP"
echo "Bundled: $APP"
