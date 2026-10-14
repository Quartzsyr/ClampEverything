#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$PROJECT_ROOT"
CONFIGURATION="${1:-release}"
swift build "${SWIFT_ARGS[@]}" -c "$CONFIGURATION"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$PROJECT_ROOT/build"
CLAMP_STAGING="$(mktemp -d /private/tmp/clamp-build-XXXXXX)"
trap 'rm -rf "$CLAMP_STAGING"' EXIT
APP="$CLAMP_STAGING/ClampEverything.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X "$BIN_DIR/ClampEverything" "$APP/Contents/MacOS/ClampEverything"
# Preserve imagegen alpha while downsampling packaged assets for a lightweight app.
mkdir -p "$APP/Contents/Resources/Generated"
for CLAMP_ASSET in clip-silver clip-brass clip-silver-half clip-silver-open clip-brass-open; do
    sips -Z 256 "$PROJECT_ROOT/Sources/ClampEverything/Resources/Generated/$CLAMP_ASSET.png" --out "$APP/Contents/Resources/Generated/$CLAMP_ASSET.png" >/dev/null
done
sips -Z 1024 "$PROJECT_ROOT/Sources/ClampEverything/Resources/Generated/cursor-clip-motion-v2.png" --out "$APP/Contents/Resources/Generated/cursor-clip-motion-v2.png" >/dev/null
for CLAMP_PAPER in paper-natural paper-soft-curl paper-soft-wave paper-calm-v2; do
    sips -Z 1100 "$PROJECT_ROOT/Sources/ClampEverything/Resources/Generated/$CLAMP_PAPER.png" --out "$APP/Contents/Resources/Generated/$CLAMP_PAPER.png" >/dev/null
done
sips -z 1024 1024 "$PROJECT_ROOT/Sources/ClampEverything/Resources/Generated/app-icon.png" --out "$PROJECT_ROOT/build/icon.png" >/dev/null
sips -Z 256 "$PROJECT_ROOT/Sources/ClampEverything/Resources/Generated/app-icon.png" --out "$APP/Contents/Resources/Generated/app-icon.png" >/dev/null
ICONSET="$PROJECT_ROOT/build/ClampEverything.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" build/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" build/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ClampEverything.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ClampEverything</string>
<key>CFBundleDisplayName</key><string>屏幕夹子</string>
<key>CFBundleIdentifier</key><string>local.quartz.ClampEverything</string>
<key>CFBundleExecutable</key><string>ClampEverything</string>
<key>CFBundleIconFile</key><string>ClampEverything</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.1</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>NSDocumentsFolderUsageDescription</key><string>访问你主动夹住的文件与文件夹。</string>
<key>NSDesktopFolderUsageDescription</key><string>访问你主动夹住的桌面内容。</string>
<key>NSDownloadsFolderUsageDescription</key><string>访问你主动夹住的下载内容。</string>
</dict></plist>
PLIST
# Finder / file-provider folders may attach FinderInfo to a freshly generated bundle.
# Only clear signing-incompatible attributes on this generated application.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
# Prefer an existing development identity: ad hoc signatures use a changing
# code hash as their identity, invalidating TCC authorization on every rebuild.
CLAMP_SIGNING_IDENTITY="${CLAMP_SIGNING_IDENTITY:-}"
if [ -z "$CLAMP_SIGNING_IDENTITY" ]; then
    CLAMP_SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')"
fi
codesign --force --sign "${CLAMP_SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
CLAMP_FINAL="$PROJECT_ROOT/build/ClampEverything.app"
CLAMP_PREVIOUS="$PROJECT_ROOT/build/ClampEverything.previous.app"
if [ -d "$CLAMP_PREVIOUS" ]; then rm -rf "$CLAMP_PREVIOUS"; fi
if [ -d "$CLAMP_FINAL" ]; then mv "$CLAMP_FINAL" "$CLAMP_PREVIOUS"; fi
mv "$APP" "$CLAMP_FINAL"
xattr -dr com.apple.FinderInfo "$CLAMP_FINAL" 2>/dev/null || true
codesign --verify --strict "$CLAMP_FINAL"
echo "Built $CLAMP_FINAL"
