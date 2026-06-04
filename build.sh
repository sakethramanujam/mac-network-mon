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

echo "Signing App with Hardened Runtime & App Sandbox..."
codesign --force --options runtime --entitlements NetworkMon.entitlements --sign "-" "$APP_DIR"

echo "Build complete! NetworkMon.app is ready."
