#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Check failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${KLIK_PRO_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCH="$(uname -m)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/build/check-$STAMP"
MODULE_CACHE="$OUT/module-cache"
DUPLICATION_SOURCES=("$ROOT"/Sources/Duplication/*.swift)
LAUNCHER_RUNTIME_SOURCES=(
  "$ROOT/Sources/Duplication/InstalledApp.swift"
  "$ROOT/Sources/Duplication/EngineDetector.swift"
  "$ROOT/Sources/Duplication/AppScanner.swift"
  "$ROOT/Sources/Duplication/ManagedLauncherPayload.swift"
)
mkdir -p "$OUT" "$MODULE_CACHE"

compile() {
  local arch="$1"
  local source="$2"
  local output="$3"
  if [[ "$source" == "KlikProApp.swift" ]]; then
    xcrun swiftc \
      -sdk "$SDK" \
      -module-cache-path "$MODULE_CACHE" \
      -target "$arch-apple-macosx13.0" \
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
    -warnings-as-errors \
    "$ROOT/Sources/$source" \
    "$ROOT/Sources/KlikProBrand.swift" \
    "$ROOT/Sources/KlikProConfig.swift" \
    "${DUPLICATION_SOURCES[@]}" \
    -o "$output"
}

require_source_literal() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -qF "$needle" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_source_regex() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_block_literal() {
  local needle="$1"
  local block="$2"
  local message="$3"
  if ! grep -qF "$needle" <<<"$block"; then
    echo "$message" >&2
    exit 1
  fi
}

for plist in \
  "$ROOT/App/Info.plist" \
  "$ROOT/App/KlikProHelper-Info.plist" \
  "$ROOT/LaunchAgents/local.klik-pro.input.plist"
do
  plutil -lint "$plist"
done
for product_plist in \
  "$ROOT/App/Info.plist" \
  "$ROOT/App/KlikProHelper-Info.plist"
do
  product_version="$(plutil -extract CFBundleShortVersionString raw -o - "$product_plist")"
  product_build="$(plutil -extract CFBundleVersion raw -o - "$product_plist")"
  if [[ "$product_version" != "1.5.7" || "$product_build" != "30" ]]; then
    echo "$(basename "$product_plist") must remain version 1.5.7 build 30; found version $product_version build $product_build" >&2
    exit 1
  fi
done
if [[ -e "$ROOT/LaunchAgents/local.klik-pro.menu.plist" ]]; then
  echo "The obsolete separate menu LaunchAgent must not ship" >&2
  exit 1
fi
if grep -Eq -- '--input-only|--menu-only' "$ROOT/LaunchAgents/local.klik-pro.input.plist"; then
  echo "The combined LaunchAgent must not pass a mode argument" >&2
  exit 1
fi
if grep -Eq 'runMenu|runInput|quickLaunchServiceQueue' "$ROOT/Sources/KlikProInput.swift"; then
  echo "The input helper must not contain a split menu/input service path" >&2
  exit 1
fi
if [[ "${#DUPLICATION_SOURCES[@]}" -ne 9 ]]; then
  echo "Expected exactly 9 duplication source files, found ${#DUPLICATION_SOURCES[@]}" >&2
  exit 1
fi
# Pin the production registry against docs/COMPATIBILITY.md, the sole source of
# truth for both the shipping catalogue and badge (owner decision 2026-07-26).
# Test evidence and historical rule-ID suffixes never promote or demote an app.
#
# These use `if ... exit 1` rather than a bare `[[ ]]`: /bin/bash on macOS is 3.2,
# where `set -e` does NOT abort on a failing `[[ ]]` compound command, so a bare
# bracket assertion is a silent no-op. That is how this registry drifted out of
# sync with the document unnoticed.
production_block="$(sed -n '/static let production = AppCompatibilityRegistry(rules: \[/,/^    \])/p' \
  "$ROOT/Sources/Duplication/EngineDetector.swift")"
if [[ -z "$production_block" ]]; then
  echo "Production compatibility registry block was not found" >&2
  exit 1
fi
production_rules="$(printf '%s\n' "$production_block" \
  | awk '/AppCompatibilityRule\(/ { count++ } END { print count + 0 }')"
if [[ "$production_rules" -ne 16 ]]; then
  echo "Production registry must ship exactly 16 rules, found $production_rules" >&2
  exit 1
fi
compatibility_verified="$OUT/compatibility-verified.txt"
registry_catalogue="$OUT/registry-catalogue.txt"
awk -F '|' '
  /^## Verified$/ { verified = 1; next }
  /^## Unverified$/ { verified = 0 }
  verified && /^\|/ {
    for (column = 2; column < NF; column++) {
      value = $column
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value != "" && value != "App" && value !~ /^-+$/) print value
    }
  }
' "$ROOT/docs/COMPATIBILITY.md" | LC_ALL=C sort > "$compatibility_verified"
printf '%s\n' "$production_block" \
  | sed -n 's/^[[:space:]]*catalogueName: "\(.*\)",$/\1/p' \
  | LC_ALL=C sort > "$registry_catalogue"
compatibility_verified_count="$(wc -l < "$compatibility_verified" | tr -d '[:space:]')"
registry_catalogue_count="$(wc -l < "$registry_catalogue" | tr -d '[:space:]')"
if [[ "$compatibility_verified_count" -ne 16
      || "$registry_catalogue_count" -ne 16 ]]; then
  echo "COMPATIBILITY.md and the production registry must each contain exactly 16 Verified apps; found $compatibility_verified_count and $registry_catalogue_count" >&2
  exit 1
fi
if ! cmp -s "$compatibility_verified" "$registry_catalogue"; then
  echo "Production registry catalogue names differ from docs/COMPATIBILITY.md" >&2
  diff -u "$compatibility_verified" "$registry_catalogue" >&2 || :
  exit 1
fi
compatibility_unverified="$(awk '
  /^## Unverified$/ { unverified = 1; next }
  /^## Pending$/ { unverified = 0 }
  unverified {
    value = $0
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    if (value != "") print value
  }
' "$ROOT/docs/COMPATIBILITY.md")"
if [[ "$compatibility_unverified" != "None yet." ]]; then
  echo "The compiled registry currently models every shipping rule as Verified; the COMPATIBILITY.md Unverified section must remain 'None yet.'" >&2
  exit 1
fi
if grep -Eq 'assurance:|testedVersions:|acceptsAnyVersion:' <<<"$production_block"; then
  echo "Production compatibility badges must not depend on assurance, tested versions, or version acceptance evidence" >&2
  exit 1
fi
require_block_literal \
  'id: "com-anthropic-claudefordesktop-verified"' \
  "$production_block" \
  "Claude's frozen production rule ID is missing"
require_block_literal \
  'bundleIdentifier: "com.anthropic.claudefordesktop"' \
  "$production_block" \
  "Claude's production bundle identity is missing"
require_block_literal \
  'teamIdentifier: "Q6L2SF6YDW"' \
  "$production_block" \
  "Claude's production Team ID is missing"
require_block_literal \
  'id: "com-openai-codex-untested"' \
  "$production_block" \
  "ChatGPT / Codex's frozen historical rule ID is missing"
require_block_literal \
  'bundleIdentifier: "com.openai.codex"' \
  "$production_block" \
  "ChatGPT / Codex's production bundle identity is missing"
require_block_literal \
  'teamIdentifier: "2DC432GLL2"' \
  "$production_block" \
  "ChatGPT / Codex's production Team ID is missing"
require_block_literal \
  '"CODEX_HOME": "{codexHomeDir}"' \
  "$production_block" \
  "ChatGPT / Codex must retain its isolated CODEX_HOME"
require_block_literal \
  '"CODEX_ELECTRON_USER_DATA_PATH": "{profileDir}"' \
  "$production_block" \
  "ChatGPT / Codex must retain its isolated Electron profile path"
require_block_literal \
  '"CLAUDE_CONFIG_DIR": "{codexHomeDir}"' \
  "$production_block" \
  "Claude must retain its isolated config home"
require_block_literal \
  'homeSymlinkPrefix: "claude"' \
  "$production_block" \
  "Claude must retain its stable home-symlink prefix"
require_block_literal \
  'homeSymlinkPrefix: "codex"' \
  "$production_block" \
  "ChatGPT / Codex must retain its stable home-symlink prefix"
grep -q 'M1 removes only Klik PRO' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'currentCandidate.canCreate' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'eligibility.allowsManagedProfile' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
# A relaunch of an already-running profile must reopen that instance, never spawn
# a duplicate — apps like Claude for Desktop enforce no single-instance lock of
# their own. Menu-bar path reopens the one running pid; the Dock/Launchpad/Finder
# runner scans for it before ever creating a new instance.
grep -q 'reopenWindow: true' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
grep -q 'sendReopenEvent(to: existing.processIdentifier)' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
grep -q 'KlikProOriginalLauncher' "$ROOT/Sources/KlikProOriginalLauncher.swift"
grep -q 'originalDockLauncherPath' "$ROOT/Sources/KlikProConfig.swift"
# The original-app Dock icon is opt-in and append-only: it reuses the same
# addLauncherToDock path as profiles and never rewrites the native vendor tile.
# It is compulsory only at profile generation (forced, locked checkbox), where
# failure blocks creation, and is otherwise offered via a per-card toggle.
grep -q 'func ensureOriginalDockIcon' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func createOriginalDockIcon' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func deleteOriginalDockIcon' "$ROOT/Sources/KlikProApp.swift"
# A third gear action removes the NATIVE app's own Dock tile (app stays installed),
# gated on Klik PRO's own Dock icon already existing and confirmed before it runs.
grep -q 'func removeNativeOriginalDockTile' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Remove Native App Dock Icon' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'forcedOriginalDockVendorName' "$ROOT/Sources/KlikProApp.swift"
grep -q 'writeBadgedOriginalIcon' "$ROOT/Sources/KlikProApp.swift"
grep -q 'onCreateOriginalDock' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'func setOriginalDockPinned' "$ROOT/Sources/AppProfilesUI.swift"
# The auto-rewrite of the user's native vendor Dock tile must NOT return.
if grep -q 'rewriteOriginalDockTileIfPresent\|repairOriginalDockLaunchersIfNeeded' \
  "$ROOT/Sources/KlikProApp.swift"; then
  echo "Original Dock icon must be opt-in; native-tile auto-rewrite is not allowed" >&2
  exit 1
fi
grep -q 'configuration.createsNewApplicationInstance = true' \
  "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
# A mouse button / hotkey assigned to a NATIVE app resolves to its legacy mirror
# row; launchOrFocus must route a recognized native target through launchOriginal
# (which excludes managed --user-data-dir processes and forces a fresh original),
# NOT plain launchExternal — otherwise the native "Open App" is hijacked onto an
# already-running managed profile of the same vendor app.
grep -A1 'if let target = instance.legacyQuickLaunchTarget {' \
  "$ROOT/Sources/Duplication/AppProfileRuntime.swift" \
  | grep -q 'launchOriginal(target, completion: completion)'
# Reopen Apple events require a purpose string in both the main app and every
# generated launcher. Existing launchers embed their own runner and metadata, so
# healing must update both in place without touching profile data.
apple_events_usage="$(plutil -extract NSAppleEventsUsageDescription raw -o - "$ROOT/App/Info.plist")"
if [[ "$apple_events_usage" != \
  "Klik PRO reopens the selected App Profile's existing window without launching a duplicate." ]]; then
  echo "Unexpected NSAppleEventsUsageDescription" >&2
  exit 1
fi
grep -q '"NSAppleEventsUsageDescription": Self.appleEventsUsageDescription' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'func refreshLauncherRuntimeIfStale' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'refreshLauncherRuntimeIfStale(for: updated.instances\[index\])' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'rollback must restore executable permissions' \
  "$ROOT/Tests/AppProfilesFoundationTests.swift"
grep -q 'SecStaticCodeCheckValidity' "$ROOT/Sources/Duplication/AppScanner.swift"
grep -q 'kSecCodeInfoEntitlementsDict' "$ROOT/Sources/Duplication/AppScanner.swift"
grep -q 'app.sandboxEntitlement == true' "$ROOT/Sources/Duplication/EngineDetector.swift"
grep -q 'app.hasProvisioningProfile && app.sandboxEntitlement == nil' \
  "$ROOT/Sources/Duplication/EngineDetector.swift"
grep -qF '"CODEX_HOME",' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -qF '"CODEX_ELECTRON_USER_DATA_PATH",' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -qF '"CLAUDE_CONFIG_DIR",' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -qF '"CFFIXED_USER_HOME",' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
launcher_environment_keys="$(grep -cE '^        "[A-Z_]+",$' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift")"
if [[ "$launcher_environment_keys" -ne 4 ]]; then
  echo "Launcher environment allowlist must contain exactly 4 keys, found $launcher_environment_keys" >&2
  exit 1
fi
if grep -q 'environmentOverrides: \[:\]' "$ROOT/Sources/Duplication/AppProfileManager.swift"; then
  echo "Managed construction sites must derive the rule environment, never hardcode empty" >&2
  exit 1
fi
grep -q 'ruleResolvedEnvironment(' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func healManagedInstances' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'healManagedAppProfilesIfNeeded()' "$ROOT/Sources/KlikProApp.swift"
# Ad-hoc signing drops the helper's Accessibility grant on every update while the
# stale entry still shows enabled; the app must explain the re-grant rather than
# leave only the bare system prompt.
grep -q 'func guideAccessibilityRegrantAfterUpdateIfNeeded()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guideAccessibilityRegrantIfStillMissing()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'previous.map { \$0 != current } ?? config.onboardingCompleted' \
  "$ROOT/Sources/KlikProApp.swift"
grep -qF '{profileDir}' "$ROOT/Sources/Duplication/EngineDetector.swift"
grep -qF '{codexHomeDir}' "$ROOT/Sources/Duplication/EngineDetector.swift"
grep -qF '"CodexHomes"' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'func codexHomeURL(for id: UUID)' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
if sed -n '/func resolvedEnvironment/,/^    }/p' "$ROOT/Sources/Duplication/EngineDetector.swift" \
  | grep -q 'label'; then
  echo "Rule environment expansion must never reference labels" >&2
  exit 1
fi
require_source_literal \
  'static let currentSchemaVersion = 16' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "KlikProConfig.currentSchemaVersion must remain 16"
require_source_literal \
  'schemaVersion: KlikProConfig.currentSchemaVersion' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "New configurations must use KlikProConfig.currentSchemaVersion"
require_source_literal \
  'normalized.schemaVersion = KlikProConfig.currentSchemaVersion' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "Config normalization must write the current schema rather than a stale literal"
if grep -Eq 'normalized\.schemaVersion = (12|13)' "$ROOT/Sources/KlikProConfig.swift"; then
  echo "Config normalization must not restore the historic schema 12/13 split" >&2
  exit 1
fi
# Schema 14 mouse profiles: UUID-keyed, one active profile, and a hard maximum of
# three. Guard both validation and mutation paths so changing the display alone
# cannot accidentally permit a fourth persisted profile.
require_source_literal \
  'static let maximumCount = 3' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "MouseProfile.maximumCount must remain 3"
require_source_literal \
  'var activeMouseProfileID: UUID' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "Mouse profiles must persist one active UUID"
require_source_literal \
  'config.mouseProfiles.count <= MouseProfile.maximumCount' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "Mouse-profile validation must enforce the three-profile maximum"
require_source_literal \
  'guard updated.mouseProfiles.count < MouseProfile.maximumCount,' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "Adding a mouse profile must reject a fourth profile"
require_source_literal \
  'if profiles.count > MouseProfile.maximumCount {' \
  "$ROOT/Sources/KlikProConfig.swift" \
  "Mouse-profile normalization must clamp oversized collections"
grep -q 'createPreV2BackupIfNeeded(originalData: data)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'O_WRONLY | O_CREAT | O_EXCL' "$ROOT/Sources/KlikProConfig.swift"

# Durable Data Vault (Phase 1) pins: schema-11 storage remains intact under the
# additive schema-12 lifecycle model, with a fail-closed vault
# location gate, unchanged default derivation, and manifest-gated adopt.
grep -q 'enum AppProfileStorage' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
grep -q 'func vaultPathRejectionReason' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
# The validator must reject Application Support and .app-interior locations.
grep -q 'Library/Application Support' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
grep -qF 'hasSuffix(".app")' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
grep -q 'vaultManifestFileName = "vault.json"' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
# Absent dataRoot / .applicationSupport storage must reuse the exact original
# Application Support derivation (byte-for-byte today's layout).
grep -A3 'func profileURL(for id: UUID, storage: AppProfileStorage)' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift" | grep -q 'return profileURL(for: id)'
grep -A3 'func codexHomeURL(for id: UUID, storage: AppProfileStorage)' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift" | grep -q 'return codexHomeURL(for: id)'
# A vault instance without a wired vault root must fail closed, never fall
# back to Application Support paths.
grep -q 'case vaultUnavailable' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
# Schema 10 -> 11 decode migration: older configs get no vault markers.
grep -q 'if schemaVersion < 11 {' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'forKey: .storage)' "$ROOT/Sources/Duplication/AppProfileInstance.swift"
# Adopt refuses any folder that lacks a valid vault.json manifest.
grep -q 'throw AppProfileManagerError.vaultManifestInvalid' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'VaultManifest.read(vaultRoot: vaultRoot)' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"

# v1.2.1 lifecycle maintenance: archived rows are excluded from runtime, while
# Advanced exposes only non-destructive repair/archive/restore actions and a
# launch-time reconciliation pass repairs derived manifest/launcher state.
grep -q 'enum AppProfileState' "$ROOT/Sources/Duplication/AppProfileInstance.swift"
grep -q 'func reconcileDerivedState(config:' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func repairLauncher(' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func archive(' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func restore(' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'advancedView.onRepair' "$ROOT/Sources/KlikProApp.swift"
grep -q 'advancedView.onArchive' "$ROOT/Sources/KlikProApp.swift"
grep -q 'advancedView.onRestore' "$ROOT/Sources/KlikProApp.swift"

# Durable Data Vault (Phase 2) pins: the dormant backend is wired in through a
# single testable factory, and the locked Advanced tab drives it. The factory
# must fail safe to a no-vault generator (byte-for-byte the pre-vault app) for a
# nil/invalid/Application-Support data root — the guard is the vaultPathRejection
# gate, mirrored in the test suite.
grep -q 'func makeLauncherGenerator(forDataRoot' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func makeAppProfileManager(forDataRoot' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'additionalVaultRoots: \[URL\] = \[\]' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'a markerless UUID in a previous durable root must be Needs Manual Review' \
  "$ROOT/Tests/AppProfilesFoundationTests.swift"
grep -q 'Reveal in Finder' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'vaultPathRejectionReason(dataRoot) == nil else' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'testDataRootWiringFactorySelectsGenerator' \
  "$ROOT/Tests/AppProfilesFoundationTests.swift"
# The production manager is rebuilt from config.dataRoot (never left on the
# default no-vault generator) and the on-launch recovery + Advanced tab are wired.
grep -q 'appProfileManager = makeAppProfileManager(forDataRoot:' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'func rebuildAppProfileManager()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func recoverVaultOnLaunchIfNeeded()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'defaultCandidatePaths: \[\]' "$ROOT/Sources/KlikProApp.swift"
grep -q 'advancedTabRect' "$ROOT/Sources/KlikProApp.swift"
grep -q 'final class AdvancedSettingsContentView' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'let bottomCardHeight = bounds.height - 196' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'statusField.frame = NSRect(x: 28, y: 520, width: width - 260, height: 30)' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'chooseButton.frame = NSRect(x: 28, y: 140, width: 132, height: 28)' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'deepScanButton.frame = NSRect(x: rightColumnX, y: 132' \
  "$ROOT/Sources/AppProfilesUI.swift"
# Advanced tab: the lock icon is the pressable control, gated by a risk confirmation.
grep -q '@objc private func lockPressed()' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'var locked: Bool { isLocked }' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'func confirmUnlockAdvancedSettings()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Only continue if you understand the consequences' "$ROOT/Sources/KlikProApp.swift"
grep -q 'confirmUnlockAdvancedSettings() else { return }' "$ROOT/Sources/KlikProApp.swift"
grep -q 'idx == 3, advancedView.locked' "$ROOT/Sources/KlikProApp.swift"
grep -q 'appProfileManager.adoptVault(config:' "$ROOT/Sources/KlikProApp.swift"
grep -q 'NSOpenPanel()' "$ROOT/Sources/KlikProApp.swift"
# The vault UI must reuse the fail-closed location gate before persisting a path,
# never invent its own validation.
adopt_block="$(sed -n '/private func chooseVaultDataFolder/,/private func createManagedAppProfile/p' \
  "$ROOT/Sources/KlikProApp.swift")"
grep -q 'vaultPathRejectionReason(path)' <<<"$adopt_block"
grep -q 'where instance.state == .active && instance.pinToMenuBar' \
  "$ROOT/Sources/KlikProInput.swift"
grep -q 'updateCheckRequestedNotification' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'title: "Check for updates…"' "$ROOT/Sources/KlikProInput.swift"
grep -q 'DistributedNotificationCenter.default().post(' "$ROOT/Sources/KlikProInput.swift"
grep -q 'forName: updateCheckRequestedNotification' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func checkForUpdatesFromMenuBar()' "$ROOT/Sources/KlikProApp.swift"
# Reopening the app must restart the background helper so the menu-bar icon
# returns after a menu-bar Quit (it stops + disables the helper).
grep -q 'controller?.ensureBackgroundHelperRunningAtLaunch()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func ensureBackgroundHelperRunningAtLaunch()' "$ROOT/Sources/KlikProApp.swift"
# The Dock stores launcher paths as percent-encoded file URLs, so pin detection
# and rename migration must parse them as URLs — a raw path substring match misses
# every launcher whose name has a space.
grep -q 'func dockEntryFilePath' "$ROOT/Sources/KlikProApp.swift"
grep -q 'url.isFileURL' "$ROOT/Sources/KlikProApp.swift"
# Do not restore the failed hidden-launch experiment: it fired a launcher process
# after Apply but did not invalidate the Dock's cached tile.
if grep -Rqs 'KLIK_PRO_DOCK_ICON_REFRESH' \
  "$ROOT/Sources/KlikProApp.swift" "$ROOT/Sources/KlikProManagedLauncher.swift"; then
  echo "The failed Dock icon no-op refresh path must remain removed" >&2
  exit 1
fi
if grep -Eq 'title: "Instances"|openAppProfileInstance|instanceIDsByMenuTag|showsInKlikProInstancesMenu' \
  "$ROOT/Sources/KlikProInput.swift" "$ROOT/Sources/KlikProConfig.swift"; then
  echo "The main Klik PRO menu-bar context menu must not expose an Instances submenu" >&2
  exit 1
fi
grep -q 'bundleIdentifierPrefix = "local.klik-pro.launcher.i"' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
grep -q 'isInternalLauncher || isVisibleLauncher' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
grep -q 'payload.validatedProfileURL(' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
grep -q 'allowsManagedProfile(usingRuleID: payload.compatibilityRuleID)' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
grep -q 'case applicationSupport' \
  "$ROOT/Sources/Duplication/ManagedLauncherPayload.swift"
grep -q 'case vault' \
  "$ROOT/Sources/Duplication/ManagedLauncherPayload.swift"
grep -q 'profileStorage: spec.storage == .vault ? .vault : .applicationSupport' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'payloadIsCurrent' \
  "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'local.klik-pro.settings.app-profile-health' \
  "$ROOT/Sources/KlikProApp.swift"
health_block="$(sed -n '/private func refreshAppProfileHealth()/,/private func appProfileRuntimeErrorMessage/p' \
  "$ROOT/Sources/KlikProApp.swift")"
grep -q 'appProfileHealthQueue.async' <<<"$health_block"
grep -q 'private static func renameDockLauncherIfPresent' "$ROOT/Sources/KlikProApp.swift"
grep -q 'CFPreferencesSetAppValue' "$ROOT/Sources/KlikProApp.swift"
grep -q 'tileData\["file-label"\] = updatedURL.deletingPathExtension().lastPathComponent' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'func generatedLauncherURL(for instance: AppProfileInstance)' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
open_profile_block="$(sed -n '/private func launchAppProfile/,/private func refreshAppProfileHealth/p' \
  "$ROOT/Sources/KlikProApp.swift")"
grep -q 'appProfileManager.generatedLauncherURL(for: instance)' <<<"$open_profile_block"
grep -q 'NSWorkspace.shared.openApplication(' <<<"$open_profile_block"
grep -q 'proc_pidpath' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
grep -q 'KERN_PROCARGS2' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
grep -q 'mode: .exclusive' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'for scanIndex in 0..<2' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'suppressedLegacyInstanceIDs' "$ROOT/Sources/KlikProConfig.swift"

if plutil -extract NSHumanReadableCopyright raw -o - "$ROOT/App/Info.plist" >/dev/null 2>&1; then
  echo "The app bundle must not display a copyright line" >&2
  exit 1
fi
if plutil -extract NSHumanReadableCopyright raw -o - "$ROOT/App/KlikProHelper-Info.plist" >/dev/null 2>&1; then
  echo "The helper bundle must not display a copyright line" >&2
  exit 1
fi
grep -q 'GNU GENERAL PUBLIC LICENSE' "$ROOT/LICENSE"
grep -q 'Version 3, 29 June 2007' "$ROOT/LICENSE"
grep -q 'Copyright © 2026 Aminudin Murad' "$ROOT/README.md"
grep -q 'render-dmg-background.swift' "$ROOT/tools/build-release.sh"
grep -q 'set background picture of theViewOptions' "$ROOT/tools/build-release.sh"
grep -q 'file ".background:dmg-background.png"' "$ROOT/tools/build-release.sh"
grep -Fq 'DMG_MOUNT="/Volumes/Klik PRO v$VERSION"' "$ROOT/tools/build-release.sh"
grep -q 'DMG volume is already mounted' "$ROOT/tools/build-release.sh"
grep -q 'Drag Klik PRO to Applications' "$ROOT/tools/render-dmg-background.swift"
grep -q 'arrow.lineWidth = 9' "$ROOT/tools/render-dmg-background.swift"
grep -q 'arrow.line(to: NSPoint(x: 255, y: 210))' "$ROOT/tools/render-dmg-background.swift"
grep -q 'Manual installation tools are available in Extras' \
  "$ROOT/tools/render-dmg-background.swift"
grep -q 'DMG top level must keep technical files inside Extras' "$ROOT/tools/build-release.sh"
grep -q 'Extras/LaunchAgents' "$ROOT/tools/build-release.sh"
if [[ "$(grep -ci 'copyright' "$ROOT/README.md")" -ne 1 ]]; then
  echo "README must assert the project copyright exactly once (GPL-3.0 requires the owner's notice)" >&2
  exit 1
fi
grep -q '^## Support development$' "$ROOT/README.md"
readme_license_mentions="$(grep -c \
  'This app is open source under the GNU General' "$ROOT/README.md")"
if [[ "$readme_license_mentions" -ne 2 ]]; then
  echo "README must contain the GPL-3.0 statement exactly twice" >&2
  exit 1
fi
grep -q 'https://github.com/sponsors/aminudinmurad' "$ROOT/README.md"
grep -q 'https://ko-fi.com/aminudinmurad' "$ROOT/README.md"
grep -q 'https://www.paypal.com/paypalme/aminudinmurad' "$ROOT/README.md"
grep -q '\*\*Not affiliated with Logitech\.\*\*' "$ROOT/README.md"
grep -q 'trademarks of Logitech International S.A.' "$ROOT/README.md"
unrelatedAppPattern='Snap''zy|Dock''Door'
if grep -Eiq "$unrelatedAppPattern" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/docs/INSTALL.md"; then
  echo "Release-facing documentation contains unrelated app-specific references" >&2
  exit 1
fi

# The Terminal installer must fail closed around the checked-in release trust root.
bash -n \
  "$ROOT/install.sh" \
  "$ROOT/tools/sign-release-manifest.sh" \
  "$ROOT/tools/build-release.sh" \
  "$ROOT/tools/xcode-dev.sh"
bash -n "$ROOT/tools/evidence-run.sh"
for executable_script in \
  "$ROOT/install.sh" \
  "$ROOT/tools/sign-release-manifest.sh" \
  "$ROOT/tools/evidence-run.sh"
do
  if [[ ! -x "$executable_script" ]]; then
    echo "Required script is not executable: $executable_script" >&2
    exit 1
  fi
done
installerPublicKey="$(sed -n 's/^readonly RELEASE_PUBLIC_KEY="\(.*\)"/\1/p' "$ROOT/install.sh")"
signerPublicKey="$(sed -n 's/^readonly EXPECTED_PUBLIC_KEY="\(.*\)"/\1/p' "$ROOT/tools/sign-release-manifest.sh")"
publishedPublicKey="$(awk '{ print $1 " " $2 }' "$ROOT/release-signing-key.pub")"
if [[ -z "$installerPublicKey" || "$installerPublicKey" != "$signerPublicKey" ]]; then
  echo "Installer and manifest signer must embed the same non-empty release public key" >&2
  exit 1
fi
if [[ "$installerPublicKey" != "$publishedPublicKey" ]]; then
  echo "Embedded release public key must match release-signing-key.pub" >&2
  exit 1
fi
release_key_fingerprint="$(ssh-keygen -lf "$ROOT/release-signing-key.pub" | awk '{ print $2 }')"
if [[ "$release_key_fingerprint" != \
  'SHA256:Evg4ITqpPJY/aIT48Zv9Cp3psQfo977uCz/35a2k79E' ]]; then
  echo "Unexpected release signing key fingerprint" >&2
  exit 1
fi
printf 'klik-pro-release %s\n' "$installerPublicKey" > "$OUT/release-allowed-signers"
ssh-keygen -Y verify \
  -f "$OUT/release-allowed-signers" \
  -I klik-pro-release \
  -n klik-pro-release \
  -s "$ROOT/Tests/fixtures/release-manifest-test.sha256.sig" \
  < "$ROOT/Tests/fixtures/release-manifest-test.sha256" >/dev/null
grep -q -- "--proto '=https'" "$ROOT/install.sh"
grep -q -- '-readonly' "$ROOT/install.sh"
grep -q 'ssh-keygen -Y verify' "$ROOT/install.sh"
grep -q 'shasum -a 256' "$ROOT/install.sh"
grep -q 'codesign --verify --deep --strict' "$ROOT/install.sh"
grep -q 'EXPECTED_HELPER_IDENTIFIER="local.klik-pro.helper"' "$ROOT/install.sh"
grep -q 'xattr -dr com.apple.quarantine "$stage_path"' "$ROOT/install.sh"
grep -q 'Keeping the existing app as a temporary rollback copy' "$ROOT/install.sh"
grep -q 'verify_executable_identity "$source_app" "$stage_path" "Staged app"' \
  "$ROOT/install.sh"
grep -q 'verify_executable_identity "$source_app" "$destination_app" "Installed app"' \
  "$ROOT/install.sh"
if sed '/^[[:space:]]*#/d' "$ROOT/install.sh" \
  | grep -Eq 'curl[^#]*\|[[:space:]]*(ba)?sh'; then
  echo "Installer must never pipe a network response into a shell" >&2
  exit 1
fi

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/Tests/MouseButtonRoutingTests.swift" \
  -o "$OUT/mouse-button-routing-tests"
"$OUT/mouse-button-routing-tests"

# The Mappings mouse slide lays a transparent full-card overlay over the mapping
# rows, so it needs a custom hitTest: clicks must fall through to the rows while the
# overlay's own gear and arrows stay clickable. `NSView.hitTest(_:)` takes a point in
# the receiver's SUPERVIEW space, so converting into a subview's own space first
# subtracts its frame origin twice — which once shipped the gear and both arrows
# completely unclickable. Screenshot fixtures cannot see this: a dead gear renders
# exactly like a live one.
require_source_literal \
  'let local = superview.map { convert(point, from: $0) } ?? point' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The mouse slide overlay must convert hit-test points from its superview space"
if grep -qF 'subview.convert(point, from: self)' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Hit-test points must not be converted into a subview's own space before NSView.hitTest" >&2
  exit 1
fi
# The gear presents its menu from mouseDown, which bypasses NSControl's own disabled
# guard, so isEnabled has to be rechecked there.
require_source_literal \
  'guard isEnabled, let onMouseDown else {' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "A gear that opens its menu on mouse-down must still honor isEnabled"
# RefreshIconButton's hitTest carried the same slip in the other direction: it
# compared the superview-space point with its own `bounds`, anchoring the hit region
# at the superview's origin and leaving every refresh button dead where it is drawn.
require_source_literal \
  'guard !isHidden, frame.contains(point) else { return nil }' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "A button that overrides hitTest must compare the point with its frame, not its bounds"
if grep -qF 'bounds.contains(point) ? self : nil' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "A superview-space hit-test point must not be compared with bounds" >&2
  exit 1
fi

awk '/^@main$/ { exit } { print }' \
  "$ROOT/Sources/KlikProApp.swift" > "$OUT/MouseSlideHitTestAppBody.swift"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$OUT/MouseSlideHitTestAppBody.swift" \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "$ROOT/Sources/KlikProBrand.swift" \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/tools/MouseSlideHitTestMain.swift" \
  -o "$OUT/mouse-slide-hit-test"
"$OUT/mouse-slide-hit-test"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/Tests/LaunchAgentInstallerTests.swift" \
  -o "$OUT/launch-agent-installer-tests"
"$OUT/launch-agent-installer-tests"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/Tests/AppProfilesFoundationTests.swift" \
  -o "$OUT/app-profiles-foundation-tests"
"$OUT/app-profiles-foundation-tests"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/tools/EvidenceMain.swift" \
  -o "$OUT/evidence-main"
if grep -q 'KlikProConfigStore.save' "$ROOT/tools/EvidenceMain.swift"; then
  echo "Evidence harness must never write the real Klik PRO config" >&2
  exit 1
fi
grep -q 'applicationSupportURL: workspace' "$ROOT/tools/EvidenceMain.swift"
grep -q 'identity changed since inspect/create' "$ROOT/tools/EvidenceMain.swift"
grep -q 'expandingTildeInPath' "$ROOT/tools/EvidenceMain.swift"
grep -q 'must not be inside live Klik PRO Application Support' "$ROOT/tools/EvidenceMain.swift"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "${LAUNCHER_RUNTIME_SOURCES[@]}" \
  "$ROOT/Sources/KlikProManagedLauncher.swift" \
  -o "$OUT/klik-pro-managed-launcher"

if grep -En 'CGEventType\.(keyDown|keyUp)|keyboardEventKeycode|kVK_Tab' "$ROOT/Sources/KlikProInput.swift"; then
  echo "Input helper must never subscribe to or inspect keyboard Command-Tab" >&2
  exit 1
fi
grep -q 'gestureSentinelKeyCode' "$ROOT/Sources/KlikProInput.swift"
grep -q 'applyGestureSentinelMappingIfSafe' "$ROOT/Sources/KlikProInput.swift"
grep -q 'isReservedKeyboardCommandTab(config.chatGPTHotkey.combo)' "$ROOT/Sources/KlikProInput.swift"
grep -q 'isReservedKeyboardCommandTab(config.claudeHotkey.combo)' "$ROOT/Sources/KlikProInput.swift"
grep -q 'mouseButtonDispatchState.begin' "$ROOT/Sources/KlikProInput.swift"
grep -q 'mouseButtonDispatchState.end' "$ROOT/Sources/KlikProInput.swift"
grep -q 'klikProStatusController = KlikProStatusController(' "$ROOT/Sources/KlikProInput.swift"
grep -q 'caffeinateMenuEnabled: config.caffeinateMenuEnabled' "$ROOT/Sources/KlikProInput.swift"
grep -q 'button.image = klikProMenuBarIcon()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'image.isTemplate = true' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'green: 187 / 255' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'activeIndicatorView.image = klikProMenuBarActiveIndicator()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'activeIndicatorView.isHidden = !active' "$ROOT/Sources/KlikProInput.swift"
grep -q 'setKlikProInputActive(CGEvent.tapIsEnabled(tap: tap))' "$ROOT/Sources/KlikProInput.swift"
klikProStatusBlock="$(sed -n '/private final class KlikProStatusController/,/^}/p' "$ROOT/Sources/KlikProInput.swift")"
grep -q 'title: "Settings…"' <<<"$klikProStatusBlock"
grep -q 'contextMenu.minimumWidth = 220' <<<"$klikProStatusBlock"
grep -q 'statusItem.menu = contextMenu' <<<"$klikProStatusBlock"
grep -q 'sender.performClick(nil)' <<<"$klikProStatusBlock"
grep -q 'func menuDidClose' <<<"$klikProStatusBlock"
if grep -q 'contextMenu.popUp' <<<"$klikProStatusBlock"; then
  echo "Klik PRO status menu must use native status-item positioning" >&2
  exit 1
fi
grep -q 'title: "About Klik PRO"' <<<"$klikProStatusBlock"
grep -q 'makeKlikProAboutAlert(version: version, build: build, icon: icon)' <<<"$klikProStatusBlock"
grep -q 'alert.runModal()' <<<"$klikProStatusBlock"
if grep -q 'orderFrontStandardAboutPanel' <<<"$klikProStatusBlock"; then
  echo "About Klik PRO must use the shared branded About panel" >&2
  exit 1
fi
brandBlock="$(sed -n '/enum KlikProBrand/,/^}/p' "$ROOT/Sources/KlikProBrand.swift")"
grep -q 'badgeFont = NSFont.systemFont(ofSize: 5, weight: .bold)' <<<"$brandBlock"
grep -q 'badgeHeight: CGFloat = 8' <<<"$brandBlock"
grep -q 'badgeHorizontalPadding: CGFloat = 2' <<<"$brandBlock"
grep -q 'badgeCornerRadius: CGFloat = 1.5' <<<"$brandBlock"
grep -q 'wordmarkGap: CGFloat = 3' <<<"$brandBlock"
grep -q 'badgeRaise: CGFloat = 4' <<<"$brandBlock"
grep -q 'srgbRed: 25 / 255' <<<"$brandBlock"
grep -q 'green: 187 / 255' <<<"$brandBlock"
grep -q 'blue: 19 / 255' <<<"$brandBlock"
grep -q 'final class KlikProWordmarkView' "$ROOT/Sources/KlikProBrand.swift"
grep -q 'func makeKlikProAboutAlert' "$ROOT/Sources/KlikProBrand.swift"
grep -q 'https://github.com/AminudinMurad/klik-pro' "$ROOT/Sources/KlikProBrand.swift"
grep -q 'title: "Support"' "$ROOT/Sources/KlikProBrand.swift"
grep -q 'https://github.com/sponsors/aminudinmurad' "$ROOT/Sources/KlikProBrand.swift"
grep -q 'title: "Quit Klik PRO…"' <<<"$klikProStatusBlock"
grep -q 'button.sendAction(on: \[.leftMouseUp, .rightMouseUp\])' <<<"$klikProStatusBlock"
grep -q 'if config.showMenuBarIcon' "$ROOT/Sources/KlikProInput.swift"
grep -q 'compactMenuBarApplicationIcon(icon)' "$ROOT/Sources/KlikProInput.swift"
if grep -q 'if config.showQuickLaunchMenuIcons' "$ROOT/Sources/KlikProInput.swift"; then
  echo "App Profile menu-bar icons must not be blocked by a Settings master toggle" >&2
  exit 1
fi
grep -q 'quickLaunchMenuBarController = MenuBarController()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'installAccessibilitySetupObserver()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'installAccessibilityStatusCheckObserver()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'application.finishLaunching()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'let trusted = AXIsProcessTrusted()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'name: accessibilitySetupRequestedNotification' "$ROOT/Sources/KlikProApp.swift"
grep -q 'name: accessibilityStatusCheckRequestedNotification' "$ROOT/Sources/KlikProApp.swift"
grep -q 'title: "Reset…"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'title: "Recheck"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'preferencesView.recheckAccessibilityLink.onClick' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recheckAccessibilityLink.title = "Checking…"' "$ROOT/Sources/KlikProApp.swift"
grep -A16 'openAccessibilityLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'width: 136'
grep -A12 'recheckAccessibilityLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'x: rxi + 144'
grep -A12 'resetAccessibilityLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'x: rxi + 224'
grep -A12 'openLogsLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'x: rxi + 316'
grep -q 'statusColor.withAlphaComponent(0.42).setStroke()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'pillPath.lineWidth = 1' "$ROOT/Sources/KlikProApp.swift"
grep -q 'executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")' "$ROOT/Sources/KlikProApp.swift"
grep -q 'process.arguments = \["reset", "Accessibility", bundleIdentifier\]' "$ROOT/Sources/KlikProApp.swift"
grep -q 'resetAccessibilityApproval(bundleIdentifier: "local.klik-pro.helper")' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func installLaunchAgentPlist(' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory()' "$ROOT/Sources/KlikProConfig.swift"
grep -q '"LimitLoadToSessionType": "Aqua"' "$ROOT/Sources/KlikProConfig.swift"
grep -q '<key>LimitLoadToSessionType</key>' "$ROOT/LaunchAgents/local.klik-pro.input.plist"
grep -q '<string>Aqua</string>' "$ROOT/LaunchAgents/local.klik-pro.input.plist"
grep -q '_ = installLaunchAgentPlist(appBundleURL: Bundle.main.bundleURL)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guard ensureLaunchAgentSetup() else { return }' "$ROOT/Sources/KlikProApp.swift"
grep -q 'alert.messageText = "Background services could not be installed"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.beginAccessibilitySetup()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'final class OnboardingChecklistView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'enum OnboardingStep: Int' "$ROOT/Sources/KlikProApp.swift"
grep -q 'final class OnboardingWelcomePageView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'final class OnboardingAccessibilityPageView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func makeOnboardingAlert(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'step: OnboardingStep,' "$ROOT/Sources/KlikProApp.swift"
# The stepped flow must offer Back on later steps and never offer a Cancel/skip.
grep -q 'alert.addButton(withTitle: "Back")' "$ROOT/Sources/KlikProApp.swift"
if grep -qE 'addButton\(withTitle: (accessibilityGranted \? "Close" : )?"Not Now"\)' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Onboarding must not offer a Not Now/Cancel escape" >&2
  exit 1
fi
grep -q 'forResource: "OnboardingPreviewIcon"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'OnboardingPreviewIcon.png' "$ROOT/tools/render-previews.sh"
grep -q 'prefix: "Welcome to "' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private let headerWordmark: KlikProWordmarkView' "$ROOT/Sources/KlikProApp.swift"
grep -A10 'private let headerWordmark: KlikProWordmarkView' "$ROOT/Sources/KlikProApp.swift" | grep -q 'let scale: CGFloat = 2'
grep -A10 'private let headerWordmark: KlikProWordmarkView' "$ROOT/Sources/KlikProApp.swift" | grep -q 'scale: scale'
grep -q 'addSubview(headerWordmark)' "$ROOT/Sources/KlikProApp.swift"
if grep -q 'OnboardingWelcomeTitleView' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Onboarding must use the shared Klik PRO wordmark" >&2
  exit 1
fi
onboardingHoverBlock="$(sed -n '/final class ButtonHoverOutlineView/,/^}/p' "$ROOT/Sources/KlikProApp.swift")"
grep -q 'options: \[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect\]' <<<"$onboardingHoverBlock"
grep -q 'NSColor.controlAccentColor.withAlphaComponent(0.82).setStroke()' <<<"$onboardingHoverBlock"
grep -q 'backButton.addSubview(backHoverOutline)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'showFirstLaunchOnboardingIfNeeded()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'presentOnboarding(force: true)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'alert.addButton(withTitle: "Start Using Klik PRO")' "$ROOT/Sources/KlikProApp.swift"
grep -q 'alert.addButton(withTitle: "Set Up Accessibility…")' "$ROOT/Sources/KlikProApp.swift"
grep -q 'KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED' "$ROOT/Sources/KlikProApp.swift"
# Step 4 is opt-in: grant now, or "Skip for Now" (completes onboarding, grant later).
grep -q 'alert.addButton(withTitle: "Skip for Now")' "$ROOT/Sources/KlikProApp.swift"
if grep -q 'addButton(withTitle: "View Mappings")' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Onboarding step 4 no longer offers View Mappings" >&2
  exit 1
fi
# Step 2 offers the suggested data folder as the default action, so a fresh install
# can store profiles durably without a later migration. Its skip uses the same
# "Skip for Now" wording as the Accessibility step — never "Not Now"/Cancel — so the
# choice is never forced and never reads as an escape. The folder must be applied
# with the other first-run choices rather than persisted mid-flow.
grep -q 'alert.addButton(withTitle: "Use This Folder")' "$ROOT/Sources/KlikProApp.swift"
dataFolderStepBlock="$(sed -n '/^    case .dataFolder:/,/^    case .preferences:/p' \
  "$ROOT/Sources/KlikProApp.swift")"
grep -q 'alert.addButton(withTitle: "Skip for Now")' <<<"$dataFolderStepBlock"
grep -q 'alert.addButton(withTitle: "Back")' <<<"$dataFolderStepBlock"
grep -q 'func defaultVaultDataRootPath' "$ROOT/Sources/Duplication/VaultDataRoot.swift"
grep -q 'pendingOnboardingDataRoot' "$ROOT/Sources/KlikProApp.swift"
if grep -q 'KlikProConfigStore.save' <<<"$(sed -n '/func prepareOnboardingDataFolder/,/^    }/p' "$ROOT/Sources/KlikProApp.swift")"; then
  echo "The first-run data folder must not be persisted before onboarding completes" >&2
  exit 1
fi
grep -q 'KLIK_PRO_PREVIEW_ONBOARDING_STEP=4' "$ROOT/tools/render-previews.sh"
grep -q 'onboarding-data-folder.png' "$ROOT/tools/render-previews.sh"
grep -q 'onboardingCompleted = schemaVersion < 8' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'Open-source mouse shortcuts and App Profiles for macOS.' "$ROOT/Sources/KlikProApp.swift"
grep -A4 'openAccessibilityLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" | grep -q 'style: .outline'
grep -A4 'openAccessibilityLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" | grep -q 'Privacy_Accessibility'
if grep -Eq 'title: "(Input Monitoring|Screen Recording|Automation)"|statusText: "Not required"' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Permissions card must show only required permissions" >&2
  exit 1
fi
grep -q 'showMenuBarIconRow.onToggleChange' "$ROOT/Sources/KlikProApp.swift"
if grep -Eq 'showQuickLaunchMenuIconsRow|Show Dual App menu bar icons|Show generated Dual Apps' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Settings must not expose a master App Profile menu-bar icon toggle" >&2
  exit 1
fi
grep -q 'hoverTitle: "Change ⋯"' "$ROOT/Sources/AppProfilesUI.swift"
toggle_menu_block="$(sed -n '/private func toggleMenuBarPin/,/private func renameAppProfile/p' "$ROOT/Sources/KlikProApp.swift")"
grep -q 'appProfileQueue.async' <<<"$toggle_menu_block"
grep -q 'Showing \\(instance.label) in the menu bar…' <<<"$toggle_menu_block"
before_toggle_queue="$(sed -n '/private func toggleMenuBarPin/,/appProfileQueue.async/p' "$ROOT/Sources/KlikProApp.swift")"
if grep -q 'applySavedConfig()' <<<"$before_toggle_queue"; then
  echo "App Profile menu-bar toggle must not apply helper changes synchronously on the UI thread" >&2
  exit 1
fi
if grep -q 'Assigned:' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "App Profile rows must show the current button beside the Change control, not as an Assigned badge" >&2
  exit 1
fi
grep -q 'options: \[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect\]' "$ROOT/Sources/KlikProApp.swift"
grep -q 'animation.duration = 0.14' "$ROOT/Sources/KlikProApp.swift"
grep -q 'forKey: "supportButtonHover"' "$ROOT/Sources/KlikProApp.swift"
headerActionBlock="$(sed -n '/final class HeaderActionButton/,/^}/p' "$ROOT/Sources/KlikProApp.swift")"
grep -q 'options: \[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect\]' <<<"$headerActionBlock"
grep -q ': (isHovered ? KlikProBrand.green : accent)' <<<"$headerActionBlock"
grep -q 'if isHovered && isEnabled' <<<"$headerActionBlock"
grep -q 'case .primary: stroke = .black' <<<"$headerActionBlock"
grep -A6 'private let saveButton = HeaderActionButton' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'symbolName: "externaldrive.fill"'
grep -A6 'private let closeDashboardButton = HeaderActionButton' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'symbolName: "xmark"'
grep -A6 'private let powerOffButton = HeaderActionButton' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'symbolName: "power"'
grep -q 'saveButton.onPress' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.saveConfiguration()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'closeDashboardButton.onPress' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.requestCloseDashboard()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'powerOffButton.onPress' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.requestPowerOff()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'label: "local.klik-pro.settings.save-apply"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'saveApplyQueue.async' "$ROOT/Sources/KlikProApp.swift"
grep -q 'DispatchQueue.main.async' "$ROOT/Sources/KlikProApp.swift"
grep -q 'saveButton.setAccessibilityLabel(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Saved — helper apply timed out.' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func run(_ arguments: \[String\], timeout: TimeInterval = 8)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'completion.wait(timeout: .now() + timeout)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'checkForUpdatesLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift"
grep -A8 'checkForUpdatesLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'title: "Updates…"'
grep -q 'preferencesView.onCheckForUpdates' "$ROOT/Sources/KlikProApp.swift"
grep -q 'showUpdateButtonHoverPreview()' "$ROOT/Sources/KlikProApp.swift"
if grep -Eq 'updateButtonRect|updateButtonHovered|updateButtonTrackingArea' \
  "$ROOT/Sources/KlikProApp.swift"; then
  echo "Updates must live in Settings > About, not in the dashboard header" >&2
  exit 1
fi
grep -q 'alert.messageText = "Power Off Klik PRO?"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'UserDefaults.standard.set(false, forKey: launchAtLoginPreferenceKey)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'let disabled = run(\["disable", inputTarget\]) == 0' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q '_ = run(\["bootout", domain, inputPlistPath\])' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'if previewRenderingIsActive {' "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let footerHeight: CGFloat = 20' "$ROOT/Sources/KlikProApp.swift"
if grep -Eq 'closeButtonRect|showCloseButtonHoverPreview|drawCentered\(\"Close\"' \
  "$ROOT/Sources/KlikProApp.swift"; then
  echo "Close must remain a native header action, not a custom footer control" >&2
  exit 1
fi
grep -q 'let settingsButton = IconActionButton(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private let appProfilesView: AppProfilesContentView' "$ROOT/Sources/KlikProApp.swift"
# Tab rects are recomputed each draw for the centered pill bar, so they are vars.
grep -q 'private var appProfilesTabRect' "$ROOT/Sources/KlikProApp.swift"
grep -q 'refreshSupportedAppCandidates()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'appProfileManager.candidates()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func supportedCandidates(searchRoots:' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'appProfilesView.onGenerate' "$ROOT/Sources/KlikProApp.swift"
grep -q 'APP PROFILE GENERATOR' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'Generate another icon for the same app, with a separate login and settings.' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'The native app is never copied, cloned or modified.' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'AppProfileButton(title: "+ New Profile"' "$ROOT/Sources/AppProfilesUI.swift"
if grep -q 'AppProfileButton(title: "Generate"' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "App Profile generator must use the approved + New Profile label" >&2
  exit 1
fi
grep -q 'Assign Button' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'case original(QuickLaunchTarget)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'case profile(UUID)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'func assigningMouseButton(' "$ROOT/Sources/KlikProConfig.swift"
# The Mappings native rows carry NO "Native app" subtitle — it was the third row,
# dropped for the same reason as the generator's "Installed" line. The list is
# titled NATIVE APPS, so repeating it per card said nothing.
if grep -q 'labelWithString: "Native app"' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "Mappings native rows must not carry a per-card \"Native app\" subtitle" >&2
  exit 1
fi
grep -q 'mappingProfilesView.onAssignOriginal' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private static let generatorColumnRatio: CGFloat = 0.50' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'let generatorColumnWidth = floor(width \* Self.generatorColumnRatio)' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'let profilesX = generatorColumnWidth + 16' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'statusField.frame = NSRect(x: profilesX, y: 108' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'x: generatorColumnWidth + 12' "$ROOT/Sources/AppProfilesUI.swift"
# The generator card's actions stay right-flushed, and the assignment pill sizes to
# its own label (fit-to-text) instead of stretching or using a fixed width.
grep -q 'func relayoutActionButtons' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'YOUR APP PROFILES' "$ROOT/Sources/AppProfilesUI.swift"
# The assign control carries the assignment in its own label with a chain-link
# indicator (linked when assigned, link-plus when not) — no separate green caption.
grep -q 'symbolName: "link"' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'symbolName: "link.badge.plus"' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'Force Release & Assign' "$ROOT/Sources/KlikProApp.swift"
grep -q 'final class DualAppGeneratorCard' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'showSupportedAppProfilesPreview()' "$ROOT/tools/PreviewMain.swift"
grep -q 'showEmptyAppProfilesPreview()' "$ROOT/tools/PreviewMain.swift"
grep -q 'app-profiles-empty.png' "$ROOT/tools/render-previews.sh"
if grep -Eq 'AppProfilePicker|Search installed apps|Browse…|＋ Add app|Search profiles|Unsupported|Testing Planned|Convert' \
  "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "App Profiles must not expose generic search, unsupported apps, or conversion" >&2
  exit 1
fi
grep -q 'KlikProManagedLauncher' "$ROOT/tools/build-release.sh"
grep -q 'final class MappingAppProfilesView' "$ROOT/Sources/AppProfilesUI.swift"
# All four app lists share one 86-point row geometry and one persistent custom
# right-side scrollbar whose handle is exactly one card tall. AppKit's native
# proportional/auto-hidden scroller is deliberately disabled.
require_source_literal \
  'static let height: CGFloat = 86' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "All app-list cards must use the shared 86-point AppCardMetrics height"
app_card_row_types="$(awk '
  /static let (cardHeight|rowHeight): CGFloat = AppCardMetrics.height/ { count++ }
  END { print count + 0 }
' "$ROOT/Sources/AppProfilesUI.swift")"
if [[ "$app_card_row_types" -ne 4 ]]; then
  echo "All four app card row types must use AppCardMetrics.height; found $app_card_row_types" >&2
  exit 1
fi
require_source_literal \
  'private final class FixedAppCardScrollbarView: NSView' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The four app lists must use the deterministic fixed scrollbar"
require_source_literal \
  'private let scrollbar: FixedAppCardScrollbarView' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The shared AppCardListView must own its fixed scrollbar"
require_source_literal \
  'thumbHeight: CGFloat = AppCardMetrics.height,' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The app-list scrollbar handle must default to one 86-point app card"
require_source_literal \
  'let thumbHeight = min(self.thumbHeight, track.height)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The shared scrollbar must use its configured handle height"
require_source_literal \
  'x: bounds.width - FixedAppCardScrollbarView.width,' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The fixed app-list scrollbar must remain on the right edge"
require_source_literal \
  'scrollView.autohidesScrollers = false' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "App-list scrollbars must remain visible regardless of macOS preferences"
if grep -qF 'scrollView.autohidesScrollers = true' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "The shared app-list scrollbar must never auto-hide" >&2
  exit 1
fi
shared_list_declarations="$(awk '
  /private let (listView|generatorList|profilesList) = AppCardListView\(frame: \.zero\)/ {
    count++
  }
  END { print count + 0 }
' "$ROOT/Sources/AppProfilesUI.swift")"
mapping_section_instances="$(awk '
  /= MappingSectionCardView\(/ { count++ }
  END { print count + 0 }
' "$ROOT/Sources/AppProfilesUI.swift")"
if [[ "$shared_list_declarations" -ne 3 || "$mapping_section_instances" -ne 2 ]]; then
  echo "Expected two App Profiles lists plus two Mappings lists to share AppCardListView; found $shared_list_declarations declarations and $mapping_section_instances Mappings sections" >&2
  exit 1
fi
# The Mappings tab has two independently scrolling side-by-side sections, while
# the App Profiles tab supplies the other two shared lists.
require_source_literal \
  'private final class MappingSectionCardView: NSView' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings must retain its shared app-list section component"
require_source_literal \
  'title: "NATIVE APPS"' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings must retain the Native Apps list"
require_source_literal \
  'title: "APP PROFILES"' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings must retain the App Profiles list"
require_source_literal \
  'private let generatorList = AppCardListView(frame: .zero)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The App Profile Generator must use the shared scroll list"
require_source_literal \
  'private let profilesList = AppCardListView(frame: .zero)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Your App Profiles must use the shared scroll list"

# Every refresh button swaps its arrow for the native spinner during a scan, and
# every list receives the same dimmed-card spinner overlay. Three source
# declarations create four runtime buttons because MappingSectionCardView is
# instantiated twice.
refresh_button_declarations="$(awk '
  /= makeRefreshIconButton\(\)/ { count++ }
  END { print count + 0 }
' "$ROOT/Sources/AppProfilesUI.swift")"
if [[ "$refresh_button_declarations" -ne 3 ]]; then
  echo "Expected four runtime refresh arrows from three shared declarations; found $refresh_button_declarations" >&2
  exit 1
fi
require_source_literal \
  'final class RefreshIconButton: AppProfileButton' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "App-list refresh controls must use RefreshIconButton"
require_source_literal \
  'private let spinner = NSProgressIndicator()' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Refresh buttons must use the native macOS progress indicator"
require_source_literal \
  'glyphView.isHidden = refreshing' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Refresh buttons must hide the static arrow while loading"
require_source_literal \
  'spinner.isHidden = !refreshing' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Refresh buttons must show the spinner only while loading"
require_source_literal \
  'spinner.startAnimation(nil)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Refresh must start the native spinner"
require_source_literal \
  'spinner.stopAnimation(nil)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Refresh completion must stop the native spinner"
require_source_literal \
  'private final class AppCardRefreshOverlayView: NSView' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Every app list must retain the shared loading overlay"
require_source_literal \
  'private let refreshOverlay = AppCardRefreshOverlayView(frame: .zero)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "AppCardListView must own its loading overlay"
require_source_literal \
  'spinner.startAnimation(nil)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The app-list loading overlay must animate its spinner"
require_source_literal \
  'spinner.stopAnimation(nil)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The app-list loading overlay must stop its spinner when refresh finishes"
require_source_literal \
  'refreshOverlay.setActive(refreshing, message: message)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "The shared list busy state must drive its loading overlay"
require_source_literal \
  'nativeCard.setRefreshing(refreshing, message: message)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings Native Apps must show the shared refresh state"
require_source_literal \
  'profilesCard.setRefreshing(refreshing, message: message)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings App Profiles must show the shared refresh state"
require_source_literal \
  'nativeCard.setRefreshing(false)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings Native Apps must clear its initial loading overlay once apps arrive"
require_source_literal \
  'generatorList.setRefreshing(refreshing, message: message)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "App Profile Generator must show the shared refresh overlay"
require_source_literal \
  'profilesList.setRefreshing(refreshing, message: message)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Your App Profiles must show the shared refresh overlay"
require_source_literal \
  'appProfilesView.setRefreshing(busy)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The controller must synchronize both App Profiles refresh controls"
require_source_literal \
  'contentView.mappingProfilesView.setRefreshing(busy)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The controller must synchronize both Mappings refresh controls"
require_source_literal \
  'setRefreshControlsBusy(true)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "App discovery must visibly enter the shared refresh state"
require_source_literal \
  'setRefreshControlsBusy(false)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "App discovery must always leave the shared refresh state"
# Both the full App Profiles rows and compact Mappings rows must use the same
# direct launcher-icon loader. Loading the source bundle in Mappings would hide
# every managed profile's custom/tinted/badged icon there.
grep -q 'private func appProfileDisplayIcon(for instance: AppProfileInstance)' \
  "$ROOT/Sources/AppProfilesUI.swift"
if [[ "$(grep -c 'iconView.image = appProfileDisplayIcon(for: instance)' \
  "$ROOT/Sources/AppProfilesUI.swift")" -ne 2 ]]; then
  echo "App Profiles and Mappings must share the managed profile icon loader" >&2
  exit 1
fi
grep -q 'mappingProfilesView.onOpen' "$ROOT/Sources/KlikProApp.swift"
grep -q 'mappingProfilesView.setInstances' "$ROOT/Sources/KlikProApp.swift"
grep -q 'mappingProfilesView.setRuntimeHealth' "$ROOT/Sources/KlikProApp.swift"
grep -q 'mappingProfilesView.setStatus' "$ROOT/Sources/KlikProApp.swift"
# The list-order pin. No test target compiles AppProfilesUI.swift or KlikProApp.swift,
# so these greps are the only guard the pin has against a later refactor dropping it.
grep -q 'static let topPinLimit = 1' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'static func pinFrame(cardWidth: CGFloat)' "$ROOT/Sources/AppProfilesUI.swift"
grep -q -- '-20 \* .pi / 180' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'button.contentTintColor = .black' "$ROOT/Sources/AppProfilesUI.swift"
# All four card types carry a pin: the two Mappings rows, the generator card, and the
# App Profiles tab's own row. Five hits = the factory's own declaration plus one
# construction site per card.
if [[ "$(grep -c 'makePinIconButton()' "$ROOT/Sources/AppProfilesUI.swift")" -ne 5 ]]; then
  echo "All four card types must carry exactly one list-order pin" >&2
  exit 1
fi
# Ordering must filter the ordered pin array, never iterate a Set: Set iteration order
# varies per process, which would make the two fixture renders below differ.
grep -q 'func topPinnedFirst<Element, Key: Hashable>' "$ROOT/Sources/AppProfilesUI.swift"
# A pin is a view preference, so it must not restart the input helper and must not
# raise the unsaved-changes footer. Both are guaranteed by writing the pin field to
# `config` and `persistedConfig` together without calling applySavedConfig().
if grep -A24 'private func applyTopPins' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'applySavedConfig'; then
  echo "Pinning must not restart the input helper" >&2
  exit 1
fi
grep -A12 'private func applyTopPins' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'config.topPinnedOriginals = originals'
# Natives have no onInstancesChange fan-out, so the pin refresh must rebuild them.
# The -A window is deliberately generous: it is a proximity check, not a line count, and
# adding a line to the function should not fail the build. Widen it rather than delete it.
grep -A20 'private func refreshTopPinViews' "$ROOT/Sources/KlikProApp.swift" \
  | grep -q 'refreshOriginalAssignmentViews'
# Renaming / removing / creating a profile must refresh the Mappings "Open App"
# callout pickers immediately, not just the compact list — the onInstancesChange
# fan-out rebuilds both, so a new label or a deleted profile never lingers in the
# dropdown until relaunch.
grep -A24 'onInstancesChange = { \[weak self\] instances in' \
  "$ROOT/Sources/KlikProApp.swift" | grep -q 'refreshQuickLaunchAssignments'
grep -q 'systemSymbolName: "arrow.counterclockwise"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Reset .* shortcut to default' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recorder.setCombo(self.defaultCombo)' "$ROOT/Sources/KlikProApp.swift"
# The Mappings tab groups the mouse and all five compact mapping cards in one
# bordered slide. Browsing is display-only; the gear remains the sole
# activation/assignment/management surface.
grep -Eq 'static let deviceCard +=' "$ROOT/Sources/KlikProApp.swift"
grep -q 'drawDeviceCard(in: SettingsContentView.deviceCard)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'drawSectionLabel("Mouse Mappings"' "$ROOT/Sources/KlikProApp.swift"
grep -Eq 'static let deviceCard += NSRect\(x: 0, y: 0, width: .* height: 374\)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -Eq 'static let mappingBottomCard += NSRect\(x: 0, y: 388,' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'scrollView.frame = NSRect(x: 34, y: 82, width: 872, height: 636)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'func applyCompactCardLayout()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let thumbWheelCard = NSRect(x: 304, y: 30, width: 264, height: 44)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let middleButtonCard = NSRect(x: 44, y: 81, width: 250, height: 82)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let backButtonCard = NSRect(x: 578, y: 81, width: 250, height: 82)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let forwardButtonCard = NSRect(x: 44, y: 211, width: 250, height: 82)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let gestureButtonCard = NSRect(x: 578, y: 211, width: 250, height: 82)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'drawCompactMappingCard(in: card)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'y: card.midY - drawHeight / 2' "$ROOT/Sources/KlikProApp.swift"
grep -q 'thumbWheelBrowsers.useCompactIconPresentation()' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'frame: NSRect(x: thumbCard.maxX - 44, y: thumbCard.minY + 10, width: 26, height: 24)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'if c.title != "Horizontal Thumb Wheel"' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'let leftDotCount = viewedIndex' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let rightDotCount = profileIDs.count - viewedIndex - 1' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'let cx = pill.minX + hpad' "$ROOT/Sources/KlikProApp.swift"
grep -q 'scrollView.hasVerticalScroller = false' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private let menuButton = AppProfileGearButton' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private var presentedMenu: NSMenu?' "$ROOT/Sources/KlikProApp.swift"
grep -q 'presentedMenu = menu' "$ROOT/Sources/KlikProApp.swift"
# The gear opens its menu from mouse-down, like a native pull-down, so tracking
# starts inside the same event that pressed it. This guard replaces an earlier one
# that pinned a deferred `DispatchQueue.main.async` popUp: that workaround was
# removed in 941be25, and because a bare `grep -q` prints nothing under `set -e`,
# the stale guard made every later run of this script exit 1 in silence.
grep -q 'menuButton.onMouseDown = { \[weak self\] _ in self?.presentMenu() }' \
  "$ROOT/Sources/KlikProApp.swift"
if grep -q 'DispatchQueue.main.async { \[weak self, weak menu\] in' \
  "$ROOT/Sources/KlikProApp.swift"; then
  echo "The mouse gear menu must open from mouse-down, not a deferred popUp" >&2
  exit 1
fi
grep -q 'menu.popUp(positioning: nil, at: origin, in: self)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'let listY: CGFloat = 50' "$ROOT/Sources/AppProfilesUI.swift"
grep -Fq '"Activate “\(profile.name)”"' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Add Mapping"' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Rename Mapping…"' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Duplicate Mapping"' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Reset Mapping…"' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Delete Mapping…"' "$ROOT/Sources/KlikProApp.swift"
profile_menu_block="$(sed -n '/private func presentMenu()/,/private func makeSlideColorMenu/p' \
  "$ROOT/Sources/KlikProApp.swift")"
if grep -Eq 'Assign Mouse|Change Mouse|Unassign Mouse|makeDeviceMenu' \
  <<<"$profile_menu_block"; then
  echo "Mapping preset menu must not imply unsupported physical-mouse routing" >&2
  exit 1
fi
# The carousel wraps. This replaces the original stop-at-each-end rule: with the cap of
# three mappings in use, stopping dead at an edge read as a broken arrow. A single mapping
# still goes nowhere, so browse refuses rather than animating a slide onto itself.
grep -q 'let next = ((index + offset) % count + count) % count' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'profileIDs.count > 1 else { return }' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let canBrowse = profileIDs.count > 1' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func handleHorizontalScroll(_ event: NSEvent)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'NSWorkspace.shared.accessibilityDisplayShouldReduceMotion' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'systemSymbolName: "checkmark.square.fill"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'systemSymbolName: "square"' "$ROOT/Sources/KlikProApp.swift"
# Input Monitoring. Without it IOHIDManagerOpen returns kIOReturnNotPermitted and the
# scan finds nothing; nothing used to request the permission, so macOS never prompted,
# Klik PRO never appeared in Privacy & Security, and the gear reported "no mice found"
# forever with no way for the user to discover or fix the real cause.
grep -q 'func requestMouseMonitoringAccessIfNeeded()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown' \
  "$ROOT/Sources/KlikProApp.swift"
# A refusal must stay distinguishable from an empty result.
grep -q 'enum MouseScanOutcome' "$ROOT/Sources/KlikProApp.swift"
grep -q 'openStatus == kIOReturnNotPermitted ? .permissionRequired : .scanned(\[\])' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'Klik PRO needs permission to see your mice.' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Privacy_ListenEvent' "$ROOT/Sources/KlikProApp.swift"
# The dormant scanner remains available for future physical-device routing, but
# global mapping presets must never request its permission.
access_calls="$(grep -c '^ *requestMouseMonitoringAccessIfNeeded()' \
  "$ROOT/Sources/KlikProApp.swift" || true)"
if [[ "$access_calls" != "0" ]]; then
  echo "Global mapping presets must not request Input Monitoring" >&2
  exit 1
fi

# The mouse artwork and its leader lines are drawn by the slide container, so the browse
# CATransition carries them with the controls. Painted by the superview they sat outside
# the animated layer and stayed put while the controls slid across.
grep -q 'var drawArtwork: ((NSRect) -> Void)?' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private func drawMouseArtwork(in card: NSRect)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.drawMouseArtwork(in: card)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'mouseSlideContainer.needsDisplay = true' "$ROOT/Sources/KlikProApp.swift"
settings_draw="$(sed -n '/^    override func draw(_ dirtyRect: NSRect) {$/,/^    }$/p' \
  "$ROOT/Sources/KlikProApp.swift")"
if grep -q 'drawDeviceCallouts(in: rect)' <<<"$settings_draw"; then
  echo "The mouse artwork must be drawn by the slide container, not its superview" >&2
  exit 1
fi

# Mapping presets currently apply globally, so an update must not ask for Input
# Monitoring as though physical-device routing were active.
after_update="$(sed -n '/func guideAccessibilityRegrantAfterUpdateIfNeeded()/,/^    }/p' \
  "$ROOT/Sources/KlikProApp.swift")"
if grep -q 'guideMouseMonitoringRegrantIfStillMissing()' <<<"$after_update"; then
  echo "The post-update check must not request dormant mouse-binding permission" >&2
  exit 1
fi
if grep -cq 'consumeBundleVersionChanged()' <<<"$after_update"; then
  :
else
  echo "Both permission checks must share the one consumeBundleVersionChanged() read" >&2
  exit 1
fi

# Closing must not silently discard staged edits. Nearly every mouse-mapping
# change only stages, so every termination route must use the same decision.
grep -q 'func confirmCloseDiscardingUnsavedChanges() -> Bool' "$ROOT/Sources/KlikProApp.swift"
grep -q 'discardButtonTitle: "Discard and Close"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'discardButtonTitle: "Discard and Power Off"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'alert.addButton(withTitle: discardButtonTitle)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func windowShouldClose(_ sender: NSWindow) -> Bool' "$ROOT/Sources/KlikProApp.swift"
grep -q 'windowCloseApprovedForTermination = true' "$ROOT/Sources/KlikProApp.swift"
grep -q '"KLIK_PRO_PREVIEW_CONFIRM_CLOSE"' "$ROOT/Sources/KlikProApp.swift"
# Cmd-Q, the Dock and the menu bar reach NSApp.terminate directly.
grep -q 'func applicationShouldTerminate(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guard controller?.confirmCloseDiscardingUnsavedChanges() ?? true else {' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'return .terminateCancel' "$ROOT/Sources/KlikProApp.swift"
# Choosing Save in the quit warning must finish the asynchronous transaction before
# terminating. Keeping the window open after a successful save made the command look
# ignored and encouraged a second, destructive quit attempt.
grep -q 'saveConfiguration { savedCurrentDraft in' "$ROOT/Sources/KlikProApp.swift"
grep -q 'completion?(savedCurrentDraft)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'savedCurrentDraft = !newerEditsRemain' "$ROOT/Sources/KlikProApp.swift"

# The slide arrows must show they are controls. The glyph alone read as decoration, so
# hover gives them a wash, and a boundary arrow is dimmed hard rather than a shade away
# from the live one — and must not light up, since there is no slide to go to.
nav_button_block="$(sed -n '/^final class MouseSlideNavigationButton: NSButton {/,/^}/p' \
  "$ROOT/Sources/KlikProApp.swift")"
grep -q 'override func mouseEntered(with event: NSEvent) { setHovered(true) }' \
  <<<"$nav_button_block"
grep -q 'override func mouseExited(with event: NSEvent) { setHovered(false) }' \
  <<<"$nav_button_block"
grep -q 'let next = hovered && isEnabled' <<<"$nav_button_block"
grep -q 'disabledTint = NSColor.appTextSecondary.withAlphaComponent(0.28)' \
  <<<"$nav_button_block"
if ! grep -q 'if isHovered && isEnabled {' <<<"$nav_button_block"; then
  echo "A disabled slide arrow must not draw a hover wash" >&2
  exit 1
fi

# Vendor app icons are cached. Icon Services lookups were repeated for every row of all
# four lists on every rebuild, several rebuilds deep per refresh, on the main thread.
grep -q 'enum VendorAppIconCache' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'VendorAppIconCache.invalidate()' "$ROOT/Sources/KlikProApp.swift"
# Only the two lookups inside VendorAppIconCache itself may call NSWorkspace directly:
# the caching one, and the preview bypass that keeps fixture renders deterministic.
if grep -n 'NSWorkspace.shared.icon(forFile:' "$ROOT/Sources/AppProfilesUI.swift" \
  | grep -v '^[0-9]*:///' \
  | grep -v 'let icon = NSWorkspace.shared.icon(forFile: path)' \
  | grep -vq 'return NSWorkspace.shared.icon(forFile: path)'; then
  echo "App list rows must fetch vendor icons through VendorAppIconCache" >&2
  exit 1
fi
grep -q 'guard !previewRenderingIsActive else {' "$ROOT/Sources/AppProfilesUI.swift"
# A managed launcher's own icns stays uncached so Change Icon shows up immediately.
display_icon_block="$(sed -n '/^private func appProfileDisplayIcon/,/^}/p' \
  "$ROOT/Sources/AppProfilesUI.swift")"
if ! grep -q 'NSImage(contentsOf: launcherIconURL)' <<<"$display_icon_block"; then
  echo "appProfileDisplayIcon must keep reading AppIcon.icns directly" >&2
  exit 1
fi

# Reset must resync the Settings tab, or its thumb-wheel switch keeps the pre-reset value
# and the first click writes the value it already holds.
reset_block="$(sed -n '/private func resetMouseProfile(_ id: UUID)/,/^    }/p' \
  "$ROOT/Sources/KlikProApp.swift")"
if ! grep -q 'refreshActiveMouseProfileSettings()' <<<"$reset_block"; then
  echo "resetMouseProfile must resync the Settings tab from config" >&2
  exit 1
fi
# Activation repaints the ACTIVE badge before saving, so it must refuse during a save.
activate_block="$(sed -n '/private func activateMouseProfile(_ id: UUID)/,/^    }/p' \
  "$ROOT/Sources/KlikProApp.swift")"
if ! grep -q 'guard !saveInProgress, !appProfileLifecycleInProgress else {' \
  <<<"$activate_block"; then
  echo "activateMouseProfile must not repaint the ACTIVE badge during a save" >&2
  exit 1
fi

# Mouse slide colourways. Colour follows the mapping set, not its carousel position,
# and is chosen from the gear rather than derived from an index.
grep -q 'func setMouseSlideColor(_ color: MouseSlideColor)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'var slideColor: MouseSlideColor?' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'colour.submenu = makeSlideColorMenu(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func makeSlideColorMenu(selected: MouseSlideColor)' \
  "$ROOT/Sources/KlikProApp.swift"
if [[ "$(grep -c '    case ' <<<"$(sed -n '/^enum MouseSlideColor/,/^    var title/p' \
  "$ROOT/Sources/KlikProConfig.swift")")" != "8" ]]; then
  echo "Mouse slide colourways must stay at exactly eight" >&2
  exit 1
fi
# The palette washes remain stable; the three default slides deliberately use
# Pearl White, Mist Blue, and Rose.
grep -q 'red: 0.45, green: 0.72, blue: 0.94, alpha: 0.18' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'red: 0.92, green: 0.66, blue: 0.42, alpha: 0.16' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'case 1: return .mistBlue' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'case 2: return .rose' "$ROOT/Sources/KlikProConfig.swift"
# The tint is composited while the artwork is drawn, inside a transparency layer so the
# fill sees only the mouse's own alpha, and inside a saved GState so .sourceAtop cannot
# leak into the leader lines drawn straight afterwards.
grep -q 'context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'context.setBlendMode(.sourceAtop)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'context.endTransparencyLayer()' "$ROOT/Sources/KlikProApp.swift"
# Reject a return to baking the tint into an offscreen copy of the 1000x742 artwork.
# Every refreshMouseProfileEditor() call reached that path, so it re-rasterized the
# mouse on browse, activate, rename, reset, delete, bind and rescan alike.
if grep -Eq 'displayedMouseImage|func tintedMouseImage' "$ROOT/Sources/KlikProApp.swift"; then
  echo "The mouse slide tint must be drawn, not baked into a cached NSImage" >&2
  exit 1
fi
# An unchanged colour must cost a comparison, not a redraw.
grep -q 'guard tint != mouseSlideTint else { return }' "$ROOT/Sources/KlikProApp.swift"

# setOriginals still ends the first-launch overlay (guarded above), but it runs
# synchronously from the Mappings refresh handler while the scan is still in flight, so
# during a shared refresh it must leave the state to setRefreshControlsBusy(_:) — else the
# native card drops out of step and only App Profiles appears to refresh.
grep -q 'sharedRefreshActive = refreshing' "$ROOT/Sources/AppProfilesUI.swift"
set_originals_block="$(sed -n '/func setOriginals(_ originals: \[MappingNativeApp\])/,/^    }/p' \
  "$ROOT/Sources/AppProfilesUI.swift")"
if ! grep -q 'if !sharedRefreshActive {' <<<"$set_originals_block"; then
  echo "setOriginals must not clear the native card while a shared refresh is running" >&2
  exit 1
fi

# Pinned rows are sticky in all four lists: they live on the list view rather than in the
# scroller's document, so scrolling moves everything except them, and a rebuild from
# either refresh path re-establishes them.
grep -q 'private var stickyRows: \[NSView\] = \[\]' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'func setRows(_ newRows: \[NSView\], stickyCount: Int = 0, emptyMessage: String)' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'let stickyHeight = stickyRows.isEmpty ? 0 : CGFloat(stickyRows.count) \* pitch' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'scrollView.frame = NSRect(' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'x: 0, y: stickyHeight, width: contentWidth, height: scrollHeight' \
  "$ROOT/Sources/AppProfilesUI.swift"
# All four lists, or the feature is half-applied and the tabs disagree.
grep -q 'stickyCount: originals.prefix { \$0.topPinned }.count' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'stickyCount: ordered.prefix { topPinnedProfileIDs.contains(\$0.id) }.count' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'stickyCount: visible.prefix { topPinnedOriginals.contains(\$0.target) }.count' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'stickyCount: orderedInstances.prefix { topPinnedProfileIDs.contains(\$0.id) }.count' \
  "$ROOT/Sources/AppProfilesUI.swift"
# A lone pinned card must not sit above an "empty list" caption.
set_rows_block="$(sed -n '/func setRows(_ newRows: \[NSView\], stickyCount/,/^    }/p' \
  "$ROOT/Sources/AppProfilesUI.swift")"
if ! grep -q 'if newRows.isEmpty {' <<<"$set_rows_block"; then
  echo "The list empty state must count sticky rows, not only the scrolling rows" >&2
  exit 1
fi
grep -q 'contentView.setMouseControlsAvailable(true)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q '"Save “\\(profile.name)”"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'header.onSave = ' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private func saveMouseProfile(_ id: UUID)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'thumbWheelCard = NSRect(x: leftX' "$ROOT/Sources/KlikProApp.swift"
grep -q 'actionPicker.addItems(withTitles: \[baseActionTitle, "Open App"\])' "$ROOT/Sources/KlikProApp.swift"
grep -q 'baseActionTitle: "Shortcut"' "$ROOT/Sources/KlikProApp.swift"
if grep -Eq 'baseActionTitle: "Browser (Forward|Back)"' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Forward and Back must use the same Shortcut action menu as the other buttons" >&2
  exit 1
fi
if grep -q 'showsShortcutControls: false' "$ROOT/Sources/KlikProApp.swift"; then
  echo "All four mouse-button rows must expose their shortcut recorder" >&2
  exit 1
fi
grep -q 'case application(InstalledApplicationTarget)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'case launchApplication(InstalledApplicationTarget)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'URL(fileURLWithPath: "/System/Applications"' \
  "$ROOT/Sources/Duplication/AppScanner.swift"
grep -q 'URL(fileURLWithPath: "/System/Applications/Utilities"' \
  "$ROOT/Sources/Duplication/AppScanner.swift"
grep -q 'func setDualAppMapping(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'target: LaunchAssignmentTarget?' "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let dormantLinkGap: CGFloat = 6' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recorderX - dormantLinkGap - dormantLinkIconSize' "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let linkedFieldWidth: CGFloat = 360' "$ROOT/Sources/KlikProApp.swift"
grep -q 'static let linkedLockGap: CGFloat = 6' "$ROOT/Sources/KlikProApp.swift"
grep -q 'toggle.isHidden = false' "$ROOT/Sources/KlikProApp.swift"
grep -q 'x: ShortcutRowLayout.dormantLinkX,' "$ROOT/Sources/KlikProApp.swift"
grep -q 'respectFlipped: true' "$ROOT/Sources/KlikProApp.swift"
grep -q 'permCard    = NSRect(x: rightX, y: 20, width: cardW, height: 132)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'aboutCard   = NSRect(x: rightX, y: 168, width: cardW, height: 126)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'title: "© 2026 Aminudin Murad · GPL-3.0"' "$ROOT/Sources/KlikProApp.swift"
grep -A5 'openLogsLink = URLLinkView' "$ROOT/Sources/KlikProApp.swift" | grep -q 'style: .outline'
grep -q 'supportCard = NSRect(x: rightX, y: 310, width: cardW, height: 92)' "$ROOT/Sources/KlikProApp.swift"
grep -q '"Support open-source development"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let settingsGithubLink: URLLinkView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let settingsSponsorsLink: URLLinkView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let settingsKofiLink: URLLinkView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let settingsPayPalLink: URLLinkView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'settingsGithubLink,' "$ROOT/Sources/KlikProApp.swift"
grep -q 'settingsSponsorsLink,' "$ROOT/Sources/KlikProApp.swift"
grep -q 'settingsKofiLink,' "$ROOT/Sources/KlikProApp.swift"
grep -q 'settingsPayPalLink,' "$ROOT/Sources/KlikProApp.swift"
grep -q 'firefoxCheck.onChange' "$ROOT/Sources/KlikProApp.swift"
grep -q 'org.mozilla.firefoxdeveloperedition' "$ROOT/Sources/KlikProInput.swift"
grep -q 'thumbWheelMappingIsEnabled(' "$ROOT/Sources/KlikProInput.swift"
if grep -q 'specialFeatureActive' <<<"$klikProStatusBlock"; then
  echo "Klik PRO active dots must reflect the input helper, not Special Feature state" >&2
  exit 1
fi
if grep -q 'RegisterEventHotKey' <<<"$klikProStatusBlock"; then
  echo "Klik PRO status item must not register a keyboard shortcut" >&2
  exit 1
fi
# Scroll Mode was abandoned as a feature; it must not reappear anywhere in the app.
if grep -Eriq 'scroll ?mode|scrollmode' "$ROOT/Sources"; then
  echo "Scroll Mode was removed and must not be reintroduced in Sources" >&2
  exit 1
fi
quickLaunchButtons="$(sed -n '/enum QuickLaunchMouseButton:/,/^}/p' "$ROOT/Sources/KlikProConfig.swift")"
for requiredButton in 'case middle' 'case gesture' 'case forward' 'case back'; do
  grep -q "$requiredButton" <<<"$quickLaunchButtons"
done
mouseMappingBlock="$(sed -n '/private func setupMouseMappings()/,/^}/p' "$ROOT/Sources/KlikProInput.swift")"
if grep -Eq 'isMenuRunning\(|run\(' <<<"$mouseMappingBlock"; then
  echo "Mouse event handling must not synchronously invoke launchctl" >&2
  exit 1
fi
grep -q 'case launch(QuickLaunchTarget)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'installed: quickLaunchTargetIsInstalled(target)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'quickLaunchApplicationBundleIsValid' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'wrapperPresent: quickLaunchLauncherIsRunnable(target)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'disabledDetail: "Install ChatGPT or Claude to enable"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'specialFeatureToggleRow.isEnabled = available' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guard hasInstalledQuickLaunchTarget() else' "$ROOT/Sources/KlikProApp.swift"
grep -q 'chatGPTButtonPicker.setReadiness(chatGPTReadiness)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'chatGPTHotkeyRow.setReadiness(chatGPTReadiness)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let originalTargets: \[(target: LaunchAssignmentTarget, label: String)\]' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'row.setOpenAppOptions(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'assignedTarget: launchAssignmentOwner(of: button, in: config)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'quickLaunchMousePickerIsEnabled(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'quickLaunchMouseSelectionIsAllowed(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guard !previewRenderingIsActive else { return 1 }' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'if !previewRenderingIsActive && autoCheckEnabled' "$ROOT/Sources/KlikProApp.swift"
grep -q 'NSApp.disableRelaunchOnLogin()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'previewRenderingIsActive = true' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_INSTALLED_TARGETS' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_UNSAVED' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_INTERACTIVE' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_FOCUS_BEST_FIT' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_USE_INSTALLED_APP_ICONS' "$ROOT/Sources/KlikProApp.swift"
grep -q 'render_preview "$ROOT/assets/screenshot-mappings.png" mappings "" 1' "$ROOT/tools/render-previews.sh"
grep -q 'special-feature-no-apps.png' "$ROOT/tools/render-previews.sh"
grep -q 'special-feature-chatgpt-only.png' "$ROOT/tools/render-previews.sh"
grep -q 'mouse-mapping-single.png' "$ROOT/tools/render-previews.sh"
grep -q 'mouse-mapping-first.png' "$ROOT/tools/render-previews.sh"
grep -q 'mouse-mapping-middle.png' "$ROOT/tools/render-previews.sh"
grep -q 'mouse-mapping-final.png' "$ROOT/tools/render-previews.sh"
grep -q 'private struct AppControlState: Equatable' "$ROOT/Sources/KlikProApp.swift"
grep -q 'controlState != persistedControlState' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private func recheckControlState()' "$ROOT/Sources/KlikProApp.swift"
grep -A4 'private func configurationDidChange()' "$ROOT/Sources/KlikProApp.swift" | grep -q 'recheckControlState()'
grep -A32 'preferencesView.launchAtLoginRow.onToggleChange' "$ROOT/Sources/KlikProApp.swift" | grep -q 'configurationDidChange()'
launch_at_login_block="$(grep -A32 'preferencesView.launchAtLoginRow.onToggleChange' "$ROOT/Sources/KlikProApp.swift")"
grep -q 'launchAtLoginPreferenceKey' <<<"$launch_at_login_block"
grep -q 'ensureInputHelperRunning(launchAtLoginEnabled: false)' <<<"$launch_at_login_block"
if grep -q 'bootout' <<<"$launch_at_login_block"; then
  echo "Launch at login OFF must not stop the currently running helper or hide menu-bar icons" >&2
  exit 1
fi
grep -A4 'preferencesView.autoUpdateRow.onToggleChange' "$ROOT/Sources/KlikProApp.swift" | grep -q 'configurationDidChange()'
grep -A24 'contentView.specialFeatureToggleRow.onToggleChange' "$ROOT/Sources/KlikProApp.swift" | grep -q 'configurationDidChange()'
grep -q 'func ensureInputHelperRunning(launchAtLoginEnabled: Bool? = nil)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'func applySavedConfig(launchAtLoginEnabled: Bool? = nil)' "$ROOT/Sources/KlikProConfig.swift"
# The five-second helper monitor must not repeat full source code-signature
# validation while every managed profile path is unchanged. Runtime actions still
# call AppProfileRuntime and revalidate independently before launching.
grep -q 'private func currentAppProfilePollFingerprint()' "$ROOT/Sources/KlikProInput.swift"
grep -q 'let profileFilesChanged = currentFingerprint != appProfilePollFingerprint' \
  "$ROOT/Sources/KlikProInput.swift"
grep -q 'if profileFilesChanged || legacyAvailabilityChanged' \
  "$ROOT/Sources/KlikProInput.swift"
if [[ "$(grep -Fc 'appProfileRuntime.health(for: instance)' "$ROOT/Sources/KlikProInput.swift")" != "1" ]]; then
  echo "The stable availability poll must not repeat full managed-profile health checks" >&2
  exit 1
fi
grep -A4 'persistedConfig = configToSave' "$ROOT/Sources/KlikProApp.swift" | grep -q 'persistedControlState = controlStateToSave'
grep -q '"Unsaved changes"' "$ROOT/Sources/KlikProApp.swift"
grep -q '("Unsaved changes", .systemRed)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'unsaved-changes.png' "$ROOT/tools/render-previews.sh"
grep -q 'save-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'settings.png' "$ROOT/tools/render-previews.sh"
grep -q 'update-hover.png' "$ROOT/tools/render-previews.sh"
if grep -q 'close-hover.png' "$ROOT/tools/render-previews.sh"; then
  echo "Close uses the shared native header action and needs no bespoke fixture" >&2
  exit 1
fi
grep -q 'onboarding-back-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'about.png' "$ROOT/tools/render-previews.sh"
# README shows the animated onboarding flow (GIF) at the same display width. It is
# built from the rendered fixtures — one frame per first-run page — so an added or
# reordered step can never leave a stale recording in the README.
grep -q 'onboarding-flow.gif' "$ROOT/README.md"
grep -Eq 'onboarding-flow\.gif[^\"]*" width="462"' "$ROOT/README.md"
if [[ ! -s "$ROOT/assets/onboarding-flow.gif" ]]; then
  echo "Onboarding flow GIF is missing or empty" >&2
  exit 1
fi
grep -q 'tools/render-onboarding-flow.swift' "$ROOT/tools/render-previews.sh"
onboardingFlowFrames="$(sed -n '/^let frameNames = \[/,/^\]/p' \
  "$ROOT/tools/render-onboarding-flow.swift")"
for onboardingFlowFrame in \
  onboarding.png onboarding-data-folder.png onboarding-toggles.png onboarding-access.png
do
  grep -q "\"$onboardingFlowFrame\"" <<<"$onboardingFlowFrames" || {
    echo "The onboarding flow GIF must include every first-run page" >&2
    exit 1
  }
done
[[ "$(sips -g pixelWidth "$ROOT/assets/onboarding-flow.gif" 2>/dev/null \
  | awk '/pixelWidth/ { print $2 }')" == "972" ]] || {
  echo "Unexpected onboarding flow GIF width" >&2
  exit 1
}
grep -q 'app-profiles-icon-showcase.gif' "$ROOT/README.md"
if [[ ! -s "$ROOT/assets/app-profiles-icon-showcase.gif" ]]; then
  echo "App Profiles icon showcase GIF is missing or empty" >&2
  exit 1
fi
# The locked-state Advanced screenshot documents the new lock/warning gate.
grep -q 'screenshot-advanced-locked.png' "$ROOT/README.md"
grep -q 'roundedRect: borderRect' "$ROOT/tools/PreviewMain.swift"
grep -q 'let previewScale: CGFloat = 2' "$ROOT/tools/PreviewMain.swift"
grep -q 'bitmap.size = bounds.size' "$ROOT/tools/PreviewMain.swift"
grep -q 'screenshot-onboarding.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-mappings-13-m1.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-profiles-13-modern.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-profiles-14.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-profiles-15.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-profiles-16.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-mappings-16.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-settings-16.png' "$ROOT/tools/render-previews.sh"
grep -q 'responsive-advanced-16.png' "$ROOT/tools/render-previews.sh"

require_source_literal \
  'styleMask: [.titled, .closable, .miniaturizable, .resizable]' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The v1.5.6 dashboard window must remain vertically resizable"
require_source_literal \
  'static let minimumContentSize = NSSize(width: 940, height: 738)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The released 13-inch content size must remain the responsive minimum"
require_source_literal \
  'static let maximumContentSize = NSSize(width: 940, height: 928)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The dashboard maximum must retain the fixed width and 16-inch height"
for fixedWidthPreset in \
  'case .air13M1: return NSSize(width: 940, height: 770)' \
  'case .air13Modern: return NSSize(width: 940, height: 820)' \
  'case .pro14: return NSSize(width: 940, height: 860)' \
  'case .air15: return NSSize(width: 940, height: 900)' \
  'case .pro16: return NSSize(width: 940, height: 960)'
do
  require_source_literal \
    "$fixedWidthPreset" \
    "$ROOT/Sources/KlikProApp.swift" \
    "Every Dashboard Height preset must retain the fixed 940-point width"
done
require_source_literal \
  'private func persistWindowFrame()' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The responsive dashboard must remember its last frame"
require_source_literal \
  'forKey: KlikProDashboardMetrics.framePreferenceKey' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The responsive dashboard frame must use a stable preference key"
require_source_literal \
  'final class DashboardBestFitControl: NSView' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Settings must retain the visual Best Fit panel"
require_source_literal \
  'final class DashboardPresetTileButton: NSButton' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Each Best Fit preset must remain an accessible MacBook tile"
require_source_literal \
  'setAccessibilityRole(.radioGroup)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The visual Best Fit panel must remain a radio group"
require_source_literal \
  'setAccessibilityLabel("Dashboard Height")' \
  "$ROOT/Sources/KlikProApp.swift" \
  "The fixed-width presets must use the Dashboard Height label"
require_source_literal \
  'setButtonType(.radio)' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Each visual Best Fit tile must retain radio-button semantics"
require_source_literal \
  '(cell as? NSButtonCell)?.highlightsBy = []' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Best Fit tiles must suppress AppKit's blue radio press artwork"
require_source_literal \
  'private func drawMacBookIcon(' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Best Fit tiles must keep their MacBook screen-size silhouettes"
require_source_literal \
  'Width stays fixed at 940; the window remains vertically resizable.' \
  "$ROOT/Sources/KlikProApp.swift" \
  "Best Fit guidance must describe the actual Klik PRO minimum"
if grep -q 'dashboardSizeControl = NSSegmentedControl' \
  "$ROOT/Sources/KlikProApp.swift"; then
  echo "The old text-only Best Fit segmented control must not return" >&2
  exit 1
fi
require_source_literal \
  'height: max(0, bounds.height - listY - 12)' \
  "$ROOT/Sources/AppProfilesUI.swift" \
  "Mappings app lists must consume added dashboard height"

previewRunOne="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-check-preview-one-$STAMP.XXXXXX")"
previewRunTwo="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-check-preview-two-$STAMP.XXXXXX")"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/ComparePreviewPixels.swift" \
  -o "$OUT/compare-preview-pixels"
KLIK_PRO_PREVIEW_WORK_DIRECTORY="$previewRunOne" \
  "$ROOT/tools/render-previews.sh" --fixtures-only > "$OUT/preview-fixtures-one.log"
KLIK_PRO_PREVIEW_WORK_DIRECTORY="$previewRunTwo" \
  "$ROOT/tools/render-previews.sh" --fixtures-only > "$OUT/preview-fixtures-two.log"

for fixtureName in \
  app-profiles.png \
  app-profiles-empty.png \
  special-feature-no-apps.png \
  special-feature-chatgpt-only.png \
  mouse-mapping-single.png \
  mouse-mapping-first.png \
  mouse-mapping-middle.png \
  mouse-mapping-final.png \
  settings.png \
  settings-needs-permission.png \
  unsaved-changes.png \
  save-hover.png \
  update-hover.png
do
  firstFixture="$previewRunOne/fixtures/$fixtureName"
  secondFixture="$previewRunTwo/fixtures/$fixtureName"
  [[ -f "$firstFixture" && -f "$secondFixture" ]] || {
    echo "Missing rendered preview fixture: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g pixelWidth "$firstFixture" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "1880" ]] || {
    echo "Unexpected preview width: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g pixelHeight "$firstFixture" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "1476" ]] || {
    echo "Unexpected preview height: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g hasAlpha "$firstFixture" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "no" ]] || {
    echo "Preview fixture must be opaque: $fixtureName" >&2
    exit 1
  }
  "$OUT/compare-preview-pixels" "$firstFixture" "$secondFixture"
done

# Every Best Fit fixture is Retina-rendered from the content rect. Exact
# dimensions prove that the requested outer frame reached AppKit and that the
# minimum did not silently grow.
responsiveFixturePixels() {
  case "$1" in
    responsive-mappings-13-m1.png) echo "1880 1476" ;;
    responsive-profiles-13-modern.png) echo "1880 1576" ;;
    responsive-profiles-14.png) echo "1880 1656" ;;
    responsive-profiles-15.png) echo "1880 1736" ;;
    responsive-profiles-16.png|responsive-mappings-16.png|responsive-settings-16.png|responsive-advanced-16.png) echo "1880 1856" ;;
    *) echo "0 0" ;;
  esac
}
for fixtureName in \
  responsive-mappings-13-m1.png \
  responsive-profiles-13-modern.png \
  responsive-profiles-14.png \
  responsive-profiles-15.png \
  responsive-profiles-16.png \
  responsive-mappings-16.png \
  responsive-settings-16.png \
  responsive-advanced-16.png
do
  firstFixture="$previewRunOne/fixtures/$fixtureName"
  secondFixture="$previewRunTwo/fixtures/$fixtureName"
  [[ -f "$firstFixture" && -f "$secondFixture" ]] || {
    echo "Missing responsive preview fixture: $fixtureName" >&2
    exit 1
  }
  read -r expectedWidth expectedHeight <<<"$(responsiveFixturePixels "$fixtureName")"
  [[ "$(sips -g pixelWidth "$firstFixture" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "$expectedWidth" ]] || {
    echo "Unexpected responsive preview width: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g pixelHeight "$firstFixture" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "$expectedHeight" ]] || {
    echo "Unexpected responsive preview height: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g hasAlpha "$firstFixture" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "no" ]] || {
    echo "Responsive preview fixture must be opaque: $fixtureName" >&2
    exit 1
  }
  "$OUT/compare-preview-pixels" "$firstFixture" "$secondFixture"
done

# Step pages have different heights; each fixture pins its own expected height.
onboardingFixtureHeight() {
  case "$(basename "$1")" in
    onboarding.png) echo "576" ;;
    onboarding-data-folder.png) echo "860" ;;
    onboarding-toggles.png) echo "832" ;;
    onboarding-access.png|onboarding-back-hover.png) echo "736" ;;
    onboarding-granted.png) echo "668" ;;
    *) echo "0" ;;
  esac
}
for onboardingFixture in \
  "$previewRunOne/fixtures/onboarding.png" \
  "$previewRunTwo/fixtures/onboarding.png" \
  "$previewRunOne/fixtures/onboarding-data-folder.png" \
  "$previewRunTwo/fixtures/onboarding-data-folder.png" \
  "$previewRunOne/fixtures/onboarding-toggles.png" \
  "$previewRunTwo/fixtures/onboarding-toggles.png" \
  "$previewRunOne/fixtures/onboarding-access.png" \
  "$previewRunTwo/fixtures/onboarding-access.png" \
  "$previewRunOne/fixtures/onboarding-granted.png" \
  "$previewRunTwo/fixtures/onboarding-granted.png" \
  "$previewRunOne/fixtures/onboarding-back-hover.png" \
  "$previewRunTwo/fixtures/onboarding-back-hover.png"
do
  [[ -f "$onboardingFixture" ]] || {
    echo "Missing rendered onboarding fixture" >&2
    exit 1
  }
  [[ "$(sips -g hasAlpha "$onboardingFixture" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "no" ]] || {
    echo "Onboarding preview fixture must be opaque" >&2
    exit 1
  }
  [[ "$(sips -g pixelWidth "$onboardingFixture" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "924" ]] || {
    echo "Unexpected onboarding preview width" >&2
    exit 1
  }
  [[ "$(sips -g pixelHeight "$onboardingFixture" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "$(onboardingFixtureHeight "$onboardingFixture")" ]] || {
    echo "Unexpected onboarding preview height: $onboardingFixture" >&2
    exit 1
  }
done
cmp \
  "$previewRunOne/fixtures/onboarding.png" \
  "$previewRunTwo/fixtures/onboarding.png"
cmp \
  "$previewRunOne/fixtures/onboarding-data-folder.png" \
  "$previewRunTwo/fixtures/onboarding-data-folder.png"
cmp \
  "$previewRunOne/fixtures/onboarding-toggles.png" \
  "$previewRunTwo/fixtures/onboarding-toggles.png"
cmp \
  "$previewRunOne/fixtures/onboarding-access.png" \
  "$previewRunTwo/fixtures/onboarding-access.png"
cmp \
  "$previewRunOne/fixtures/onboarding-granted.png" \
  "$previewRunTwo/fixtures/onboarding-granted.png"
cmp \
  "$previewRunOne/fixtures/onboarding-back-hover.png" \
  "$previewRunTwo/fixtures/onboarding-back-hover.png"

for aboutFixture in \
  "$previewRunOne/fixtures/about.png" \
  "$previewRunTwo/fixtures/about.png"
do
  [[ -f "$aboutFixture" ]] || {
    echo "Missing rendered About fixture" >&2
    exit 1
  }
  [[ "$(sips -g hasAlpha "$aboutFixture" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "no" ]] || {
    echo "About preview fixture must be opaque" >&2
    exit 1
  }
done
cmp \
  "$previewRunOne/fixtures/about.png" \
  "$previewRunTwo/fixtures/about.png"

if cmp -s \
  "$previewRunOne/fixtures/onboarding-access.png" \
  "$previewRunOne/fixtures/onboarding-back-hover.png"
then
  echo "Onboarding Back hover fixture must differ from its normal state" >&2
  exit 1
fi

if cmp -s \
  "$previewRunOne/fixtures/special-feature-no-apps.png" \
  "$previewRunOne/fixtures/save-hover.png"
then
  echo "Save hover fixture must differ from its normal state" >&2
  exit 1
fi

if cmp -s \
  "$previewRunOne/fixtures/settings.png" \
  "$previewRunOne/fixtures/update-hover.png"
then
  echo "Check-for-Updates hover fixture must differ from its normal state" >&2
  exit 1
fi

echo "Scroll Mode removal check passed"
echo "Keyboard Command-Tab isolation check passed"
echo "Persistent Klik PRO menu-bar isolation check passed"
echo "Flexible Special Feature assignment isolation check passed"
echo "Installed-app Special Feature gate isolation check passed"
echo "Runnable-bundle readiness and combined-service checks passed"
echo "Deterministic Special Feature preview fixtures check passed"
echo "Unsaved-configuration indicator check passed"
echo "Save-button hover check passed"
echo "Check-for-Updates hover check passed"
echo "Native close protection check passed"
echo "Onboarding Back-button hover check passed"

for arch in arm64 x86_64; do
  compile "$arch" KlikProInput.swift "$OUT/klik-pro-input-$arch"
  compile "$arch" KlikProApp.swift "$OUT/klik-pro-app-$arch"
  xcrun swiftc \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -target "$arch-apple-macosx13.0" \
    -warnings-as-errors \
    "${LAUNCHER_RUNTIME_SOURCES[@]}" \
    "$ROOT/Sources/KlikProManagedLauncher.swift" \
    -o "$OUT/klik-pro-managed-launcher-$arch"
  xcrun swiftc \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -target "$arch-apple-macosx13.0" \
    -warnings-as-errors \
    "$ROOT/Sources/KlikProConfig.swift" \
    "${DUPLICATION_SOURCES[@]}" \
    "$ROOT/Sources/KlikProOriginalLauncher.swift" \
    -o "$OUT/klik-pro-original-launcher-$arch"
done

lipo -create \
  "$OUT/klik-pro-managed-launcher-arm64" \
  "$OUT/klik-pro-managed-launcher-x86_64" \
  -output "$OUT/KlikProManagedLauncher"
lipo -create \
  "$OUT/klik-pro-original-launcher-arm64" \
  "$OUT/klik-pro-original-launcher-x86_64" \
  -output "$OUT/KlikProOriginalLauncher"
runnerArchs="$(lipo -archs "$OUT/KlikProManagedLauncher")"
if [[ "$runnerArchs" != "x86_64 arm64" && "$runnerArchs" != "arm64 x86_64" ]]; then
  echo "Managed launcher must contain arm64 and x86_64, found: $runnerArchs" >&2
  exit 1
fi
originalRunnerArchs="$(lipo -archs "$OUT/KlikProOriginalLauncher")"
if [[ "$originalRunnerArchs" != "x86_64 arm64" && "$originalRunnerArchs" != "arm64 x86_64" ]]; then
  echo "Original launcher must contain arm64 and x86_64, found: $originalRunnerArchs" >&2
  exit 1
fi
for arch in arm64 x86_64; do
  vtool -show-build -arch "$arch" "$OUT/KlikProManagedLauncher" | grep -q 'minos 13.0'
  vtool -show-build -arch "$arch" "$OUT/KlikProOriginalLauncher" | grep -q 'minos 13.0'
done

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/crop-device.swift" \
  -o "$OUT/crop-device"
"$OUT/crop-device" \
  "$ROOT/assets/Klik PRO mouse.png" \
  "$OUT/device-reference.png"
cmp "$OUT/device-reference.png" "$ROOT/assets/device-reference.png"

mouse_has_alpha="$(sips -g hasAlpha "$ROOT/assets/Klik PRO mouse.png" 2>/dev/null \
  | awk '/hasAlpha/ { print $2 }')"
if [[ "$mouse_has_alpha" != "yes" ]]; then
  echo "Klik PRO mouse source must retain its alpha channel" >&2
  exit 1
fi
device_reference_width="$(sips -g pixelWidth "$OUT/device-reference.png" 2>/dev/null \
  | awk '/pixelWidth/ { print $2 }')"
device_reference_height="$(sips -g pixelHeight "$OUT/device-reference.png" 2>/dev/null \
  | awk '/pixelHeight/ { print $2 }')"
if [[ "$device_reference_width" != "1000" || "$device_reference_height" != "742" ]]; then
  echo "Device reference must be 1000x742, found ${device_reference_width}x${device_reference_height}" >&2
  exit 1
fi

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/render-app-icon.swift" \
  -o "$OUT/render-app-icon"
"$OUT/render-app-icon" \
  "$OUT/icon-master.png"
cmp "$OUT/icon-master.png" "$ROOT/assets/icon-master.png"
sips -z 400 400 "$OUT/icon-master.png" --out "$OUT/icon.png" >/dev/null
cmp "$OUT/icon.png" "$ROOT/assets/icon.png"

iconutil -c iconset "$ROOT/assets/KlikPRO.icns" -o "$OUT/KlikPRO.iconset"
expectedIconRepresentations=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)
for representation in "${expectedIconRepresentations[@]}"; do
  filename="${representation%%:*}"
  expectedSize="${representation##*:}"
  iconPath="$OUT/KlikPRO.iconset/$filename"
  icon_width="$(sips -g pixelWidth "$iconPath" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  icon_height="$(sips -g pixelHeight "$iconPath" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
  if [[ "$icon_width" != "$expectedSize" || "$icon_height" != "$expectedSize" ]]; then
    echo "$filename must be ${expectedSize}x${expectedSize}, found ${icon_width}x${icon_height}" >&2
    exit 1
  fi
done

# iconutil may rewrite PNG metadata while preserving pixels, so normalize the 1024px
# representation to BMP before comparing it with the tracked master.
sips -s format bmp "$OUT/icon-master.png" --out "$OUT/icon-master.bmp" >/dev/null
sips -s format bmp \
  "$OUT/KlikPRO.iconset/icon_512x512@2x.png" \
  --out "$OUT/icon-from-icns.bmp" >/dev/null
cmp "$OUT/icon-master.bmp" "$OUT/icon-from-icns.bmp"

echo "All checks passed (outputs: $OUT)"
