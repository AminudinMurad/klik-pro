#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${KLIK_PRO_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCH="$(uname -m)"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/App/Info.plist")"
STAMP="$(date +%Y%m%d-%H%M%S)"
# A full check renders two bundles back-to-back. Include this renderer process so
# LaunchServices never confuses the second temporary app with the first one.
PREVIEW_BUNDLE_ID="local.klik-pro.preview.p${STAMP//-/}.r$$"
# Keep the runnable preview bundle out of Documents/File Provider storage. Newer
# macOS builds can refuse to register an ad-hoc preview application while its bundle
# is being observed or decorated there; the release builder already follows the same
# non-synced-work-directory rule.
WORK="${KLIK_PRO_PREVIEW_WORK_DIRECTORY:-$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-preview-v$VERSION-$STAMP.XXXXXX")}"
BUNDLE="$WORK/Klik PRO Preview.app"
EXECUTABLE="$BUNDLE/Contents/MacOS/preview-render"
CONFIG="$WORK/config"
FIXTURES="$WORK/fixtures"
MODULE_CACHE="$WORK/module-cache"
DUPLICATION_SOURCES=("$ROOT"/Sources/Duplication/*.swift)

MODE="${1:-all}"
case "$MODE" in
  all|--fixtures-only) ;;
  *)
    echo "Usage: $0 [--fixtures-only]" >&2
    exit 64
    ;;
esac

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$CONFIG" "$FIXTURES" "$MODULE_CACHE"
awk '/^@main$/ { exit } { print }' \
  "$ROOT/Sources/KlikProApp.swift" > "$WORK/PreviewAppBody.swift"

cp "$ROOT/App/Info.plist" "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleExecutable -string preview-render "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$PREVIEW_BUNDLE_ID" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/assets/KlikPRO.icns" "$BUNDLE/Contents/Resources/KlikPRO.icns"
cp "$ROOT/assets/icon-master.png" "$BUNDLE/Contents/Resources/OnboardingPreviewIcon.png"
cp "$ROOT/assets/device-reference.png" "$BUNDLE/Contents/Resources/device-reference.png"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$WORK/PreviewAppBody.swift" \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "$ROOT/Sources/KlikProBrand.swift" \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/tools/PreviewMain.swift" \
  -o "$EXECUTABLE"
xattr -cr "$BUNDLE"
codesign --force --sign - --timestamp=none "$BUNDLE"

render_preview() {
  local output="$1"
  local tab="$2"
  local installed_targets="${3:-}"
  local use_installed_icons="${4:-0}"
  local app_profiles_empty="${5:-0}"

  local launch=(
    /usr/bin/open -W -n -g
    --env "KLIK_PRO_CONFIG_DIRECTORY=$CONFIG"
    --env "KLIK_PRO_PREVIEW_USE_INSTALLED_APP_ICONS=$use_installed_icons"
    --env "KLIK_PRO_PREVIEW_APP_PROFILES_EMPTY=$app_profiles_empty"
  )
  if [[ -n "$installed_targets" ]]; then
    launch+=(--env "KLIK_PRO_PREVIEW_INSTALLED_TARGETS=$installed_targets")
  fi
  "${launch[@]}" "$BUNDLE" --args "$output" "$tab"
}

if [[ "$MODE" == "all" ]]; then
  render_preview "$ROOT/assets/screenshot-onboarding.png" onboarding
  # The public README screenshot reflects the real installed apps on the release-test
  # Mac. Deterministic fixtures below keep using generated fallback tiles.
  render_preview "$ROOT/assets/screenshot-mappings.png" mappings "" 1
  render_preview "$ROOT/assets/screenshot-app-profiles.png" profiles "" 1
  render_preview "$ROOT/assets/screenshot-settings.png" settings
fi

# The onboarding fixture is the actual first-run state: permission still required.
render_preview "$FIXTURES/onboarding.png" onboarding
# A matched pair verifies the hover outline on the Close state independently of
# the permission-status copy and primary action.
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED=1 \
  "$EXECUTABLE" "$FIXTURES/onboarding-granted.png" onboarding
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED=1 \
  KLIK_PRO_PREVIEW_ONBOARDING_CLOSE_HOVER=1 \
  "$EXECUTABLE" "$FIXTURES/onboarding-close-hover.png" onboarding
# Menu-bar About uses the same shared wordmark and badge metrics.
render_preview "$FIXTURES/about.png" about
# The longer permission badge is retained as a regression fixture so the nearby
# Recheck button cannot silently drift back into it.
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED=0 \
  "$EXECUTABLE" "$FIXTURES/settings-needs-permission.png" settings
render_preview "$FIXTURES/app-profiles.png" profiles
render_preview "$FIXTURES/app-profiles-empty.png" profiles "" 0 1
# Build-only Special Feature fixtures. These never replace the tracked README images.
# PreviewMain converts the environment value into in-process Config overrides before
# ToggleView is created; previews never inspect or mutate a live background service.
render_preview "$FIXTURES/special-feature-no-apps.png" mappings none
render_preview "$FIXTURES/special-feature-chatgpt-only.png" mappings chatgpt
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_UNSAVED=1 \
  "$EXECUTABLE" "$FIXTURES/unsaved-changes.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_INSTALLED_TARGETS=none \
  KLIK_PRO_PREVIEW_SAVE_HOVER=1 \
  "$EXECUTABLE" "$FIXTURES/save-hover.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_INSTALLED_TARGETS=none \
  KLIK_PRO_PREVIEW_UPDATE_HOVER=1 \
  "$EXECUTABLE" "$FIXTURES/update-hover.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_INSTALLED_TARGETS=none \
  KLIK_PRO_PREVIEW_CLOSE_HOVER=1 \
  "$EXECUTABLE" "$FIXTURES/close-hover.png" mappings

echo "Rendered v$VERSION previews (working directory: $WORK)"
echo "UI fixtures:"
echo "  $FIXTURES/onboarding.png"
echo "  $FIXTURES/onboarding-granted.png"
echo "  $FIXTURES/onboarding-close-hover.png"
echo "  $FIXTURES/about.png"
echo "  $FIXTURES/settings-needs-permission.png"
echo "  $FIXTURES/app-profiles.png"
echo "  $FIXTURES/app-profiles-empty.png"
echo "  $FIXTURES/special-feature-no-apps.png"
echo "  $FIXTURES/special-feature-chatgpt-only.png"
echo "  $FIXTURES/unsaved-changes.png"
echo "  $FIXTURES/save-hover.png"
echo "  $FIXTURES/update-hover.png"
echo "  $FIXTURES/close-hover.png"
