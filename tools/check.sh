#!/usr/bin/env bash
set -euo pipefail

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

for plist in \
  "$ROOT/App/Info.plist" \
  "$ROOT/App/KlikProHelper-Info.plist" \
  "$ROOT/LaunchAgents/local.klik-pro.input.plist"
do
  plutil -lint "$plist"
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
[[ "${#DUPLICATION_SOURCES[@]}" -eq 9 ]]
# Pin the production registry's exact intent: Claude remains evidence-backed
# Verified, while ChatGPT is explicitly owner-enabled as Untested with its
# required isolation environment and no tested-version claim.
production_block="$(sed -n '/static let production = AppCompatibilityRegistry(rules: \[/,/^    \])/p' \
  "$ROOT/Sources/Duplication/EngineDetector.swift")"
[[ -n "$production_block" ]]
[[ "$(printf '%s\n' "$production_block" | grep -c 'AppCompatibilityRule(')" -eq 2 ]]
printf '%s\n' "$production_block" | grep -qF 'id: "com-anthropic-claudefordesktop-verified"'
printf '%s\n' "$production_block" | grep -qF 'bundleIdentifier: "com.anthropic.claudefordesktop"'
printf '%s\n' "$production_block" | grep -qF 'teamIdentifier: "Q6L2SF6YDW"'
printf '%s\n' "$production_block" | grep -qF 'testedVersions: ["1.21459.0", "1.21459.1"]'
printf '%s\n' "$production_block" | grep -qF 'id: "com-openai-codex-untested"'
printf '%s\n' "$production_block" | grep -qF 'bundleIdentifier: "com.openai.codex"'
printf '%s\n' "$production_block" | grep -qF 'teamIdentifier: "2DC432GLL2"'
printf '%s\n' "$production_block" | grep -qF 'assurance: .untested'
printf '%s\n' "$production_block" | grep -qF 'acceptsAnyVersion: true'
[[ "$(printf '%s\n' "$production_block" | grep -cF 'acceptsAnyVersion: true')" -eq 2 ]]
printf '%s\n' "$production_block" | grep -qF '"CODEX_HOME": "{codexHomeDir}"'
printf '%s\n' "$production_block" | grep -qF '"CODEX_ELECTRON_USER_DATA_PATH": "{profileDir}"'
printf '%s\n' "$production_block" | grep -qF '"CLAUDE_CONFIG_DIR": "{codexHomeDir}"'
printf '%s\n' "$production_block" | grep -qF 'homeSymlinkPrefix: "claude"'
printf '%s\n' "$production_block" | grep -qF 'homeSymlinkPrefix: "codex"'
grep -q 'M1 removes only Klik PRO' "$ROOT/Sources/Duplication/LauncherGenerator.swift"
grep -q 'currentCandidate.canCreate' "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'eligibility.compatibilityRuleID != nil' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
# A relaunch of an already-running profile must reopen that instance, never spawn
# a duplicate — apps like Claude for Desktop enforce no single-instance lock of
# their own. Menu-bar path reopens the one running pid; the Dock/Launchpad/Finder
# runner scans for it before ever creating a new instance.
grep -q 'reopenWindow: true' "$ROOT/Sources/Duplication/AppProfileRuntime.swift"
grep -q 'sendReopenEvent(to: existing.processIdentifier)' \
  "$ROOT/Sources/KlikProManagedLauncher.swift"
# Reopen Apple events require a purpose string in both the main app and every
# generated launcher. Existing launchers embed their own runner and metadata, so
# healing must update both in place without touching profile data.
[[ "$(plutil -extract NSAppleEventsUsageDescription raw -o - "$ROOT/App/Info.plist")" \
  == "Klik PRO reopens the selected App Profile's existing window without launching a duplicate." ]]
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
[[ "$(grep -cE '^        "[A-Z_]+",$' "$ROOT/Sources/Duplication/LauncherGenerator.swift")" -eq 3 ]]
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
grep -q 'normalized.schemaVersion = 12' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'createPreV2BackupIfNeeded(originalData: data)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'O_WRONLY | O_CREAT | O_EXCL' "$ROOT/Sources/KlikProConfig.swift"

# Durable Data Vault (Phase 1) pins: additive schema 11, fail-closed vault
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

