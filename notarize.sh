#!/bin/bash
# Notarize a Developer ID–signed NetworkMon.app.
# Prerequisites:
#   - Apple Developer ID Application certificate in Keychain
#   - App-specific password or keychain profile for notarytool
#   - Run ./build.sh first, then re-sign with your Developer ID (see below)
set -euo pipefail

APP="NetworkMon.app"
ZIP="NetworkMon-notarize.zip"
IDENTITY="${CODESIGN_IDENTITY:-}"
PROFILE="${NOTARYTOOL_PROFILE:-NetworkMon-notary}"

if [[ -z "$IDENTITY" ]]; then
  echo "Set CODESIGN_IDENTITY to your Developer ID Application identity."
  echo "Example:"
  echo "  security find-identity -v -p codesigning"
  echo "  CODESIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./notarize.sh"
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP — run ./build.sh first."
  exit 1
fi

echo "Re-signing $APP with $IDENTITY ..."
codesign --force --options runtime --timestamp \
  --entitlements NetworkMon.entitlements \
  --sign "$IDENTITY" "$APP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Zipping for notarytool..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (profile: $PROFILE)..."
echo "Create a profile once with:"
echo "  xcrun notarytool store-credentials \"$PROFILE\" --apple-id YOU@EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "Done. Distribute $APP (or a fresh zip of the stapled app)."
rm -f "$ZIP"
