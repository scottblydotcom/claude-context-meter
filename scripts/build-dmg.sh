#!/usr/bin/env bash
# Build a distributable DMG for ClaudeContextMeter.
#
# Usage:
#   ./scripts/build-dmg.sh /path/to/ClaudeContextMeter.app
#
# Steps to get the .app before running this script:
#   1. Xcode → Product → Archive
#   2. Organizer → Distribute App → Custom → Copy App
#   3. Save the exported ClaudeContextMeter.app somewhere
#   4. Run this script with the path to that .app

set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ]; then
    echo "Usage: $0 /path/to/ClaudeContextMeter.app"
    exit 1
fi

if [ ! -d "$APP" ]; then
    echo "Error: '$APP' not found or is not a directory."
    exit 1
fi

VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="ClaudeContextMeter-${VERSION}"
VOLUME_NAME="Claude Context Meter"
OUTPUT_DIR="$(dirname "$APP")"

echo "Building DMG for $APP (version $VERSION)..."

# Create staging directory
STAGING=$(mktemp -d)
cp -r "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME.dmg"

rm -rf "$STAGING"

echo ""
echo "Done: $OUTPUT_DIR/$DMG_NAME.dmg"