# Durable Data Vault (Phase 2) pins: the dormant backend is wired in through a
# single testable factory, and the locked Advanced tab drives it. The factory
# must fail safe to a no-vault generator (byte-for-byte the pre-vault app) for a
# nil/invalid/Application-Support data root — the guard is the vaultPathRejection
# gate, mirrored in the test suite.
grep -q 'func makeLauncherGenerator(forDataRoot' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'func makeAppProfileManager(forDataRoot' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
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
grep -q 'Drag Klik PRO.app to Applications' "$ROOT/tools/render-dmg-background.swift"
grep -q 'DMG top level must keep technical files inside Extras' "$ROOT/tools/build-release.sh"
grep -q 'Extras/LaunchAgents' "$ROOT/tools/build-release.sh"
if [[ "$(grep -ci 'copyright' "$ROOT/README.md")" -ne 1 ]]; then
  echo "README must assert the project copyright exactly once (GPL-3.0 requires the owner's notice)" >&2
  exit 1
fi
grep -q '^## Support development$' "$ROOT/README.md"
[[ "$(grep -c 'This app is open source under the GNU General Public License v3.0.' "$ROOT/README.md")" -eq 2 ]]
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
bash -n "$ROOT/install.sh" "$ROOT/tools/sign-release-manifest.sh" "$ROOT/tools/build-release.sh"
bash -n "$ROOT/tools/evidence-run.sh"
[[ -x "$ROOT/install.sh" ]]
[[ -x "$ROOT/tools/sign-release-manifest.sh" ]]
[[ -x "$ROOT/tools/evidence-run.sh" ]]
installerPublicKey="$(sed -n 's/^readonly RELEASE_PUBLIC_KEY="\(.*\)"/\1/p' "$ROOT/install.sh")"
signerPublicKey="$(sed -n 's/^readonly EXPECTED_PUBLIC_KEY="\(.*\)"/\1/p' "$ROOT/tools/sign-release-manifest.sh")"
publishedPublicKey="$(awk '{ print $1 " " $2 }' "$ROOT/release-signing-key.pub")"
[[ -n "$installerPublicKey" && "$installerPublicKey" == "$signerPublicKey" ]]
[[ "$installerPublicKey" == "$publishedPublicKey" ]]
[[ "$(ssh-keygen -lf "$ROOT/release-signing-key.pub" | awk '{ print $2 }')" \
  == 'SHA256:Evg4ITqpPJY/aIT48Zv9Cp3psQfo977uCz/35a2k79E' ]]
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
grep -q 'title: "Reset Access…"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'title: "Recheck"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'preferencesView.recheckAccessibilityLink.onClick' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recheckAccessibilityLink.title = "Checking…"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'permissionRecheckXOffset: CGFloat = 168' "$ROOT/Sources/KlikProApp.swift"
grep -q 'x: rxi + PreferencesContentView.permissionRecheckXOffset' "$ROOT/Sources/KlikProApp.swift"
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
# Step 3 is opt-in: grant now, or "Skip for Now" (completes onboarding, grant later).
grep -q 'alert.addButton(withTitle: "Skip for Now")' "$ROOT/Sources/KlikProApp.swift"
if grep -q 'addButton(withTitle: "View Mappings")' "$ROOT/Sources/KlikProApp.swift"; then
  echo "Onboarding step 3 no longer offers View Mappings" >&2
  exit 1
