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
  local advanced_unlocked="${6:-0}"

  local launch=(
    /usr/bin/open -W -n -g
    --env "KLIK_PRO_CONFIG_DIRECTORY=$CONFIG"
    --env "KLIK_PRO_PREVIEW_USE_INSTALLED_APP_ICONS=$use_installed_icons"
    --env "KLIK_PRO_PREVIEW_APP_PROFILES_EMPTY=$app_profiles_empty"
    --env "KLIK_PRO_PREVIEW_ADVANCED_UNLOCKED=$advanced_unlocked"
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
  render_preview "$ROOT/assets/screenshot-advanced-locked.png" advanced
  render_preview "$ROOT/assets/screenshot-advanced.png" advanced "" 0 0 1
  xcrun swift "$ROOT/tools/render-app-profiles-showcase.swift"
fi

# Onboarding fixtures cover all four steps. Step 4 renders the actual first-run
# state (permission still required) plus the granted variant.
render_preview "$FIXTURES/onboarding.png" onboarding
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ONBOARDING_STEP=2 \
  "$EXECUTABLE" "$FIXTURES/onboarding-data-folder.png" onboarding
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ONBOARDING_STEP=3 \
  "$EXECUTABLE" "$FIXTURES/onboarding-toggles.png" onboarding
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ONBOARDING_STEP=4 \
  "$EXECUTABLE" "$FIXTURES/onboarding-access.png" onboarding
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ONBOARDING_STEP=4 \
  KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED=1 \
  "$EXECUTABLE" "$FIXTURES/onboarding-granted.png" onboarding
# A matched pair verifies the hover outline on the Back button independently of
# the permission-status copy and primary action.
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_ONBOARDING_STEP=4 \
  KLIK_PRO_PREVIEW_ONBOARDING_BACK_HOVER=1 \
  "$EXECUTABLE" "$FIXTURES/onboarding-back-hover.png" onboarding
# Menu-bar About uses the same shared wordmark and badge metrics.
render_preview "$FIXTURES/about.png" about
# Settings fixtures keep the compact Permissions action bar and About-card Updates
# control deterministic in both granted and needs-permission states.
render_preview "$FIXTURES/settings.png" settings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED=0 \
  "$EXECUTABLE" "$FIXTURES/settings-needs-permission.png" settings
render_preview "$FIXTURES/app-profiles.png" profiles
render_preview "$FIXTURES/app-profiles-empty.png" profiles "" 0 1
# Responsive v1.5.6 acceptance: width remains fixed at 940 points while each
# larger MacBook height gives long lists more viewport.
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x770 \
  "$EXECUTABLE" "$FIXTURES/responsive-mappings-13-m1.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x820 \
  "$EXECUTABLE" "$FIXTURES/responsive-profiles-13-modern.png" profiles
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x860 \
  "$EXECUTABLE" "$FIXTURES/responsive-profiles-14.png" profiles
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x900 \
  "$EXECUTABLE" "$FIXTURES/responsive-profiles-15.png" profiles
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x960 \
  "$EXECUTABLE" "$FIXTURES/responsive-profiles-16.png" profiles
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x960 \
  "$EXECUTABLE" "$FIXTURES/responsive-mappings-16.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x960 \
  "$EXECUTABLE" "$FIXTURES/responsive-settings-16.png" settings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_FRAME_SIZE=940x960 \
  KLIK_PRO_PREVIEW_ADVANCED_UNLOCKED=1 \
  "$EXECUTABLE" "$FIXTURES/responsive-advanced-16.png" advanced
# Build-only Special Feature fixtures. These never replace the tracked README images.
# PreviewMain converts the environment value into in-process Config overrides before
# ToggleView is created; previews never inspect or mutate a live background service.
render_preview "$FIXTURES/special-feature-no-apps.png" mappings none
render_preview "$FIXTURES/special-feature-chatgpt-only.png" mappings chatgpt
# Three deterministic slide states cover the boundary arrows, viewed dot/name,
# and active-versus-viewed badge without touching the user's real config.
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_SINGLE_MOUSE_MAPPING=1 \
  "$EXECUTABLE" "$FIXTURES/mouse-mapping-single.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_MOUSE_MAPPING_INDEX=0 \
  "$EXECUTABLE" "$FIXTURES/mouse-mapping-first.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_MOUSE_MAPPING_INDEX=1 \
  "$EXECUTABLE" "$FIXTURES/mouse-mapping-middle.png" mappings
KLIK_PRO_CONFIG_DIRECTORY="$CONFIG" \
  KLIK_PRO_PREVIEW_MOUSE_MAPPING_INDEX=2 \
  "$EXECUTABLE" "$FIXTURES/mouse-mapping-final.png" mappings
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
  "$EXECUTABLE" "$FIXTURES/update-hover.png" settings
if [[ "$MODE" == "all" ]]; then
  # The README onboarding animation is built from the fixtures above, so adding or
  # reordering a first-run page can never leave a stale hand-made recording behind.
  xcrun swift "$ROOT/tools/render-onboarding-flow.swift" "$FIXTURES"
fi

echo "Rendered v$VERSION previews (working directory: $WORK)"
echo "UI fixtures:"
echo "  $FIXTURES/onboarding.png"
echo "  $FIXTURES/onboarding-data-folder.png"
echo "  $FIXTURES/onboarding-toggles.png"
echo "  $FIXTURES/onboarding-access.png"
echo "  $FIXTURES/onboarding-granted.png"
echo "  $FIXTURES/onboarding-back-hover.png"
echo "  $FIXTURES/about.png"
echo "  $FIXTURES/settings.png"
echo "  $FIXTURES/settings-needs-permission.png"
echo "  $FIXTURES/app-profiles.png"
echo "  $FIXTURES/app-profiles-empty.png"
echo "  $FIXTURES/responsive-mappings-13-m1.png"
echo "  $FIXTURES/responsive-profiles-13-modern.png"
echo "  $FIXTURES/responsive-profiles-14.png"
echo "  $FIXTURES/responsive-profiles-15.png"
echo "  $FIXTURES/responsive-profiles-16.png"
echo "  $FIXTURES/responsive-mappings-16.png"
echo "  $FIXTURES/responsive-settings-16.png"
echo "  $FIXTURES/responsive-advanced-16.png"
echo "  $FIXTURES/special-feature-no-apps.png"
echo "  $FIXTURES/special-feature-chatgpt-only.png"
echo "  $FIXTURES/mouse-mapping-single.png"
echo "  $FIXTURES/mouse-mapping-first.png"
echo "  $FIXTURES/mouse-mapping-middle.png"
echo "  $FIXTURES/mouse-mapping-final.png"
echo "  $FIXTURES/unsaved-changes.png"
echo "  $FIXTURES/save-hover.png"
echo "  $FIXTURES/update-hover.png"
