#!/bin/bash
set -euo pipefail
CLAMP_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
CLAMP_APP="$CLAMP_PROJECT/build/ClampEverything.app"
[ -d "$CLAMP_APP" ] || { echo 'Run bash scripts/build-app.sh first' >&2; exit 1; }
CLAMP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CLAMP_APP/Contents/Info.plist")"
CLAMP_NAME="ClampEverything-$CLAMP_VERSION-arm64.dmg"
CLAMP_STAGE="$(mktemp -d /private/tmp/clamp-dmg-XXXXXX)"
CLAMP_MOUNT="$CLAMP_STAGE/mount"
CLAMP_MOUNTED=false
cleanup() {
    if [ "$CLAMP_MOUNTED" = true ]; then hdiutil detach "$CLAMP_MOUNT" >/dev/null || true; fi
    rm -rf "$CLAMP_STAGE"
}
trap cleanup EXIT
# These small Python packages write Finder metadata; they are build-only dependencies.
if ! PYTHONPATH="$CLAMP_PROJECT/build/dmg-tools" python3 -c 'import ds_store, mac_alias' >/dev/null 2>&1; then
    python3 -m pip install --cert /etc/ssl/cert.pem --target "$CLAMP_PROJECT/build/dmg-tools" -r "$CLAMP_PROJECT/scripts/dmg-requirements.txt"
fi
bash "$CLAMP_PROJECT/scripts/make-installer-icon.sh"
swift -module-cache-path "$CLAMP_PROJECT/.build/module-cache" "$CLAMP_PROJECT/scripts/make-dmg-background.swift" "$CLAMP_PROJECT/build/dmg-background.png" "$CLAMP_PROJECT/docs/assets/installer/paper-arrow-v1.png"
mkdir -p "$CLAMP_STAGE/volume"
ditto "$CLAMP_APP" "$CLAMP_STAGE/volume/ClampEverything.app"
# Finder metadata may be reattached to the build directory; clean the staged copy.
xattr -dr com.apple.FinderInfo "$CLAMP_STAGE/volume/ClampEverything.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$CLAMP_STAGE/volume/ClampEverything.app" 2>/dev/null || true
codesign --verify --deep --strict "$CLAMP_STAGE/volume/ClampEverything.app"
ln -s /Applications "$CLAMP_STAGE/volume/Applications"
cp "$CLAMP_PROJECT/docs/INSTALL.txt" "$CLAMP_STAGE/volume/安装说明.txt"
mkdir -p "$CLAMP_STAGE/volume/.background" "$CLAMP_MOUNT"
cp "$CLAMP_PROJECT/build/dmg-background.png" "$CLAMP_STAGE/volume/.background/background.png"
cp "$CLAMP_PROJECT/build/Installer.icns" "$CLAMP_STAGE/volume/.VolumeIcon.icns"
hdiutil create -volname "ClampEverything $CLAMP_VERSION" -srcfolder "$CLAMP_STAGE/volume" -fs HFS+ -format UDRW -ov "$CLAMP_STAGE/layout.dmg"
hdiutil attach "$CLAMP_STAGE/layout.dmg" -nobrowse -mountpoint "$CLAMP_MOUNT" >/dev/null
CLAMP_MOUNTED=true
SetFile -a C "$CLAMP_MOUNT"
PYTHONPATH="$CLAMP_PROJECT/build/dmg-tools" python3 "$CLAMP_PROJECT/scripts/configure-dmg.py" "$CLAMP_MOUNT" "$CLAMP_STAGE/background.alias"
swift -module-cache-path "$CLAMP_PROJECT/.build/module-cache" "$CLAMP_PROJECT/scripts/verify-dmg-background.swift" "$CLAMP_STAGE/background.alias" "$CLAMP_MOUNT/.background/background.png"
hdiutil detach "$CLAMP_MOUNT" >/dev/null
CLAMP_MOUNTED=false
hdiutil convert "$CLAMP_STAGE/layout.dmg" -format UDZO -o "$CLAMP_PROJECT/build/$CLAMP_NAME" -ov
swift -module-cache-path "$CLAMP_PROJECT/.build/module-cache" "$CLAMP_PROJECT/scripts/set-file-icon.swift" "$CLAMP_PROJECT/build/Installer.icns" "$CLAMP_PROJECT/build/$CLAMP_NAME"
hdiutil verify "$CLAMP_PROJECT/build/$CLAMP_NAME"
# Reattach at a DIFFERENT path: background lookup must survive relocation.
CLAMP_MOUNT="$CLAMP_STAGE/final-mount"
mkdir -p "$CLAMP_MOUNT"
# Resolve the final compressed artifact with macOS itself.
hdiutil attach "$CLAMP_PROJECT/build/$CLAMP_NAME" -readonly -nobrowse -mountpoint "$CLAMP_MOUNT" >/dev/null
CLAMP_MOUNTED=true
PYTHONPATH="$CLAMP_PROJECT/build/dmg-tools" python3 "$CLAMP_PROJECT/scripts/verify-dmg-layout.py" "$CLAMP_MOUNT" "$CLAMP_STAGE/final-background.alias"
swift -module-cache-path "$CLAMP_PROJECT/.build/module-cache" "$CLAMP_PROJECT/scripts/verify-dmg-background.swift" "$CLAMP_STAGE/final-background.alias" "$CLAMP_MOUNT/.background/background.png"
codesign --verify --deep --strict "$CLAMP_MOUNT/ClampEverything.app"
hdiutil detach "$CLAMP_MOUNT" >/dev/null
CLAMP_MOUNTED=false
(cd "$CLAMP_PROJECT/build" && shasum -a 256 "$CLAMP_NAME" > "$CLAMP_NAME.sha256")
echo "Built $CLAMP_PROJECT/build/$CLAMP_NAME"
