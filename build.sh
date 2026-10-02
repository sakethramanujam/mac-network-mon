#!/bin/bash
set -e

echo "Building NetworkMon (Release)..."
swift build -c release

APP_DIR="NetworkMon.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "Creating App Bundle Structure..."
mkdir -p "$BIN_DIR"
mkdir -p "$RES_DIR"

echo "Copying Binary..."
cp .build/release/network-mon "$BIN_DIR/NetworkMon"

echo "Copying Info.plist..."
cp Info.plist "$APP_DIR/Contents/Info.plist"

if [[ -f Assets/AppIcon.icns ]]; then
  echo "Copying AppIcon.icns..."
  cp Assets/AppIcon.icns "$RES_DIR/AppIcon.icns"
fi

# Bundle localization resources produced by SwiftPM if present
if [[ -d .build/release/network-mon_network-mon.bundle ]]; then
  cp -R .build/release/network-mon_network-mon.bundle "$RES_DIR/" 2>/dev/null || true
fi

echo "Signing App with Hardened Runtime & App Sandbox (ad-hoc)..."
codesign --force --options runtime --entitlements NetworkMon.entitlements --sign "-" "$APP_DIR"
echo "For Developer ID notarization, see docs/NOTARIZATION.md and ./notarize.sh"

echo "Build complete! NetworkMon.app is ready."
