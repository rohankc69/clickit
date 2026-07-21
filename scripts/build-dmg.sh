#!/bin/bash
#
# Builds Clickit and packages it into an UNSIGNED .dmg.
#
# The result is not signed with a Developer ID and not notarized, so Gatekeeper
# will refuse to open it on any Mac other than the one that built it until the
# user removes the quarantine flag. See the "Opening an unsigned build" section
# of README.md for what recipients have to do, and ROADMAP phase 5 for what
# would make that unnecessary.
#
# Usage: ./scripts/build-dmg.sh [output-directory]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist}"
BUILD_DIR="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR" "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

VERSION="$(xcodebuild -project Clickit.xcodeproj -target Clickit -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')"
VERSION="${VERSION:-0.0.0}"
DMG_NAME="Clickit-$VERSION.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "Building Clickit $VERSION (Release)"
xcodebuild build \
    -project Clickit.xcodeproj \
    -scheme Clickit \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    >/dev/null

APP_PATH="$BUILD_DIR/Build/Products/Release/Clickit.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build did not produce $APP_PATH" >&2
    exit 1
fi

# Fail loudly rather than shipping a broken bundle.
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
    || echo "note: ad-hoc signature only; this build is not distributable without notarization"

echo "Staging disk image contents"
cp -R "$APP_PATH" "$STAGING_DIR/"
# The Applications symlink is what makes drag-to-install obvious.
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_NAME"
hdiutil create \
    -volname "Clickit $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    >/dev/null

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
echo
echo "Created $DMG_PATH ($SIZE)"
echo
echo "This build is UNSIGNED. To open it on another Mac, the recipient must run:"
echo "  xattr -d com.apple.quarantine /Applications/Clickit.app"
echo "Do not ask users to do this casually; prefer a notarized build (roadmap phase 5)."
