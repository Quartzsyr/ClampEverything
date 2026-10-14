#!/bin/bash
set -euo pipefail
CLAMP_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
CLAMP_APP="$CLAMP_PROJECT/build/ClampEverything.app"
[ -d "$CLAMP_APP" ] || { echo 'Run bash scripts/build-app.sh first' >&2; exit 1; }
CLAMP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CLAMP_APP/Contents/Info.plist")"
CLAMP_NAME="ClampEverything-$CLAMP_VERSION-arm64.dmg"
CLAMP_STAGE="$(mktemp -d /private/tmp/clamp-dmg-XXXXXX)"
trap 'rm -rf "$CLAMP_STAGE"' EXIT
mkdir -p "$CLAMP_STAGE/volume"
ditto "$CLAMP_APP" "$CLAMP_STAGE/volume/ClampEverything.app"
# Finder metadata may be reattached to the build directory; clean the staged copy.
xattr -dr com.apple.FinderInfo "$CLAMP_STAGE/volume/ClampEverything.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$CLAMP_STAGE/volume/ClampEverything.app" 2>/dev/null || true
codesign --verify --deep --strict "$CLAMP_STAGE/volume/ClampEverything.app"
ln -s /Applications "$CLAMP_STAGE/volume/Applications"
cp "$CLAMP_PROJECT/docs/INSTALL.txt" "$CLAMP_STAGE/volume/安装说明.txt"
hdiutil create -volname "ClampEverything $CLAMP_VERSION" -srcfolder "$CLAMP_STAGE/volume" -format UDZO -ov "$CLAMP_PROJECT/build/$CLAMP_NAME"
hdiutil verify "$CLAMP_PROJECT/build/$CLAMP_NAME"
(cd "$CLAMP_PROJECT/build" && shasum -a 256 "$CLAMP_NAME" > "$CLAMP_NAME.sha256")
echo "Built $CLAMP_PROJECT/build/$CLAMP_NAME"
