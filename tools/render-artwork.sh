#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${KLIK_PRO_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCH="$(uname -m)"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$ROOT/build/artwork-$STAMP"
MODULE_CACHE="$WORK/module-cache"
ICONSET="$WORK/KlikPRO.iconset"
mkdir -p "$ICONSET" "$MODULE_CACHE"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/crop-device.swift" \
  -o "$WORK/crop-device"
"$WORK/crop-device" \
  "$ROOT/assets/Klik PRO mouse.png" \
  "$ROOT/assets/device-reference.png"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/render-app-icon.swift" \
  -o "$WORK/render-app-icon"
"$WORK/render-app-icon" \
  "$ROOT/assets/icon-master.png"

sips -z 400 400 "$ROOT/assets/icon-master.png" --out "$ROOT/assets/icon.png" >/dev/null
sips -z 16 16 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ROOT/assets/icon-master.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ROOT/assets/KlikPRO.icns"

echo "Rendered frosted-white device artwork and decoupled app icon"
echo "Working directory: $WORK"
