import CoreGraphics
import Foundation
import ImageIO

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

/// Writes a solid-colour PNG of the given pixel dimensions, for exercising the
/// custom-icon (PNG → .icns) path.
private func writeTestPNG(width: Int, height: Int, to url: URL) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    _ = CGImageDestinationFinalize(destination)
}

/// The largest-frame pixel width of an encoded icns (0 if it cannot be read).
private func icnsFrameCountAndMaxWidth(_ data: Data) -> (count: Int, maxWidth: Int) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (0, 0) }
    let count = CGImageSourceGetCount(source)
    var maxWidth = 0
    for index in 0..<count {
        if let image = CGImageSourceCreateImageAtIndex(source, index, nil) {
            maxWidth = max(maxWidth, image.width)
        }
    }
    return (count, maxWidth)
}

private func temporaryDirectory(_ label: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("klik-pro-\(label)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Test double for the injectable Move-to-Trash op: moves items into a temp
/// directory (never the real Trash) and records every request, so a test can
/// prove Trash mode used this op and never a permanent `removeItem`.
private final class TrashSpy {
    let destination: URL
    private(set) var moved: [URL] = []
    init(destination: URL) { self.destination = destination }
    func trash(_ url: URL) throws -> URL? {
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true
        )
        let target = destination.appendingPathComponent(
            url.lastPathComponent + "-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.moveItem(at: url, to: target)
        moved.append(url.standardizedFileURL)
        return target
    }
}

private func makeInstalledApp(
    root: URL,
    bundleIdentifier: String = "com.example.electron",
    teamIdentifier: String? = "TEAM123456",
    version: String = "1.0"
) -> InstalledApp {
    let bundleURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
    try! FileManager.default.createDirectory(
        at: bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true),
        withIntermediateDirectories: true
    )
    return InstalledApp(
        bundleIdentifier: bundleIdentifier,
        bundleURL: bundleURL,
        displayName: "Fixture",
        version: version,
        teamIdentifier: teamIdentifier
    )
}

/// A solid-colour opaque bitmap used as an in-memory "source app icon" for the
/// tint/badge composition tests (no file round-trip needed).
private func makeTestBitmap(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A managed generator wired at `support` with signing stubbed to true. Matches
/// the production wiring except for the signer, which the icon paths under test
/// do not exercise (isSafeGeneratedLauncher does not verify a real signature).
private struct ManagedFixture {
    let root: URL
    let generator: LauncherGenerator
    let source: InstalledApp
}

private func makeManagedFixture(_ label: String) -> ManagedFixture {
    let root = temporaryDirectory(label)
    let support = root.appendingPathComponent("Support", isDirectory: true)
    let runner = root.appendingPathComponent("KlikProManagedLauncher")
    try! Data("fixture-runner".utf8).write(to: runner)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)
    let source = makeInstalledApp(root: root)
    let generator = LauncherGenerator(
        applicationSupportURL: support,
        launcherExecutableURL: runner,
        signLauncher: { _ in true }
    )
    return ManagedFixture(root: root, generator: generator, source: source)
}

private func makeManagedInstance(
    id: UUID, generator: LauncherGenerator, source: InstalledApp
) -> AppProfileInstance {
    AppProfileInstance(
        id: id,
        label: "Work",
        launcherKind: .managed,
        launcherPath: generator.launcherURL(for: id).path,
        profileDirectory: generator.profileURL(for: id).path,
        profileOwnership: .managed,
        source: AppProfileSource(
            bundleIdentifier: source.bundleIdentifier,
            bundleURL: source.bundleURL.path
        ),
        pinToMenuBar: false,
        hotkey: ShortcutMapping(
            enabled: false,
            combo: KeyCombo(keyCode: 0, keyDisplay: "A",
                            command: false, option: false, control: true, shift: false)
        ),
        mouseButton: nil,
        compatibilityRuleID: "fixture-rule"
    )
}

@main
private struct AppProfilesFoundationTests {
    static func main() {
        testSchema10DefaultsAndSynchronization()
        testExternalDualAppDiscoveryIsNarrowAndReadOnly()
        testSchema9MigrationAndBackup()
        testAppScannerIdentityAndManagedLauncherExclusion()
        testManagedLauncherPayloadValidatesStorageLayouts()
        testEngineDetectionAndRegistryGate()
        testLauncherSpecificationIsUUIDKeyedAndStructured()
        testManagedLifecycleIsRegistryGatedAndRetainsProfiles()
        testProcessInspectionAndFailClosedProfileDeletion()
        testExplicitLegacyConversionLeavesExternalDataUntouched()
        testRuleRequiredEnvironmentDerivation()
        testProductionRegistryPinsExplicitRules()
        testCodexHomeSiblingPlaceholderAndPrecreation()
        testHomeSymlinkNamingAndLifecycle()
        testHealingUpgradesExistingInstancesInPlace()
        testRealAdHocLauncherMaterialization()
        testManagedInstanceReleasesPhantomDuplicateBadge()
        testMakeICNSDataSizeValidation()
        testCustomIconSurvivesRematerialization()
        testCustomIconTintAndBadgeGeometry()
        testResetRemovesPersistedCustomIcon()
        testUpdateManagedIconRejectsExternalRow()
        testUpdateManagedIconMapsInvalidImage()
        testVaultPathDerivationAndDefaultGolden()
        testVaultLocationValidationFailsClosed()
        testSchema11VaultMigrationRoundTrip()
        testCreateInVaultWritesManifestAndLeavesExistingUntouched()
        testVaultHealParityAndPortability()
        testVaultAdoptionRegeneratesFromManifest()
        testVaultInstanceRemovalAndManifestWriteFailSafe()
        testArchiveRestoreAndRepairPreserveVaultData()
        testForgetEntryDropsStaleRecordWithoutDeletingData()
        testOrphanScanClassifiesRecordlessData()
        testReclaimDataTrashPermanentAndFailClosed()
        testReclaimDataMultiArtifactPartialAndMarkerless()
        testLauncherLeftoverScanAndTrashAreOwnershipGated()
        testDataRootWiringFactorySelectsGenerator()
        testSettledProcessScanResolvesTransientAmbiguity()
        print("App Profiles foundation tests passed")
    }

    private static func testExternalDualAppDiscoveryIsNarrowAndReadOnly() {
        let home = temporaryDirectory("external-dual-app-discovery")
        defer { try? FileManager.default.removeItem(at: home) }
        let contents = home.appendingPathComponent(
            "Applications/ChatGPT P.app/Contents", isDirectory: true
        )
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "local.chatgpt.profile1",
            "CFBundlePackageType": "APPL",
        ]
        let data = try! PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0
        )
        try! data.write(to: contents.appendingPathComponent("Info.plist"))

        let discovered = discoveredExternalDualAppInstances(homeDirectory: home.path)
        expect(discovered.count == 1, "discovery must include only present known launchers")
        expect(discovered[0].label == "ChatGPT P", "the existing launcher label must be stable")
        expect(discovered[0].launcherKind == .legacyExternal,
               "discovered launchers must remain externally owned")
        expect(discovered[0].profileDirectory == nil,
               "discovery must never claim or infer external profile data")
        expect(FileManager.default.fileExists(atPath: contents.path),
               "discovery must not move, rename, or remove the launcher")
    }

    private static func testSchema10DefaultsAndSynchronization() {
        let defaults = KlikProConfig.default
        expect(defaults.schemaVersion == 12, "new configs must use schema 12")
        expect(defaults.dataRoot == nil, "new configs must default to no vault (Application Support)")
        expect(defaults.instances.count == 2, "schema 12 must contain both legacy targets")

        for target in QuickLaunchTarget.allCases {
            guard let instance = defaults.instances.first(where: {
                $0.legacyQuickLaunchTarget == target
            }) else {
                fputs("FAIL: missing legacy row for \(target.title)\n", stderr)
                exit(1)
            }
            expect(instance.id == target.legacyInstanceID, "legacy IDs must be stable")
            expect(instance.launcherKind == .legacyExternal, "legacy wrapper must stay external")
            expect(instance.profileDirectory == nil, "legacy wrapper profile must stay unknown")
            expect(instance.profileOwnership == .external, "legacy data must never be owned")
            expect(instance.launcherPath == target.launcherWrapperPath,
                   "legacy wrapper path must remain byte-for-byte compatible")
            expect(instance.hotkey == baseMapping(for: target.shortcutSlot, in: defaults),
                   "legacy instance hotkey must mirror the v1 field")
            expect(instance.mouseButton == quickLaunchMouseButton(for: target, in: defaults),
                   "legacy instance button must mirror the v1 field")
            expect(instance.menuColor == nil, "legacy instances default to no menu marker")
        }

        var edited = defaults
        let existingChatGPT = edited.instances.first {
            $0.legacyQuickLaunchTarget == .chatGPT
        }!
        let coloredChatGPT = AppProfileInstance(
            id: existingChatGPT.id,
            label: existingChatGPT.label,
            launcherKind: existingChatGPT.launcherKind,
            launcherPath: existingChatGPT.launcherPath,
            profileDirectory: existingChatGPT.profileDirectory,
            profileOwnership: existingChatGPT.profileOwnership,
            source: existingChatGPT.source,
            environmentOverrides: existingChatGPT.environmentOverrides,
            iconPath: existingChatGPT.iconPath,
            menuColor: .green,
            pinToMenuBar: existingChatGPT.pinToMenuBar,
            hotkey: existingChatGPT.hotkey,
            mouseButton: existingChatGPT.mouseButton,
            lastDetectedEngine: existingChatGPT.lastDetectedEngine,
            lastVerifiedAppVersion: existingChatGPT.lastVerifiedAppVersion,
            lastVerifiedTeamIdentifier: existingChatGPT.lastVerifiedTeamIdentifier,
            compatibilityRuleID: existingChatGPT.compatibilityRuleID
        )
        edited.instances.removeAll { $0.id == existingChatGPT.id }
        edited.instances.append(coloredChatGPT)
        edited.chatGPTHotkey.enabled = false
        edited.chatGPTMouseButton = .middle
        edited.showQuickLaunchMenuIcons = false
        let synchronized = normalizedQuickLaunchConfig(edited)
        let chatGPT = synchronized.instances.first { $0.legacyQuickLaunchTarget == .chatGPT }
        expect(chatGPT?.hotkey.enabled == false, "legacy hotkey edits must stay authoritative in M0")
        expect(chatGPT?.mouseButton == .middle, "legacy button edits must sync into instances")
        expect(chatGPT?.pinToMenuBar == existingChatGPT.pinToMenuBar,
               "legacy pin must preserve the per-instance menu-bar setting once a row exists")
        expect(chatGPT?.menuColor == .green, "legacy synchronization must preserve display markers")

        let managedID = UUID()
        let managed = AppProfileInstance(
            id: managedID,
            label: "Managed fixture",
            launcherKind: .managed,
            launcherPath: "/tmp/Launchers/\(managedID.uuidString).app",
            profileDirectory: "/tmp/Profiles/\(managedID.uuidString)",
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: "com.example.managed",
                bundleURL: "/Applications/Managed.app"
            ),
            pinToMenuBar: false,
            hotkey: defaults.chatGPTHotkey,
            mouseButton: nil
        )
        edited.instances.append(managed)
        expect(normalizedQuickLaunchConfig(edited).instances.contains(managed),
               "legacy synchronization must preserve managed/future instances")
    }

    private static func testSchema9MigrationAndBackup() {
        let root = temporaryDirectory("schema10-migration")
        defer { try? FileManager.default.removeItem(at: root) }

        var schema9 = KlikProConfig.default
        schema9.schemaVersion = 9
        schema9.instances = []
        schema9.onboardingCompleted = true
        schema9.chatGPTHotkey.enabled = false

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var object = try! JSONSerialization.jsonObject(with: encoder.encode(schema9))
            as! [String: Any]
        object.removeValue(forKey: "instances")
        let originalData = try! JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let configURL = root.appendingPathComponent("config.json")
        try! originalData.write(to: configURL)

        setenv("KLIK_PRO_CONFIG_DIRECTORY", root.path, 1)
        defer { unsetenv("KLIK_PRO_CONFIG_DIRECTORY") }

        let migrated = KlikProConfigStore.load()
        expect(migrated.schemaVersion == 12, "schema 9 must migrate through to schema 12")
        expect(migrated.instances.count == 2, "migration must add two legacy rows")
        expect(!migrated.chatGPTHotkey.enabled, "migration must preserve customized hotkeys")

        let backupURL = root.appendingPathComponent("config.json.pre-v2")
        let backupData = try! Data(contentsOf: backupURL)
        expect(backupData == originalData, "pre-v2 backup must preserve original bytes verbatim")
        let permissions = (try! FileManager.default.attributesOfItem(atPath: backupURL.path))[
            .posixPermissions
        ] as! NSNumber
        expect(permissions.intValue & 0o777 == 0o600, "pre-v2 backup must be mode 0600")

        let saved = try! JSONDecoder().decode(
            KlikProConfig.self,
            from: Data(contentsOf: configURL)
        )
        expect(saved.schemaVersion == 12 && saved.instances.count == 2,
               "the atomically replaced config must be schema 12")

        var later = migrated
        later.middleButton.enabled.toggle()
        expect(KlikProConfigStore.save(later), "schema-10 save must succeed")
        _ = KlikProConfigStore.load()
        expect(try! Data(contentsOf: backupURL) == originalData,
               "repeated loads and saves must never overwrite the pre-v2 backup")
    }

    private static func testAppScannerIdentityAndManagedLauncherExclusion() {
        let root = temporaryDirectory("app-scanner")
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = AppScanner()

        func makeBundle(name: String, bundleIdentifier: String) -> URL {
            let bundleURL = root.appendingPathComponent(name + ".app", isDirectory: true)
            let macOSURL = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
            try! FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
            let executableURL = macOSURL.appendingPathComponent("Fixture")
            try! Data([0]).write(to: executableURL)
            try! FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
            let info: [String: Any] = [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": name,
                "CFBundleDisplayName": name,
                "CFBundlePackageType": "APPL",
                "CFBundleExecutable": "Fixture",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1"
            ]
            let infoData = try! PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try! infoData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
            return bundleURL
        }

        let firstURL = makeBundle(name: "First", bundleIdentifier: "com.example.shared")
        let secondURL = makeBundle(name: "Second", bundleIdentifier: "com.example.shared")
        let managedURL = makeBundle(
            name: "KlikManaged",
            bundleIdentifier: "local.klik-pro.launcher.ifake"
        )

        let first = scanner.inspect(firstURL)
        let second = scanner.inspect(secondURL)
        expect(first != nil && second != nil, "scanner must inspect runnable application bundles")
        expect(first?.bundleIdentifier == second?.bundleIdentifier,
               "fixture must exercise two installs sharing one bundle identifier")
        expect(first?.id != second?.id,
               "two installations sharing a bundle identifier must get distinct scan IDs")
        expect(scanner.inspect(managedURL) == nil,
               "scanner must never offer a Klik PRO-generated launcher as a source app")

        let scanned = scanner.scan(searchRoots: [root])
        expect(Set(scanned.map(\.bundleURL)) == Set([firstURL, secondURL]),
               "root scan must return source apps once and exclude managed launchers")
    }

    private static func testManagedLauncherPayloadValidatesStorageLayouts() {
        let root = temporaryDirectory("managed-launcher-storage")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let id = UUID()
        let marker = ".klik-pro-owned-profile"

        func makeProfile(_ url: URL) {
            try! FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
            try! Data(id.uuidString.uppercased().utf8)
                .write(to: url.appendingPathComponent(marker))
        }

        let supportProfile = support
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
        makeProfile(supportProfile)
        let supportPayload = ManagedLauncherPayload(
            sourceBundlePath: "/Applications/Fixture.app",
            arguments: ["--user-data-dir=" + supportProfile.path],
            environment: [:],
            compatibilityRuleID: "fixture",
            profileDirectory: supportProfile.path,
            profileStorage: .applicationSupport
        )
        expect(supportPayload.validatedProfileURL(
            instanceID: id, applicationSupportURL: support
        ) == supportProfile.standardizedFileURL,
        "the signed runner payload must accept the exact owned Application Support profile")

        let vaultProfile = root
            .appendingPathComponent("Vault/Instances", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
            .appendingPathComponent("user-data", isDirectory: true)
        makeProfile(vaultProfile)
        let vaultPayload = ManagedLauncherPayload(
            sourceBundlePath: "/Applications/Fixture.app",
            arguments: ["--user-data-dir=" + vaultProfile.path],
            environment: [:],
            compatibilityRuleID: "fixture",
            profileDirectory: vaultProfile.path,
            profileStorage: .vault
        )
        expect(vaultPayload.validatedProfileURL(
            instanceID: id, applicationSupportURL: support
        ) == vaultProfile.standardizedFileURL,
        "the signed runner payload must accept the exact owned vault profile")

        let wrongArgument = ManagedLauncherPayload(
            sourceBundlePath: vaultPayload.sourceBundlePath,
            arguments: ["--user-data-dir=/tmp/wrong"],
            environment: [:],
            compatibilityRuleID: vaultPayload.compatibilityRuleID,
            profileDirectory: vaultProfile.path,
            profileStorage: .vault
        )
        expect(wrongArgument.validatedProfileURL(
            instanceID: id, applicationSupportURL: support
        ) == nil, "a payload whose argument disagrees with its signed profile must fail closed")

        let markerURL = vaultProfile.appendingPathComponent(marker)
        try! FileManager.default.removeItem(at: markerURL)
        expect(vaultPayload.validatedProfileURL(
            instanceID: id, applicationSupportURL: support
        ) == nil, "a vault profile without its exact ownership marker must fail closed")
    }

    private static func testEngineDetectionAndRegistryGate() {
        let electronRoot = temporaryDirectory("electron-engine")
        let geckoRoot = temporaryDirectory("gecko-engine")
        defer {
            try? FileManager.default.removeItem(at: electronRoot)
            try? FileManager.default.removeItem(at: geckoRoot)
        }

        let electron = makeInstalledApp(root: electronRoot)
        let electronFramework = electron.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(
            at: electronFramework,
            withIntermediateDirectories: true
        )
        let detector = EngineDetector()
        expect(detector.detect(electron) == .electron,
               "literal Electron framework marker must be detected")
        expect(detector.eligibility(for: electron).kind == .experimental,
               "engine detection alone must never grant Verified")

        let renamedRoot = temporaryDirectory("renamed-electron-engine")
        defer { try? FileManager.default.removeItem(at: renamedRoot) }
        let renamed = makeInstalledApp(
            root: renamedRoot,
            bundleIdentifier: "com.example.renamed-electron"
        )
        let renamedFramework = renamed.bundleURL
            .appendingPathComponent("Contents/Frameworks/Fixture Framework.framework")
        try! FileManager.default.createDirectory(
            at: renamedFramework,
            withIntermediateDirectories: true
        )
        let renamedInfo: [String: Any] = ["ElectronHint": true]
        let renamedInfoData = try! PropertyListSerialization.data(
            fromPropertyList: renamedInfo,
            format: .xml,
            options: 0
        )
        try! renamedInfoData.write(
            to: renamed.bundleURL.appendingPathComponent("Contents/Info.plist")
        )
        expect(detector.detect(renamed) == .electron,
               "a renamed framework plus an Electron hint must classify the engine")
        expect(detector.eligibility(for: renamed).kind == .experimental,
               "renamed-framework detection must remain creation-disabled without a rule")

        let rule = AppCompatibilityRule(
            id: "fixture-electron-1",
            bundleIdentifier: electron.bundleIdentifier,
            teamIdentifier: "TEAM123456",
            engine: .electron,
            testedVersions: ["1.0"]
        )
        let registry = AppCompatibilityRegistry(rules: [rule])
        let verified = detector.eligibility(for: electron, registry: registry)
        expect(verified == .verified(ruleID: rule.id),
               "exact bundle/team/engine/version rule must grant Verified")
        let catalogueManager = AppProfileManager(
            detector: detector,
            registry: registry,
            scanApplications: { _ in [renamed, electron] },
            inspectApplication: { _ in nil }
        )
        let supportedCatalogue = catalogueManager.supportedCandidates()
        expect(supportedCatalogue.map { $0.app.id } == [electron.id],
               "the user-facing catalogue must omit every scan result without an approved rule")

        var untestedRule = AppCompatibilityRule(
            id: "fixture-electron-untested",
            bundleIdentifier: electron.bundleIdentifier,
            teamIdentifier: "TEAM123456",
            engine: .electron,
            testedVersions: []
        )
        untestedRule.assurance = .untested
        untestedRule.acceptsAnyVersion = true
        let untestedEligibility = detector.eligibility(
            for: electron,
            registry: AppCompatibilityRegistry(rules: [untestedRule])
        )
        expect(untestedEligibility.kind == .experimental,
               "an owner-enabled Untested rule must never be labelled Verified")
        expect(untestedEligibility.compatibilityRuleID == untestedRule.id,
               "an owner-enabled Untested rule must expose its isolation recipe")
        expect(untestedEligibility.allowsManagedProfile(usingRuleID: untestedRule.id),
               "an owner-enabled Untested rule must pass exact launcher revalidation")
        expect(!untestedEligibility.allowsManagedProfile(usingRuleID: "wrong-rule"),
               "a generated launcher with a changed rule ID must fail closed")
        expect(
            AppProfileCandidate(
                app: electron,
                engine: .electron,
                eligibility: untestedEligibility
            ).canCreate,
            "an explicit Untested rule must enable creation"
        )
        expect(
            !AppProfileCandidate(
                app: renamed,
                engine: .electron,
                eligibility: detector.eligibility(for: renamed)
            ).canCreate,
            "generic engine detection must remain creation-disabled without an explicit rule"
        )
        expect(!detector.eligibility(for: renamed).allowsManagedProfile,
               "generic Experimental detection must never pass launcher revalidation")

        var wrongTeam = electron
        wrongTeam.teamIdentifier = "OTHERTEAM1"
        expect(detector.eligibility(for: wrongTeam, registry: registry).kind == .experimental,
               "a modified signing identity must not inherit Verified")

        let gecko = makeInstalledApp(
            root: geckoRoot,
            bundleIdentifier: "org.mozilla.fixture",
            teamIdentifier: nil
        )
        let xul = gecko.bundleURL.appendingPathComponent("Contents/MacOS/XUL")
        try! FileManager.default.createDirectory(
            at: xul.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try! Data().write(to: xul)
        expect(detector.detect(gecko) == .gecko,
               "Gecko markers under Contents/MacOS must be detected")
        expect(detector.eligibility(for: gecko).kind == .experimental,
               "Gecko creation must stay disabled for v2.0")

        var appStore = electron
        appStore.hasAppStoreReceipt = true
        appStore.sandboxEntitlement = false
        expect(detector.eligibility(for: appStore).kind == .unsupported,
               "App Store apps must stay unsupported regardless of sandbox state")

        var sandboxed = electron
        sandboxed.sandboxEntitlement = true
        expect(detector.eligibility(for: sandboxed).kind == .unsupported,
               "a provably sandboxed app must be unsupported even without a provisioning profile")

        var provisionedUnknown = electron
        provisionedUnknown.hasProvisioningProfile = true
        provisionedUnknown.sandboxEntitlement = nil
        expect(detector.eligibility(for: provisionedUnknown).kind == .unsupported,
               "a provisioned app with an unreadable sandbox entitlement must fail closed")

        var provisionedNotSandboxed = electron
        provisionedNotSandboxed.hasProvisioningProfile = true
        provisionedNotSandboxed.sandboxEntitlement = false
        expect(detector.eligibility(for: provisionedNotSandboxed).kind == .experimental,
               "a provisioned but provably non-sandboxed app must reach normal engine gating")
        expect(detector.eligibility(for: provisionedNotSandboxed, registry: registry)
                == .verified(ruleID: rule.id),
               "a provisioned but provably non-sandboxed app must be able to match a Verified rule")
    }

    private static func testLauncherSpecificationIsUUIDKeyedAndStructured() {
        let root = temporaryDirectory("launcher-generator")
        defer { try? FileManager.default.removeItem(at: root) }
        let generator = LauncherGenerator(applicationSupportURL: root)
        let id = UUID(uuidString: "C6724E1B-8DAB-4923-A731-44CD77841E25")!
        let launcherURL = generator.launcherURL(for: id)
        let profileURL = generator.profileURL(for: id)
        let source = AppProfileSource(
            bundleIdentifier: "com.example.fixture",
            bundleURL: "/Applications/Fixture App.app"
        )
        var instance = AppProfileInstance(
            id: id,
            label: "Work; $(unsafe label)",
            launcherKind: .managed,
            launcherPath: launcherURL.path,
            profileDirectory: profileURL.path,
            profileOwnership: .managed,
            source: source,
            environmentOverrides: ["CODEX_HOME": root.appendingPathComponent("Codex Home").path],
            menuColor: .purple,
            pinToMenuBar: false,
            hotkey: KlikProConfig.default.chatGPTHotkey,
            mouseButton: nil
        )

        let specification = try! generator.specification(for: instance)
        expect(specification.displayName == instance.label, "label must remain display-only")
        expect(!specification.launcherURL.path.contains(instance.label),
               "label must never determine the launcher path")
        expect(!specification.profileURL.path.contains(instance.label),
               "label must never determine the profile path")
        expect(!specification.bundleIdentifier.contains("unsafe"),
               "label must never determine the bundle identifier")
        expect(specification.arguments == ["--user-data-dir=" + profileURL.path],
               "profile path must be one structured argument")
        let encodedInstance = try! JSONEncoder().encode(instance)
        let encodedObject = try! JSONSerialization.jsonObject(with: encodedInstance)
            as! [String: Any]
        expect(encodedObject["profileDir"] as? String == profileURL.path,
               "schema 10 must encode the documented profileDir field")
        expect(encodedObject["envOverrides"] != nil,
               "schema 10 must encode the documented envOverrides field")
        expect(encodedObject["menuColor"] as? String == AppProfileMenuColor.purple.rawValue,
               "schema 10 may persist a display-only menu marker")
        let encodedSource = encodedObject["source"] as? [String: Any]
        expect(encodedSource?["bundleId"] as? String == source.bundleIdentifier,
               "schema 10 must encode the documented source.bundleId field")

        instance.environmentOverrides["PATH"] = "/tmp/unsafe"
        do {
            _ = try generator.specification(for: instance)
            expect(false, "arbitrary environment variables must be rejected")
        } catch let error as LauncherGeneratorError {
            expect(error == .disallowedEnvironmentKey("PATH"),
                   "rejection must identify the disallowed environment key")
        } catch {
            expect(false, "unexpected launcher validation error: \(error)")
        }

        instance.launcherKind = .legacyExternal
        do {
            _ = try generator.specification(for: instance)
            expect(false, "legacy wrappers must never be passed to the managed generator")
        } catch let error as LauncherGeneratorError {
            expect(error == .notManaged, "legacy wrapper rejection must be explicit")
        } catch {
            expect(false, "unexpected legacy rejection error: \(error)")
        }
    }

    private static func testManagedLifecycleIsRegistryGatedAndRetainsProfiles() {
        let root = temporaryDirectory("m1-managed-lifecycle")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )

        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let rule = AppCompatibilityRule(
            id: "fixture-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        let registry = AppCompatibilityRegistry(rules: [rule])
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        var persisted: KlikProConfig?
        var persistenceAllowed = true
        let manager = AppProfileManager(
            registry: registry,
            generator: generator,
            persist: {
                if persistenceAllowed { persisted = $0 }
                return persistenceAllowed
            },
            scanApplications: { _ in [source] },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )

        let candidate = manager.candidate(for: source)
        expect(candidate.canCreate, "an exact test registry match must enable creation")
        let id = UUID(uuidString: "96CB55A3-3D42-4207-A8CA-E89FE7A96D44")!
        let created = try! manager.create(
            from: candidate,
            label: "Work; $(display only)",
            config: KlikProConfig.default,
            instanceID: id
        )
        expect(created.instance.launcherKind == .managed, "M1 must create a managed row")
        expect(created.instance.compatibilityRuleID == rule.id,
               "the exact rule ID must be persisted as a non-authoritative hint")
        expect(persisted?.instances.contains(created.instance) == true,
               "creation must persist the new row")
        expect(FileManager.default.fileExists(atPath: created.instance.launcherPath),
               "creation must materialize the human-named launcher")
        expect(URL(fileURLWithPath: created.instance.launcherPath).lastPathComponent
               == LauncherGenerator.safeLauncherFileName(for: created.instance.label),
               "the visible launcher filename must follow the requested app name")
        expect(FileManager.default.fileExists(atPath: created.instance.profileDirectory!),
               "creation must materialize the UUID-keyed profile")

        let payloadURL = URL(fileURLWithPath: created.instance.launcherPath)
            .appendingPathComponent("Contents/Resources/LaunchSpec.plist")
        let payload = try! PropertyListDecoder().decode(
            ManagedLauncherPayload.self,
            from: Data(contentsOf: payloadURL)
        )
        expect(payload.sourceBundlePath == source.bundleURL.path,
               "launcher payload must retain the exact source bundle path")
        expect(payload.arguments == ["--user-data-dir=" + created.instance.profileDirectory!],
               "launcher payload must use one structured profile argument")
        expect(payload.compatibilityRuleID == rule.id,
               "launcher payload must carry the exact Verified rule for reinspection")
        expect(!created.instance.profileDirectory!.contains(created.instance.label),
               "adversarial display labels must not enter profile paths")
        expect(try! manager.launcherURL(for: created.instance)
                == URL(fileURLWithPath: created.instance.launcherPath).standardizedFileURL,
               "managed launch must revalidate and return the human-named launcher")
        expect(try! manager.generatedLauncherURL(for: created.instance)
                == URL(fileURLWithPath: created.instance.launcherPath).standardizedFileURL,
               "the Dual App Open entry point must use the same validated generated launcher as Spotlight and Dock")
        do {
            _ = try manager.generatedLauncherURL(for: KlikProConfig.default.instances[0])
            expect(false, "the generated-launcher entry point must reject external rows")
        } catch let error as AppProfileManagerError {
            expect(error == .externalInstance,
                   "external rows must remain on their legacy runtime path")
        } catch {
            expect(false, "unexpected generated-launcher validation error: \(error)")
        }
        var tamperedLauncherPath = created.instance
        tamperedLauncherPath.launcherPath = root
            .appendingPathComponent("arbitrary.app", isDirectory: true).path
        do {
            _ = try manager.launcherURL(for: tamperedLauncherPath)
            expect(false, "managed launch must reject a non-UUID launcher path")
        } catch let error as AppProfileManagerError {
            expect(error == .launcherUnavailable,
                   "unsafe managed launch paths must fail as unavailable")
        } catch {
            expect(false, "unexpected managed-launch validation error: \(error)")
        }

        let secondID = UUID(uuidString: "1CCB8FE3-83ED-4EB0-848C-02300946949D")!
        let second = try! manager.create(
            from: candidate,
            label: "Personal",
            config: created.config,
            instanceID: secondID
        )
        expect(second.config.instances.contains { $0.id == id }
               && second.config.instances.contains { $0.id == secondID },
               "M2 must allow multiple UUID-keyed instances for one exact source")
        expect(second.instance.profileDirectory != created.instance.profileDirectory,
               "same-source instances must use distinct UUID-keyed profile paths")
        let recolored = try! manager.updateManagedInstance(
            instanceID: secondID,
            label: "Personal Renamed",
            menuColor: .orange,
            pinToMenuBar: second.instance.pinToMenuBar,
            hotkey: second.instance.hotkey,
            mouseButton: second.instance.mouseButton,
            config: second.config
        )
        let recoloredInstance = recolored.instances.first { $0.id == secondID }
        expect(recoloredInstance?.menuColor == .orange,
               "M3 menu differentiation must persist as display-only instance metadata")
        expect(recoloredInstance?.label == "Personal Renamed",
               "renaming must persist the new display label")
        let renamedLauncherURL = URL(fileURLWithPath: recoloredInstance!.launcherPath)
        let renamedInfo = NSDictionary(
            contentsOf: renamedLauncherURL.appendingPathComponent("Contents/Info.plist")
        )
        expect(renamedInfo?["CFBundleDisplayName"] as? String == "Personal Renamed",
               "renaming must update the generated icon name")
        expect(renamedLauncherURL.lastPathComponent
               == LauncherGenerator.safeLauncherFileName(for: "Personal Renamed"),
               "renaming must update the visible app filename")
        expect(recoloredInstance?.profileDirectory == second.instance.profileDirectory,
               "renaming must not alter UUID-keyed profile paths")
        expect(persisted?.instances.first { $0.id == secondID }?.menuColor == .orange,
               "display-marker updates must persist with the managed row")
        do {
            _ = try manager.create(
                from: candidate,
                config: recolored,
                instanceID: secondID
            )
            expect(false, "reusing an existing instance UUID must fail")
        } catch let error as AppProfileManagerError {
            expect(error == .duplicateInstanceID, "duplicate UUID rejection must be explicit")
        } catch {
            expect(false, "unexpected duplicate UUID error: \(error)")
        }

        persistenceAllowed = false
        do {
            _ = try manager.remove(instanceID: id, config: recolored)
            expect(false, "failed removal persistence must not report success")
        } catch let error as AppProfileManagerError {
            expect(error == .persistenceFailed,
                   "failed removal persistence must remain explicit")
        } catch {
            expect(false, "unexpected transactional-removal error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: created.instance.launcherPath),
               "failed removal persistence must restore the staged launcher")
        expect(persisted?.instances.contains(created.instance) == true,
               "failed removal persistence must retain the prior config row")

        persistenceAllowed = true
        let removed = try! manager.remove(instanceID: id, config: recolored)
        expect(removed.launcherCleanupCompleted, "managed launcher cleanup must complete")
        expect(!removed.config.instances.contains { $0.id == id },
               "Remove must persistently drop the managed row")
        expect(removed.config.instances.contains { $0.id == secondID },
               "removing one UUID must retain the same-source sibling")
        expect(!FileManager.default.fileExists(atPath: created.instance.launcherPath),
               "Remove must delete only Klik PRO's generated launcher")
        expect(FileManager.default.fileExists(atPath: created.instance.profileDirectory!),
               "M1 Remove must retain profile data for M2-safe deletion")

        let protected = root.appendingPathComponent("must-not-delete", isDirectory: true)
        try! FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        let expectedLauncher = URL(fileURLWithPath: created.instance.launcherPath, isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: expectedLauncher, withDestinationURL: protected)
        do {
            try generator.removeLauncher(for: created.instance)
            expect(false, "Remove must reject a launcher-path symlink")
        } catch let error as LauncherGeneratorError {
            expect(error == .unsafeRemoval, "symlink removal must fail closed")
        } catch {
            expect(false, "unexpected symlink-removal error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: protected.path),
               "a rejected launcher symlink must never delete its target")
        try? FileManager.default.removeItem(at: expectedLauncher)

        let experimentalManager = AppProfileManager(
            registry: .production,
            generator: generator,
            persist: { _ in true },
            inspectApplication: { _ in source }
        )
        do {
            _ = try experimentalManager.launcherURL(for: created.instance)
            expect(false, "the production registry must block relaunch for apps without a matching rule")
        } catch let error as AppProfileManagerError {
            guard case .creationDisabled = error else {
                expect(false, "production relaunch must fail as creationDisabled")
                return
            }
        } catch {
            expect(false, "unexpected production-relaunch error: \(error)")
        }
        do {
            _ = try experimentalManager.create(
                from: experimentalManager.candidate(for: source),
                config: KlikProConfig.default
            )
            expect(false, "engine detection alone must not reach materialization")
        } catch let error as AppProfileManagerError {
            guard case .creationDisabled = error else {
                expect(false, "production registry must fail as creationDisabled")
                return
            }
        } catch {
            expect(false, "unexpected production-gate error: \(error)")
        }

        let rollbackSupport = root.appendingPathComponent("Rollback", isDirectory: true)
        let rollbackGenerator = LauncherGenerator(
            applicationSupportURL: rollbackSupport,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        let rollbackManager = AppProfileManager(
            registry: registry,
            generator: rollbackGenerator,
            persist: { _ in false },
            inspectApplication: { _ in source }
        )
        let rollbackID = UUID()
        do {
            _ = try rollbackManager.create(
                from: rollbackManager.candidate(for: source),
                config: KlikProConfig.default,
                instanceID: rollbackID
            )
            expect(false, "a failed config save must fail creation")
        } catch let error as AppProfileManagerError {
            expect(error == .persistenceFailed, "save failure must be explicit")
        } catch {
            expect(false, "unexpected rollback error: \(error)")
        }
        expect(!FileManager.default.fileExists(
            atPath: rollbackGenerator.launcherURL(for: rollbackID, label: source.displayName).path
        ), "failed persistence must roll back the generated launcher")
        expect(!FileManager.default.fileExists(
            atPath: rollbackGenerator.profileURL(for: rollbackID).path
        ), "failed persistence must roll back its never-launched fresh profile")
    }

    private static func testProcessInspectionAndFailClosedProfileDeletion() {
        var argc: Int32 = 3
        var processData = withUnsafeBytes(of: &argc) { Data($0) }
        processData.append(Data("/Applications/Fixture.app/Contents/MacOS/Fixture\0\0".utf8))
        processData.append(Data("Fixture\0--user-data-dir=/tmp/profile\0--flag\0".utf8))
        processData.append(Data("SECRET_ENV=must-not-be-parsed\0".utf8))
        expect(
            ManagedProcessInspector.parseArguments(processData)
                == ["Fixture", "--user-data-dir=/tmp/profile", "--flag"],
            "KERN_PROCARGS2 parsing must stop after declared argc"
        )

        let executable = URL(fileURLWithPath: "/Applications/Fixture.app/Contents/MacOS/Fixture")
        let profile = URL(fileURLWithPath: "/tmp/profile")
        let inspector = ManagedProcessInspector(
            listProcesses: { [41, 42] },
            executablePath: { pid in
                pid == 41 || pid == 42 ? executable.path : nil
            },
            processArguments: { pid in
                pid == 41
                    ? ["Fixture", "--user-data-dir=/tmp/profile"]
                    : ["Fixture", "--user-data-dir=/tmp/other"]
            }
        )
        expect(
            inspector.verifiedRoots(executableURL: executable, profileURL: profile)
                == .complete([41]),
            "runtime discovery must match exact executable and exact profile argument"
        )
        let incomplete = ManagedProcessInspector(
            listProcesses: { [43] },
            executablePath: { _ in executable.path },
            processArguments: { _ in nil }
        )
        expect(
            incomplete.verifiedRoots(executableURL: executable, profileURL: profile)
                == .incomplete,
            "unreadable candidate arguments must make runtime discovery incomplete"
        )

        let root = temporaryDirectory("m2-profile-delete")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        let id = UUID()
        let instance = AppProfileInstance(
            id: id,
            label: "Delete fixture",
            launcherKind: .managed,
            launcherPath: generator.launcherURL(for: id).path,
            profileDirectory: generator.profileURL(for: id).path,
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: source.bundleIdentifier,
                bundleURL: source.bundleURL.path
            ),
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0, keyDisplay: "A",
                    command: false, option: false, control: true, shift: false
                )
            ),
            mouseButton: nil,
            compatibilityRuleID: "delete-fixture-rule"
        )
        _ = try! generator.materialize(instance: instance, sourceApp: source)
        var config = KlikProConfig.default
        config.instances.append(instance)

        let unreadableInspector = ManagedProcessInspector(
            listProcesses: { [77] },
            executablePath: { _ in
                source.bundleURL.appendingPathComponent("Contents/MacOS/Fixture").path
            },
            processArguments: { _ in nil }
        )
        let blockedManager = AppProfileManager(
            generator: generator,
            processInspector: unreadableInspector,
            persist: { _ in true },
            waitBetweenProfileScans: {},
            inspectApplication: { _ in source }
        )
        do {
            _ = try blockedManager.remove(
                instanceID: id,
                config: config,
                deleteProfileData: true
            )
            expect(false, "incomplete process scanning must block profile deletion")
        } catch let error as AppProfileManagerError {
            expect(error == .processScanIncomplete,
                   "incomplete deletion scan must fail with an explicit error")
        } catch {
            expect(false, "unexpected incomplete-scan error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: instance.launcherPath),
               "blocked deletion must restore the staged launcher")
        expect(FileManager.default.fileExists(atPath: instance.profileDirectory!),
               "blocked deletion must retain profile data")

        let clearInspector = ManagedProcessInspector(
            listProcesses: { [] },
            executablePath: { _ in nil },
            processArguments: { _ in nil }
        )
        let outside = root.appendingPathComponent("outside-data", isDirectory: true)
        try! FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let nestedLink = URL(fileURLWithPath: instance.profileDirectory!)
            .appendingPathComponent("unsafe-link")
        try! FileManager.default.createSymbolicLink(at: nestedLink, withDestinationURL: outside)
        let symlinkManager = AppProfileManager(
            generator: generator,
            processInspector: clearInspector,
            persist: { _ in true },
            waitBetweenProfileScans: {},
            inspectApplication: { _ in source }
        )
        do {
            _ = try symlinkManager.remove(
                instanceID: id,
                config: config,
                deleteProfileData: true
            )
            expect(false, "a symlink anywhere inside an owned profile must block deletion")
        } catch let error as AppProfileManagerError {
            expect(error == .profileCleanupFailed,
                   "nested profile symlinks must fail closed")
        } catch {
            expect(false, "unexpected profile-symlink error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: outside.path),
               "rejected profile symlinks must never delete their targets")
        try! FileManager.default.removeItem(at: nestedLink)

        var persisted: KlikProConfig?
        let deletionManager = AppProfileManager(
            generator: generator,
            processInspector: clearInspector,
            persist: { persisted = $0; return true },
            waitBetweenProfileScans: {},
            inspectApplication: { _ in source }
        )
        let removed = try! deletionManager.remove(
            instanceID: id,
            config: config,
            deleteProfileData: true
        )
        expect(removed.profileDeleted && removed.profileCleanupCompleted,
               "two complete zero-reference scans must permit explicit owned-profile deletion")
        expect(!FileManager.default.fileExists(atPath: instance.profileDirectory!),
               "successful explicit deletion must remove the UUID-owned profile")
        expect(persisted?.instances.contains { $0.id == id } == false,
               "profile deletion must remove the same UUID config row transactionally")
    }

    private static func testExplicitLegacyConversionLeavesExternalDataUntouched() {
        let root = temporaryDirectory("m2-legacy-conversion")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let rule = AppCompatibilityRule(
            id: "conversion-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        let externalLauncher = root.appendingPathComponent("External.app", isDirectory: true)
        try! FileManager.default.createDirectory(at: externalLauncher, withIntermediateDirectories: true)
        let externalSentinel = externalLauncher.appendingPathComponent("external-data")
        try! Data("untouched".utf8).write(to: externalSentinel)
        let target = QuickLaunchTarget.chatGPT
        let legacy = AppProfileInstance(
            id: target.legacyInstanceID,
            label: "Legacy work",
            launcherKind: .legacyExternal,
            launcherPath: externalLauncher.path,
            profileDirectory: nil,
            profileOwnership: .external,
            source: AppProfileSource(
                bundleIdentifier: source.bundleIdentifier,
                bundleURL: source.bundleURL.path
            ),
            menuColor: .blue,
            pinToMenuBar: true,
            hotkey: KlikProConfig.default.chatGPTHotkey,
            mouseButton: .middle
        )
        var config = KlikProConfig.default
        config.instances = [legacy]
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        var persisted: KlikProConfig?
        let manager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [rule]),
            generator: generator,
            persist: { persisted = $0; return true },
            resolveLegacyTarget: { $0.id == target.legacyInstanceID ? target : nil },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        let converted = try! manager.convertLegacy(
            instanceID: legacy.id,
            config: config,
            managedInstanceID: UUID()
        )
        expect(converted.instance.launcherKind == .managed,
               "conversion must create a managed UUID-keyed row")
        expect(converted.instance.hotkey == legacy.hotkey
               && converted.instance.mouseButton == legacy.mouseButton
               && converted.instance.pinToMenuBar == legacy.pinToMenuBar
               && converted.instance.menuColor == legacy.menuColor,
               "conversion must transfer per-instance display and assignment metadata transactionally")
        expect(converted.config.suppressedLegacyInstanceIDs.contains(target.legacyInstanceID),
               "conversion must suppress only the converted legacy UUID")
        expect(!normalizedQuickLaunchConfig(converted.config).instances.contains {
            $0.id == target.legacyInstanceID
        }, "normalization must not silently recreate a converted legacy row")
        expect(try! Data(contentsOf: externalSentinel) == Data("untouched".utf8),
               "conversion must never alter the external wrapper or its data")
        expect(persisted?.instances.contains(converted.instance) == true,
               "converted row and suppression must persist in one config write")
    }

    private static func testRuleRequiredEnvironmentDerivation() {
        let root = temporaryDirectory("m5-required-env")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        var rule = AppCompatibilityRule(
            id: "env-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        rule.assurance = .untested
        rule.requiredEnvironment = [
            "CODEX_HOME": "{profileDir}/codex-home",
            "CODEX_ELECTRON_USER_DATA_PATH": "{profileDir}",
        ]
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        let manager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [rule]),
            generator: generator,
            persist: { _ in true },
            resolveLegacyTarget: { _ in .chatGPT },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )

        let id = UUID()
        let profilePath = generator.profileURL(for: id).path
        let created = try! manager.create(
            from: manager.candidate(for: source),
            environmentOverrides: ["CODEX_HOME": "/evil/weakened"],
            config: KlikProConfig.default,
            instanceID: id
        )
        expect(created.instance.environmentOverrides == [
            "CODEX_HOME": profilePath + "/codex-home",
            "CODEX_ELECTRON_USER_DATA_PATH": profilePath,
        ], "rule-derived environment must win over caller overrides and expand {profileDir}")
        let payload = try! PropertyListDecoder().decode(
            ManagedLauncherPayload.self,
            from: Data(contentsOf: URL(fileURLWithPath: created.instance.launcherPath)
                .appendingPathComponent("Contents/Resources/LaunchSpec.plist"))
        )
        expect(payload.environment == created.instance.environmentOverrides,
               "the launcher payload environment must match the persisted instance exactly")

        let legacy = AppProfileInstance(
            id: QuickLaunchTarget.chatGPT.legacyInstanceID,
            label: "Legacy env",
            launcherKind: .legacyExternal,
            launcherPath: root.appendingPathComponent("External.app").path,
            profileDirectory: nil,
            profileOwnership: .external,
            source: AppProfileSource(
                bundleIdentifier: source.bundleIdentifier,
                bundleURL: source.bundleURL.path
            ),
            environmentOverrides: ["CODEX_HOME": "/legacy/stale-home"],
            pinToMenuBar: false,
            hotkey: KlikProConfig.default.chatGPTHotkey,
            mouseButton: nil
        )
        try! FileManager.default.createDirectory(
            at: URL(fileURLWithPath: legacy.launcherPath),
            withIntermediateDirectories: true
        )
        var config = KlikProConfig.default
        config.instances = [legacy]
        let managedID = UUID()
        let converted = try! manager.convertLegacy(
            instanceID: legacy.id,
            config: config,
            managedInstanceID: managedID
        )
        let convertedProfile = generator.profileURL(for: managedID).path
        expect(converted.instance.environmentOverrides == [
            "CODEX_HOME": convertedProfile + "/codex-home",
            "CODEX_ELECTRON_USER_DATA_PATH": convertedProfile,
        ], "conversion must derive the environment fresh from the rule, never from the legacy row")

        var badRule = AppCompatibilityRule(
            id: "bad-token-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        badRule.requiredEnvironment = ["CODEX_HOME": "{unknownToken}/home"]
        let badManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [badRule]),
            generator: generator,
            persist: { _ in true },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        do {
            _ = try badManager.create(
                from: badManager.candidate(for: source),
                config: KlikProConfig.default
            )
            expect(false, "an unresolved rule token must fail creation closed")
        } catch let error as AppProfileManagerError {
            guard case .creationDisabled = error else {
                expect(false, "unresolved tokens must fail as creationDisabled")
                return
            }
        } catch {
            expect(false, "unexpected unresolved-token error: \(error)")
        }
    }

    private static func testProductionRegistryPinsExplicitRules() {
        let root = temporaryDirectory("m6-production-pin")
        defer { try? FileManager.default.removeItem(at: root) }

        let rules = AppCompatibilityRegistry.production.rules
        expect(rules.count == 2,
               "production must contain exactly Claude Verified and ChatGPT Untested")
        guard let claude = rules.first(where: {
            $0.id == "com-anthropic-claudefordesktop-verified"
        }), let chatGPT = rules.first(where: {
            $0.id == "com-openai-codex-untested"
        }) else {
            expect(false, "both explicit production rules must be present")
            return
        }
        expect(claude.id == "com-anthropic-claudefordesktop-verified",
               "the production rule id must match the emitted draft rule")
        expect(claude.bundleIdentifier == "com.anthropic.claudefordesktop",
               "the production rule must pin the evidenced bundle identifier")
        expect(claude.teamIdentifier == "Q6L2SF6YDW",
               "the production rule must pin the evidenced Team ID")
        expect(claude.engine == .electron,
               "the production rule must pin the evidenced engine")
        expect(claude.testedVersions == ["1.21459.0", "1.21459.1"],
               "the production rule must list exactly the versions both gates covered")
        expect(claude.assurance == .verified && claude.acceptsAnyVersion,
               "Claude approval must survive vendor updates while retaining its evidence record")
        expect(claude.requiredEnvironment == [
            "CLAUDE_CONFIG_DIR": "{codexHomeDir}",
        ], "Claude must point CLAUDE_CONFIG_DIR at the instance's sibling home (2026-07-19 owner decision)")
        expect(claude.homeSymlinkPrefix == "claude",
               "Claude profiles must expose a visible ~/.claude-* home symlink")

        expect(chatGPT.bundleIdentifier == "com.openai.codex",
               "ChatGPT must pin the installed bundle identifier")
        expect(chatGPT.teamIdentifier == "2DC432GLL2",
               "ChatGPT must pin OpenAI's signing Team ID")
        expect(chatGPT.engine == .electron,
               "ChatGPT must pin its detected Electron engine")
        expect(chatGPT.assurance == .untested && chatGPT.acceptsAnyVersion,
               "ChatGPT must stay honestly Untested while accepting vendor updates")
        expect(chatGPT.testedVersions.isEmpty,
               "ChatGPT must not claim evidence-backed tested versions")
        expect(chatGPT.requiredEnvironment == [
            "CODEX_HOME": "{codexHomeDir}",
            "CODEX_ELECTRON_USER_DATA_PATH": "{profileDir}",
        ], "ChatGPT must retain both required isolation paths")
        expect(chatGPT.homeSymlinkPrefix == "codex",
               "ChatGPT profiles must expose a visible ~/.codex-* home symlink")

        let tested = makeInstalledApp(
            root: root,
            bundleIdentifier: "com.anthropic.claudefordesktop",
            teamIdentifier: "Q6L2SF6YDW",
            version: "1.21459.1"
        )
        expect(
            AppCompatibilityRegistry.production
                .matchingRule(for: tested, engine: .electron)?.id == claude.id,
            "the evidenced Claude identity must match the production rule"
        )
        let updatedClaude = makeInstalledApp(
            root: root,
            bundleIdentifier: "com.anthropic.claudefordesktop",
            teamIdentifier: "Q6L2SF6YDW",
            version: "9.9.9"
        )
        expect(
            AppCompatibilityRegistry.production
                .matchingRule(for: updatedClaude, engine: .electron)?.id == claude.id,
            "an approved Claude installation must remain visible after a vendor update"
        )

        let futureChatGPT = makeInstalledApp(
            root: root,
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "2DC432GLL2",
            version: "99.0"
        )
        try! FileManager.default.createDirectory(
            at: futureChatGPT.bundleURL
                .appendingPathComponent("Contents/Frameworks/Codex Framework.framework"),
            withIntermediateDirectories: true
        )
        let chatGPTInfo: [String: Any] = ["ElectronHint": true]
        try! PropertyListSerialization.data(
            fromPropertyList: chatGPTInfo,
            format: .xml,
            options: 0
        ).write(to: futureChatGPT.bundleURL.appendingPathComponent("Contents/Info.plist"))
        let futureEligibility = EngineDetector().eligibility(for: futureChatGPT)
        expect(futureEligibility.kind == .experimental,
               "future ChatGPT versions must remain labelled Untested")
        expect(futureEligibility.compatibilityRuleID == chatGPT.id,
               "future ChatGPT versions must stay addable through the explicit rule")
        expect(
            AppProfileCandidate(
                app: futureChatGPT,
                engine: .electron,
                eligibility: futureEligibility
            ).canCreate,
            "the explicit ChatGPT rule must enable Add for future vendor versions"
        )
    }

    private static func testCodexHomeSiblingPlaceholderAndPrecreation() {
        let root = temporaryDirectory("m6-codex-home-sibling")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        var rule = AppCompatibilityRule(
            id: "sibling-env-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        rule.requiredEnvironment = ["CODEX_HOME": "{codexHomeDir}"]
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        let manager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [rule]),
            generator: generator,
            persist: { _ in true },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )

        let id = UUID()
        let expectedHome = generator.codexHomeURL(for: id)
        let created = try! manager.create(
            from: manager.candidate(for: source),
            config: KlikProConfig.default,
            instanceID: id
        )
        expect(created.instance.environmentOverrides == ["CODEX_HOME": expectedHome.path],
               "{codexHomeDir} must expand to the UUID-keyed sibling home")
        expect(expectedHome.path.contains("/CodexHomes/"),
               "the sibling home must live under CodexHomes/, outside Profiles/")
        var isDirectory: ObjCBool = false
        expect(FileManager.default.fileExists(
            atPath: expectedHome.path, isDirectory: &isDirectory
        ) && isDirectory.boolValue,
               "materialize must pre-create the sibling home so the app cannot fall back to its default home")

        let failingID = UUID()
        let failingManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [rule]),
            generator: generator,
            persist: { _ in false },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        do {
            _ = try failingManager.create(
                from: failingManager.candidate(for: source),
                config: KlikProConfig.default,
                instanceID: failingID
            )
            expect(false, "a persist failure must throw, not succeed")
        } catch {
            expect(!FileManager.default.fileExists(
                atPath: generator.codexHomeURL(for: failingID).path
            ), "rollback must remove a still-empty pre-created sibling home")
        }

        // A non-empty sibling home must be retained by rollback, fail-safe.
        try! Data("user-data".utf8).write(
            to: expectedHome.appendingPathComponent("state.json")
        )
        generator.rollbackNewMaterialization(for: created.instance)
        expect(FileManager.default.fileExists(atPath: expectedHome.path),
               "rollback must retain a sibling home that already holds data")

        // A symlinked CodexHomes root must fail creation closed and must not
        // materialize anything at the symlink's target.
        let externalTarget = root.appendingPathComponent("outside-tree", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: externalTarget, withIntermediateDirectories: true
        )
        let swappedSupport = root.appendingPathComponent("SwappedSupport", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: swappedSupport, withIntermediateDirectories: true
        )
        try! FileManager.default.createSymbolicLink(
            at: swappedSupport.appendingPathComponent("CodexHomes", isDirectory: true),
            withDestinationURL: externalTarget
        )
        let swappedGenerator = LauncherGenerator(
            applicationSupportURL: swappedSupport,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )
        let swappedManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [rule]),
            generator: swappedGenerator,
            persist: { _ in true },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        let swappedID = UUID()
        do {
            _ = try swappedManager.create(
                from: swappedManager.candidate(for: source),
                config: KlikProConfig.default,
                instanceID: swappedID
            )
            expect(false, "a symlinked CodexHomes root must fail creation closed")
        } catch {
            expect(!FileManager.default.fileExists(
                atPath: externalTarget
                    .appendingPathComponent(swappedID.uuidString.uppercased()).path
            ), "nothing may be created at a symlinked root's target")
        }
    }

    private static func testHomeSymlinkNamingAndLifecycle() {
        expect(LauncherGenerator.homeSymlinkName(prefix: "claude", label: "Claude A")
                == ".claude-a",
               "a Claude A profile must derive the .claude-a dot-folder name")
        expect(LauncherGenerator.homeSymlinkName(prefix: "codex", label: "ChatGPT B")
                == ".codex-b",
               "a ChatGPT label must fold its family word into the codex prefix")
        expect(LauncherGenerator.homeSymlinkName(prefix: "claude", label: "Claude")
                == ".claude",
               "a bare family label must derive the bare prefix name")
        expect(LauncherGenerator.homeSymlinkName(prefix: "claude", label: "Claude — Work (2)")
                == ".claude-work-2",
               "non-alphanumeric label characters must collapse into single dashes")

        let root = temporaryDirectory("home-symlink-lifecycle")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let linksRoot = root.appendingPathComponent("Home", isDirectory: true)
        try! FileManager.default.createDirectory(at: linksRoot, withIntermediateDirectories: true)
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            homeSymlinkRootURL: linksRoot,
            launcherExecutableURL: nil,
            signLauncher: { _ in true }
        )
        let id = UUID()
        let home = generator.codexHomeURL(for: id)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let environment = ["CLAUDE_CONFIG_DIR": home.path]

        // No link without an environment that references the sibling home.
        expect(generator.createHomeSymlink(
            for: id,
            environment: ["CLAUDE_CONFIG_DIR": "/somewhere/else"],
            preferredName: ".claude-a"
        ) == nil, "a link must only be created when the environment references the sibling home")

        let link = generator.createHomeSymlink(
            for: id,
            environment: environment,
            preferredName: ".claude-a"
        )
        expect(link?.lastPathComponent == ".claude-a",
               "the preferred dot-folder name must be used when free")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: linksRoot.appendingPathComponent(".claude-a").path
        )) == home.path, "the visible link must point at the UUID-keyed sibling home")

        // Re-creating for the same instance reuses the existing link.
        expect(generator.createHomeSymlink(
            for: id,
            environment: environment,
            preferredName: ".claude-a"
        )?.lastPathComponent == ".claude-a",
               "an existing owned link must be reused, not duplicated")

        // A real pre-existing item is never adopted: a numbered name is used.
        let otherID = UUID()
        let otherHome = generator.codexHomeURL(for: otherID)
        try! FileManager.default.createDirectory(at: otherHome, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(
            at: linksRoot.appendingPathComponent(".claude-b"),
            withIntermediateDirectories: true
        )
        let collided = generator.createHomeSymlink(
            for: otherID,
            environment: ["CLAUDE_CONFIG_DIR": otherHome.path],
            preferredName: ".claude-b"
        )
        expect(collided?.lastPathComponent == ".claude-b-2",
               "a name collision with a real item must fall back to a numbered suffix")
        var realIsDirectory: ObjCBool = false
        expect(FileManager.default.fileExists(
            atPath: linksRoot.appendingPathComponent(".claude-b").path,
            isDirectory: &realIsDirectory
        ) && realIsDirectory.boolValue
            && (try? FileManager.default.destinationOfSymbolicLink(
                atPath: linksRoot.appendingPathComponent(".claude-b").path
            )) == nil,
               "the pre-existing real directory must remain an untouched real directory")

        // Removal deletes only links whose destination is this instance's home.
        generator.removeHomeSymlinks(for: id)
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: linksRoot.appendingPathComponent(".claude-a").path
        )) == nil, "removal must delete the instance's own link")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: linksRoot.appendingPathComponent(".claude-b-2").path
        )) == otherHome.path,
               "removal must never touch another instance's link")
        expect(FileManager.default.fileExists(atPath: home.path),
               "removing the visible link must never delete the sibling home itself")
    }

    private static func testHealingUpgradesExistingInstancesInPlace() {
        let root = temporaryDirectory("healing-pass")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let linksRoot = root.appendingPathComponent("Home", isDirectory: true)
        try! FileManager.default.createDirectory(at: linksRoot, withIntermediateDirectories: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            homeSymlinkRootURL: linksRoot,
            launcherExecutableURL: runner,
            signLauncher: { _ in true }
        )

        // Yesterday's rule: no required environment, no visible home.
        let oldRule = AppCompatibilityRule(
            id: "healing-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        let oldManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [oldRule]),
            generator: generator,
            persist: { _ in true },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        let id = UUID()
        let created = try! oldManager.create(
            from: oldManager.candidate(for: source),
            label: "Claude A",
            config: KlikProConfig.default,
            instanceID: id
        )
        expect(created.instance.environmentOverrides.isEmpty,
               "the pre-heal instance must have been created without environment")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: linksRoot.appendingPathComponent(".claude-a").path
        )) == nil, "no visible link must exist before the rule requests one")

        let launcherURL = URL(
            fileURLWithPath: created.instance.launcherPath, isDirectory: true
        )
        let embeddedRunner = launcherURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(LauncherGenerator.executableName)
        let launcherInfoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        var legacyInfo = try! PropertyListSerialization.propertyList(
            from: Data(contentsOf: launcherInfoURL), options: [], format: nil
        ) as! [String: Any]
        legacyInfo.removeValue(forKey: "NSAppleEventsUsageDescription")
        try! PropertyListSerialization.data(
            fromPropertyList: legacyInfo, format: .xml, options: 0
        ).write(to: launcherInfoURL, options: .atomic)
        try! Data("fixture-runner-v2".utf8).write(to: runner, options: .atomic)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: runner.path
        )

        // Today's rule: the same id now requires the sibling home + link.
        var newRule = oldRule
        newRule.requiredEnvironment = ["CLAUDE_CONFIG_DIR": "{codexHomeDir}"]
        newRule.homeSymlinkPrefix = "claude"
        var persistCount = 0
        let newManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [newRule]),
            generator: generator,
            persist: { _ in
                persistCount += 1
                return true
            },
            inspectApplication: { url in
                url.standardizedFileURL == source.bundleURL ? source : nil
            }
        )
        let healed = newManager.healManagedInstances(config: created.config)
        let home = generator.codexHomeURL(for: id)
        // KlikProConfig.default may carry machine-discovered legacy external
        // rows, so the managed instance is looked up by id, never by position.
        let healedInstance = healed.instances.first { $0.id == id }
        expect(healedInstance?.environmentOverrides
                == ["CLAUDE_CONFIG_DIR": home.path],
               "healing must derive the rule's environment for the existing instance")
        expect(persistCount == 1,
               "a real heal must persist exactly once")
        var homeIsDirectory: ObjCBool = false
        expect(FileManager.default.fileExists(
            atPath: home.path, isDirectory: &homeIsDirectory
        ) && homeIsDirectory.boolValue,
               "healing must pre-create the sibling home")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: linksRoot.appendingPathComponent(".claude-a").path
        )) == home.path,
               "healing must create the visible home symlink")
        let payloadURL = URL(
            fileURLWithPath: healedInstance!.launcherPath, isDirectory: true
        ).appendingPathComponent("Contents/Resources/LaunchSpec.plist")
        let payload = try! PropertyListDecoder().decode(
            ManagedLauncherPayload.self,
            from: Data(contentsOf: payloadURL)
        )
        expect(payload.environment == ["CLAUDE_CONFIG_DIR": home.path],
               "healing must rewrite the launcher's baked payload environment")
        expect(FileManager.default.fileExists(
            atPath: generator.profileURL(for: id).path
        ), "healing must never touch the profile data directory")
        expect(try! Data(contentsOf: embeddedRunner) == Data("fixture-runner-v2".utf8),
               "healing must refresh the embedded runner for existing launchers")
        let healedInfo = try! PropertyListSerialization.propertyList(
            from: Data(contentsOf: launcherInfoURL), options: [], format: nil
        ) as! [String: Any]
        expect(healedInfo["NSAppleEventsUsageDescription"] as? String
                == LauncherGenerator.appleEventsUsageDescription,
               "healing must add the required Apple-events purpose string")
        expect(FileManager.default.isExecutableFile(atPath: embeddedRunner.path),
               "a refreshed embedded runner must remain executable")

        // Idempotence: a second heal changes nothing and persists nothing.
        let again = newManager.healManagedInstances(config: healed)
        expect(again == healed, "an already-healed config must be returned unchanged")
        expect(persistCount == 1, "an already-healed config must not persist again")

        // A launcher created before the signed storage fields existed must be
        // upgraded even when its persisted environment and profile path did not
        // otherwise change.
        let legacyPayload: [String: Any] = [
            "sourceBundlePath": source.bundleURL.path,
            "arguments": ["--user-data-dir=" + generator.profileURL(for: id).path],
            "environment": ["CLAUDE_CONFIG_DIR": home.path],
            "compatibilityRuleID": newRule.id,
        ]
        try! PropertyListSerialization.data(
            fromPropertyList: legacyPayload, format: .xml, options: 0
        ).write(to: payloadURL, options: .atomic)
        let contractHealed = newManager.healManagedInstances(config: healed)
        let upgradedPayload = try! PropertyListDecoder().decode(
            ManagedLauncherPayload.self, from: Data(contentsOf: payloadURL)
        )
        expect(contractHealed == healed && persistCount == 1,
               "a launcher-only contract upgrade must not rewrite config")
        expect(upgradedPayload.profileDirectory == generator.profileURL(for: id).path
               && upgradedPayload.profileStorage == .applicationSupport,
               "healing must add the signed profile path and storage contract")

        // A failed re-sign must restore the previous executable bytes, metadata,
        // and mode instead of leaving an unlaunchable half-updated bundle.
        try! Data("fixture-runner-v3".utf8).write(to: runner, options: .atomic)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: runner.path
        )
        let infoBeforeFailedRefresh = try! Data(contentsOf: launcherInfoURL)
        var signAttempts = 0
        let failingGenerator = LauncherGenerator(
            applicationSupportURL: support,
            homeSymlinkRootURL: linksRoot,
            launcherExecutableURL: runner,
            signLauncher: { _ in
                signAttempts += 1
                return signAttempts > 1
            }
        )
        do {
            _ = try failingGenerator.refreshLauncherRuntimeIfStale(for: healedInstance!)
            expect(false, "a failed launcher re-sign must surface an error")
        } catch LauncherGeneratorError.materializationFailed {
            // Expected.
        } catch {
            expect(false, "unexpected launcher-refresh rollback error: \(error)")
        }
        expect(signAttempts == 2, "rollback must attempt to re-sign the restored launcher")
        expect(try! Data(contentsOf: embeddedRunner) == Data("fixture-runner-v2".utf8),
               "rollback must restore the previous embedded runner bytes")
        expect(FileManager.default.isExecutableFile(atPath: embeddedRunner.path),
               "rollback must restore executable permissions")
        expect(try! Data(contentsOf: launcherInfoURL) == infoBeforeFailedRefresh,
               "rollback must restore the previous launcher metadata")
    }

    private static func testRealAdHocLauncherMaterialization() {
        let root = temporaryDirectory("m1-real-launcher-signing")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let generator = LauncherGenerator(
            applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true),
            launcherExecutableURL: runner
        )
        let source = makeInstalledApp(root: root)
        let id = UUID()
        let instance = AppProfileInstance(
            id: id,
            label: "Signed fixture",
            launcherKind: .managed,
            launcherPath: generator.launcherURL(for: id).path,
            profileDirectory: generator.profileURL(for: id).path,
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: source.bundleIdentifier,
                bundleURL: source.bundleURL.path
            ),
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0,
                    keyDisplay: "A",
                    command: false,
                    option: false,
                    control: true,
                    shift: false
                )
            ),
            mouseButton: nil,
            compatibilityRuleID: "signing-fixture-rule"
        )
        let materialized = try! generator.materialize(instance: instance, sourceApp: source)
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", materialized.launcherURL.path]
        try! verify.run()
        verify.waitUntilExit()
        expect(verify.terminationStatus == 0,
               "the real generated launcher bundle must pass strict code-sign verification")
        try! generator.removeLauncher(for: instance)
        expect(FileManager.default.fileExists(atPath: materialized.profileURL.path),
               "real launcher removal must also retain profile data")
    }

    /// The only ImageIO-dependent claim: an under-256 image is rejected, while a
    /// square and a non-square source both encode into a valid multi-size icns
    /// whose largest element is 512.
    private static func testMakeICNSDataSizeValidation() {
        let root = temporaryDirectory("icns-size-validation")
        defer { try? FileManager.default.removeItem(at: root) }

        let tooSmall = root.appendingPathComponent("small.png")
        writeTestPNG(width: 128, height: 128, to: tooSmall)
        var rejected = false
        do {
            _ = try LauncherGenerator.makeICNSData(fromImageAt: tooSmall)
        } catch LauncherGeneratorError.iconImageInvalid {
            rejected = true
        } catch {
            expect(false, "small image must fail with iconImageInvalid, not \(error)")
        }
        expect(rejected, "an image under 256px on its short side must be rejected")

        let square = root.appendingPathComponent("square.png")
        writeTestPNG(width: 256, height: 256, to: square)
        let squareData = try! LauncherGenerator.makeICNSData(fromImageAt: square)
        let squareInfo = icnsFrameCountAndMaxWidth(squareData)
        expect(squareInfo.count >= 1 && squareInfo.maxWidth == 512,
               "a 256px square must encode a valid icns whose largest element is 512")

        let wide = root.appendingPathComponent("wide.png")
        writeTestPNG(width: 512, height: 300, to: wide)
        let wideData = try! LauncherGenerator.makeICNSData(fromImageAt: wide)
        expect(icnsFrameCountAndMaxWidth(wideData).maxWidth == 512,
               "a non-square source must be aspect-fit into a valid 512-max icns")

        // Pin the exact canonical size set as a regression tripwire. makeICNSData
        // emits exactly 16/32/128/256/512 — 64 is intentionally omitted because
        // ImageIO's icns encoder silently drops it. The shipped assertions above
        // only check count >= 1 / maxWidth, so a silent size-set change (a re-added
        // 64, an added retina type) would slip through; this catches it.
        let canonical = root.appendingPathComponent("canonical.png")
        writeTestPNG(width: 512, height: 512, to: canonical)
        let canonicalData = try! LauncherGenerator.makeICNSData(fromImageAt: canonical)
        let canonicalSource = CGImageSourceCreateWithData(canonicalData as CFData, nil)!
        var canonicalWidths: Set<Int> = []
        for index in 0..<CGImageSourceGetCount(canonicalSource) {
            if let image = CGImageSourceCreateImageAtIndex(canonicalSource, index, nil) {
                canonicalWidths.insert(image.width)
            }
        }
        expect(canonicalWidths == [16, 32, 128, 256, 512],
               "makeICNSData must emit exactly the 5 canonical sizes 16/32/128/256/512")
    }

    /// A custom icon persisted under CustomIcons/<UUID>.icns must be preferred by
    /// buildLauncherBundle, so it survives a launcher re-materialization (heal /
    /// adopt / legacy conversion) rather than reverting to the source app icon.
    private static func testCustomIconSurvivesRematerialization() {
        let root = temporaryDirectory("custom-icon-survives")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let generator = LauncherGenerator(
            applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true),
            launcherExecutableURL: runner
        )
        let source = makeInstalledApp(root: root)
        let id = UUID()
        let instance = AppProfileInstance(
            id: id,
            label: "Custom icon fixture",
            launcherKind: .managed,
            launcherPath: generator.launcherURL(for: id).path,
            profileDirectory: generator.profileURL(for: id).path,
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: source.bundleIdentifier,
                bundleURL: source.bundleURL.path
            ),
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0, keyDisplay: "A",
                    command: false, option: false, control: true, shift: false
                )
            ),
            mouseButton: nil,
            compatibilityRuleID: "signing-fixture-rule"
        )
        _ = try! generator.materialize(instance: instance, sourceApp: source)

        let png = root.appendingPathComponent("chosen.png")
        writeTestPNG(width: 512, height: 512, to: png)
        let stampedURL = try! generator.setCustomIcon(fromImageAt: png, for: instance)
        expect(generator.hasCustomIcon(for: id),
               "setting a custom icon must persist a CustomIcons/<UUID>.icns copy")
        let persisted = try! Data(contentsOf: generator.customIconURL(for: id))
        let stampedBytes = try! Data(contentsOf: stampedURL)
        expect(stampedBytes == persisted,
               "the stamped bundle icon must equal the persisted custom copy")

        // Simulate a lost launcher that heal/adopt/regenerate would rebuild —
        // delete the bundle directly (NOT removeLauncher, which is a permanent
        // removal that deliberately purges the persisted custom copy). The
        // fixture source app declares no icon, so any AppIcon.icns after the
        // rebuild can only have come from the persisted custom copy.
        try! FileManager.default.removeItem(
            at: URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
        )
        expect(generator.hasCustomIcon(for: id),
               "a rebuild-triggering launcher loss must not remove the persisted custom icon")
        let regenerated = try! generator.regenerateLauncher(instance: instance, sourceApp: source)
        let rebuiltIcon = regenerated.launcherURL
            .appendingPathComponent("Contents/Resources/AppIcon.icns")
        expect(FileManager.default.fileExists(atPath: rebuiltIcon.path),
               "re-materialization must restore the custom icon into the rebuilt bundle")
        expect(try! Data(contentsOf: rebuiltIcon) == persisted,
               "the re-materialized icon must be the persisted custom copy, not the source icon")
    }

    /// Tint and badge compositions always emit onto the square render canvas,
    /// independent of source aspect, and a whitespace-only badge letter must not
    /// crash or fail to render.
    private static func testCustomIconTintAndBadgeGeometry() {
        let source = makeTestBitmap(width: 400, height: 400)
        let tinted = LauncherGenerator.tintedIcon(source, color: AppProfileMenuColor.green.iconColor)
        expect(tinted != nil, "tint must produce an image")
        expect(tinted!.width == LauncherGenerator.renderCanvasSize
               && tinted!.height == LauncherGenerator.renderCanvasSize,
               "tinted output must be the square render canvas")

        let badged = LauncherGenerator.badgedIcon(
            source, color: AppProfileMenuColor.pink.iconColor, letter: "Work")
        expect(badged != nil && badged!.width == LauncherGenerator.renderCanvasSize,
               "badge must produce a square render-canvas image")

        let blankBadge = LauncherGenerator.badgedIcon(
            source, color: AppProfileMenuColor.gray.iconColor, letter: "   ")
        expect(blankBadge != nil, "a whitespace-only label must still render a (letterless) badge")

        let wideBadge = LauncherGenerator.badgedIcon(
            makeTestBitmap(width: 800, height: 200),
            color: AppProfileMenuColor.blue.iconColor, letter: "A")
        expect(wideBadge != nil && wideBadge!.width == wideBadge!.height,
               "a non-square source must still yield a square badge composite")
    }

    /// Reset drops the persisted CustomIcons/<UUID>.icns so future
    /// re-materializations follow the source again. (The fixture source declares
    /// no icon, so reset takes the removeIcon path — the file must still be gone.)
    private static func testResetRemovesPersistedCustomIcon() {
        let fixture = makeManagedFixture("icon-reset")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID()
        let instance = makeManagedInstance(id: id, generator: fixture.generator, source: fixture.source)
        _ = try! fixture.generator.materialize(instance: instance, sourceApp: fixture.source)

        let png = fixture.root.appendingPathComponent("chosen.png")
        writeTestPNG(width: 300, height: 300, to: png)
        _ = try! fixture.generator.setCustomIcon(fromImageAt: png, for: instance)
        expect(fixture.generator.hasCustomIcon(for: id), "precondition: custom icon persisted")

        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
        _ = try! fixture.generator.resetCustomIcon(for: instance, sourceBundleURL: sourceURL)
        expect(!fixture.generator.hasCustomIcon(for: id),
               "reset must delete the persisted custom icon")
    }

    /// updateManagedIcon must refuse a non-managed (legacy external) row rather
    /// than touch the user's own untracked app.
    private static func testUpdateManagedIconRejectsExternalRow() {
        let manager = AppProfileManager(persist: { _ in true })
        let config = KlikProConfig.default
        let external = config.instances.first { $0.launcherKind == .legacyExternal }
        expect(external != nil, "the default config must contain a legacy external row to test")
        do {
            _ = try manager.updateManagedIcon(
                instanceID: external!.id, edit: .tint(.blue), config: config)
            expect(false, "updateManagedIcon must reject a legacy external row")
        } catch let error as AppProfileManagerError {
            expect(error == .externalInstance, "external rows must fail as .externalInstance")
        } catch {
            expect(false, "unexpected error rejecting external row: \(error)")
        }
    }

    /// A too-small chosen image must surface as .iconImageInvalid at the manager
    /// boundary (LauncherGeneratorError -> AppProfileManagerError).
    private static func testUpdateManagedIconMapsInvalidImage() {
        let fixture = makeManagedFixture("icon-invalid-map")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID()
        let instance = makeManagedInstance(id: id, generator: fixture.generator, source: fixture.source)
        _ = try! fixture.generator.materialize(instance: instance, sourceApp: fixture.source)

        var config = KlikProConfig.default
        config.instances.append(instance)
        let manager = AppProfileManager(generator: fixture.generator, persist: { _ in true })

        let tiny = fixture.root.appendingPathComponent("tiny.png")
        writeTestPNG(width: 64, height: 64, to: tiny)
        do {
            _ = try manager.updateManagedIcon(instanceID: id, edit: .image(tiny), config: config)
            expect(false, "a 64px image must be rejected")
        } catch let error as AppProfileManagerError {
            expect(error == .iconImageInvalid, "invalid image must map to .iconImageInvalid")
        } catch {
            expect(false, "unexpected error for invalid image: \(error)")
        }
    }

    /// The menu-bar launch regression: a transient double-process (or a
    /// momentarily incomplete scan) must be re-scanned and settled rather than
    /// hard-failing with ambiguousProcesses, while genuine persistent ambiguity
    /// still fails closed.
    private static func testSettledProcessScanResolvesTransientAmbiguity() {
        // A transient race that clears within the budget settles to the single
        // root (focus), consuming exactly the attempts and settling between each.
        var clearing: [ManagedProcessScan] = [.complete([11, 22]), .incomplete, .complete([11])]
        var settleCount = 0
        let resolved = settledManagedProcessScan(
            attempts: 3,
            scan: { clearing.removeFirst() },
            settle: { settleCount += 1 }
        )
        expect(resolved == .complete([11]), "a clearing transient must settle to the single focus root")
        expect(settleCount == 2, "must settle between re-scans, never after the final attempt")
        expect(clearing.isEmpty, "a transient that persists until the last attempt consumes the budget")

        // Persistent ambiguity is a real duplicate — after the budget it must
        // remain ambiguous so launchOrFocus still fails closed.
        var persistentScans = 0
        let persistent = settledManagedProcessScan(
            attempts: 3,
            scan: { persistentScans += 1; return .complete([11, 22]) },
            settle: {}
        )
        expect(persistent == .complete([11, 22]),
               "persistent ambiguity must remain ambiguous (still fails closed)")
        expect(persistentScans == 3, "persistent ambiguity must exhaust exactly the attempt budget")

        // Stable results resolve on the first attempt with no settle: one root
        // (focus) and zero roots (launch fresh).
        for stable in [ManagedProcessScan.complete([11]), .complete([])] {
            var scans = 0
            let result = settledManagedProcessScan(
                attempts: 3,
                scan: { scans += 1; return stable },
                settle: { expect(false, "a stable first scan must never settle") }
            )
            expect(result == stable && scans == 1,
                   "a stable scan resolves immediately without re-scanning")
        }
    }

    // MARK: - Durable Data Vault (schema 11, Phase 1)

    private struct VaultFixture {
        let root: URL
        let support: URL
        let linksRoot: URL
        let vault: URL
        let runner: URL
        let source: InstalledApp
        let rule: AppCompatibilityRule
    }

    private static func makeVaultFixture(_ label: String) -> VaultFixture {
        let root = temporaryDirectory(label)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let linksRoot = root.appendingPathComponent("Home", isDirectory: true)
        try! FileManager.default.createDirectory(at: linksRoot, withIntermediateDirectories: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let runner = root.appendingPathComponent("KlikProManagedLauncher")
        try! Data("fixture-runner".utf8).write(to: runner)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        let source = makeInstalledApp(root: root)
        let framework = source.bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try! FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        var rule = AppCompatibilityRule(
            id: "vault-fixture-rule",
            bundleIdentifier: source.bundleIdentifier,
            teamIdentifier: source.teamIdentifier!,
            engine: .electron,
            testedVersions: [source.version!]
        )
        rule.requiredEnvironment = ["CLAUDE_CONFIG_DIR": "{codexHomeDir}"]
        rule.homeSymlinkPrefix = "claude"
        return VaultFixture(
            root: root,
            support: support,
            linksRoot: linksRoot,
            vault: vault,
            runner: runner,
            source: source,
            rule: rule
        )
    }

    private static func makeVaultManager(
        _ fixture: VaultFixture,
        vaultRoot: URL?,
        support: URL? = nil,
        persist: @escaping (KlikProConfig) -> Bool = { _ in true },
        processInspector: ManagedProcessInspector = ManagedProcessInspector(),
        trashItem: @escaping (URL) throws -> URL? = LauncherGenerator.defaultTrash
    ) -> (manager: AppProfileManager, generator: LauncherGenerator) {
        let generator = LauncherGenerator(
            applicationSupportURL: support ?? fixture.support,
            homeSymlinkRootURL: fixture.linksRoot,
            vaultRootURL: vaultRoot,
            launcherExecutableURL: fixture.runner,
            signLauncher: { _ in true },
            trashItem: trashItem
        )
        let manager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [fixture.rule]),
            generator: generator,
            processInspector: processInspector,
            persist: persist,
            waitBetweenProfileScans: {},
            inspectApplication: { url in
                url.standardizedFileURL == fixture.source.bundleURL ? fixture.source : nil
            }
        )
        return (manager, generator)
    }

    private static func launcherPayload(at launcherPath: String) -> ManagedLauncherPayload {
        try! PropertyListDecoder().decode(
            ManagedLauncherPayload.self,
            from: Data(contentsOf: URL(fileURLWithPath: launcherPath, isDirectory: true)
                .appendingPathComponent("Contents/Resources/LaunchSpec.plist"))
        )
    }

    private static func testVaultPathDerivationAndDefaultGolden() {
        let fixture = makeVaultFixture("vault-derivation")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID(uuidString: "7A40E5D1-64C4-4E9B-96A7-1FBD0A3C2E51")!

        let plain = makeVaultManager(fixture, vaultRoot: nil)
        expect(try! plain.generator.profileURL(for: id, storage: .applicationSupport)
                == plain.generator.profileURL(for: id),
               "the default storage derivation must be the unchanged Profiles/<UUID> path")
        expect(try! plain.generator.codexHomeURL(for: id, storage: .applicationSupport)
                == plain.generator.codexHomeURL(for: id),
               "the default storage derivation must be the unchanged CodexHomes/<UUID> path")
        do {
            _ = try plain.generator.profileURL(for: id, storage: .vault)
            expect(false, "vault derivation without a wired vault root must fail closed")
        } catch let error as LauncherGeneratorError {
            expect(error == .vaultUnavailable,
                   "a missing vault root must never fall back to Application Support")
        } catch {
            expect(false, "unexpected vault-derivation error: \(error)")
        }

        let vaulted = makeVaultManager(fixture, vaultRoot: fixture.vault)
        expect(vaulted.generator.profileURL(for: id) == plain.generator.profileURL(for: id),
               "wiring a vault must not alter the Application Support derivation")
        let vaultBase = fixture.vault.standardizedFileURL.path
        expect(try! vaulted.generator.profileURL(for: id, storage: .vault).path
                == vaultBase + "/Instances/" + id.uuidString + "/user-data",
               "vault profiles must derive as <Vault>/Instances/<UUID>/user-data")
        expect(try! vaulted.generator.codexHomeURL(for: id, storage: .vault).path
                == vaultBase + "/Instances/" + id.uuidString + "/config-home",
               "vault homes must derive as <Vault>/Instances/<UUID>/config-home")

        // Filesystem golden: creating with dataRoot = nil must produce exactly
        // today's Application Support layout, nothing more, nothing else.
        let created = try! plain.manager.create(
            from: plain.manager.candidate(for: fixture.source),
            label: "Golden",
            config: KlikProConfig.default,
            instanceID: id
        )
        expect(created.instance.storage == .applicationSupport,
               "dataRoot = nil must create an Application Support instance")
        let base = plain.generator.applicationSupportURL.path
        var relative = Set<String>()
        let enumerator = FileManager.default.enumerator(
            at: plain.generator.applicationSupportURL,
            includingPropertiesForKeys: nil,
            options: []
        )!
        for case let url as URL in enumerator {
            // The enumerator may report the /private-prefixed spelling of the
            // same temp path; normalize without resolving entry symlinks.
            var path = url.path
            if path.hasPrefix("/private") && !base.hasPrefix("/private") {
                path = String(path.dropFirst("/private".count))
            }
            guard path.hasPrefix(base + "/") else { continue }
            let relativePath = String(path.dropFirst(base.count + 1))
            if relativePath.split(separator: "/").count <= 2 {
                relative.insert(relativePath)
            }
        }
        let expected: Set<String> = [
            "CodexHomes", "CodexHomes/" + id.uuidString,
            "Profiles", "Profiles/" + id.uuidString,
            "Visible Launchers", "Visible Launchers/Golden.app",
        ]
        expect(relative == expected,
               "dataRoot = nil must reproduce the exact pre-vault layout, got: \(relative.sorted())")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-golden").path
        )) == plain.generator.codexHomeURL(for: id).path,
               "the golden create must keep the unchanged visible home symlink")
        let marker = plain.generator.profileURL(for: id)
            .appendingPathComponent(".klik-pro-owned-profile")
        expect((try? Data(contentsOf: marker))
                == Data(id.uuidString.uppercased().utf8),
               "the golden layout must keep the UUID ownership marker byte-for-byte")
        expect(VaultManifest.read(vaultRoot: fixture.vault) == nil
               && !FileManager.default.fileExists(atPath: fixture.vault.path),
               "a defaults-only create must never touch or create a vault")
    }

    private static func testVaultLocationValidationFailsClosed() {
        let root = temporaryDirectory("vault-validation")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("HomeDir", isDirectory: true)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        expect(vaultPathRejectionReason("relative/vault", homeDirectory: home.path) != nil,
               "a non-absolute vault path must be rejected")
        expect(vaultPathRejectionReason(
            home.path + "/Library/Application Support/Klik PRO Vault",
            homeDirectory: home.path
        ) != nil, "a vault inside Application Support must be rejected — uninstallers wipe it")
        expect(vaultPathRejectionReason(
            root.path + "/Fake.app/Contents/Vault",
            homeDirectory: home.path
        ) != nil, "a vault inside an .app bundle must be rejected")

        let unwritable = root.appendingPathComponent("unwritable", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: unwritable,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o500]
        )
        expect(vaultPathRejectionReason(unwritable.path, homeDirectory: home.path) != nil,
               "an unwritable existing folder must be rejected")
        expect(vaultPathRejectionReason(
            unwritable.path + "/Nested Vault",
            homeDirectory: home.path
        ) != nil, "a new folder under an unwritable parent must be rejected")
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: unwritable.path
        )

        expect(vaultPathRejectionReason(
            root.path + "/Fresh Vault",
            homeDirectory: home.path
        ) == nil, "a creatable location outside Application Support must be accepted")
        let existing = root.appendingPathComponent("Existing", isDirectory: true)
        try! FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        expect(vaultPathRejectionReason(existing.path, homeDirectory: home.path) == nil,
               "an existing writable folder must be accepted")

        // F2: a case-variant of the Application Support prefix must still be
        // rejected on the case-insensitive default volume.
        expect(vaultPathRejectionReason(
            home.path + "/Library/application support/Klik PRO Vault",
            homeDirectory: home.path
        ) != nil, "a case-variant Application Support path must be rejected")

        // F2: a symlink pointing into Application Support must be rejected by
        // where it physically resolves, not by its cosmetic path.
        let realAppSupport = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: realAppSupport, withIntermediateDirectories: true
        )
        let sneakyLink = root.appendingPathComponent("innocent-looking", isDirectory: true)
        try! FileManager.default.createSymbolicLink(
            at: sneakyLink, withDestinationURL: realAppSupport
        )
        expect(vaultPathRejectionReason(
            sneakyLink.path + "/Vault",
            homeDirectory: home.path
        ) != nil, "a symlink resolving into Application Support must be rejected")

        // F3: a symlink resolving into an .app bundle interior must also be
        // rejected — the .app rule must inspect the canonical path, not the
        // cosmetic one that carries no ".app" component.
        let realBundleInterior = root
            .appendingPathComponent("Some.app/Contents", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: realBundleInterior, withIntermediateDirectories: true
        )
        let bundleLink = root.appendingPathComponent("harmless-name", isDirectory: true)
        try! FileManager.default.createSymbolicLink(
            at: bundleLink, withDestinationURL: realBundleInterior
        )
        expect(vaultPathRejectionReason(
            bundleLink.path + "/Vault",
            homeDirectory: home.path
        ) != nil, "a symlink resolving into an .app bundle must be rejected")
    }

    private static func testSchema11VaultMigrationRoundTrip() {
        let defaults = KlikProConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var object = try! JSONSerialization.jsonObject(with: encoder.encode(defaults))
            as! [String: Any]
        expect(object["dataRoot"] == nil,
               "a nil dataRoot must stay absent from the encoded config")

        // Fabricate a schema-10 file, including hand-edited vault markers that
        // a pre-11 schema must ignore fail-safe.
        object["schemaVersion"] = 10
        object["dataRoot"] = "/tmp/pre-11-vault-marker"
        var rawInstances = object["instances"] as! [[String: Any]]
        for index in rawInstances.indices {
            rawInstances[index].removeValue(forKey: "storage")
        }
        if !rawInstances.isEmpty { rawInstances[0]["storage"] = "vault" }
        object["instances"] = rawInstances
        let schema10Data = try! JSONSerialization.data(withJSONObject: object)
        let decoded = try! JSONDecoder().decode(KlikProConfig.self, from: schema10Data)
        expect(decoded.dataRoot == nil,
               "a schema-10 config must decode with dataRoot = nil")
        expect(decoded.instances.allSatisfy { $0.storage == .applicationSupport },
               "every schema-10 instance must migrate as .applicationSupport")
        expect(normalizedQuickLaunchConfig(decoded).schemaVersion == 12,
               "normalization must bump migrated configs to schema 12")

        // Schema 11 → 12 is lifecycle-only and must default every existing row
        // to active without inventing an archive timestamp.
        var schema11Object = try! JSONSerialization.jsonObject(with: encoder.encode(defaults))
            as! [String: Any]
        schema11Object["schemaVersion"] = 11
        var schema11Instances = schema11Object["instances"] as! [[String: Any]]
        for index in schema11Instances.indices {
            schema11Instances[index].removeValue(forKey: "state")
            schema11Instances[index].removeValue(forKey: "archivedAt")
        }
        schema11Object["instances"] = schema11Instances
        let schema11Data = try! JSONSerialization.data(withJSONObject: schema11Object)
        let lifecycleMigrated = try! JSONDecoder().decode(KlikProConfig.self, from: schema11Data)
        expect(lifecycleMigrated.instances.allSatisfy {
            $0.state == .active && $0.archivedAt == nil
        }, "schema 11 rows must migrate to active with no archive timestamp")
        expect(normalizedQuickLaunchConfig(lifecycleMigrated).schemaVersion == 12,
               "normalization must bump schema 11 configs to schema 12")

        // Schema-11 round trip: dataRoot and per-instance storage survive.
        var vaulted = defaults
        vaulted.dataRoot = "/Volumes/T7/Klik PRO Data"
        let vaultID = UUID()
        vaulted.instances.append(AppProfileInstance(
            id: vaultID,
            label: "Vaulted",
            launcherKind: .managed,
            launcherPath: "/tmp/Launchers/Vaulted.app",
            profileDirectory: "/Volumes/T7/Klik PRO Data/Instances/"
                + vaultID.uuidString + "/user-data",
            profileOwnership: .managed,
            source: AppProfileSource(
                bundleIdentifier: "com.example.managed",
                bundleURL: "/Applications/Managed.app"
            ),
            storage: .vault,
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0, keyDisplay: "A",
                    command: false, option: false, control: true, shift: false
                )
            ),
            mouseButton: nil
        ))
        let roundTripped = try! JSONDecoder().decode(
            KlikProConfig.self,
            from: try! JSONEncoder().encode(vaulted)
        )
        expect(roundTripped == vaulted,
               "schema 11 must round-trip dataRoot and storage untouched")
    }

    private static func testCreateInVaultWritesManifestAndLeavesExistingUntouched() {
        let fixture = makeVaultFixture("vault-create")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let plain = makeVaultManager(fixture, vaultRoot: nil)
        let baseID = UUID()
        let base = try! plain.manager.create(
            from: plain.manager.candidate(for: fixture.source),
            label: "Claude Base",
            config: KlikProConfig.default,
            instanceID: baseID
        )
        let baseProfile = URL(fileURLWithPath: base.instance.profileDirectory!, isDirectory: true)
        try! Data("existing-login".utf8).write(
            to: baseProfile.appendingPathComponent("sentinel")
        )
        let baseListing = try! FileManager.default
            .contentsOfDirectory(atPath: baseProfile.path).sorted()
        let baseMarker = try! Data(
            contentsOf: baseProfile.appendingPathComponent(".klik-pro-owned-profile")
        )

        // A configured dataRoot without a matching wired vault root fails closed.
        var mismatched = base.config
        mismatched.dataRoot = fixture.vault.path
        do {
            _ = try plain.manager.create(
                from: plain.manager.candidate(for: fixture.source),
                label: "Should Fail",
                config: mismatched,
                instanceID: UUID()
            )
            expect(false, "a dataRoot the generator is not wired for must disable creation")
        } catch let error as AppProfileManagerError {
            guard case .creationDisabled = error else {
                expect(false, "vault wiring mismatch must fail as creationDisabled")
                return
            }
        } catch {
            expect(false, "unexpected vault-mismatch error: \(error)")
        }

        var persisted: KlikProConfig?
        let vaulted = makeVaultManager(fixture, vaultRoot: fixture.vault, persist: {
            persisted = $0
            return true
        })
        var config = base.config
        config.dataRoot = fixture.vault.path
        let vaultID = UUID()
        let created = try! vaulted.manager.create(
            from: vaulted.manager.candidate(for: fixture.source),
            label: "Claude Vault",
            config: config,
            instanceID: vaultID
        )
        expect(created.instance.storage == .vault,
               "a configured dataRoot must create a vault-stored instance")
        let expectedProfile = try! vaulted.generator.profileURL(for: vaultID, storage: .vault)
        let expectedHome = try! vaulted.generator.codexHomeURL(for: vaultID, storage: .vault)
        expect(created.instance.profileDirectory == expectedProfile.path,
               "the vault instance must materialize under Instances/<UUID>/user-data")
        expect(FileManager.default.fileExists(atPath: expectedProfile.path),
               "the vault profile directory must exist")
        expect(created.instance.environmentOverrides
                == ["CLAUDE_CONFIG_DIR": expectedHome.path],
               "{codexHomeDir} must expand into the vault's config-home")
        expect(FileManager.default.fileExists(atPath: expectedHome.path),
               "the vault config-home must be pre-created")
        expect(FileManager.default.fileExists(atPath: created.instance.launcherPath)
               && created.instance.launcherPath.hasPrefix(
                   vaulted.generator.visibleLaunchersRootURL.path
               ),
               "the launcher must stay in the unchanged launcher root, outside the vault")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-vault").path
        )) == expectedHome.path,
               "the visible home symlink must point into the vault's config-home")
        let payload = launcherPayload(at: created.instance.launcherPath)
        expect(payload.arguments == ["--user-data-dir=" + expectedProfile.path],
               "the baked launcher argument must use the vault profile path")

        guard let manifest = VaultManifest.read(vaultRoot: fixture.vault) else {
            expect(false, "creating a vault instance must write vault.json")
            return
        }
        expect(manifest.schemaVersion == VaultManifest.currentSchemaVersion,
               "the manifest must carry its schema version")
        expect(manifest.instances.count == 1
               && manifest.instances[0].id == vaultID
               && manifest.instances[0].label == "Claude Vault"
               && manifest.instances[0].compatibilityRuleID == fixture.rule.id
               && manifest.instances[0].homeSymlinkPrefix == "claude",
               "the manifest must record the vault instance's re-derivable identity")
        expect(manifest.instances[0].archived == false
               && manifest.instances[0].menuColor == nil
               && manifest.instances[0].customIcon == false,
               "new manifest lifecycle/icon fields must default safely")
        var v1ManifestObject = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(manifest)
        ) as! [String: Any]
        v1ManifestObject["schemaVersion"] = 1
        var v1Records = v1ManifestObject["instances"] as! [[String: Any]]
        for index in v1Records.indices {
            v1Records[index].removeValue(forKey: "archived")
            v1Records[index].removeValue(forKey: "menuColor")
            v1Records[index].removeValue(forKey: "customIcon")
        }
        v1ManifestObject["instances"] = v1Records
        let v1Manifest = try! JSONDecoder().decode(
            VaultManifest.self,
            from: JSONSerialization.data(withJSONObject: v1ManifestObject)
        )
        expect(v1Manifest.instances[0].archived == false
               && v1Manifest.instances[0].menuColor == nil
               && v1Manifest.instances[0].customIcon == false,
               "manifest schema 1 must decode with safe lifecycle/icon defaults")
        expect(!manifest.instances.contains { $0.id == baseID },
               "Application Support instances must never enter the vault manifest")

        // Existing instance provably untouched.
        expect(try! FileManager.default
            .contentsOfDirectory(atPath: baseProfile.path).sorted() == baseListing,
               "creating a vault instance must not write into an existing profile")
        expect(try! Data(
            contentsOf: baseProfile.appendingPathComponent(".klik-pro-owned-profile")
        ) == baseMarker, "the existing instance's ownership marker must be untouched")
        expect(created.config.instances.first { $0.id == baseID } == base.instance,
               "the existing instance's config row must be byte-identical")
        expect(persisted?.instances.contains(created.instance) == true,
               "the vault instance must persist in the config cache")
    }

    private static func testVaultHealParityAndPortability() {
        let fixture = makeVaultFixture("vault-heal")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let plain = makeVaultManager(fixture, vaultRoot: nil)
        let baseID = UUID()
        let base = try! plain.manager.create(
            from: plain.manager.candidate(for: fixture.source),
            label: "Claude Base",
            config: KlikProConfig.default,
            instanceID: baseID
        )

        var createPersistCount = 0
        let vaultedA = makeVaultManager(fixture, vaultRoot: fixture.vault, persist: { _ in
            createPersistCount += 1
            return true
        })
        var config = base.config
        config.dataRoot = fixture.vault.path
        let vaultID = UUID()
        let created = try! vaultedA.manager.create(
            from: vaultedA.manager.candidate(for: fixture.source),
            label: "Claude Vault",
            config: config,
            instanceID: vaultID
        )
        let oldProfile = created.instance.profileDirectory!
        try! Data("vault-login".utf8).write(
            to: URL(fileURLWithPath: oldProfile).appendingPathComponent("sentinel")
        )
        let oldHome = try! vaultedA.generator.codexHomeURL(for: vaultID, storage: .vault)
        try! Data("cli-state".utf8).write(
            to: oldHome.appendingPathComponent("state.json")
        )

        // Parity: an in-place config (both storages) is already healed — no-op.
        expect(vaultedA.manager.healManagedInstances(config: created.config) == created.config,
               "an unmoved vault + Application Support config must heal as a no-op")
        expect(createPersistCount == 1,
               "a no-op heal must not persist (only the create persisted)")

        // Move the vault, then heal against its new root.
        let movedVault = fixture.root.appendingPathComponent("Moved Vault", isDirectory: true)
        try! FileManager.default.moveItem(at: fixture.vault, to: movedVault)
        var healPersistCount = 0
        let vaultedB = makeVaultManager(fixture, vaultRoot: movedVault, persist: { _ in
            healPersistCount += 1
            return true
        })
        var movedConfig = created.config
        movedConfig.dataRoot = movedVault.path
        let healed = vaultedB.manager.healManagedInstances(config: movedConfig)
        let healedInstance = healed.instances.first { $0.id == vaultID }
        let newProfile = try! vaultedB.generator.profileURL(for: vaultID, storage: .vault)
        let newHome = try! vaultedB.generator.codexHomeURL(for: vaultID, storage: .vault)
        expect(healedInstance?.profileDirectory == newProfile.path,
               "heal must rewrite the stored profile path against the vault's current root")
        expect(healedInstance?.environmentOverrides == ["CLAUDE_CONFIG_DIR": newHome.path],
               "heal must re-derive the isolation env against the vault's current root")
        let payload = launcherPayload(at: healedInstance!.launcherPath)
        expect(payload.arguments == ["--user-data-dir=" + newProfile.path]
               && payload.environment == ["CLAUDE_CONFIG_DIR": newHome.path],
               "heal must rewrite the launcher's baked payload to the moved vault")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-vault").path
        )) == newHome.path,
               "heal must re-point the visible home symlink at the moved vault")
        expect(!FileManager.default.fileExists(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-vault-2").path
        ) && (try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-vault-2").path
        )) == nil, "healing a moved vault must not leave stale or numbered duplicate links")
        expect(healPersistCount == 1, "a real heal must persist exactly once")
        expect(try! Data(contentsOf: newProfile.appendingPathComponent("sentinel"))
                == Data("vault-login".utf8),
               "heal must never touch the vault instance's profile data")
        expect(try! Data(contentsOf: newHome.appendingPathComponent("state.json"))
                == Data("cli-state".utf8),
               "heal must never touch the vault instance's config-home data")

        // The Application Support instance rode through both heals untouched.
        expect(healed.instances.first { $0.id == baseID } == base.instance,
               "healing vault instances must leave Application Support instances identical")

        // Idempotent: a second heal changes nothing and persists nothing.
        expect(vaultedB.manager.healManagedInstances(config: healed) == healed
               && healPersistCount == 1,
               "an already-healed moved vault must heal as a no-op")
    }

    private static func testVaultAdoptionRegeneratesFromManifest() {
        let fixture = makeVaultFixture("vault-adopt")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let vaultedA = makeVaultManager(fixture, vaultRoot: fixture.vault)
        var config = KlikProConfig.default
        config.dataRoot = fixture.vault.path
        let id = UUID()
        let created = try! vaultedA.manager.create(
            from: vaultedA.manager.candidate(for: fixture.source),
            label: "Claude Vault",
            config: config,
            instanceID: id
        )
        let profileURL = URL(
            fileURLWithPath: created.instance.profileDirectory!,
            isDirectory: true
        )
        try! Data("survives-uninstall".utf8).write(
            to: profileURL.appendingPathComponent("Login Data")
        )

        // Simulated uninstall: the entire Application Support cache (config,
        // profiles root, visible launchers) disappears; the vault and the `~`
        // dot-symlinks survive.
        try! FileManager.default.removeItem(at: fixture.support)

        // Discovery ladder: the surviving symlink recovers the vault root.
        let discovered = discoverVaultRootCandidates(
            rememberedPath: nil,
            homeSymlinkRootURL: fixture.linksRoot,
            defaultCandidatePaths: []
        )
        expect(discovered.map(\.path) == [fixture.vault.standardizedFileURL.path],
               "a surviving home symlink must recover the vault root, got: \(discovered)")
        expect(discoverVaultRootCandidates(
            rememberedPath: fixture.vault.path,
            homeSymlinkRootURL: fixture.root.appendingPathComponent("nowhere"),
            defaultCandidatePaths: []
        ).map(\.path) == [fixture.vault.standardizedFileURL.path],
               "a remembered pointer must recover the vault root without any symlink")

        // Fresh install: new Application Support tree, adopt from the vault.
        var persisted: KlikProConfig?
        let supportB = fixture.root.appendingPathComponent("SupportB", isDirectory: true)
        let fresh = makeVaultManager(
            fixture,
            vaultRoot: fixture.vault,
            support: supportB,
            persist: { persisted = $0; return true }
        )
        let result = try! fresh.manager.adoptVault(config: KlikProConfig.default)
        expect(result.adopted.count == 1 && result.skippedInstanceIDs.isEmpty,
               "a valid vault must re-adopt its single instance")
        let adopted = result.adopted[0]
        expect(adopted.id == id, "adopt must preserve the instance's UUID identity")
        expect(adopted.storage == .vault && adopted.label == "Claude Vault",
               "adopt must reconstruct the manifest's instance record")
        let currentProfile = try! fresh.generator.profileURL(for: id, storage: .vault)
        let currentHome = try! fresh.generator.codexHomeURL(for: id, storage: .vault)
        expect(adopted.profileDirectory == currentProfile.path,
               "adopt must derive paths from the vault's current location")
        expect(FileManager.default.fileExists(atPath: adopted.launcherPath)
               && adopted.launcherPath.hasPrefix(fresh.generator.visibleLaunchersRootURL.path),
               "adopt must regenerate the missing launcher into the new launcher root")
        let payload = launcherPayload(at: adopted.launcherPath)
        expect(payload.arguments == ["--user-data-dir=" + currentProfile.path]
               && payload.environment == ["CLAUDE_CONFIG_DIR": currentHome.path],
               "the regenerated launcher must bake the vault's current paths")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-vault").path
        )) == currentHome.path,
               "adopt must keep or recreate the visible home symlink")
        expect(try! Data(contentsOf: currentProfile.appendingPathComponent("Login Data"))
                == Data("survives-uninstall".utf8),
               "adopt must never write into the vault instance's data")
        expect(persisted?.instances.contains { $0.id == id } == true,
               "adopt must persist the merged config once")

        // Re-adopting a config that already holds the instance is a no-op.
        let again = try! fresh.manager.adoptVault(config: result.config)
        expect(again.adopted.isEmpty && again.config == result.config,
               "existing instances must be merged untouched, never re-adopted")

        // A surviving valid launcher is reused but its payload is re-baked.
        let reuse = try! fresh.manager.adoptVault(config: KlikProConfig.default)
        expect(reuse.adopted.count == 1
               && launcherPayload(at: reuse.adopted[0].launcherPath).arguments
                    == ["--user-data-dir=" + currentProfile.path],
               "a surviving launcher must be revalidated and re-baked, not rebuilt")

        // Refusals: no manifest ⇒ no adoption, even with plausible-looking data.
        let foreign = fixture.root.appendingPathComponent("Foreign", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: foreign.appendingPathComponent(
                "Instances/" + UUID().uuidString + "/user-data",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        let foreignManager = makeVaultManager(fixture, vaultRoot: foreign, support: supportB)
        do {
            _ = try foreignManager.manager.adoptVault(config: KlikProConfig.default)
            expect(false, "a folder without a valid vault.json must be refused")
        } catch let error as AppProfileManagerError {
            expect(error == .vaultManifestInvalid,
                   "manifest-less folders must fail as vaultManifestInvalid")
        } catch {
            expect(false, "unexpected foreign-folder error: \(error)")
        }

        // Refusal: adopt without any wired vault root.
        let rootless = makeVaultManager(fixture, vaultRoot: nil, support: supportB)
        do {
            _ = try rootless.manager.adoptVault(config: KlikProConfig.default)
            expect(false, "adopt without a vault root must be refused")
        } catch let error as AppProfileManagerError {
            expect(error == .vaultUnavailable, "rootless adopt must fail as vaultUnavailable")
        } catch {
            expect(false, "unexpected rootless-adopt error: \(error)")
        }

        // A manifest record whose Instances/<UUID> data is missing is skipped,
        // and a fully-skipped adopt never persists.
        let ghostVault = fixture.root.appendingPathComponent("GhostVault", isDirectory: true)
        let ghostID = UUID()
        VaultManifest(
            schemaVersion: VaultManifest.currentSchemaVersion,
            instances: [VaultManifestInstanceRecord(
                id: ghostID,
                label: "Ghost",
                sourceBundleIdentifier: fixture.source.bundleIdentifier,
                sourceTeamIdentifier: fixture.source.teamIdentifier,
                sourceBundleURL: fixture.source.bundleURL.path,
                compatibilityRuleID: fixture.rule.id,
                homeSymlinkPrefix: "claude"
            )]
        ).write(to: ghostVault)
        var ghostPersisted = false
        let ghostManager = makeVaultManager(
            fixture,
            vaultRoot: ghostVault,
            support: supportB,
            persist: { _ in ghostPersisted = true; return true }
        )
        let ghostResult = try! ghostManager.manager.adoptVault(config: KlikProConfig.default)
        expect(ghostResult.adopted.isEmpty && ghostResult.skippedInstanceIDs == [ghostID],
               "a record without matching Instances/<UUID> data must be skipped")
        expect(!ghostPersisted, "a fully-skipped adopt must not persist anything")

        // F1: a rule whose home-symlink prefix was renamed after the vault was
        // written must still adopt — the cached manifest prefix is convenience
        // only, and adopt re-derives the current prefix from the rule.
        try! FileManager.default.removeItem(at: supportB)
        var renamedRule = fixture.rule
        renamedRule.homeSymlinkPrefix = "assistant"
        let renamedGenerator = LauncherGenerator(
            applicationSupportURL: supportB,
            homeSymlinkRootURL: fixture.linksRoot,
            vaultRootURL: fixture.vault,
            launcherExecutableURL: fixture.runner,
            signLauncher: { _ in true }
        )
        let renamedManager = AppProfileManager(
            registry: AppCompatibilityRegistry(rules: [renamedRule]),
            generator: renamedGenerator,
            persist: { _ in true },
            inspectApplication: { url in
                url.standardizedFileURL == fixture.source.bundleURL ? fixture.source : nil
            }
        )
        let renamedAdopt = try! renamedManager.adoptVault(config: KlikProConfig.default)
        expect(renamedAdopt.adopted.count == 1 && renamedAdopt.skippedInstanceIDs.isEmpty,
               "a renamed home-symlink prefix must not make a pre-existing vault un-adoptable")
        let renamedHome = try! renamedGenerator.codexHomeURL(for: id, storage: .vault)
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".assistant-vault").path
        )) == renamedHome.path,
               "adopt must recreate the visible symlink under the rule's CURRENT prefix")
    }

    private static func testVaultInstanceRemovalAndManifestWriteFailSafe() {
        let fixture = makeVaultFixture("vault-removal")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let clearInspector = ManagedProcessInspector(
            listProcesses: { [] },
            executablePath: { _ in nil },
            processArguments: { _ in nil }
        )
        var persisted: KlikProConfig?
        let vaulted = makeVaultManager(
            fixture,
            vaultRoot: fixture.vault,
            persist: { persisted = $0; return true },
            processInspector: clearInspector
        )
        var config = KlikProConfig.default
        config.dataRoot = fixture.vault.path
        let keepID = UUID()
        let keep = try! vaulted.manager.create(
            from: vaulted.manager.candidate(for: fixture.source),
            label: "Claude Keep",
            config: config,
            instanceID: keepID
        )
        let dropID = UUID()
        let drop = try! vaulted.manager.create(
            from: vaulted.manager.candidate(for: fixture.source),
            label: "Claude Drop",
            config: keep.config,
            instanceID: dropID
        )
        let keepProfile = URL(fileURLWithPath: keep.instance.profileDirectory!, isDirectory: true)
        try! Data("keep-login".utf8).write(to: keepProfile.appendingPathComponent("sentinel"))
        let keepHome = try! vaulted.generator.codexHomeURL(for: keepID, storage: .vault)
        try! Data("keep-cli".utf8).write(to: keepHome.appendingPathComponent("state.json"))

        // A vault instance handled by a generator with no wired vault root
        // must fail closed on removal too: its paths can never be derived, so
        // nothing may be staged, deleted, or misresolved.
        let rootless = makeVaultManager(
            fixture,
            vaultRoot: nil,
            processInspector: clearInspector
        )
        do {
            _ = try rootless.manager.remove(instanceID: dropID, config: drop.config)
            expect(false, "removing a vault instance without a wired vault root must fail closed")
        } catch let error as AppProfileManagerError {
            expect(error == .launcherCleanupFailed,
                   "rootless vault removal must fail before touching anything")
        } catch {
            expect(false, "unexpected rootless-removal error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: drop.instance.profileDirectory!),
               "a failed rootless removal must leave the vault data untouched")
        expect(FileManager.default.fileExists(atPath: drop.instance.launcherPath),
               "a failed rootless removal must leave the launcher in place")

        // Explicit data deletion removes the vault instance's user-data, its
        // launcher and visible symlink, and rewrites the manifest down to the
        // surviving instances — without touching any other instance.
        let removed = try! vaulted.manager.remove(
            instanceID: dropID,
            config: drop.config,
            deleteProfileData: true
        )
        expect(removed.profileDeleted && removed.launcherCleanupCompleted,
               "vault profile deletion must complete when nothing references the profile")
        expect(!FileManager.default.fileExists(atPath: drop.instance.profileDirectory!),
               "explicit deletion must remove the vault instance's user-data")
        expect(!FileManager.default.fileExists(atPath: drop.instance.launcherPath),
               "explicit deletion must remove the vault instance's launcher")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-drop").path
        )) == nil, "explicit deletion must remove the vault instance's home symlink")
        expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: fixture.linksRoot.appendingPathComponent(".claude-keep").path
        )) == keepHome.path, "removal must never touch another vault instance's symlink")
        expect(persisted?.instances.contains { $0.id == dropID } == false,
               "the removed vault row must leave the persisted config")
        guard let manifest = VaultManifest.read(vaultRoot: fixture.vault) else {
            expect(false, "the manifest must survive a vault-instance removal")
            return
        }
        expect(manifest.instances.map(\.id) == [keepID],
               "removal must rewrite the manifest down to the surviving instances")
        expect(try! Data(contentsOf: keepProfile.appendingPathComponent("sentinel"))
                == Data("keep-login".utf8),
               "removing one vault instance must never touch another's profile data")
        expect(try! Data(contentsOf: keepHome.appendingPathComponent("state.json"))
                == Data("keep-cli".utf8),
               "removing one vault instance must never touch another's config-home data")

        // Manifest fail-safe: a read-only vault makes the write a surfaced
        // no-op (false) that never corrupts the manifest already on disk.
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: fixture.vault.path
        )
        expect(!VaultManifest(
            schemaVersion: VaultManifest.currentSchemaVersion,
            instances: []
        ).write(to: fixture.vault),
               "a manifest write onto a read-only vault must report failure, never crash")
        expect(VaultManifest.read(vaultRoot: fixture.vault) == manifest,
               "a failed manifest write must leave the previous manifest intact")
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fixture.vault.path
        )
    }

    private static func testArchiveRestoreAndRepairPreserveVaultData() {
        let fixture = makeVaultFixture("archive-restore-repair")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var persisted: KlikProConfig?
        let vaulted = makeVaultManager(
            fixture,
            vaultRoot: fixture.vault,
            persist: { persisted = $0; return true }
        )
        var config = KlikProConfig.default
        config.dataRoot = fixture.vault.path
        let id = UUID()
        let created = try! vaulted.manager.create(
            from: vaulted.manager.candidate(for: fixture.source),
            label: "Claude Archive",
            config: config,
            instanceID: id
        )
        let profile = URL(fileURLWithPath: created.instance.profileDirectory!, isDirectory: true)
        let sentinel = profile.appendingPathComponent("Login Data")
        try! Data("must-survive".utf8).write(to: sentinel)
        let iconPNG = fixture.root.appendingPathComponent("custom.png")
        writeTestPNG(width: 512, height: 512, to: iconPNG)
        let withIcon = try! vaulted.manager.updateManagedIcon(
            instanceID: id,
            edit: .image(iconPNG),
            config: created.config
        )
        let workingIcon = vaulted.generator.customIconURL(for: id)
        let durableIcon = try! vaulted.generator.vaultCustomIconURL(for: id)
        expect(FileManager.default.fileExists(atPath: workingIcon.path)
               && FileManager.default.fileExists(atPath: durableIcon.path),
               "a vault custom icon must have working and durable copies")

        let archived = try! vaulted.manager.archive(
            instanceID: id,
            at: Date(timeIntervalSince1970: 1234),
            config: withIcon
        )
        let archivedRow = archived.config.instances.first { $0.id == id }!
        expect(archivedRow.state == .archived && archivedRow.archivedAt != nil,
               "Archive must keep the row and persist archived lifecycle state")
        expect(!FileManager.default.fileExists(atPath: archivedRow.launcherPath),
               "Archive must remove only the generated launcher")
        expect(FileManager.default.fileExists(atPath: sentinel.path)
               && FileManager.default.fileExists(atPath: workingIcon.path)
               && FileManager.default.fileExists(atPath: durableIcon.path),
               "Archive must preserve profile data and both custom-icon copies")
        let archivedManifest = VaultManifest.read(vaultRoot: fixture.vault)!
        expect(archivedManifest.instances.first { $0.id == id }?.archived == true,
               "Archive must retain and mark the vault manifest record")
        expect(vaulted.manager.maintenanceHealth(for: archivedRow) == .recoverableArchived,
               "an archived row with owned data must be recoverable")

        let restored = try! vaulted.manager.restore(instanceID: id, config: archived.config)
        let restoredRow = restored.instances.first { $0.id == id }!
        expect(restoredRow.state == .active && restoredRow.archivedAt == nil,
               "Restore must reactivate the same UUID")
        expect(FileManager.default.fileExists(atPath: restoredRow.launcherPath)
               && (try! Data(contentsOf: sentinel)) == Data("must-survive".utf8),
               "Restore must rebuild the launcher without changing profile data")

        let staged = try! vaulted.generator.stageLauncherRemoval(for: restoredRow)!
        try! vaulted.generator.commitLauncherRemoval(staged, preserveCustomIcon: true)
        expect(vaulted.manager.maintenanceHealth(for: restoredRow) == .missingLauncher,
               "manual launcher deletion must classify as Missing Launcher")
        let repaired = try! vaulted.manager.repairLauncher(instanceID: id, config: restored)
        let repairedRow = repaired.instances.first { $0.id == id }!
        expect(repairedRow.id == id
               && repairedRow.state == .active
               && FileManager.default.fileExists(atPath: repairedRow.launcherPath),
               "Repair must rebuild the launcher for the same active UUID")
        expect(try! Data(contentsOf: sentinel) == Data("must-survive".utf8),
               "Repair must never modify profile data")
        expect(persisted?.instances.first { $0.id == id }?.state == .active,
               "the restored/repaired lifecycle state must persist")

        var pendingArchive = repaired
        let pendingIndex = pendingArchive.instances.firstIndex { $0.id == id }!
        pendingArchive.instances[pendingIndex].state = .archived
        pendingArchive.instances[pendingIndex].archivedAt = Date(timeIntervalSince1970: 5678)
        let manifestURL = fixture.vault.appendingPathComponent(vaultManifestFileName)
        try! FileManager.default.removeItem(at: manifestURL)
        expect(vaulted.manager.reconcileDerivedState(config: pendingArchive),
               "reconciliation must complete for a writable vault")
        expect(!FileManager.default.fileExists(atPath: repairedRow.launcherPath),
               "reconciliation must finish pending archived-launcher cleanup")
        expect(FileManager.default.fileExists(atPath: sentinel.path)
               && FileManager.default.fileExists(atPath: durableIcon.path),
               "reconciliation must preserve profile data and durable custom icons")
        expect(VaultManifest.read(vaultRoot: fixture.vault)?
                .instances.first { $0.id == id }?.archived == true,
               "reconciliation must rebuild vault.json from config truth")
    }

    private static func testForgetEntryDropsStaleRecordWithoutDeletingData() {
        let fixture = makeVaultFixture("forget-entry")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var persisted: KlikProConfig?
        let env = makeVaultManager(
            fixture, vaultRoot: nil, persist: { persisted = $0; return true }
        )
        var config = KlikProConfig.default
        let id = UUID()
        let created = try! env.manager.create(
            from: env.manager.candidate(for: fixture.source),
            label: "Forget Fixture", config: config, instanceID: id
        )
        config = created.config

        // A healthy record (data present) refuses Forget.
        do {
            _ = try env.manager.forget(instanceID: id, config: config)
            expect(false, "Forget must refuse a healthy record")
        } catch let error as AppProfileManagerError {
            expect(error == .forgetUnavailable, "Forget of live data must be forgetUnavailable")
        } catch {
            expect(false, "unexpected forget error: \(error)")
        }

        // Simulate the reported case: the profile data is gone.
        let profile = URL(fileURLWithPath: created.instance.profileDirectory!)
        try! FileManager.default.removeItem(at: profile)
        expect(env.manager.maintenanceHealth(for: created.instance) == .missingData,
               "a record whose data is gone must classify as Missing Data")

        let result = try! env.manager.forget(instanceID: id, config: config)
        expect(!result.config.instances.contains { $0.id == id },
               "Forget must drop the stale row")
        expect(persisted?.instances.contains { $0.id == id } == false,
               "Forget must persist the row removal (commit point)")
        expect(!FileManager.default.fileExists(atPath: created.instance.launcherPath),
               "Forget must remove any residual launcher (a launcher is not user data)")

        // Absent row → idempotent no-op.
        let noop = try! env.manager.forget(instanceID: id, config: result.config)
        expect(noop.config.instances.count == result.config.instances.count,
               "Forget on an absent row must be a no-op")
    }

    private static func testOrphanScanClassifiesRecordlessData() {
        let fixture = makeVaultFixture("orphan-scan")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let env = makeVaultManager(fixture, vaultRoot: nil)
        var config = KlikProConfig.default
        let liveID = UUID()
        config = try! env.manager.create(
            from: env.manager.candidate(for: fixture.source),
            label: "Live Fixture", config: config, instanceID: liveID
        ).config

        let profilesRoot = fixture.support.appendingPathComponent("Profiles", isDirectory: true)
        let markerName = LauncherGenerator.profileOwnershipMarkerName

        // Marker-owned record-less folder → Orphaned Data.
        let orphanID = UUID()
        let orphanDir = profilesRoot
            .appendingPathComponent(orphanID.uuidString.uppercased(), isDirectory: true)
        try! FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try! Data(orphanID.uuidString.uppercased().utf8)
            .write(to: orphanDir.appendingPathComponent(markerName))

        // Markerless folder → Needs Manual Review.
        let reviewID = UUID()
        let reviewDir = profilesRoot
            .appendingPathComponent(reviewID.uuidString.uppercased(), isDirectory: true)
        try! FileManager.default.createDirectory(at: reviewDir, withIntermediateDirectories: true)

        // Non-UUID directory → never enumerated.
        try! FileManager.default.createDirectory(
            at: profilesRoot.appendingPathComponent("not-a-uuid", isDirectory: true),
            withIntermediateDirectories: true
        )

        let findings = env.manager.scanOrphans(config: config)
        expect(findings.contains {
            $0.instanceID == orphanID && $0.state == .orphanedData && $0.markerPresent
        }, "a marker-owned record-less folder must be Orphaned Data")
        expect(findings.contains {
            $0.instanceID == reviewID && $0.state == .needsManualReview && !$0.markerPresent
        }, "a markerless folder must be Needs Manual Review")
        expect(!findings.contains { $0.instanceID == liveID },
               "an in-config UUID must never be an orphan")
        expect(!findings.contains { finding in
            finding.dataPaths.contains { $0.lastPathComponent == "not-a-uuid" }
        }, "non-UUID names must never be enumerated")
    }

    private static func testReclaimDataTrashPermanentAndFailClosed() {
        // (a) Vault artifact plan is exactly one non-overlapping container.
        let vaultFixture = makeVaultFixture("reclaim-vault-plan")
        defer { try? FileManager.default.removeItem(at: vaultFixture.root) }
        let vaultEnv = makeVaultManager(vaultFixture, vaultRoot: vaultFixture.vault)
        var vaultConfig = KlikProConfig.default
        vaultConfig.dataRoot = vaultFixture.vault.path
        let vaultID = UUID()
        let vaultCreated = try! vaultEnv.manager.create(
            from: vaultEnv.manager.candidate(for: vaultFixture.source),
            label: "Vault Reclaim", config: vaultConfig, instanceID: vaultID
        )
        let vaultTarget = vaultEnv.manager.dataRemovalTarget(
            for: vaultCreated.config.instances.first { $0.id == vaultID }!
        )
        expect(vaultTarget.artifacts.count == 1
               && vaultTarget.artifacts.first?.kind == .vaultContainer,
               "a vault target must be exactly the one Instances/<UUID> container")

        let clear = ManagedProcessInspector(
            listProcesses: { [] }, executablePath: { _ in nil }, processArguments: { _ in nil }
        )

        // (b) Trash mode: reversible move via the injected op; no permanent delete.
        let trashDestination = temporaryDirectory("reclaim-trash-dest")
        defer { try? FileManager.default.removeItem(at: trashDestination) }
        let spy = TrashSpy(destination: trashDestination)
        var trashPersisted: KlikProConfig?
        let trashFixture = makeVaultFixture("reclaim-trash")
        defer { try? FileManager.default.removeItem(at: trashFixture.root) }
        let trashEnv = makeVaultManager(
            trashFixture, vaultRoot: nil,
            persist: { trashPersisted = $0; return true },
            processInspector: clear, trashItem: { try spy.trash($0) }
        )
        let trashID = UUID()
        let trashCreated = try! trashEnv.manager.create(
            from: trashEnv.manager.candidate(for: trashFixture.source),
            label: "Trash Reclaim", config: KlikProConfig.default, instanceID: trashID
        )
        let trashProfile = URL(fileURLWithPath: trashCreated.instance.profileDirectory!)
        try! Data("login-data".utf8).write(to: trashProfile.appendingPathComponent("Login"))
        let trashTarget = trashEnv.manager.dataRemovalTarget(
            for: trashCreated.config.instances.first { $0.id == trashID }!
        )
        let trashResult = try! trashEnv.manager.reclaimData(
            target: trashTarget, config: trashCreated.config, mode: .trash
        )
        expect(trashResult.allRemoved, "Trash mode must remove all planned artifacts")
        expect(spy.moved.contains(trashProfile.standardizedFileURL),
               "Trash mode must route the profile through the injected Trash op")
        expect(!FileManager.default.fileExists(atPath: trashProfile.path),
               "the original profile path must be empty after Trash")
        expect(trashPersisted?.instances.contains { $0.id == trashID } == false,
               "a record-bearing Trash must drop the config row")

        // (c) Permanent mode: unrecoverable removeItem; the Trash op is untouched.
        let permSpy = TrashSpy(destination: temporaryDirectory("reclaim-perm-dest"))
        let permFixture = makeVaultFixture("reclaim-permanent")
        defer { try? FileManager.default.removeItem(at: permFixture.root) }
        let permEnv = makeVaultManager(
            permFixture, vaultRoot: nil,
            processInspector: clear, trashItem: { try permSpy.trash($0) }
        )
        let permID = UUID()
        let permCreated = try! permEnv.manager.create(
            from: permEnv.manager.candidate(for: permFixture.source),
            label: "Permanent Reclaim", config: KlikProConfig.default, instanceID: permID
        )
        let permProfile = URL(fileURLWithPath: permCreated.instance.profileDirectory!)
        let permTarget = permEnv.manager.dataRemovalTarget(
            for: permCreated.config.instances.first { $0.id == permID }!
        )
        let permResult = try! permEnv.manager.reclaimData(
            target: permTarget, config: permCreated.config, mode: .permanent
        )
        expect(permResult.allRemoved, "Permanent mode must remove all planned artifacts")
        expect(permSpy.moved.isEmpty, "Permanent mode must never use the Trash op")
        expect(!FileManager.default.fileExists(atPath: permProfile.path),
               "Permanent mode must delete the profile data")

        // (d) Fail closed: a referencing/unreadable process blocks removal.
        let inUseFixture = makeVaultFixture("reclaim-inuse")
        defer { try? FileManager.default.removeItem(at: inUseFixture.root) }
        let sourceExec = inUseFixture.source.bundleURL
            .appendingPathComponent("Contents/MacOS/Fixture").path
        let inUseEnv = makeVaultManager(
            inUseFixture, vaultRoot: nil,
            processInspector: ManagedProcessInspector(
                listProcesses: { [7] },
                executablePath: { _ in sourceExec },
                processArguments: { _ in nil }
            )
        )
        let inUseID = UUID()
        let inUseCreated = try! inUseEnv.manager.create(
            from: inUseEnv.manager.candidate(for: inUseFixture.source),
            label: "In-Use Reclaim", config: KlikProConfig.default, instanceID: inUseID
        )
        let inUseProfile = URL(fileURLWithPath: inUseCreated.instance.profileDirectory!)
        let inUseTarget = inUseEnv.manager.dataRemovalTarget(
            for: inUseCreated.config.instances.first { $0.id == inUseID }!
        )
        do {
            _ = try inUseEnv.manager.reclaimData(
                target: inUseTarget, config: inUseCreated.config, mode: .trash
            )
            expect(false, "an incomplete/refusing process scan must block removal")
        } catch let error as AppProfileManagerError {
            expect(error == .processScanIncomplete,
                   "unreadable process arguments must fail closed as processScanIncomplete")
        } catch {
            expect(false, "unexpected reclaim error: \(error)")
        }
        expect(FileManager.default.fileExists(atPath: inUseProfile.path),
               "a blocked reclaim must leave all profile data on disk")
    }

    private static func testReclaimDataMultiArtifactPartialAndMarkerless() {
        let clear = ManagedProcessInspector(
            listProcesses: { [] }, executablePath: { _ in nil }, processArguments: { _ in nil }
        )

        // (M3a) Application Support target with all three artifacts, Trash mode.
        let multiFixture = makeVaultFixture("reclaim-multi")
        defer { try? FileManager.default.removeItem(at: multiFixture.root) }
        let multiSpy = TrashSpy(destination: temporaryDirectory("reclaim-multi-dest"))
        let multiEnv = makeVaultManager(
            multiFixture, vaultRoot: nil,
            processInspector: clear, trashItem: { try multiSpy.trash($0) }
        )
        let multiID = UUID()
        let multiCreated = try! multiEnv.manager.create(
            from: multiEnv.manager.candidate(for: multiFixture.source),
            label: "Multi Reclaim", config: KlikProConfig.default, instanceID: multiID
        )
        let iconPNG = multiFixture.root.appendingPathComponent("icon.png")
        writeTestPNG(width: 512, height: 512, to: iconPNG)
        let withIcon = try! multiEnv.manager.updateManagedIcon(
            instanceID: multiID, edit: .image(iconPNG), config: multiCreated.config
        )
        let profile = URL(fileURLWithPath: multiCreated.instance.profileDirectory!)
        let codexHome = multiEnv.generator.codexHomeURL(for: multiID)
        let icon = multiEnv.generator.customIconURL(for: multiID)
        expect(FileManager.default.fileExists(atPath: profile.path)
               && FileManager.default.fileExists(atPath: codexHome.path)
               && FileManager.default.fileExists(atPath: icon.path),
               "the fixture must have profile, codex-home, and custom-icon artifacts")
        let multiTarget = multiEnv.manager.dataRemovalTarget(
            for: withIcon.instances.first { $0.id == multiID }!
        )
        expect(multiTarget.artifacts.count == 3,
               "an App Support target must list its three independent roots")
        let multiResult = try! multiEnv.manager.reclaimData(
            target: multiTarget, config: withIcon, mode: .trash
        )
        expect(multiResult.allRemoved && multiSpy.moved.count == 3,
               "Trash mode must move all three artifacts via the injected op")
        expect(!FileManager.default.fileExists(atPath: profile.path)
               && !FileManager.default.fileExists(atPath: codexHome.path)
               && !FileManager.default.fileExists(atPath: icon.path),
               "every listed artifact must be gone from its original location")

        // (M3b) Vault-container Trash, executed end-to-end (not just planned).
        let vaultFixture = makeVaultFixture("reclaim-vault-trash")
        defer { try? FileManager.default.removeItem(at: vaultFixture.root) }
        let vaultSpy = TrashSpy(destination: temporaryDirectory("reclaim-vault-dest"))
        let vaultEnv = makeVaultManager(
            vaultFixture, vaultRoot: vaultFixture.vault,
            processInspector: clear, trashItem: { try vaultSpy.trash($0) }
        )
        var vaultConfig = KlikProConfig.default
        vaultConfig.dataRoot = vaultFixture.vault.path
        let vaultID = UUID()
        let vaultCreated = try! vaultEnv.manager.create(
            from: vaultEnv.manager.candidate(for: vaultFixture.source),
            label: "Vault Trash", config: vaultConfig, instanceID: vaultID
        )
        let container = try! vaultEnv.generator.vaultInstanceDirectoryURL(for: vaultID)
        try! Data("login".utf8).write(
            to: container.appendingPathComponent("user-data/Login")
        )
        let vaultTarget = vaultEnv.manager.dataRemovalTarget(
            for: vaultCreated.config.instances.first { $0.id == vaultID }!
        )
        let vaultResult = try! vaultEnv.manager.reclaimData(
            target: vaultTarget, config: vaultCreated.config, mode: .trash
        )
        expect(vaultResult.allRemoved
               && vaultSpy.moved.contains(container.standardizedFileURL)
               && !FileManager.default.fileExists(atPath: container.path),
               "vault Trash must move exactly the owned container and leave nothing behind")

        // (M2) Partial failure: one artifact's op throws → row retained, reported.
        let partialFixture = makeVaultFixture("reclaim-partial")
        defer { try? FileManager.default.removeItem(at: partialFixture.root) }
        let partialSpy = TrashSpy(destination: temporaryDirectory("reclaim-partial-dest"))
        var partialPersisted: KlikProConfig?
        let partialEnv = makeVaultManager(
            partialFixture, vaultRoot: nil,
            persist: { partialPersisted = $0; return true },
            processInspector: clear,
            trashItem: { url in
                if url.lastPathComponent.hasSuffix(".icns") {
                    throw LauncherGeneratorError.unsafeRemoval
                }
                return try partialSpy.trash(url)
            }
        )
        let partialID = UUID()
        let partialCreated = try! partialEnv.manager.create(
            from: partialEnv.manager.candidate(for: partialFixture.source),
            label: "Partial Reclaim", config: KlikProConfig.default, instanceID: partialID
        )
        let partialIconPNG = partialFixture.root.appendingPathComponent("icon.png")
        writeTestPNG(width: 512, height: 512, to: partialIconPNG)
        let partialWithIcon = try! partialEnv.manager.updateManagedIcon(
            instanceID: partialID, edit: .image(partialIconPNG), config: partialCreated.config
        )
        let partialIcon = partialEnv.generator.customIconURL(for: partialID)
        let partialTarget = partialEnv.manager.dataRemovalTarget(
            for: partialWithIcon.instances.first { $0.id == partialID }!
        )
        // Ignore persists from create/updateManagedIcon; watch only the reclaim.
        partialPersisted = nil
        let partialResult = try! partialEnv.manager.reclaimData(
            target: partialTarget, config: partialWithIcon, mode: .trash
        )
        expect(!partialResult.allRemoved,
               "a single-artifact failure must make the result not-all-removed")
        expect(partialResult.perArtifact.contains {
            if case .failed = $0.outcome { return true }
            return false
        }, "the failed artifact must be reported")
        expect(FileManager.default.fileExists(atPath: partialIcon.path),
               "the artifact whose op threw must remain on disk")
        expect(partialResult.config.instances.contains { $0.id == partialID },
               "a partial removal must retain the config row")
        expect(partialPersisted == nil,
               "a partial removal must not persist a row drop")

        // (M4) A markerless target fails closed — nothing is removed.
        let markerlessFixture = makeVaultFixture("reclaim-markerless")
        defer { try? FileManager.default.removeItem(at: markerlessFixture.root) }
        let markerlessEnv = makeVaultManager(
            markerlessFixture, vaultRoot: nil, processInspector: clear
        )
        let markerlessID = UUID()
        let markerlessDir = markerlessFixture.support
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(markerlessID.uuidString.uppercased(), isDirectory: true)
        try! FileManager.default.createDirectory(
            at: markerlessDir, withIntermediateDirectories: true
        )
        try! Data("data".utf8).write(to: markerlessDir.appendingPathComponent("data"))
        let markerlessTarget = DataRemovalTarget(
            instanceID: markerlessID,
            storage: .applicationSupport,
            artifacts: [DataRemovalArtifact(
                url: markerlessDir.standardizedFileURL, kind: .profileRoot
            )],
            sizeBytes: 0,
            hasConfigRecord: false
        )
        let markerlessResult = try! markerlessEnv.manager.reclaimData(
            target: markerlessTarget, config: KlikProConfig.default, mode: .permanent
        )
        expect(!markerlessResult.allRemoved,
               "a markerless target must never be fully removed")
        expect(FileManager.default.fileExists(atPath: markerlessDir.path),
               "a markerless folder must survive a reclaim attempt (fail closed)")
    }

    /// Deep-scan metadata candidates must be exact UUID-keyed Klik PRO paths,
    /// exclude every active UUID, and use the injected reversible Trash op.
    private static func testLauncherLeftoverScanAndTrashAreOwnershipGated() {
        let root = temporaryDirectory("leftover-scan")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let trashSpy = TrashSpy(destination: root.appendingPathComponent("Trash"))
        let generator = LauncherGenerator(
            applicationSupportURL: support,
            trashItem: { try trashSpy.trash($0) }
        )
        let orphanID = UUID()
        let activeID = UUID()
        let orphanIcon = generator.customIconURL(for: orphanID)
        let activeIcon = generator.customIconURL(for: activeID)
        let orphanLock = generator.managedInstanceLockURL(for: orphanID)
        let malformedIcon = orphanIcon.deletingLastPathComponent()
            .appendingPathComponent("not-a-uuid.icns")
        for url in [orphanIcon, activeIcon, orphanLock, malformedIcon] {
            try! FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try! Data("fixture".utf8).write(to: url)
        }

        let found = generator.scanLauncherLeftovers(activeIDs: [activeID])
        expect(found.count == 2,
               "deep scan must find only the orphan UUID's exact icon and lock paths")
        expect(Set(found.map(\.instanceID)) == [orphanID],
               "active and malformed metadata must never be reported as leftovers")
        expect(!found.contains { $0.url == activeIcon || $0.url == malformedIcon },
               "ownership gating must exclude active and non-UUID filenames")

        for leftover in found {
            _ = try! generator.removeLauncherLeftover(leftover, mode: .trash)
        }
        expect(trashSpy.moved.count == 2,
               "Trash cleanup must route every scanned metadata item through the injected op")
        expect(FileManager.default.fileExists(atPath: activeIcon.path)
               && FileManager.default.fileExists(atPath: malformedIcon.path),
               "cleanup must leave excluded active and malformed files untouched")
    }

    /// Phase 2 wiring decision: `makeLauncherGenerator(forDataRoot:)` is the one
    /// switch that turns the dormant vault backend on. It must wire the vault root
    /// only for a data root that passes the fail-closed location gate, and
    /// otherwise return a no-vault generator so behavior stays byte-for-byte the
    /// pre-vault app. A no-vault generator must never be able to derive a vault
    /// path (it fails closed), which is what keeps `dataRoot = nil` inert.
    private static func testDataRootWiringFactorySelectsGenerator() {
        let id = UUID()

        // nil → no vault wired, and vault derivation fails closed.
        let none = makeLauncherGenerator(forDataRoot: nil)
        expect(none.vaultRootURL == nil,
               "a nil dataRoot must produce a generator with no wired vault root")
        do {
            _ = try none.profileURL(for: id, storage: .vault)
            expect(false, "a no-vault generator must never derive a vault path")
        } catch let error as LauncherGeneratorError {
            expect(error == .vaultUnavailable,
                   "a nil dataRoot must fail closed, never fall back to Application Support")
        } catch {
            expect(false, "unexpected derivation error: \(error)")
        }

        // A valid, writable folder outside Application Support → wired at exactly
        // that (standardized) path, the equality newInstanceStorage requires.
        let validRoot = temporaryDirectory("wiring-valid")
        defer { try? FileManager.default.removeItem(at: validRoot) }
        let vaultPath = validRoot.appendingPathComponent("Klik PRO Data", isDirectory: true).path
        let wired = makeLauncherGenerator(forDataRoot: vaultPath)
        let expectedPath = URL(fileURLWithPath: vaultPath, isDirectory: true).standardizedFileURL.path
        expect(wired.vaultRootURL?.path == expectedPath,
               "a valid dataRoot must wire the vault root at exactly that path")
        expect(vaultPathRejectionReason(vaultPath) == nil,
               "the chosen fixture path must itself pass the location gate")

        // A non-absolute path is rejected by the gate → fail-safe to no-vault.
        expect(makeLauncherGenerator(forDataRoot: "relative/data").vaultRootURL == nil,
               "a non-absolute dataRoot must fail safe to a no-vault generator")

        // A path inside Application Support is rejected by the gate → no-vault,
        // so a hand-edited config can never smuggle the vault into the wiped tree.
        let insideSupport = NSHomeDirectory()
            + "/Library/Application Support/Klik PRO Vault Wiring Test"
        expect(makeLauncherGenerator(forDataRoot: insideSupport).vaultRootURL == nil,
               "a dataRoot inside Application Support must fail safe to a no-vault generator")
    }

    // Regression: the mouse-shortcut conflict checker only recognised the legacy
    // chatGPTMouseButton / claudeMouseButton mirrors via `activeQuickLaunchTarget`. A
    // managed App Profile instance owns its mouse slot directly on the instance, so a
    // Gesture button bound to a launchable managed Claude instance ("Claude T") fell
    // through to the Gesture slot's stored base combo and flagged Middle=Gesture-base as
    // a phantom Duplicate — even though the runtime launches the instance and never fires
    // that combo. The fix mirrors the input helper: a slot served by a launchable managed
    // instance is a pure launch action, so the checker resolves it to .ok and excludes it
    // from the keyboard-combo duplicate comparison (never leaking its base combo).
    private static func testManagedInstanceReleasesPhantomDuplicateBadge() {
        var config = KlikProConfig.default
        config.specialFeatureEnabled = true
        // The managed instance owns the Gesture slot on the instance itself; the legacy
        // mouse mirrors stay unassigned, exactly as in the reported configuration.
        config.chatGPTMouseButton = nil
        config.claudeMouseButton = nil
        // Reproduce the report: Middle carries the Gesture slot's default base combo.
        config.middleButton.combo = config.gestureButton.combo
        expect(config.middleButton.combo.signature == config.gestureButton.combo.signature,
               "fixture must pit Middle against the Gesture slot's stale base combo")

        // Placeholder hotkey shared by managed instances that have no assigned hotkey —
        // the disabled default. Two managed rows carrying it must NOT duplicate each other.
        let placeholderHotkey = ShortcutMapping(
            enabled: false,
            combo: KeyCombo(
                keyCode: 0,
                keyDisplay: "A",
                command: false,
                option: false,
                control: true,
                shift: false
            )
        )
        func makeManagedClaude(
            id: UUID,
            label: String,
            mouseButton: QuickLaunchMouseButton
        ) -> AppProfileInstance {
            AppProfileInstance(
                id: id,
                label: label,
                launcherKind: .managed,
                launcherPath: "/tmp/Launchers/\(id.uuidString).app",
                profileDirectory: "/tmp/Profiles/\(id.uuidString)",
                profileOwnership: .managed,
                source: AppProfileSource(
                    bundleIdentifier: "com.anthropic.claudefordesktop",
                    bundleURL: "/Applications/Claude.app"
                ),
                pinToMenuBar: false,
                hotkey: placeholderHotkey,
                mouseButton: mouseButton
            )
        }
        let gestureInstanceID = UUID()
        let forwardInstanceID = UUID()
        config.instances = [
            makeManagedClaude(id: gestureInstanceID, label: "Claude T", mouseButton: .gesture),
            makeManagedClaude(id: forwardInstanceID, label: "Claude G", mouseButton: .forward),
        ]

        // Launchable managed instances ⇒ the runtime launches them, so each mouse slot
        // releases its base combo. Middle must no longer read as a Duplicate, and the two
        // managed rows must not duplicate each other via their shared placeholder hotkey.
        let launchableIDs = launchableAppProfileInstanceIDs(
            in: config,
            legacyTargetIsAvailable: { _ in false },
            instanceIsLaunchable: { _ in true }
        )
        expect(launchableIDs == [gestureInstanceID, forwardInstanceID],
               "launchable managed instances must be treated as active launch sources")
        let launchableStatuses = evaluateShortcutConflicts(
            candidate: config,
            persisted: config,
            browserExtensionShortcuts: [],
            specialFeatureActive: true,
            activeInstanceIDs: launchableIDs
        )
        expect(launchableStatuses[.middleButton] == .ok,
               "Middle must not be a phantom Duplicate when the Gesture launches Claude T")
        expect(launchableStatuses[.gestureButton] == .ok,
               "the Gesture row must follow its managed launcher, not leak its stale base combo")
        expect(launchableStatuses[.forwardButton] == .ok,
               "two managed launch rows must not duplicate each other via a shared placeholder hotkey")

        // Negative control: a genuinely unlaunchable instance leaves nothing active, so
        // the runtime reverts the Gesture to its base combo and the real Duplicate stands.
        let unavailableIDs = launchableAppProfileInstanceIDs(
            in: config,
            legacyTargetIsAvailable: { _ in false },
            instanceIsLaunchable: { _ in false }
        )
        expect(unavailableIDs.isEmpty,
               "an unlaunchable managed instance must not be treated as an active launch source")
        let unavailableStatuses = evaluateShortcutConflicts(
            candidate: config,
            persisted: config,
            browserExtensionShortcuts: [],
            specialFeatureActive: true,
            activeInstanceIDs: unavailableIDs
        )
        expect(unavailableStatuses[.middleButton] == .duplicate,
               "a genuinely unlaunchable Gesture must still surface the Middle Duplicate")
        expect(unavailableStatuses[.gestureButton] == .duplicate,
               "the reverted Gesture base combo must also report the real conflict")
    }
}
