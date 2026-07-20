#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${KLIK_PRO_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
export COPYFILE_DISABLE=1
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/App/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$ROOT/App/Info.plist")"
HELPER_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/App/KlikProHelper-Info.plist")"
HELPER_BUILD="$(plutil -extract CFBundleVersion raw -o - "$ROOT/App/KlikProHelper-Info.plist")"
STAMP="$(date +%Y%m%d-%H%M%S)"
# Build outside Documents/File Provider-managed storage. Those providers can
# reattach FinderInfo while a nested bundle is being signed, which codesign rejects.
WORK="${KLIK_PRO_RELEASE_WORK_DIRECTORY:-$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-release-v$VERSION-$STAMP.XXXXXX")}"
MODULE_CACHE="$WORK/module-cache"
PACKAGE="$WORK/Klik PRO v$VERSION"
APP="$PACKAGE/Klik PRO.app"
HELPER="$APP/Contents/Helpers/Klik PRO Helper.app"
RELEASES="$ROOT/releases"
ZIP="$RELEASES/Klik-PRO-v$VERSION-macos-universal.zip"
ZIP_SHA="$ZIP.sha256"
DMG="$RELEASES/Klik-PRO-v$VERSION-macos-universal.dmg"
DMG_SHA="$DMG.sha256"
INSTALLER="$RELEASES/install-klik-pro.sh"
INSTALLER_SHA="$INSTALLER.sha256"
DUPLICATION_SOURCES=("$ROOT"/Sources/Duplication/*.swift)
LAUNCHER_RUNTIME_SOURCES=(
  "$ROOT/Sources/Duplication/InstalledApp.swift"
  "$ROOT/Sources/Duplication/EngineDetector.swift"
  "$ROOT/Sources/Duplication/AppScanner.swift"
  "$ROOT/Sources/Duplication/ManagedLauncherPayload.swift"
)

if [[ "$HELPER_VERSION" != "$VERSION" || "$HELPER_BUILD" != "$BUILD" ]]; then
  echo "Main/helper version mismatch: $VERSION ($BUILD) vs $HELPER_VERSION ($HELPER_BUILD)" >&2
  exit 1
fi

mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$HELPER/Contents/MacOS" \
  "$HELPER/Contents/Resources" \
  "$PACKAGE/LaunchAgents" \
  "$RELEASES" \
  "$MODULE_CACHE"

compile() {
  local arch="$1"
  local source="$2"
  local output="$3"
  if [[ "$source" == "KlikProApp.swift" ]]; then
    xcrun swiftc \
      -sdk "$SDK" \
      -module-cache-path "$MODULE_CACHE" \
      -target "$arch-apple-macosx13.0" \
      -O \
      -warnings-as-errors \
      "$ROOT/Sources/$source" \
      "$ROOT/Sources/AppProfilesUI.swift" \
      "$ROOT/Sources/KlikProBrand.swift" \
      "$ROOT/Sources/KlikProConfig.swift" \
      "${DUPLICATION_SOURCES[@]}" \
      -o "$output"
    return
  fi
  xcrun swiftc \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -target "$arch-apple-macosx13.0" \
    -O \
    -warnings-as-errors \
    "$ROOT/Sources/$source" \
    "$ROOT/Sources/KlikProBrand.swift" \
    "$ROOT/Sources/KlikProConfig.swift" \
    "${DUPLICATION_SOURCES[@]}" \
    -o "$output"
}

for arch in arm64 x86_64; do
  compile "$arch" KlikProInput.swift "$WORK/klik-pro-input-$arch"
  compile "$arch" KlikProApp.swift "$WORK/klik-pro-app-$arch"
  xcrun swiftc \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -target "$arch-apple-macosx13.0" \
    -O \
    -warnings-as-errors \
    "${LAUNCHER_RUNTIME_SOURCES[@]}" \
    "$ROOT/Sources/KlikProManagedLauncher.swift" \
    -o "$WORK/klik-pro-managed-launcher-$arch"
done

lipo -create \
  "$WORK/klik-pro-input-arm64" \
  "$WORK/klik-pro-input-x86_64" \
  -output "$HELPER/Contents/MacOS/klik-pro-input"
lipo -create \
  "$WORK/klik-pro-app-arm64" \
  "$WORK/klik-pro-app-x86_64" \
  -output "$APP/Contents/MacOS/Klik PRO"
lipo -create \
  "$WORK/klik-pro-managed-launcher-arm64" \
  "$WORK/klik-pro-managed-launcher-x86_64" \
  -output "$APP/Contents/Resources/KlikProManagedLauncher"
chmod 755 "$APP/Contents/Resources/KlikProManagedLauncher"

cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/KlikProHelper-Info.plist" "$HELPER/Contents/Info.plist"
cp "$ROOT/assets/KlikPRO.icns" "$APP/Contents/Resources/KlikPRO.icns"
cp "$ROOT/assets/KlikPRO.icns" "$HELPER/Contents/Resources/KlikPRO.icns"
cp "$ROOT/assets/device-reference.png" "$APP/Contents/Resources/device-reference.png"
cmp "$APP/Contents/Resources/KlikPRO.icns" "$ROOT/assets/KlikPRO.icns"
cmp "$HELPER/Contents/Resources/KlikPRO.icns" "$ROOT/assets/KlikPRO.icns"
cp "$ROOT/LaunchAgents/"*.plist "$PACKAGE/LaunchAgents/"
cp "$ROOT/docs/INSTALL.md" "$PACKAGE/INSTALL.md"
cp "$ROOT/LICENSE" "$PACKAGE/LICENSE"
cp "$ROOT/NOTICE.md" "$PACKAGE/NOTICE.md"

xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$HELPER"
xattr -cr "$APP"
if xattr -lr "$APP" | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork)'; then
  echo "Bundle still contains Finder/resource metadata before outer signing" >&2
  exit 1
fi
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=4 "$APP"

for binary in \
  "$APP/Contents/MacOS/Klik PRO" \
  "$APP/Contents/Resources/KlikProManagedLauncher" \
  "$HELPER/Contents/MacOS/klik-pro-input"
do
  [[ "$(lipo -archs "$binary")" == "x86_64 arm64" || "$(lipo -archs "$binary")" == "arm64 x86_64" ]]
  for arch in arm64 x86_64; do
    vtool -show-build -arch "$arch" "$binary" | grep -q 'minos 13.0'
  done
done

[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$HELPER/Contents/Info.plist")" == "$VERSION" ]]
cmp "$APP/Contents/Resources/device-reference.png" "$ROOT/assets/device-reference.png"

if [[ -e "$ZIP" ]]; then
  mv "$ZIP" "$WORK/$(basename "$ZIP").previous"
fi
for artifact in "$ZIP_SHA" "$ZIP_SHA.sig" "$DMG" "$DMG_SHA" "$DMG_SHA.sig" \
  "$INSTALLER" "$INSTALLER_SHA" "$INSTALLER_SHA.sig"; do
  if [[ -e "$artifact" ]]; then
    mv "$artifact" "$WORK/$(basename "$artifact").previous"
  fi
done

ditto -c -k --norsrc --noqtn --keepParent "$PACKAGE" "$ZIP"
unzip -t "$ZIP" >/dev/null

if zipinfo -1 "$ZIP" | grep -E '(^|/)(\.git|\.DS_Store|__MACOSX)(/|$)|(^|/)\._|00_AI_Agent|worktrees|Sources|build/' >/dev/null; then
  echo "Archive contains development or metadata files" >&2
  exit 1
fi

VERIFY="$WORK/verify"
mkdir -p "$VERIFY"
ditto -x -k --norsrc "$ZIP" "$VERIFY"
codesign --verify --deep --strict --verbose=4 "$VERIFY/Klik PRO v$VERSION/Klik PRO.app"
cmp \
  "$VERIFY/Klik PRO v$VERSION/Klik PRO.app/Contents/Resources/device-reference.png" \
  "$ROOT/assets/device-reference.png"
cmp \
  "$VERIFY/Klik PRO v$VERSION/Klik PRO.app/Contents/Resources/KlikPRO.icns" \
  "$ROOT/assets/KlikPRO.icns"
cmp \
  "$VERIFY/Klik PRO v$VERSION/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app/Contents/Resources/KlikPRO.icns" \
  "$ROOT/assets/KlikPRO.icns"

DMG_ROOT="$WORK/dmg-root"
DMG_MOUNT="$WORK/verify-dmg"
DMG_RW="$WORK/Klik-PRO-v$VERSION-layout.dmg"
mkdir -p "$DMG_ROOT" "$DMG_MOUNT"
ditto --norsrc --noqtn "$APP" "$DMG_ROOT/Klik PRO.app"
ln -s /Applications "$DMG_ROOT/Applications"
mkdir -p "$DMG_ROOT/Extras/LaunchAgents" "$DMG_ROOT/.background"
cp "$ROOT/LaunchAgents/"*.plist "$DMG_ROOT/Extras/LaunchAgents/"
cp "$ROOT/docs/INSTALL.md" "$DMG_ROOT/Extras/INSTALL.md"
cp "$ROOT/LICENSE" "$DMG_ROOT/Extras/LICENSE"
cp "$ROOT/NOTICE.md" "$DMG_ROOT/Extras/NOTICE.md"
xcrun swift "$ROOT/tools/render-dmg-background.swift" \
  "$DMG_ROOT/.background/dmg-background.png"

codesign --verify --deep --strict --verbose=4 "$DMG_ROOT/Klik PRO.app"
hdiutil create \
  -volname "Klik PRO v$VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDRW \
  "$DMG_RW" >/dev/null

hdiutil attach \
  -readwrite \
  -noverify \
  -mountpoint "$DMG_MOUNT" \
  "$DMG_RW" >/dev/null
trap 'hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true' EXIT

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$DMG_MOUNT" as alias
  set backgroundFile to POSIX file "$DMG_MOUNT/.background/dmg-background.png" as alias
  open dmgFolder
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set bounds of container window of dmgFolder to {120, 120, 880, 540}
  set theViewOptions to icon view options of container window of dmgFolder
  set arrangement of theViewOptions to not arranged
  set icon size of theViewOptions to 96
  set text size of theViewOptions to 14
  set background picture of theViewOptions to backgroundFile
  set position of item "Applications" of dmgFolder to {170, 210}
  set position of item "Klik PRO.app" of dmgFolder to {610, 210}
  set position of item "Extras" of dmgFolder to {390, 340}
  close container window of dmgFolder
  open dmgFolder
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
end tell
APPLESCRIPT

hdiutil detach "$DMG_MOUNT" >/dev/null
trap - EXIT

hdiutil convert "$DMG_RW" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$DMG_MOUNT" \
  "$DMG" >/dev/null
trap 'hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true' EXIT

[[ -L "$DMG_MOUNT/Applications" ]]
[[ "$(readlink "$DMG_MOUNT/Applications")" == "/Applications" ]]
[[ -d "$DMG_MOUNT/Extras/LaunchAgents" ]]
[[ -f "$DMG_MOUNT/Extras/INSTALL.md" ]]
[[ -f "$DMG_MOUNT/Extras/LICENSE" ]]
[[ -f "$DMG_MOUNT/Extras/NOTICE.md" ]]
[[ -f "$DMG_MOUNT/.background/dmg-background.png" ]]
[[ -f "$DMG_MOUNT/.DS_Store" ]]
if [[ -e "$DMG_MOUNT/INSTALL.md" || -e "$DMG_MOUNT/LICENSE" || -e "$DMG_MOUNT/NOTICE.md" || -e "$DMG_MOUNT/LaunchAgents" ]]; then
  echo "DMG top level must keep technical files inside Extras" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=4 "$DMG_MOUNT/Klik PRO.app"
cmp "$DMG_MOUNT/Klik PRO.app/Contents/Resources/device-reference.png" "$ROOT/assets/device-reference.png"
cmp "$DMG_MOUNT/Klik PRO.app/Contents/Resources/KlikPRO.icns" "$ROOT/assets/KlikPRO.icns"
cmp \
  "$DMG_MOUNT/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app/Contents/Resources/KlikPRO.icns" \
  "$ROOT/assets/KlikPRO.icns"

hdiutil detach "$DMG_MOUNT" >/dev/null
trap - EXIT

(
  cd "$RELEASES"
  shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP_SHA")"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG_SHA")"
)

cp "$ROOT/install.sh" "$INSTALLER"
chmod 755 "$INSTALLER"
(
  cd "$RELEASES"
  shasum -a 256 "$(basename "$INSTALLER")" > "$(basename "$INSTALLER_SHA")"
)

releaseSigningKey="${KLIK_PRO_RELEASE_SIGNING_KEY:-$HOME/.config/klik-pro/release-signing/id_ed25519}"
if [[ -f "$releaseSigningKey" ]]; then
  "$ROOT/tools/sign-release-manifest.sh" "$ZIP_SHA" "$DMG_SHA" "$INSTALLER_SHA"
else
  echo "Warning: official release-signing key not found; local artifacts remain unsigned" >&2
fi

echo "Built Klik PRO v$VERSION ($BUILD)"
echo "ZIP: $ZIP"
echo "ZIP checksum: $ZIP_SHA"
if [[ -f "$ZIP_SHA.sig" ]]; then
  echo "ZIP checksum signature: $ZIP_SHA.sig"
fi
echo "DMG: $DMG"
echo "DMG checksum: $DMG_SHA"
if [[ -f "$DMG_SHA.sig" ]]; then
  echo "DMG checksum signature: $DMG_SHA.sig"
fi
echo "Terminal installer: $INSTALLER"
echo "Terminal installer checksum: $INSTALLER_SHA"
if [[ -f "$INSTALLER_SHA.sig" ]]; then
  echo "Terminal installer signature: $INSTALLER_SHA.sig"
fi
echo "Working directory: $WORK"