fi
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
primarySaveBlock="$(sed -n '/final class PrimaryHoverButton/,/^}/p' "$ROOT/Sources/KlikProApp.swift")"
grep -q 'options: \[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect\]' <<<"$primarySaveBlock"
grep -q ': (isHovered ? KlikProBrand.green : accent)' <<<"$primarySaveBlock"
grep -q 'if isHovered && isEnabled' <<<"$primarySaveBlock"
grep -q 'NSColor.black.setStroke()' <<<"$primarySaveBlock"
grep -q 'saveButton.onPress' "$ROOT/Sources/KlikProApp.swift"
grep -q 'self?.saveConfiguration()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'label: "local.klik-pro.settings.save-apply"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'saveApplyQueue.async' "$ROOT/Sources/KlikProApp.swift"
grep -q 'DispatchQueue.main.async' "$ROOT/Sources/KlikProApp.swift"
grep -q 'saveButton.title = inProgress ? "Applying…" : "Save"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Saved — helper apply timed out.' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func run(_ arguments: \[String\], timeout: TimeInterval = 8)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'completion.wait(timeout: .now() + timeout)' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'rect: updateButtonRect' "$ROOT/Sources/KlikProApp.swift"
grep -q 'updateButtonHovered ? 0.20 : 0.12' "$ROOT/Sources/KlikProApp.swift"
grep -q 'showUpdateButtonHoverPreview()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'rect: closeButtonRect' "$ROOT/Sources/KlikProApp.swift"
grep -q 'showCloseButtonHoverPreview()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'if closeButtonHovered' "$ROOT/Sources/KlikProApp.swift"
grep -q 'let settingsButton = IconActionButton(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private let appProfilesView: AppProfilesContentView' "$ROOT/Sources/KlikProApp.swift"
grep -q 'private let appProfilesTabRect' "$ROOT/Sources/KlikProApp.swift"
grep -q 'refreshSupportedAppCandidates()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'appProfileManager.supportedCandidates()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func supportedCandidates(searchRoots:' \
  "$ROOT/Sources/Duplication/AppProfileManager.swift"
grep -q 'appProfilesView.onGenerate' "$ROOT/Sources/KlikProApp.swift"
grep -q 'APP PROFILE GENERATOR' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'Generate another icon for the same app, with a separate login and settings.' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'The original app is never copied, cloned or modified.' \
  "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'AppProfileButton(title: "Generate"' "$ROOT/Sources/AppProfilesUI.swift"
if grep -q 'Generate Another' "$ROOT/Sources/AppProfilesUI.swift"; then
  echo "App Profile generator must use the approved Generate label" >&2
  exit 1
fi
grep -q 'Assign Button' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'statusField.frame = NSRect(x: 344, y: 108' "$ROOT/Sources/AppProfilesUI.swift"
grep -q 'scrollView.frame = NSRect(x: 340, y: 142' "$ROOT/Sources/AppProfilesUI.swift"
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
grep -q 'scrollView.autohidesScrollers = false' "$ROOT/Sources/AppProfilesUI.swift"
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
grep -q 'systemSymbolName: "arrow.counterclockwise"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'Reset .* shortcut to default' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recorder.setCombo(self.defaultCombo)' "$ROOT/Sources/KlikProApp.swift"
grep -q 'recordableCard     = NSRect(x: leftCardX' "$ROOT/Sources/KlikProApp.swift"
grep -q 'thumbWheelCard     = NSRect(x: leftCardX' "$ROOT/Sources/KlikProApp.swift"
grep -q 'actionPicker.addItems(withTitles: \["Shortcut", "Open App"\])' "$ROOT/Sources/KlikProApp.swift"
grep -q 'func setDualAppMapping(instanceID:' "$ROOT/Sources/KlikProApp.swift"
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
grep -q 'row.setOpenAppOptions(availableInstances, assignedID: assigned?.id)' \
  "$ROOT/Sources/KlikProApp.swift"
grep -q 'quickLaunchMousePickerIsEnabled(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'quickLaunchMouseSelectionIsAllowed(' "$ROOT/Sources/KlikProApp.swift"
grep -q 'guard !previewRenderingIsActive else { return 1 }' "$ROOT/Sources/KlikProConfig.swift"
grep -q 'if !previewRenderingIsActive && autoCheckEnabled' "$ROOT/Sources/KlikProApp.swift"
grep -q 'NSApp.disableRelaunchOnLogin()' "$ROOT/Sources/KlikProApp.swift"
grep -q 'previewRenderingIsActive = true' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_INSTALLED_TARGETS' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_UNSAVED' "$ROOT/tools/PreviewMain.swift"
grep -q 'KLIK_PRO_PREVIEW_USE_INSTALLED_APP_ICONS' "$ROOT/Sources/KlikProApp.swift"
grep -q 'render_preview "$ROOT/assets/screenshot-mappings.png" mappings "" 1' "$ROOT/tools/render-previews.sh"
grep -q 'special-feature-no-apps.png' "$ROOT/tools/render-previews.sh"
grep -q 'special-feature-chatgpt-only.png' "$ROOT/tools/render-previews.sh"
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
grep -A4 'persistedConfig = configToSave' "$ROOT/Sources/KlikProApp.swift" | grep -q 'persistedControlState = controlStateToSave'
grep -q '"Unsaved changes"' "$ROOT/Sources/KlikProApp.swift"
grep -q 'NSColor.systemRed' "$ROOT/Sources/KlikProApp.swift"
grep -q 'unsaved-changes.png' "$ROOT/tools/render-previews.sh"
grep -q 'save-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'update-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'close-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'onboarding-back-hover.png' "$ROOT/tools/render-previews.sh"
grep -q 'about.png' "$ROOT/tools/render-previews.sh"
# README shows the animated onboarding flow (GIF) at the same display width.
grep -q 'onboarding-flow.gif' "$ROOT/README.md"
grep -Eq 'onboarding-flow\.gif[^\"]*" width="462"' "$ROOT/README.md"
grep -q 'app-profiles-icon-showcase.gif' "$ROOT/README.md"
[[ -s "$ROOT/assets/app-profiles-icon-showcase.gif" ]]
# The locked-state Advanced screenshot documents the new lock/warning gate.
grep -q 'screenshot-advanced-locked.png' "$ROOT/README.md"
grep -q 'roundedRect: borderRect' "$ROOT/tools/PreviewMain.swift"
grep -q 'let previewScale: CGFloat = 2' "$ROOT/tools/PreviewMain.swift"
grep -q 'bitmap.size = bounds.size' "$ROOT/tools/PreviewMain.swift"
grep -q 'screenshot-onboarding.png' "$ROOT/tools/render-previews.sh"

previewRunOne="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-check-preview-one-$STAMP.XXXXXX")"
previewRunTwo="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-check-preview-two-$STAMP.XXXXXX")"
KLIK_PRO_PREVIEW_WORK_DIRECTORY="$previewRunOne" \
  "$ROOT/tools/render-previews.sh" --fixtures-only > "$OUT/preview-fixtures-one.log"
