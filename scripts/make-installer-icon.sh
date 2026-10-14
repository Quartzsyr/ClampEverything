#!/bin/bash
set -euo pipefail
CLAMP_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
CLAMP_PNG="$CLAMP_PROJECT/docs/assets/installer/dmg-volume-icon.png"
CLAMP_ICONSET="$CLAMP_PROJECT/build/Installer.iconset"
mkdir -p "$CLAMP_ICONSET"
for CLAMP_SIZE in 16 32 128 256 512; do
    sips -z "$CLAMP_SIZE" "$CLAMP_SIZE" "$CLAMP_PNG" --out "$CLAMP_ICONSET/icon_${CLAMP_SIZE}x${CLAMP_SIZE}.png" >/dev/null
    CLAMP_DOUBLE=$((CLAMP_SIZE * 2))
    sips -z "$CLAMP_DOUBLE" "$CLAMP_DOUBLE" "$CLAMP_PNG" --out "$CLAMP_ICONSET/icon_${CLAMP_SIZE}x${CLAMP_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$CLAMP_ICONSET" -o "$CLAMP_PROJECT/build/Installer.icns"
