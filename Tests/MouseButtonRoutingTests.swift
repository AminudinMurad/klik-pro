import AppKit
import Carbon
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private struct MouseButtonRoutingTests {
    static func main() {
        let menuBarIcon = klikProMenuBarIcon()
        expect(menuBarIcon.size == NSSize(width: 18, height: 18),
               "Klik PRO menu-bar artwork must use the native 18pt status-item canvas")
        expect(menuBarIcon.isTemplate,
               "Klik PRO menu-bar artwork must be a light/dark adaptive template image")
        guard let menuBarTIFF = menuBarIcon.tiffRepresentation,
              let menuBarBitmap = NSBitmapImageRep(data: menuBarTIFF) else {
            fputs("FAIL: unable to rasterize Klik PRO menu-bar artwork\n", stderr)
            exit(1)
        }
        var visibleMenuBarPixels = 0
        for y in 0..<menuBarBitmap.pixelsHigh {
            for x in 0..<menuBarBitmap.pixelsWide {
                if (menuBarBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    visibleMenuBarPixels += 1
                }
            }
        }
        let menuBarCoverage = Double(visibleMenuBarPixels)
            / Double(menuBarBitmap.pixelsWide * menuBarBitmap.pixelsHigh)
        expect(menuBarCoverage > 0.25 && menuBarCoverage < 0.70,
               "menu-bar mouse silhouette must remain visible without becoming a solid tile")
        expect((menuBarBitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01,
               "menu-bar icon corners must remain transparent")

        let activeMenuBarIndicator = klikProMenuBarActiveIndicator()
        expect(activeMenuBarIndicator.size == NSSize(width: 18, height: 18),
               "active menu-bar dots must share the base icon's 18pt canvas")
        expect(!activeMenuBarIndicator.isTemplate,
               "green active-state dots must not be converted to a monochrome template")
        guard let activeIndicatorTIFF = activeMenuBarIndicator.tiffRepresentation,
              let activeIndicatorBitmap = NSBitmapImageRep(data: activeIndicatorTIFF) else {
            fputs("FAIL: unable to rasterize Klik PRO active-state dots\n", stderr)
            exit(1)
        }
        var greenIndicatorPixels = 0
        var visibleIndicatorPixels = 0
        for y in 0..<activeIndicatorBitmap.pixelsHigh {
            for x in 0..<activeIndicatorBitmap.pixelsWide {
                guard let color = activeIndicatorBitmap.colorAt(x: x, y: y),
                      color.alphaComponent > 0.05 else { continue }
                visibleIndicatorPixels += 1
                if color.greenComponent > 0.60,
                   color.redComponent < 0.55,
                   color.blueComponent < 0.55 {
                    greenIndicatorPixels += 1
                }
            }
        }
        expect(greenIndicatorPixels > 2,
               "active menu-bar overlay must contain visible green button dots")
        expect(visibleIndicatorPixels < activeIndicatorBitmap.pixelsWide
               * activeIndicatorBitmap.pixelsHigh / 5,
               "active menu-bar overlay must remain two compact dots, not a colored tile")
        expect((activeIndicatorBitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01,
               "active menu-bar overlay corners must remain transparent")

        let nestedHelperURL = URL(fileURLWithPath:
            "/Applications/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app"
        )
        expect(enclosingKlikProAppURL(for: nestedHelperURL)?.path
               == "/Applications/Klik PRO.app",
               "nested helper must resolve its enclosing Klik PRO app")
        expect(enclosingKlikProAppURL(for: URL(fileURLWithPath: "/tmp/klik-pro-input")) == nil,
               "an unbundled helper must not invent an enclosing app path")

        expect(ShortcutSlot.allCases.count == 6,
               "only the four active mouse mappings and two global hotkeys belong in ShortcutSlot")
        expect(QuickLaunchMouseButton.allCases.map(\.title) == ["Middle", "Gesture", "Forward", "Back"],
               "quick-launch assignment order must be Middle, Gesture, Forward, Back")
        expect(QuickLaunchTarget.chatGPT.applicationBundleIdentifier == "com.openai.codex"
               && QuickLaunchTarget.claude.applicationBundleIdentifier
               == "com.anthropic.claudefordesktop",
               "Special Feature installation checks must use the actual desktop-app bundle IDs")
        let validChatGPTBundle = QuickLaunchBundleInspection(
            bundleIdentifier: QuickLaunchTarget.chatGPT.applicationBundleIdentifier,
            packageType: "APPL",
            executableName: "ChatGPT",
            executableIsRunnable: true
        )
        expect(quickLaunchApplicationBundleIsValid(
            for: .chatGPT,
            candidatePath: QuickLaunchTarget.chatGPT.standardApplicationPath,
            inspection: validChatGPTBundle
        ), "the genuine standard ChatGPT application bundle must count as installed")
        expect(!quickLaunchApplicationBundleIsValid(
            for: .chatGPT,
            candidatePath: "/Custom/ChatGPT.app",
            inspection: validChatGPTBundle
        ), "a custom-path bundle must not enable wrappers that require /Applications")
        expect(!quickLaunchApplicationBundleIsValid(
            for: .chatGPT,
            candidatePath: QuickLaunchTarget.chatGPT.standardApplicationPath,
            inspection: QuickLaunchBundleInspection(
                bundleIdentifier: "local.chatgpt.profile1",
                packageType: "APPL",
                executableName: "ChatGPT",
                executableIsRunnable: true
            )
        ), "a launcher wrapper at the standard app path must not impersonate ChatGPT")
        expect(!quickLaunchBundleIsRunnable(QuickLaunchBundleInspection(
            bundleIdentifier: "local.invalid.bundle",
            packageType: "APPL",
            executableName: "../outside",
            executableIsRunnable: true
        )), "an app bundle executable must be a safe basename")
        for dotExecutable in [".", ".."] {
            expect(!quickLaunchBundleIsRunnable(QuickLaunchBundleInspection(
                bundleIdentifier: "local.invalid.bundle",
                packageType: "APPL",
                executableName: dotExecutable,
                executableIsRunnable: true
            )), "dot path components must not count as bundle executables")
        }
        expect(!quickLaunchBundleIsRunnable(QuickLaunchBundleInspection(
            bundleIdentifier: "local.invalid.bundle",
            packageType: "APPL",
            executableName: "MacOS",
            executableIsRegularFile: false,
            executableIsRunnable: true
        )), "a searchable directory must not count as a runnable bundle executable")
        expect(!quickLaunchBundleIsRunnable(QuickLaunchBundleInspection(
            bundleIdentifier: "local.invalid.bundle",
            packageType: "APPL",
            executableName: "launcher",
            executableIsRunnable: false
        )), "a stale wrapper directory without a runnable executable must be unavailable")
        expect(!quickLaunchBundleIsRunnable(QuickLaunchBundleInspection(
            bundleIdentifier: "local.invalid.bundle",
            packageType: nil,
            executableName: "launcher",
            executableIsRunnable: true
        )), "a launcher must be an APPL bundle")

        expect(quickLaunchTargetReadiness(appInstalled: true, launcherRunnable: true) == .ready,
               "an installed app with a runnable wrapper must be ready")
        expect(quickLaunchTargetReadiness(appInstalled: false, launcherRunnable: true)
               == .appNotInstalled,
               "a wrapper alone must report Not installed")
        expect(quickLaunchTargetReadiness(appInstalled: true, launcherRunnable: false)
               == .launcherMissing,
               "an installed app without a runnable wrapper must report Launcher missing")
        expect(QuickLaunchTargetReadiness.ready.shortLabel == nil
               && QuickLaunchTargetReadiness.appNotInstalled.shortLabel == "Not installed"
               && QuickLaunchTargetReadiness.launcherMissing.shortLabel == "Launcher missing",
               "readiness labels must be concise and omit a badge for ready targets")
        expect(!QuickLaunchTargetReadiness.ready.explanation.isEmpty
               && !QuickLaunchTargetReadiness.appNotInstalled.explanation.isEmpty
               && !QuickLaunchTargetReadiness.launcherMissing.explanation.isEmpty,
               "every readiness state must provide UI help text")
        expect(quickLaunchMouseSelectionIsAllowed(.gesture, readiness: .ready),
               "a ready launcher must accept a mouse-button assignment")
        expect(!quickLaunchMouseSelectionIsAllowed(.gesture, readiness: .appNotInstalled)
               && !quickLaunchMouseSelectionIsAllowed(.gesture, readiness: .launcherMissing),
               "an unavailable launcher must reject new mouse-button assignments")
        expect(quickLaunchMouseSelectionIsAllowed(nil, readiness: .appNotInstalled)
               && quickLaunchMouseSelectionIsAllowed(nil, readiness: .launcherMissing),
               "an unavailable launcher must still allow a stale assignment to be cleared")
        expect(!quickLaunchMousePickerIsEnabled(readiness: .appNotInstalled, selection: nil)
               && quickLaunchMousePickerIsEnabled(readiness: .appNotInstalled, selection: .back),
               "an unavailable picker must enable only when it has an assignment to repair")

        quickLaunchInstalledTargetsPreviewOverride = [.chatGPT]
        expect(quickLaunchTargetReadiness(.chatGPT) == .ready
               && quickLaunchTargetIsAvailable(.chatGPT),
               "an included preview target must bypass host bundle and wrapper state")
        expect(quickLaunchTargetReadiness(.claude) == .appNotInstalled
               && !quickLaunchTargetIsAvailable(.claude),
               "an excluded preview target must deterministically report Not installed")
        expect(quickLaunchTargetApplicationURL(.chatGPT)?.path
               == QuickLaunchTarget.chatGPT.standardApplicationPath
               && quickLaunchTargetApplicationURL(.claude) == nil,
               "preview installation resolution must return only fixture targets")
        quickLaunchInstalledTargetsPreviewOverride = []
        expect(!hasInstalledQuickLaunchTarget(),
               "an empty preview fixture must disable the Special Feature master toggle")
        quickLaunchInstalledTargetsPreviewOverride = nil

        expect(hasInstalledQuickLaunchTarget(resolver: { target in
            target == .claude
                ? URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true)
                : nil
        }), "either supported desktop app must enable the Special Feature toggle")
        expect(!hasInstalledQuickLaunchTarget(resolver: { _ in nil }),
               "the Special Feature toggle must remain disabled when both apps are absent")
        expect(quickLaunchTargetCanRun(installed: true, wrapperPresent: true),
               "an installed app with its wrapper must be runnable")
        expect(!quickLaunchTargetCanRun(installed: false, wrapperPresent: true)
               && !quickLaunchTargetCanRun(installed: true, wrapperPresent: false),
               "both the real app and its wrapper are required for launcher dispatch")

        previewRenderingIsActive = true
        quickLaunchInstalledTargetsPreviewOverride = [.chatGPT]
        expect(run(["print", "preview-must-not-call-launchctl"]) == 1,
               "preview rendering must block every launchctl invocation")
        expect(probeHotKeyAvailability(keyCode: UInt16(kVK_F19), carbonModifiers: 0),
               "preview rendering must not register transient system-wide hotkeys")
        expect(installedChromeExtensionShortcutSignatures(homeDirectory: "/unused").isEmpty,
               "preview rendering must not inspect live browser profiles")
        previewRenderingIsActive = false
        quickLaunchInstalledTargetsPreviewOverride = nil
        expect(shortcutSlot(forMouseButtonNumber: 2) == .middleButton,
               "CG button 2 must route to Middle")
        expect(shortcutSlot(forMouseButtonNumber: 3) == .backButton,
               "CG button 3 / Mouse Button 4 must route to Back")
        expect(shortcutSlot(forMouseButtonNumber: 4) == .forwardButton,
               "CG button 4 / Mouse Button 5 must route to Forward")
        expect(shortcutSlot(forMouseButtonNumber: 1) == nil,
               "unmanaged button 1 must pass through")
        expect(shortcutSlot(forMouseButtonNumber: 5) == nil,
               "unmanaged button 5 must pass through")

        expect(KlikProConfig.default.schemaVersion == 11,
               "new configurations must use schema 11 (Durable Data Vault fields)")
        expect(!KlikProConfig.default.onboardingCompleted,
               "a new configuration must begin with onboarding pending")
        expect(!KlikProConfig.default.showMenuBarIcon,
               "a fresh install starts with the menu-bar icon off; first-run onboarding turns it on")
        expect(!KlikProConfig.default.caffeinateMenuEnabled,
               "Caffeinate must start off on a fresh install")
        expect(KlikProConfig.default.showQuickLaunchMenuIcons,
               "legacy Dual App menu icon seed must remain compatible by default")
        expect(!KlikProConfig.default.specialFeatureEnabled,
               "Special Feature must remain off until the user enables it")
        expect(KlikProConfig.default.thumbWheel.firefoxEnabled,
               "Firefox thumb-wheel tab switching must be enabled by default")
        expect(KlikProConfig.default.chatGPTMouseButton == .forward
               && KlikProConfig.default.claudeMouseButton == .back,
               "new configurations must link Forward to ChatGPT and Back to Claude")

        var legacyConfig = KlikProConfig.default
        legacyConfig.schemaVersion = 4
        legacyConfig.middleButton.enabled = false
        legacyConfig.middleButton.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_M), keyDisplay: "M",
            command: true, option: true, control: false, shift: false
        )
        do {
            let encoded = try JSONEncoder().encode(legacyConfig)
            var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            object.removeValue(forKey: "chatGPTMouseButton")
            object.removeValue(forKey: "claudeMouseButton")
            object.removeValue(forKey: "showMenuBarIcon")
            object.removeValue(forKey: "showQuickLaunchMenuIcons")
            object.removeValue(forKey: "onboardingCompleted")
            var legacyThumbWheel = object["thumbWheel"] as! [String: Any]
            legacyThumbWheel.removeValue(forKey: "firefoxEnabled")
            legacyThumbWheel["defaultFallbackEnabled"] = false
            object["thumbWheel"] = legacyThumbWheel
            let legacyData = try JSONSerialization.data(withJSONObject: object)
            let decoded = try JSONDecoder().decode(KlikProConfig.self, from: legacyData)
            expect(decoded.schemaVersion == 4,
                   "a schema-4 config must decode before in-memory normalization")
            expect(decoded.chatGPTMouseButton == .forward && decoded.claudeMouseButton == .back,
                   "missing legacy assignment fields must receive the new side-button defaults")
            expect(decoded.showMenuBarIcon,
                   "an older config without icon visibility must keep the icon visible")
            expect(decoded.showQuickLaunchMenuIcons,
                   "an older config must keep its Special Feature menu icons visible")
            expect(decoded.onboardingCompleted,
                   "an existing pre-schema-8 user must not receive first-run onboarding")
            expect(!decoded.thumbWheel.firefoxEnabled,
                   "a legacy config must preserve its Firefox behavior from the generic fallback")
            let normalized = normalizedQuickLaunchConfig(decoded)
            expect(normalized.schemaVersion == 11,
                   "schema-4 configs must normalize through the layered migrations to schema 11")
            expect(normalized.instances.count == 2,
                   "pre-v2 configs must receive both legacy-external instance rows")
            expect(normalized.middleButton == legacyConfig.middleButton,
                   "normalization must preserve a custom disabled legacy button mapping")
        } catch {
            fputs("FAIL: unable to decode schema-4 compatibility fixture: \(error)\n", stderr)
            exit(1)
        }

        var completedOnboardingConfig = KlikProConfig.default
        completedOnboardingConfig.onboardingCompleted = true
        completedOnboardingConfig.specialFeatureEnabled = true
        do {
            let data = try JSONEncoder().encode(completedOnboardingConfig)
            let decoded = try JSONDecoder().decode(KlikProConfig.self, from: data)
            expect(decoded.onboardingCompleted,
                   "completed onboarding must persist across schema-10 config reloads")
            expect(decoded.specialFeatureEnabled,
                   "combined-service Special Feature state must persist in config")
        } catch {
            fputs("FAIL: unable to round-trip onboarding state: \(error)\n", stderr)
            exit(1)
        }

        do {
            let directory = NSTemporaryDirectory()
                + "/klik-pro-corrupt-config-test-\(UUID().uuidString)"
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            let file = directory + "/config.json"
            let corruptData = Data("{not valid json".utf8)
            try corruptData.write(to: URL(fileURLWithPath: file))
            setenv("KLIK_PRO_CONFIG_DIRECTORY", directory, 1)
            defer {
                unsetenv("KLIK_PRO_CONFIG_DIRECTORY")
                try? FileManager.default.removeItem(atPath: directory)
            }

            let fallback = KlikProConfigStore.load()
            expect(fallback.onboardingCompleted,
                   "an existing corrupt config must not be mistaken for a fresh installation")
            let preservedData = try Data(contentsOf: URL(fileURLWithPath: file))
            expect(preservedData == corruptData,
                   "onboarding detection must leave an existing corrupt config untouched")
        } catch {
            fputs("FAIL: unable to verify corrupt-config onboarding safety: \(error)\n", stderr)
            exit(1)
        }

        var partialLegacyConfig = KlikProConfig.default
        partialLegacyConfig.schemaVersion = 6
        partialLegacyConfig.chatGPTMouseButton = nil
        partialLegacyConfig.claudeMouseButton = .forward
        do {
            let data = try JSONEncoder().encode(partialLegacyConfig)
            let decoded = try JSONDecoder().decode(KlikProConfig.self, from: data)
            expect(decoded.chatGPTMouseButton == nil && decoded.claudeMouseButton == .forward,
                   "migration must preserve a legacy custom assignment without adding a duplicate default")
        } catch {
            fputs("FAIL: unable to migrate a partial legacy assignment: \(error)\n", stderr)
            exit(1)
        }

        var explicitNoneConfig = KlikProConfig.default
        explicitNoneConfig.chatGPTMouseButton = nil
        explicitNoneConfig.claudeMouseButton = nil
        do {
            let data = try JSONEncoder().encode(explicitNoneConfig)
            let decoded = try JSONDecoder().decode(KlikProConfig.self, from: data)
            expect(decoded.chatGPTMouseButton == nil && decoded.claudeMouseButton == nil,
                   "explicit None assignments must survive decoding without default replacement")
        } catch {
            fputs("FAIL: unable to round-trip explicit None assignments: \(error)\n", stderr)
            exit(1)
        }

        var linkedRoundTrip = KlikProConfig.default
        linkedRoundTrip.showMenuBarIcon = false
        linkedRoundTrip.showQuickLaunchMenuIcons = false
        linkedRoundTrip.thumbWheel.firefoxEnabled = false
        linkedRoundTrip.chatGPTMouseButton = .middle
        linkedRoundTrip.claudeMouseButton = .gesture
        do {
            let data = try JSONEncoder().encode(linkedRoundTrip)
            let decoded = try JSONDecoder().decode(KlikProConfig.self, from: data)
            expect(decoded == linkedRoundTrip,
                   "schema-7 settings must round-trip")
        } catch {
            fputs("FAIL: unable to round-trip schema-6 config: \(error)\n", stderr)
            exit(1)
        }
        expect(KlikProConfig.default.backButton.combo.signature == defaultBrowserBackCombo.signature,
               "default Back must retain Safari's documented Command-[ fallback")
        expect(KlikProConfig.default.forwardButton.combo.signature == defaultBrowserForwardCombo.signature,
               "default Forward must retain Safari's documented Command-] fallback")
        var browserChoices = KlikProConfig.default.thumbWheel
        browserChoices.defaultFallbackEnabled = false
        expect(thumbWheelMappingIsEnabled(
            for: "org.mozilla.firefox",
            config: browserChoices
        ), "Firefox must use its dedicated thumb-wheel setting rather than the generic fallback")
        expect(thumbWheelMappingIsEnabled(
            for: "org.mozilla.firefoxdeveloperedition",
            config: browserChoices
        ), "Firefox Developer Edition must share the Firefox thumb-wheel setting")
        browserChoices.firefoxEnabled = false
        expect(!thumbWheelMappingIsEnabled(
            for: "org.mozilla.firefox",
            config: browserChoices
        ), "turning off Firefox must pass its native horizontal scroll through")

        var quickLaunchConfig = KlikProConfig.default
        let originalMiddle = ShortcutMapping(
            enabled: false,
            combo: KeyCombo(
                keyCode: UInt16(kVK_ANSI_M), keyDisplay: "M",
                command: true, option: true, control: false, shift: false
            )
        )
        quickLaunchConfig.middleButton = originalMiddle
        quickLaunchConfig.chatGPTMouseButton = .middle
        expect(quickLaunchMouseAssignmentsAreValid(quickLaunchConfig),
               "one launcher assignment must be valid")
        expect(assignedQuickLaunchTarget(for: .middleButton, in: quickLaunchConfig) == .chatGPT,
               "Middle must resolve to its assigned ChatGPT / Codex launcher")
        let activeMiddle = mapping(
            for: .middleButton,
            in: quickLaunchConfig,
            specialFeatureActive: true,
            chatGPTAvailable: true,
            claudeAvailable: true
        )
        expect(activeMiddle.enabled,
               "an active launcher overlay must force its selected button on")
        expect(activeMiddle.combo.signature == quickLaunchConfig.chatGPTHotkey.combo.signature,
               "an active selected button must mirror the launcher combo")
        expect(mapping(
            for: .middleButton,
            in: quickLaunchConfig,
            specialFeatureActive: false,
            chatGPTAvailable: true,
            claudeAvailable: true
        ) == originalMiddle,
        "Special Feature OFF must restore the untouched underlying mapping")
        expect(mapping(
            for: .middleButton,
            in: quickLaunchConfig,
            specialFeatureActive: true,
            chatGPTAvailable: false,
            claudeAvailable: true
        ) == originalMiddle,
        "a missing ChatGPT launcher must not steal its assigned mouse button")
        quickLaunchConfig.chatGPTHotkey.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_L), keyDisplay: "L",
            command: true, option: true, control: true, shift: false
        )
        expect(mapping(for: .middleButton, in: quickLaunchConfig).combo.signature
               == quickLaunchConfig.chatGPTHotkey.combo.signature,
               "editing a launcher hotkey must update its mirrored mouse combo")

        var invalidAssignments = quickLaunchConfig
        invalidAssignments.claudeMouseButton = .middle
        expect(!quickLaunchMouseAssignmentsAreValid(invalidAssignments),
               "one physical button cannot be assigned to both launchers")
        let normalizedInvalid = normalizedQuickLaunchConfig(invalidAssignments)
        expect(normalizedInvalid.chatGPTMouseButton == .middle
               && normalizedInvalid.claudeMouseButton == .middle,
               "an invalid loaded assignment must remain visible for correction")
        expect(assignedQuickLaunchTarget(for: .middleButton, in: normalizedInvalid) == nil,
               "an invalid loaded assignment must fail closed without choosing a launcher")
        expect(mapping(for: .middleButton, in: normalizedInvalid) == originalMiddle,
               "an invalid assignment must restore the underlying runtime mapping")
        expect(normalizedInvalid.middleButton == originalMiddle,
               "fail-closed normalization must preserve the underlying mapping")

        let launchDispatch = mouseButtonShortcutDispatch(
            slot: .middleButton,
            shortcut: activeMiddle,
            frontmostBundleIdentifier: "com.apple.TextEdit",
            quickLaunchTarget: .chatGPT
        )
        expect(launchDispatch == .launch(.chatGPT),
               "an assigned available mouse button must dispatch directly to its launcher")
        let managedID = UUID()
        var instanceNativeConfig = KlikProConfig.default
        let managedInstance = AppProfileInstance(
            id: managedID,
            label: "Managed work",
            launcherKind: .managed,
            launcherPath: "/tmp/Launchers/\(managedID.uuidString).app",
            profileDirectory: "/tmp/Profiles/\(managedID.uuidString)",
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: "com.example.fixture",
                bundleURL: "/Applications/Fixture.app"
            ),
            pinToMenuBar: true,
            hotkey: ShortcutMapping(
                enabled: true,
                combo: KeyCombo(
                    keyCode: UInt16(kVK_ANSI_M), keyDisplay: "M",
                    command: true, option: true, control: true, shift: false
                )
            ),
            mouseButton: .gesture
        )
        instanceNativeConfig.instances.append(managedInstance)
        expect(appProfileAssignmentsAreValid(instanceNativeConfig),
               "a unique managed hotkey and mouse assignment must be valid")
        expect(activeAppProfileInstance(
            for: .gestureButton,
            in: instanceNativeConfig,
            activeInstanceIDs: [managedID],
            specialFeatureActive: true
        )?.id == managedID,
        "M2 mouse routing must resolve exactly one active UUID-keyed instance")
        expect(activeAppProfileInstance(
            for: .gestureButton,
            in: instanceNativeConfig,
            activeInstanceIDs: [managedID],
            specialFeatureActive: false
        )?.id == managedID,
        "Dual App mouse routing must not depend on the retired Special Feature toggle")
        let instanceDispatch = mouseButtonShortcutDispatch(
            slot: .gestureButton,
            shortcut: managedInstance.hotkey,
            frontmostBundleIdentifier: "com.apple.TextEdit",
            appProfileInstanceID: managedID
        )
        expect(instanceDispatch == .launchInstance(managedID),
               "M2 mouse dispatch must carry the instance UUID instead of a label")
        // Regression: a button assigned to a managed App Profile instance is in
        // Open-App mode, so its dormant stored shortcut must NOT raise a false
        // Duplicate against an identical real shortcut on another button.
        var dormantAppProfileConflict = instanceNativeConfig
        dormantAppProfileConflict.middleButton.combo =
            dormantAppProfileConflict.gestureButton.combo
        let dormantAppProfileStatuses = evaluateShortcutConflicts(
            candidate: dormantAppProfileConflict,
            persisted: dormantAppProfileConflict,
            browserExtensionShortcuts: [],
            specialFeatureActive: false
        )
        expect(dormantAppProfileStatuses[.middleButton] == .ok
               && dormantAppProfileStatuses[.gestureButton] == .ok,
               "an Open-App (managed-instance) button's dormant shortcut must not be a Duplicate")
        var duplicateHotkeyConfig = instanceNativeConfig
        duplicateHotkeyConfig.instances[duplicateHotkeyConfig.instances.count - 1].hotkey
            = duplicateHotkeyConfig.chatGPTHotkey
        expect(!appProfileAssignmentsAreValid(duplicateHotkeyConfig),
               "duplicate enabled instance hotkeys must fail closed")
        var launchPairState = MouseButtonDispatchState()
        _ = launchPairState.begin(buttonNumber: 2, dispatch: launchDispatch)
        expect(launchPairState.end(
            buttonNumber: 2,
            orphanFallback: .nativePassThrough
        ) == .launch(.chatGPT),
        "launcher mouse-down must keep its paired mouse-up consumed after state changes")
        _ = launchPairState.begin(buttonNumber: 2, dispatch: .nativePassThrough)
        expect(launchPairState.end(
            buttonNumber: 2,
            orphanFallback: .launch(.chatGPT)
        ) == .nativePassThrough,
        "a passed-through disabled down must keep its up native if the feature activates")

        var gestureOverlayConfig = KlikProConfig.default
        gestureOverlayConfig.gestureButton.enabled = false
        gestureOverlayConfig.claudeMouseButton = .gesture
        expect(mapping(
            for: .gestureButton,
            in: gestureOverlayConfig,
            specialFeatureActive: true,
            chatGPTAvailable: true,
            claudeAvailable: true
        ).enabled,
        "an active Gesture launcher assignment must activate the F20 receiver over a disabled base")
        expect(!mapping(
            for: .gestureButton,
            in: gestureOverlayConfig,
            specialFeatureActive: false,
            chatGPTAvailable: true,
            claudeAvailable: true
        ).enabled,
        "turning Special Feature OFF must restore a disabled underlying Gesture mapping")

        let defaultBack = KlikProConfig.default.backButton
        let defaultForward = KlikProConfig.default.forwardButton
        expect(browserHistoryDisplayOverride(
            slot: .backButton,
            combo: defaultBack.combo
        ) == "Browser ←",
        "default Back must be labelled as semantic browser history")
        expect(browserHistoryDisplayOverride(
            slot: .forwardButton,
            combo: defaultForward.combo
        ) == "Browser →",
        "default Forward must be labelled as semantic browser history")
        expect(mouseButtonShortcutDispatch(
            slot: .backButton,
            shortcut: defaultBack,
            frontmostBundleIdentifier: "com.google.Chrome"
        ) == .nativePassThrough,
        "Chrome must receive the original default Back mouse event")
        expect(mouseButtonShortcutDispatch(
            slot: .forwardButton,
            shortcut: defaultForward,
            frontmostBundleIdentifier: "org.mozilla.firefox"
        ) == .nativePassThrough,
        "Firefox must receive the original default Forward mouse event")
        expect(mouseButtonShortcutDispatch(
            slot: .backButton,
            shortcut: defaultBack,
            frontmostBundleIdentifier: "org.mozilla.firefoxdeveloperedition"
        ) == .nativePassThrough,
        "Firefox Developer Edition must receive the original default Back mouse event")
        expect(mouseButtonShortcutDispatch(
            slot: .backButton,
            shortcut: defaultBack,
            frontmostBundleIdentifier: "com.apple.Safari"
        ) == .synthesize(defaultBrowserBackCombo),
        "Safari must receive its documented Command-[ fallback")
        expect(mouseButtonShortcutDispatch(
            slot: .forwardButton,
            shortcut: defaultForward,
            frontmostBundleIdentifier: "com.apple.Safari"
        ) == .synthesize(defaultBrowserForwardCombo),
        "Safari must receive its documented Command-] fallback")
        expect(mouseButtonShortcutDispatch(
            slot: .backButton,
            shortcut: defaultBack,
            frontmostBundleIdentifier: "com.apple.TextEdit"
        ) == .synthesize(defaultBrowserBackCombo),
        "non-browser apps must retain the configured fallback")

        var customForward = defaultForward
        customForward.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_E), keyDisplay: "E",
            command: true, option: false, control: false, shift: false
        )
        expect(browserHistoryDisplayOverride(
            slot: .forwardButton,
            combo: customForward.combo
        ) == nil,
        "a non-default custom shortcut must show its recorded keystroke")
        expect(mouseButtonShortcutDispatch(
            slot: .forwardButton,
            shortcut: customForward,
            frontmostBundleIdentifier: "com.google.Chrome"
        ) == .synthesize(customForward.combo),
        "a custom Forward assignment must be synthesized even in Chrome")
        expect(mouseButtonShortcutDispatch(
            slot: .middleButton,
            shortcut: KlikProConfig.default.middleButton,
            frontmostBundleIdentifier: "com.google.Chrome"
        ) == .synthesize(KlikProConfig.default.middleButton.combo),
        "native history dispatch must never affect other mouse controls")

        var dispatchState = MouseButtonDispatchState()
        _ = dispatchState.begin(buttonNumber: 3, dispatch: .nativePassThrough)
        expect(dispatchState.end(
            buttonNumber: 3,
            orphanFallback: .synthesize(defaultBrowserBackCombo)
        ) == .nativePassThrough,
        "a Chrome-native mouse-down must keep its native mouse-up after focus changes")
        expect(dispatchState.end(
            buttonNumber: 3,
            orphanFallback: .synthesize(defaultBrowserBackCombo)
        ) == .synthesize(defaultBrowserBackCombo),
        "an orphan mouse-up must use the current safe fallback")
        _ = dispatchState.begin(
            buttonNumber: 4,
            dispatch: .synthesize(defaultBrowserForwardCombo)
        )
        expect(dispatchState.end(
            buttonNumber: 4,
            orphanFallback: .nativePassThrough
        ) == .synthesize(defaultBrowserForwardCombo),
        "a Safari synthetic mouse-down must not produce an orphan native mouse-up")
        let commandE = KeyCombo.Signature(
            keyCode: UInt16(kVK_ANSI_E),
            command: true, option: false, control: false, shift: false
        )
        expect(parseChromeExtensionAccelerator("mac:Command+E") == commandE,
               "Chrome's macOS Command-E accelerator must be parsed")
        let commandShiftLeft = KeyCombo.Signature(
            keyCode: UInt16(kVK_LeftArrow),
            command: true, option: false, control: false, shift: true
        )
        expect(parseChromeExtensionAccelerator("mac:Command+Shift+Left") == commandShiftLeft,
               "Chrome arrow accelerators and modifiers must be parsed")
        let commandForwardDelete = KeyCombo.Signature(
            keyCode: UInt16(kVK_ForwardDelete),
            command: true, option: false, control: false, shift: false
        )
        expect(parseChromeExtensionAccelerator("mac:Command+Delete") == commandForwardDelete,
               "Chrome's Delete token must map to Forward Delete")
        let commandInsert = KeyCombo.Signature(
            keyCode: UInt16(kVK_Help),
            command: true, option: false, control: false, shift: false
        )
        expect(parseChromeExtensionAccelerator("mac:Command+Insert") == commandInsert,
               "Chrome's Insert token must map to the macOS Help/Insert key")
        expect(parseChromeExtensionAccelerator("win:Ctrl+E") == nil,
               "non-macOS Chrome accelerators must be ignored")
        let chromePreferences = Data("""
        {"extensions":{"commands":{
          "mac:Command+E":{"command_name":"toggle-side-panel"},
          "win:Ctrl+E":{"command_name":"toggle-side-panel"}
        }}}
        """.utf8)
        expect(chromeExtensionShortcutSignatures(fromPreferencesData: chromePreferences) == [commandE],
               "only effective macOS Chrome extension shortcuts must be discovered")
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("klik-pro-chrome-shortcuts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let temporaryProfile = temporaryHome
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        do {
            try FileManager.default.createDirectory(
                at: temporaryProfile,
                withIntermediateDirectories: true
            )
            try chromePreferences.write(to: temporaryProfile.appendingPathComponent("Preferences"))
        } catch {
            fputs("FAIL: unable to create Chrome shortcut fixture: \(error)\n", stderr)
            exit(1)
        }
        expect(installedChromeExtensionShortcutSignatures(
            homeDirectory: temporaryHome.path
        ) == [commandE],
        "Chrome profile traversal must discover configured extension commands read-only")

        var chromeConflictCandidate = KlikProConfig.default
        chromeConflictCandidate.forwardButton.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_E), keyDisplay: "E",
            command: true, option: false, control: false, shift: false
        )
        let chromeConflictStatuses = evaluateShortcutConflicts(
            candidate: chromeConflictCandidate,
            persisted: chromeConflictCandidate,
            browserExtensionShortcuts: [commandE],
            specialFeatureActive: false
        )
        expect(chromeConflictStatuses[.forwardButton] == .mayConflict,
               "an installed Chrome extension shortcut must warn even when already persisted")

        var linkedConflictCandidate = KlikProConfig.default
        linkedConflictCandidate.chatGPTMouseButton = .middle
        linkedConflictCandidate.claudeMouseButton = nil
        var linkedStatuses = evaluateShortcutConflicts(
            candidate: linkedConflictCandidate,
            persisted: linkedConflictCandidate,
            browserExtensionShortcuts: []
        )
        expect(linkedStatuses[.chatGPTHotkey] == .ok
               && linkedStatuses[.middleButton] == .ok,
               "one launcher and its intentional mouse mirror must not be Duplicate")

        var dormantLinkedCandidate = linkedConflictCandidate
        dormantLinkedCandidate.middleButton.combo = dormantLinkedCandidate.backButton.combo
        let dormantStatuses = evaluateShortcutConflicts(
            candidate: dormantLinkedCandidate,
            persisted: dormantLinkedCandidate,
            browserExtensionShortcuts: [],
            specialFeatureActive: false,
            chatGPTAvailable: true,
            claudeAvailable: true
        )
        expect(dormantStatuses[.middleButton] == .duplicate
               && dormantStatuses[.backButton] == .duplicate,
               "Special Feature OFF must evaluate conflicts for the restored base mapping")
        let missingLauncherStatuses = evaluateShortcutConflicts(
            candidate: dormantLinkedCandidate,
            persisted: dormantLinkedCandidate,
            browserExtensionShortcuts: [],
            specialFeatureActive: true,
            chatGPTAvailable: false,
            claudeAvailable: true
        )
        expect(missingLauncherStatuses[.middleButton] == .duplicate,
               "a missing launcher must expose the restored base mapping's conflicts")

        let chatGPTSignature = linkedConflictCandidate.chatGPTHotkey.combo.signature
        linkedStatuses = evaluateShortcutConflicts(
            candidate: linkedConflictCandidate,
            persisted: linkedConflictCandidate,
            browserExtensionShortcuts: [chatGPTSignature]
        )
        expect(linkedStatuses[.chatGPTHotkey] == .mayConflict
               && linkedStatuses[.middleButton] == .mayConflict,
               "a linked mouse row must inherit its launcher's extension warning")

        linkedConflictCandidate.backButton.combo = linkedConflictCandidate.chatGPTHotkey.combo
        linkedStatuses = evaluateShortcutConflicts(
            candidate: linkedConflictCandidate,
            persisted: linkedConflictCandidate,
            browserExtensionShortcuts: []
        )
        expect(linkedStatuses[.chatGPTHotkey] == .duplicate
               && linkedStatuses[.middleButton] == .duplicate
               && linkedStatuses[.backButton] == .duplicate,
               "a third matching shortcut must make the launcher, mirror, and third row Duplicate")

        var config = KlikProConfig.default
        config.backButton.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_C), keyDisplay: "C",
            command: true, option: true, control: false, shift: true
        )
        config.forwardButton.combo = KeyCombo(
            keyCode: UInt16(kVK_ANSI_E), keyDisplay: "E",
            command: true, option: false, control: false, shift: false
        )

        let backSlot = shortcutSlot(forMouseButtonNumber: 3)!
        let forwardSlot = shortcutSlot(forMouseButtonNumber: 4)!
        expect(mapping(for: backSlot, in: config, specialFeatureActive: false) == config.backButton,
               "CG button 3 must resolve the saved Back assignment")
        expect(mapping(for: forwardSlot, in: config, specialFeatureActive: false) == config.forwardButton,
               "CG button 4 must resolve the saved Forward assignment")
        expect(mapping(for: .gestureButton, in: config) == config.gestureButton,
               "Gesture slot must resolve the saved Gesture assignment")

        expect(shouldMapThumbWheel(axis2: 1, isContinuous: false),
               "discrete horizontal thumb-wheel ticks must be eligible for mapping")
        expect(shouldMapThumbWheel(axis2: -1, isContinuous: false),
               "discrete ticks in either direction must be eligible for mapping")
        expect(!shouldMapThumbWheel(axis2: 1, isContinuous: true),
               "continuous horizontal trackpad input must pass through")
        expect(!shouldMapThumbWheel(axis2: 0, isContinuous: false),
               "non-horizontal scroll events must pass through")

        let nullMapping = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (null)
        """
        expect(parseGestureSentinelMappingState(output: nullMapping, commandSucceeded: true) == .absent,
               "a null device key map must be safe to claim")

        let emptyMapping = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (
        )
        """
        expect(parseGestureSentinelMappingState(output: emptyMapping, commandSucceeded: true) == .absent,
               "an empty device key map must be safe to claim")

        let installedMapping = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771183;
                HIDKeyboardModifierMappingSrc = 30064771115;
            }
        )
        """
        expect(parseGestureSentinelMappingState(output: installedMapping, commandSucceeded: true) == .installed,
               "the exact Tab-to-F20 device map must be recognized as Klik PRO's sentinel")

        let conflictingMapping = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771115;
            }
        )
        """
        expect(parseGestureSentinelMappingState(output: conflictingMapping, commandSucceeded: true) == .conflicting,
               "an unknown device key map must never be overwritten")
        expect(parseGestureSentinelMappingState(output: "", commandSucceeded: true) == .deviceAbsent,
               "an empty successful query means the matched device service is absent")
        expect(parseGestureSentinelMappingState(output: "", commandSucceeded: false) == .unavailable,
               "a failed hidutil query must fail safely")

        let malformedMapping = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (unexpected-value)
        """
        expect(parseGestureSentinelMappingState(output: malformedMapping, commandSucceeded: true) == .conflicting,
               "a malformed non-empty device map must never be treated as empty")

        let multipleDevices = emptyMapping + "\n" + emptyMapping
        expect(parseGestureSentinelMappingState(output: multipleDevices, commandSucceeded: true) == .conflicting,
               "multiple matched device services must not be changed together")

        let overlappingDeviceReplacement = installedMapping + "\n" + emptyMapping
        expect(parseGestureSentinelMappingState(
            output: overlappingDeviceReplacement,
            commandSucceeded: true
        ) == .ownedConflict,
        "an exact sentinel visible during service overlap must retain ownership")

        let exactSentinelPlusCustomEntry = """
        RegistryID  Key                   Value
        1000037b4   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771183;
                HIDKeyboardModifierMappingSrc = 30064771115;
            },
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771114;
            }
        )
        """
        expect(parseGestureSentinelMappingState(
            output: exactSentinelPlusCustomEntry,
            commandSucceeded: true
        ) == .ownedConflict,
        "an exact sentinel plus another map must never be abandoned as a generic conflict")

        var sentinelCandidate = KlikProConfig.default
        sentinelCandidate.gestureButton.combo = KeyCombo(
            keyCode: UInt16(kVK_F20), keyDisplay: "F20",
            command: true, option: false, control: false, shift: false
        )
        let sentinelStatuses = evaluateShortcutConflicts(
            candidate: sentinelCandidate,
            persisted: KlikProConfig.default,
            browserExtensionShortcuts: []
        )
        expect(sentinelStatuses[.gestureButton] == .unavailable,
               "Command-F20 must be rejected as a recursive Gesture output")

        var hiddenBaseSentinel = KlikProConfig.default
        hiddenBaseSentinel.gestureButton.combo = sentinelCandidate.gestureButton.combo
        hiddenBaseSentinel.chatGPTMouseButton = .gesture
        expect(mapping(for: .gestureButton, in: hiddenBaseSentinel).combo.signature
               == hiddenBaseSentinel.chatGPTHotkey.combo.signature,
               "the active overlay fixture must hide its base Gesture combo")
        expect(configuredSlotUsingGestureSentinel(in: hiddenBaseSentinel) == .gestureButton,
               "the reserved scan must still catch F20 hidden under a launcher overlay")

        var linkedSentinelCandidate = KlikProConfig.default
        linkedSentinelCandidate.chatGPTHotkey.combo = sentinelCandidate.gestureButton.combo
        linkedSentinelCandidate.chatGPTMouseButton = .forward
        let linkedSentinelStatuses = evaluateShortcutConflicts(
            candidate: linkedSentinelCandidate,
            persisted: KlikProConfig.default,
            browserExtensionShortcuts: []
        )
        expect(linkedSentinelStatuses[.chatGPTHotkey] == .unavailable
               && linkedSentinelStatuses[.forwardButton] == .unavailable,
               "a linked row must inherit the launcher's reserved F20 status")

        let commandTab = KeyCombo(
            keyCode: UInt16(kVK_Tab), keyDisplay: "⇥",
            command: true, option: false, control: false, shift: false
        )
        expect(isReservedKeyboardCommandTab(commandTab),
               "exact keyboard Command-Tab must be recognized as reserved for app switching")

        var commandTabCandidate = KlikProConfig.default
        commandTabCandidate.chatGPTHotkey.combo = commandTab
        expect(configuredGlobalHotKeyUsingReservedCommandTab(in: commandTabCandidate) == .chatGPTHotkey,
               "a global ChatGPT Command-Tab hotkey must be rejected")
        let commandTabStatuses = evaluateShortcutConflicts(
            candidate: commandTabCandidate,
            persisted: KlikProConfig.default,
            browserExtensionShortcuts: []
        )
        expect(commandTabStatuses[.chatGPTHotkey] == .unavailable,
               "Command-Tab must be unavailable for global menu hotkeys")

        commandTabCandidate.chatGPTMouseButton = .middle
        let linkedCommandTabStatuses = evaluateShortcutConflicts(
            candidate: commandTabCandidate,
            persisted: KlikProConfig.default,
            browserExtensionShortcuts: []
        )
        expect(linkedCommandTabStatuses[.middleButton] == .unavailable,
               "a linked mouse row must inherit Command-Tab protection from its launcher")

        commandTabCandidate = KlikProConfig.default
        commandTabCandidate.middleButton.combo = commandTab
        expect(configuredGlobalHotKeyUsingReservedCommandTab(in: commandTabCandidate) == nil,
               "a mouse-button output may deliberately invoke normal app switching")

        print("Mouse button routing tests passed")
    }
}