KLIK_PRO_PREVIEW_WORK_DIRECTORY="$previewRunTwo" \
  "$ROOT/tools/render-previews.sh" --fixtures-only > "$OUT/preview-fixtures-two.log"

for fixtureName in \
  app-profiles.png \
  app-profiles-empty.png \
  special-feature-no-apps.png \
  special-feature-chatgpt-only.png \
  settings-needs-permission.png \
  unsaved-changes.png \
  save-hover.png \
  update-hover.png \
  close-hover.png
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
  [[ "$(sips -g pixelHeight "$firstFixture" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "1868" ]] || {
    echo "Unexpected preview height: $fixtureName" >&2
    exit 1
  }
  [[ "$(sips -g hasAlpha "$firstFixture" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "no" ]] || {
    echo "Preview fixture must be opaque: $fixtureName" >&2
    exit 1
  }
  cmp "$firstFixture" "$secondFixture"
done

# Step pages have different heights; each fixture pins its own expected height.
onboardingFixtureHeight() {
  case "$(basename "$1")" in
    onboarding.png) echo "576" ;;
    onboarding-toggles.png) echo "832" ;;
    onboarding-access.png|onboarding-back-hover.png) echo "736" ;;
    onboarding-granted.png) echo "668" ;;
    *) echo "0" ;;
  esac
}
for onboardingFixture in \
  "$previewRunOne/fixtures/onboarding.png" \
  "$previewRunTwo/fixtures/onboarding.png" \
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
  "$previewRunOne/fixtures/special-feature-no-apps.png" \
  "$previewRunOne/fixtures/update-hover.png"
then
  echo "Check-for-Updates hover fixture must differ from its normal state" >&2
  exit 1
fi

if cmp -s \
  "$previewRunOne/fixtures/special-feature-no-apps.png" \
  "$previewRunOne/fixtures/close-hover.png"
then
  echo "Close-button hover fixture must differ from its normal state" >&2
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
echo "Close-button hover check passed"
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
done

lipo -create \
  "$OUT/klik-pro-managed-launcher-arm64" \
  "$OUT/klik-pro-managed-launcher-x86_64" \
  -output "$OUT/KlikProManagedLauncher"
runnerArchs="$(lipo -archs "$OUT/KlikProManagedLauncher")"
[[ "$runnerArchs" == "x86_64 arm64" || "$runnerArchs" == "arm64 x86_64" ]]
for arch in arm64 x86_64; do
  vtool -show-build -arch "$arch" "$OUT/KlikProManagedLauncher" | grep -q 'minos 13.0'
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

[[ "$(sips -g hasAlpha "$ROOT/assets/Klik PRO mouse.png" 2>/dev/null | awk '/hasAlpha/ { print $2 }')" == "yes" ]]
[[ "$(sips -g pixelWidth "$OUT/device-reference.png" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "1000" ]]
[[ "$(sips -g pixelHeight "$OUT/device-reference.png" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "742" ]]

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
  [[ "$(sips -g pixelWidth "$iconPath" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "$expectedSize" ]]
  [[ "$(sips -g pixelHeight "$iconPath" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == "$expectedSize" ]]
done

# iconutil may rewrite PNG metadata while preserving pixels, so normalize the 1024px
# representation to BMP before comparing it with the tracked master.
sips -s format bmp "$OUT/icon-master.png" --out "$OUT/icon-master.bmp" >/dev/null
sips -s format bmp \
  "$OUT/KlikPRO.iconset/icon_512x512@2x.png" \
  --out "$OUT/icon-from-icns.bmp" >/dev/null
cmp "$OUT/icon-master.bmp" "$OUT/icon-from-icns.bmp"

echo "All checks passed (outputs: $OUT)"
