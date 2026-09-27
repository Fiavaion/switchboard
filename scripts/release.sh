#!/bin/bash
# Universal, Developer ID-signed, notarized release zip (PRD M5, N3). See docs/DEPLOYMENT.md.
# Usage: NOTARY_PROFILE=<keychain profile> scripts/release.sh
#        scripts/release.sh --skip-notarize      # local validation: sign + zip only
set -euo pipefail
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Mark Jones (9RWD38STJV)}"
ENTITLEMENTS="$ROOT/Resources/Switchboard.entitlements"
# Separate from the dev build: re-signing build/Switchboard.app would orphan its TCC grants.
APP="$ROOT/build/release/Switchboard.app"

if [ "$SKIP_NOTARIZE" -eq 0 ] && [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "NOTARY_PROFILE is not set. Create one with 'xcrun notarytool store-credentials' (docs/DEPLOYMENT.md)," >&2
  echo "or pass --skip-notarize for a local validation build." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/release/Switchboard-$VERSION.zip"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Switchboard"
BIN="$BIN" APP="$APP" scripts/bundle.sh release

# Replace bundle.sh's development signature with Developer ID + hardened runtime.
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  echo "Skipped notarization: $ZIP is signed but NOT notarized; do not publish it."
else
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  # Re-zip so the published archive carries the stapled ticket.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "Release: $ZIP"
echo "version $VERSION"
echo "sha256 $(shasum -a 256 "$ZIP" | awk '{print $1}')"
