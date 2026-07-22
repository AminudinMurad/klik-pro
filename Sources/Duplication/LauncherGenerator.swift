import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum LauncherGeneratorError: Error, Equatable {
    case notManaged
    case invalidProfileOwnership
    case sourceMismatch
    case disallowedEnvironmentKey(String)
    case launcherExecutableUnavailable
    case alreadyExists
    case materializationFailed
    case unsafeRemoval
    /// A user-supplied icon image could not be decoded, or is smaller than
    /// `customIconMinimumPixelSize` on its shortest side.
    case iconImageInvalid
    /// A `.vault` instance was handled by a generator that has no vault root
    /// configured (or the volume is absent). Always fail closed — never fall
    /// back to Application Support paths for vault-stored data.
    case vaultUnavailable
}

struct ManagedLauncherSpecification: Equatable {
    let instanceID: UUID
    let bundleIdentifier: String
    let displayName: String
    let launcherURL: URL
    let profileURL: URL
    let sourceBundleURL: URL
    let arguments: [String]
    let environment: [String: String]
    let storage: AppProfileStorage
}

struct ManagedLauncherMaterialization: Equatable {
    let launcherURL: URL
    let profileURL: URL
    let iconURL: URL?
}

struct ManagedLauncherRemoval: Equatable {
    fileprivate let instanceID: UUID
    fileprivate let originalURL: URL
    fileprivate let stagedURL: URL
}

struct ManagedProfileRemoval: Equatable {
    fileprivate let instanceID: UUID
    fileprivate let originalURL: URL
    fileprivate let stagedURL: URL
    fileprivate let storage: AppProfileStorage
}

/// One reclaimable data root owned by an instance. Each kind carries its own
/// validation rule: `profileRoot` (and the vault `container`, whose `user-data`
/// holds the marker) is ownership-marker gated; `codexHome` and `customIcon`
/// are validated only by their standardized position directly under the exact
/// Klik PRO root with the UUID-derived name. Removal is per-artifact so a
/// partial failure never cascades.
enum OwnedArtifactKind: Equatable {
    case profileRoot
    case codexHome
    case customIcon
    case vaultContainer
}

/// How an owned artifact is reclaimed. `.trash` is reversible (macOS Trash via
/// the injected op); `.permanent` is an unrecoverable `removeItem`. The mode is
/// always the user's explicit per-action choice.
enum DataRemovalMode: Equatable {
    case trash
    case permanent
}

/// Materializes the UUID-keyed launcher bundle described by the RFC. The executable
/// is a precompiled resource shipped inside Klik PRO; labels and environment values
/// are serialized into property lists and never interpolated into a shell command.
struct LauncherGenerator {
    // Q7 decision (2026-07-16): a fixed allow-list of variables the proven
    // hand-made wrappers set. Widening further needs a new owner decision;
    // CLAUDE_CONFIG_DIR was added by the 2026-07-19 visible-home decision.
    static let allowedEnvironmentKeys: Set<String> = [
        "CODEX_HOME",
        "CODEX_ELECTRON_USER_DATA_PATH",
        "CLAUDE_CONFIG_DIR",
    ]
    static let profileOwnershipMarkerName = ".klik-pro-owned-profile"
    static let payloadResourceName = "LaunchSpec.plist"
    static let executableName = "KlikProManagedLauncher"
    static let appleEventsUsageDescription =
        "Klik PRO reopens the selected App Profile's existing window without launching a duplicate."

    let applicationSupportURL: URL
    let visibleLaunchersRootURL: URL
    /// Where visible home symlinks (`~/.claude-a` style) are created. The real
    /// home directory only when this generator manages the real support tree;
    /// any other (test) tree keeps its links sandboxed beside it.
    let homeSymlinkRootURL: URL
    /// Durable Data Vault root for instances marked `storage == .vault`.
    /// nil means no vault is configured; `.applicationSupport` instances never
    /// consult it, so the default data root keeps today's derivation exactly.
    let vaultRootURL: URL?
    private let fileManager: FileManager
    private let launcherExecutableURL: URL?
    private let signLauncher: (URL) -> Bool
    /// Injectable Move-to-Trash op. Production uses `FileManager.trashItem`;
    /// tests inject a temp-directory fake so a test run never touches the real
    /// Trash and can prove no permanent `removeItem` happened. Returns the
    /// resulting in-Trash URL (nil if the platform reports none).
    private let trashItem: (URL) throws -> URL?

    init(
        applicationSupportURL: URL = URL(
            fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Klik PRO",
            isDirectory: true
        ),
        visibleLaunchersRootURL: URL? = nil,
        homeSymlinkRootURL: URL? = nil,
        vaultRootURL: URL? = nil,
        fileManager: FileManager = .default,
        launcherExecutableURL: URL? = Bundle.main.url(
            forResource: LauncherGenerator.executableName,
            withExtension: nil
        ),
        signLauncher: @escaping (URL) -> Bool = LauncherGenerator.adHocSign,
        trashItem: @escaping (URL) throws -> URL? = LauncherGenerator.defaultTrash
    ) {
        let support = applicationSupportURL.standardizedFileURL
        self.applicationSupportURL = support
        if let visibleLaunchersRootURL {
            self.visibleLaunchersRootURL = visibleLaunchersRootURL.standardizedFileURL
        } else if support.path == NSHomeDirectory() + "/Library/Application Support/Klik PRO" {
            self.visibleLaunchersRootURL = URL(
                fileURLWithPath: NSHomeDirectory() + "/Applications/Klik PRO",
                isDirectory: true
            ).standardizedFileURL
        } else {
            self.visibleLaunchersRootURL = support
                .appendingPathComponent("Visible Launchers", isDirectory: true)
        }
        if let homeSymlinkRootURL {
            self.homeSymlinkRootURL = homeSymlinkRootURL.standardizedFileURL
        } else if support.path == NSHomeDirectory() + "/Library/Application Support/Klik PRO" {
            self.homeSymlinkRootURL = URL(
                fileURLWithPath: NSHomeDirectory(),
                isDirectory: true
            ).standardizedFileURL
        } else {
            self.homeSymlinkRootURL = support
                .appendingPathComponent("Home Symlinks", isDirectory: true)
        }
        self.vaultRootURL = vaultRootURL?.standardizedFileURL
        self.fileManager = fileManager
        self.launcherExecutableURL = launcherExecutableURL?.standardizedFileURL
        self.signLauncher = signLauncher
        self.trashItem = trashItem
    }

    /// Production Move-to-Trash: reversible, never a permanent delete.
    static func defaultTrash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    func launcherURL(for id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("Launchers", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased() + ".app", isDirectory: true)
    }

    func launcherURL(for id: UUID, label: String) -> URL {
        visibleLaunchersRootURL
            .appendingPathComponent(Self.safeLauncherFileName(for: label), isDirectory: true)
    }

    static func safeLauncherFileName(for label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/:\u{0}")
            .union(.controlCharacters)
        let cleaned = trimmed
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let base = cleaned.isEmpty ? "Klik PRO App" : String(cleaned.prefix(80))
        let visible = base.hasPrefix(".") ? "Klik PRO " + base.drop(while: { $0 == "." }) : base
        return visible.hasSuffix(".app") ? visible : visible + ".app"
    }

    func profileURL(for id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
    }

    /// The UUID-keyed sibling home a rule's `{codexHomeDir}` placeholder
    /// expands to. Deliberately outside `Profiles/<UUID>` so the target app's
    /// own symlinks (plugin caches, tmp wrappers) never sit inside the
    /// symlink-rejecting profile-deletion path.
    func codexHomeURL(for id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("CodexHomes", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
    }

    // MARK: Per-instance data root (Durable Data Vault, schema 11)

    /// `<Vault>/Instances/<UUID>` — the app-neutral per-instance container a
    /// vault-stored instance keeps its `user-data` and `config-home` in.
    func vaultInstanceDirectoryURL(for id: UUID) throws -> URL {
        guard let vaultRootURL else { throw LauncherGeneratorError.vaultUnavailable }
        return vaultRootURL
            .appendingPathComponent("Instances", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
    }

    /// Default data root: for `.applicationSupport` storage this is the
    /// UNCHANGED Application Support derivation above (`Profiles/<UUID>`),
    /// byte-for-byte today's layout. Only `.vault` instances derive into the
    /// vault, and only from its current root — never from a baked path.
    func profileURL(for id: UUID, storage: AppProfileStorage) throws -> URL {
        switch storage {
        case .applicationSupport:
            return profileURL(for: id)
        case .vault:
            return try vaultInstanceDirectoryURL(for: id)
                .appendingPathComponent("user-data", isDirectory: true)
        }
    }

    func codexHomeURL(for id: UUID, storage: AppProfileStorage) throws -> URL {
        switch storage {
        case .applicationSupport:
            return codexHomeURL(for: id)
        case .vault:
            return try vaultInstanceDirectoryURL(for: id)
                .appendingPathComponent("config-home", isDirectory: true)
        }
    }

    /// Where a validated sibling home must actually resolve to: the resolved
    /// storage base plus literal path components, so a swapped-in symlink
    /// anywhere under `CodexHomes/` (or a vault's `Instances/`) can never
    /// redirect creation or removal outside the instance's own tree.
    private func resolvedExpectedCodexHome(
        for id: UUID,
        storage: AppProfileStorage
    ) throws -> URL {
        switch storage {
        case .applicationSupport:
            return applicationSupportURL.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent("CodexHomes", isDirectory: true)
                .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
        case .vault:
            guard let vaultRootURL else { throw LauncherGeneratorError.vaultUnavailable }
            return vaultRootURL.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent("Instances", isDirectory: true)
                .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
                .appendingPathComponent("config-home", isDirectory: true)
        }
    }

    /// Creates (or validates) the `CodexHomes` root as a private directory.
    /// An existing symlink, dangling link, or non-directory at the root — or a
    /// root that does not resolve to a direct child of the resolved
    /// application-support tree — fails closed before anything is created.
    private func validatedCodexHomesRoot() throws -> URL {
        let root = applicationSupportURL
            .appendingPathComponent("CodexHomes", isDirectory: true)
        if let type = (try? fileManager.attributesOfItem(atPath: root.path))?[.type]
            as? FileAttributeType {
            // lstat semantics: a symlink (even dangling) reports as a symlink
            // here and is rejected, never followed.
            guard type == .typeDirectory else {
                throw LauncherGeneratorError.materializationFailed
            }
        } else {
            try createPrivateDirectory(root)
        }
        let expected = applicationSupportURL.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("CodexHomes", isDirectory: true)
        guard root.resolvingSymlinksInPath().standardizedFileURL == expected else {
            throw LauncherGeneratorError.materializationFailed
        }
        return root
    }

    /// Creates the instance's fresh sibling home beneath a validated root and
    /// proves the result is a resolution-stable, non-symlink direct child
    /// before returning it.
    private func createFreshCodexHome(
        for id: UUID,
        storage: AppProfileStorage
    ) throws -> URL {
        let home = try codexHomeURL(for: id, storage: storage)
        switch storage {
        case .applicationSupport:
            _ = try validatedCodexHomesRoot()
        case .vault:
            try createPrivateDirectory(try vaultInstanceDirectoryURL(for: id))
        }
        guard (try? fileManager.attributesOfItem(atPath: home.path)) == nil else {
            throw LauncherGeneratorError.alreadyExists
        }
        try fileManager.createDirectory(
            at: home,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try home.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              home.resolvingSymlinksInPath().standardizedFileURL
                == (try resolvedExpectedCodexHome(for: id, storage: storage)) else {
            throw LauncherGeneratorError.materializationFailed
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
        return home
    }

    /// The single sibling-home cleanup path (rollback and materialize-catch):
    /// removes the home only when it is a real directory (lstat, never
    /// following links), resolves exactly to the expected in-tree path, and is
    /// still EMPTY. Anything else is retained fail-safe.
    private func removeFreshCodexHome(for id: UUID, storage: AppProfileStorage) {
        guard let home = try? codexHomeURL(for: id, storage: storage),
              let expected = try? resolvedExpectedCodexHome(for: id, storage: storage),
              let type = (try? fileManager.attributesOfItem(atPath: home.path))?[.type]
                as? FileAttributeType,
              type == .typeDirectory,
              home.resolvingSymlinksInPath().standardizedFileURL == expected,
              let contents = try? fileManager.contentsOfDirectory(atPath: home.path),
              contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: home)
    }

    /// Ensures the instance's sibling home exists when the given (about-to-be
    /// applied) environment references it. An existing home is accepted only
    /// when it is a real, resolution-stable in-tree directory; a missing one
    /// is created through the same validated fresh-create path materialize
    /// uses. Used by the launch-time healing pass, which must never touch
    /// profile data.
    func ensureCodexHome(
        for id: UUID,
        environment: [String: String],
        storage: AppProfileStorage = .applicationSupport
    ) -> Bool {
        guard let home = try? codexHomeURL(for: id, storage: storage) else { return false }
        let referencesHome = environment.values.contains { value in
            value == home.path || value.hasPrefix(home.path + "/")
        }
        guard referencesHome else { return true }
        if let type = (try? fileManager.attributesOfItem(atPath: home.path))?[.type]
            as? FileAttributeType {
            guard let expected = try? resolvedExpectedCodexHome(for: id, storage: storage) else {
                return false
            }
            return type == .typeDirectory
                && home.resolvingSymlinksInPath().standardizedFileURL == expected
        }
        return (try? createFreshCodexHome(for: id, storage: storage)) != nil
    }

    /// Rewrites a generated launcher's baked LaunchSpec payload so Dock,
    /// Spotlight, and Finder launches pick up a healed environment too, then
    /// re-signs the bundle. The original payload is restored if signing fails.
    func updateEnvironment(for instance: AppProfileInstance) throws {
        let spec = try specification(for: instance)
        let launcherURL = try validatedLauncherURL(for: instance)
        guard let compatibilityRuleID = instance.compatibilityRuleID,
              !compatibilityRuleID.isEmpty else {
            throw LauncherGeneratorError.materializationFailed
        }
        let payloadURL = launcherURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(Self.payloadResourceName)
        let original = try Data(contentsOf: payloadURL)
        let payload = ManagedLauncherPayload(
            sourceBundlePath: spec.sourceBundleURL.path,
            arguments: spec.arguments,
            environment: spec.environment,
            compatibilityRuleID: compatibilityRuleID,
            profileDirectory: spec.profileURL.path,
            profileStorage: spec.storage == .vault ? .vault : .applicationSupport
        )
        let payloadData = try PropertyListEncoder().encode(payload)
        do {
            try payloadData.write(to: payloadURL, options: .atomic)
            guard signLauncher(launcherURL) else {
                throw LauncherGeneratorError.materializationFailed
            }
        } catch {
            try? original.write(to: payloadURL, options: .atomic)
            _ = signLauncher(launcherURL)
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Refreshes an older generated launcher with the current embedded runner,
    /// signed LaunchSpec storage contract, and Apple-events purpose string, then
    /// re-signs it. Profile data, custom icon, and label are never touched.
    /// Returns true when a refresh was applied, false when already current.
    /// Fail-safe: executable bytes, metadata, and permissions are restored if
    /// re-signing fails.
    @discardableResult
    func refreshLauncherRuntimeIfStale(for instance: AppProfileInstance) throws -> Bool {
        let spec = try specification(for: instance)
        guard let runner = launcherExecutableURL,
              fileManager.isExecutableFile(atPath: runner.path) else {
            throw LauncherGeneratorError.launcherExecutableUnavailable
        }
        let launcherURL = try validatedLauncherURL(for: instance)
        let embedded = launcherURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(Self.executableName, isDirectory: false)
        let current = try Data(contentsOf: runner)
        let existing = try Data(contentsOf: embedded)
        let attributes = try fileManager.attributesOfItem(atPath: embedded.path)
        guard let originalPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
            throw LauncherGeneratorError.materializationFailed
        }
        let infoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        let originalInfo = try Data(contentsOf: infoURL)
        guard var info = try? PropertyListSerialization.propertyList(
            from: originalInfo, options: [], format: nil
        ) as? [String: Any] else {
            throw LauncherGeneratorError.materializationFailed
        }
        guard let compatibilityRuleID = instance.compatibilityRuleID,
              !compatibilityRuleID.isEmpty else {
            throw LauncherGeneratorError.materializationFailed
        }
        let payloadURL = launcherURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(Self.payloadResourceName)
        let originalPayload = try Data(contentsOf: payloadURL)
        let expectedPayload = try PropertyListEncoder().encode(ManagedLauncherPayload(
            sourceBundlePath: spec.sourceBundleURL.path,
            arguments: spec.arguments,
            environment: spec.environment,
            compatibilityRuleID: compatibilityRuleID,
            profileDirectory: spec.profileURL.path,
            profileStorage: spec.storage == .vault ? .vault : .applicationSupport
        ))
        let runnerIsCurrent = existing == current
        let payloadIsCurrent = originalPayload == expectedPayload
        let purposeStringIsCurrent = info["NSAppleEventsUsageDescription"] as? String
            == Self.appleEventsUsageDescription
        if runnerIsCurrent && payloadIsCurrent && purposeStringIsCurrent { return false }
        do {
            if !runnerIsCurrent {
                try current.write(to: embedded, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: embedded.path
                )
            }
            if !purposeStringIsCurrent {
                info["NSAppleEventsUsageDescription"] = Self.appleEventsUsageDescription
                let updatedInfo = try PropertyListSerialization.data(
                    fromPropertyList: info, format: .xml, options: 0
                )
                try updatedInfo.write(to: infoURL, options: .atomic)
            }
            if !payloadIsCurrent {
                try expectedPayload.write(to: payloadURL, options: .atomic)
            }
            guard signLauncher(launcherURL) else {
                throw LauncherGeneratorError.materializationFailed
            }
            refreshLaunchServicesRegistration(for: launcherURL)
            return true
        } catch {
            try? existing.write(to: embedded, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: originalPermissions], ofItemAtPath: embedded.path
            )
            try? originalInfo.write(to: infoURL, options: .atomic)
            try? originalPayload.write(to: payloadURL, options: .atomic)
            _ = signLauncher(launcherURL)
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Derives the visible dot-folder name a profile's home symlink uses,
    /// e.g. prefix "claude" + label "Claude A" → ".claude-a". A leading family
    /// word in the label is folded into the prefix so "ChatGPT B" becomes
    /// ".codex-b" rather than ".codex-chatgpt-b".
    static func homeSymlinkName(prefix: String, label: String) -> String {
        let slug = label.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        var remainder = slug
        for family in [prefix, "chatgpt", "claude", "codex"] {
            if remainder == family {
                remainder = ""
                break
            }
            if remainder.hasPrefix(family + "-") {
                remainder = String(remainder.dropFirst(family.count + 1))
                break
            }
        }
        return remainder.isEmpty ? "." + prefix : "." + prefix + "-" + remainder
    }

    /// Creates the profile's visible home symlink (2026-07-19 owner decision):
    /// a dot-folder link in `~` pointing at the UUID-keyed sibling home, so
    /// multi-account scanners that look for `~/.claude-*` / `~/.codex-*`
    /// detect the generated profile. The link is created only when the
    /// instance's environment actually references its sibling home; a name
    /// collision with any real item is never adopted — numbered suffixes are
    /// tried instead, and giving up is non-fatal (`nil`). Ownership is carried
    /// by the link's destination, never by persisted state.
    @discardableResult
    func createHomeSymlink(
        for instanceID: UUID,
        environment: [String: String],
        preferredName: String,
        storage: AppProfileStorage = .applicationSupport
    ) -> URL? {
        guard let home = try? codexHomeURL(for: instanceID, storage: storage) else {
            return nil
        }
        let referencesHome = environment.values.contains { value in
            value == home.path || value.hasPrefix(home.path + "/")
        }
        guard referencesHome,
              preferredName.hasPrefix("."),
              preferredName.count > 1,
              !preferredName.contains("/") else {
            return nil
        }
        // The real home directory already exists and must never be re-created
        // or re-permissioned; only a sandboxed test root is provisioned here.
        if !fileManager.fileExists(atPath: homeSymlinkRootURL.path) {
            guard (try? createPrivateDirectory(homeSymlinkRootURL)) != nil else { return nil }
        }
        for attempt in 0..<10 {
            let name = attempt == 0 ? preferredName : preferredName + "-\(attempt + 1)"
            let link = homeSymlinkRootURL.appendingPathComponent(name, isDirectory: false)
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
                // An existing symlink already pointing at this instance's home
                // is ours (possibly from an interrupted earlier run) — reuse it.
                if destination == home.path { return link }
                continue
            }
            if fileManager.fileExists(atPath: link.path) { continue }
            do {
                try fileManager.createSymbolicLink(
                    atPath: link.path,
                    withDestinationPath: home.path
                )
                return link
            } catch {
                continue
            }
        }
        return nil
    }

    /// Removes every home symlink owned by the instance: only top-level
    /// dot-entries in the symlink root that are symlinks (lstat, never
    /// followed) whose literal destination is this instance's sibling home.
    /// Real directories and anyone else's links are untouched by construction.
    func removeHomeSymlinks(
        for instanceID: UUID,
        storage: AppProfileStorage = .applicationSupport
    ) {
        guard let home = try? codexHomeURL(for: instanceID, storage: storage) else { return }
        removeHomeSymlinks(withDestination: home)
    }

    /// Destination-verified removal core. Also used when a vault moved: the
    /// previously recorded home path identifies the stale links, and ownership
    /// is still proven purely by each link's literal destination.
    func removeHomeSymlinks(withDestination home: URL) {
        guard let entries = try? fileManager.contentsOfDirectory(
            atPath: homeSymlinkRootURL.path
        ) else {
            return
        }
        for entry in entries where entry.hasPrefix(".") {
            let link = homeSymlinkRootURL.appendingPathComponent(entry, isDirectory: false)
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path),
                  destination == home.path else {
                continue
            }
            try? fileManager.removeItem(at: link)
        }
    }

    func specification(for instance: AppProfileInstance) throws -> ManagedLauncherSpecification {
        guard instance.launcherKind == .managed else { throw LauncherGeneratorError.notManaged }
        guard instance.profileOwnership == .managed,
              let storedProfileDirectory = instance.profileDirectory else {
            throw LauncherGeneratorError.invalidProfileOwnership
        }

        let storedLauncher = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
            .standardizedFileURL
        let expectedProfile = try profileURL(for: instance.id, storage: instance.storage)
        let storedProfile = URL(fileURLWithPath: storedProfileDirectory, isDirectory: true)
            .standardizedFileURL
        guard isAllowedManagedLauncherPath(
                storedLauncher,
                instanceID: instance.id,
                label: instance.label
              ),
              storedProfile.path == expectedProfile.path else {
            throw LauncherGeneratorError.sourceMismatch
        }

        for key in instance.environmentOverrides.keys
            where !Self.allowedEnvironmentKeys.contains(key) {
            throw LauncherGeneratorError.disallowedEnvironmentKey(key)
        }

        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        return ManagedLauncherSpecification(
            instanceID: instance.id,
            bundleIdentifier: "local.klik-pro.launcher.i"
                + instance.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            displayName: instance.label,
            launcherURL: storedLauncher,
            profileURL: expectedProfile,
            sourceBundleURL: sourceURL,
            arguments: ["--user-data-dir=" + expectedProfile.path],
            environment: instance.environmentOverrides,
            storage: instance.storage
        )
    }

    func materialize(
        instance: AppProfileInstance,
        sourceApp: InstalledApp
    ) throws -> ManagedLauncherMaterialization {
        let spec = try specification(for: instance)
        guard spec.sourceBundleURL == sourceApp.bundleURL.standardizedFileURL,
              spec.sourceBundleURL.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: spec.sourceBundleURL.path) else {
            throw LauncherGeneratorError.sourceMismatch
        }
        guard let runner = launcherExecutableURL,
              fileManager.isExecutableFile(atPath: runner.path) else {
            throw LauncherGeneratorError.launcherExecutableUnavailable
        }
        guard let compatibilityRuleID = instance.compatibilityRuleID,
              !compatibilityRuleID.isEmpty else {
            throw LauncherGeneratorError.materializationFailed
        }
        // Q5 decision (2026-07-16): when the rule-derived environment points a
        // variable at the instance's sibling home, pre-create that directory
        // here so the launched app can never fall back to its default home.
        let expectedCodexHome = try codexHomeURL(for: instance.id, storage: instance.storage)
        let needsCodexHome = instance.environmentOverrides.values.contains { value in
            value == expectedCodexHome.path
                || value.hasPrefix(expectedCodexHome.path + "/")
        }
        guard !fileManager.fileExists(atPath: spec.launcherURL.path),
              !fileManager.fileExists(atPath: spec.profileURL.path),
              !(needsCodexHome && fileManager.fileExists(atPath: expectedCodexHome.path)) else {
            throw LauncherGeneratorError.alreadyExists
        }

        var profileCreated = false
        var codexHomeCreated = false
        do {
            try createPrivateDirectory(spec.profileURL.deletingLastPathComponent())
            try createPrivateDirectory(spec.profileURL)
            profileCreated = true
            try writeProfileMarker(instanceID: instance.id, profileURL: spec.profileURL)
            if needsCodexHome {
                _ = try createFreshCodexHome(for: instance.id, storage: instance.storage)
                codexHomeCreated = true
            }
            let iconURL = try buildLauncherBundle(
                spec: spec,
                compatibilityRuleID: compatibilityRuleID
            )
            return ManagedLauncherMaterialization(
                launcherURL: spec.launcherURL,
                profileURL: spec.profileURL,
                iconURL: iconURL
            )
        } catch let error as LauncherGeneratorError {
            // Flag-guarded AND validated: only the still-empty, in-tree
            // directory this exact call just created can be removed.
            if codexHomeCreated {
                removeFreshCodexHome(for: instance.id, storage: instance.storage)
            }
            if profileCreated {
                try? removeFreshProfile(
                    instanceID: instance.id,
                    at: spec.profileURL,
                    storage: instance.storage
                )
            }
            throw error
        } catch {
            if codexHomeCreated {
                removeFreshCodexHome(for: instance.id, storage: instance.storage)
            }
            if profileCreated {
                try? removeFreshProfile(
                    instanceID: instance.id,
                    at: spec.profileURL,
                    storage: instance.storage
                )
            }
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Adopt/recovery path (vault reinstall): rebuilds ONLY the ephemeral
    /// launcher bundle for an instance whose validated owned profile already
    /// exists. Profile data and config-home contents are never created, moved,
    /// or modified here — the vault's current path is baked into a fresh
    /// launcher instead of trusting any earlier one.
    func regenerateLauncher(
        instance: AppProfileInstance,
        sourceApp: InstalledApp
    ) throws -> ManagedLauncherMaterialization {
        let spec = try specification(for: instance)
        guard spec.sourceBundleURL == sourceApp.bundleURL.standardizedFileURL,
              spec.sourceBundleURL.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: spec.sourceBundleURL.path) else {
            throw LauncherGeneratorError.sourceMismatch
        }
        guard let compatibilityRuleID = instance.compatibilityRuleID,
              !compatibilityRuleID.isEmpty else {
            throw LauncherGeneratorError.materializationFailed
        }
        try validateOwnedProfile(
            instanceID: instance.id,
            at: spec.profileURL,
            storage: instance.storage
        )
        // A stale launcher can still occupy the target path — a compatibility-rule
        // mismatch or a structurally broken bundle both leave it on disk. Allow the
        // rebuild to replace it, but only when it is a Klik PRO-owned generated
        // launcher; never overwrite unrelated content at that path.
        var replaceExisting = false
        if itemExistsIncludingDanglingSymlink(at: spec.launcherURL) {
            guard (try? isSafeGeneratedLauncher(
                spec.launcherURL,
                expectedBundleID: spec.bundleIdentifier
            )) == true else {
                throw LauncherGeneratorError.alreadyExists
            }
            replaceExisting = true
        }
        let iconURL = try buildLauncherBundle(
            spec: spec,
            compatibilityRuleID: compatibilityRuleID,
            replaceExisting: replaceExisting
        )
        return ManagedLauncherMaterialization(
            launcherURL: spec.launcherURL,
            profileURL: spec.profileURL,
            iconURL: iconURL
        )
    }

    /// Shared launcher-bundle construction: builds the .app via a hidden
    /// temporary bundle, signs it, moves it into place, and registers it.
    /// Returns the copied icon's final URL, if the source app provided one.
    private func buildLauncherBundle(
        spec: ManagedLauncherSpecification,
        compatibilityRuleID: String,
        replaceExisting: Bool = false
    ) throws -> URL? {
        guard let runner = launcherExecutableURL,
              fileManager.isExecutableFile(atPath: runner.path) else {
            throw LauncherGeneratorError.launcherExecutableUnavailable
        }
        let launchersRoot = spec.launcherURL.deletingLastPathComponent()
        let temporaryLauncher = launchersRoot.appendingPathComponent(
            "." + spec.instanceID.uuidString + ".tmp-" + UUID().uuidString + ".app",
            isDirectory: true
        )
        var temporaryCreated = false
        do {
            try createPrivateDirectory(launchersRoot)
            let contents = temporaryLauncher.appendingPathComponent("Contents", isDirectory: true)
            let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
            let resources = contents.appendingPathComponent("Resources", isDirectory: true)
            try createPrivateDirectory(macOS)
            try createPrivateDirectory(resources)
            temporaryCreated = true

            let copiedRunner = macOS.appendingPathComponent(Self.executableName)
            try fileManager.copyItem(at: runner, to: copiedRunner)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copiedRunner.path)

            let payload = ManagedLauncherPayload(
                sourceBundlePath: spec.sourceBundleURL.path,
                arguments: spec.arguments,
                environment: spec.environment,
                compatibilityRuleID: compatibilityRuleID,
                profileDirectory: spec.profileURL.path,
                profileStorage: spec.storage == .vault ? .vault : .applicationSupport
            )
            let payloadData = try PropertyListEncoder().encode(payload)
            try payloadData.write(
                to: resources.appendingPathComponent(Self.payloadResourceName),
                options: .atomic
            )

            // A persisted custom icon (user-chosen via Change Icon) wins over
            // the source app's icon, so healing and adoption keep it.
            let copiedIcon: URL?
            let customIcon = customIconURL(for: spec.instanceID)
            if fileManager.fileExists(atPath: customIcon.path) {
                let destination = resources.appendingPathComponent("AppIcon.icns")
                try fileManager.copyItem(at: customIcon, to: destination)
                copiedIcon = destination
            } else {
                copiedIcon = try copySourceIconIfAvailable(
                    sourceBundleURL: spec.sourceBundleURL,
                    resourcesURL: resources
                )
            }
            var info: [String: Any] = [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": spec.displayName,
                "CFBundleExecutable": Self.executableName,
                "CFBundleIdentifier": spec.bundleIdentifier,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": spec.displayName,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "13.0",
                "LSUIElement": true,
                "NSAppleEventsUsageDescription": Self.appleEventsUsageDescription,
            ]
            if copiedIcon != nil { info["CFBundleIconFile"] = "AppIcon" }
            let infoData = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try infoData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)

            guard signLauncher(temporaryLauncher) else {
                throw LauncherGeneratorError.materializationFailed
            }
            if replaceExisting, itemExistsIncludingDanglingSymlink(at: spec.launcherURL) {
                // Repair may target a stale launcher still on disk. Move the old
                // owned bundle aside only after the replacement is built and
                // signed, then swap it in; restore the old copy if the swap fails.
                let asideURL = launchersRoot.appendingPathComponent(
                    "." + spec.instanceID.uuidString + ".replacing-" + UUID().uuidString + ".app",
                    isDirectory: true
                )
                try fileManager.moveItem(at: spec.launcherURL, to: asideURL)
                do {
                    try fileManager.moveItem(at: temporaryLauncher, to: spec.launcherURL)
                } catch {
                    try? fileManager.moveItem(at: asideURL, to: spec.launcherURL)
                    throw error
                }
                try? fileManager.removeItem(at: asideURL)
            } else {
                try fileManager.moveItem(at: temporaryLauncher, to: spec.launcherURL)
            }
            refreshLaunchServicesRegistration(for: spec.launcherURL)
            return copiedIcon.map {
                spec.launcherURL.appendingPathComponent(
                    "Contents/Resources/" + $0.lastPathComponent
                )
            }
        } catch let error as LauncherGeneratorError {
            if temporaryCreated { try? fileManager.removeItem(at: temporaryLauncher) }
            throw error
        } catch {
            if temporaryCreated { try? fileManager.removeItem(at: temporaryLauncher) }
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Revalidates a persisted managed launcher before exposing it to Launch
    /// Services. Legacy external wrappers deliberately bypass this managed-path
    /// contract and continue to be opened verbatim by their existing path.
    func validatedLauncherURL(for instance: AppProfileInstance) throws -> URL {
        let spec = try specification(for: instance)
        guard fileManager.fileExists(atPath: spec.launcherURL.path),
              try isSafeGeneratedLauncher(
                spec.launcherURL,
                expectedBundleID: spec.bundleIdentifier
              ) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        let executable = spec.launcherURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(Self.executableName, isDirectory: false)
        let values = try? executable.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              fileManager.isExecutableFile(atPath: executable.path) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        return spec.launcherURL
    }

    /// Updates the generated launcher's visible name and moves the user-facing app
    /// bundle when needed. UUID-keyed profile and Codex data remain unchanged.
    func updateDisplayName(
        from previous: AppProfileInstance,
        to updated: AppProfileInstance
    ) throws -> URL {
        let originalLauncherURL = try validatedLauncherURL(for: previous)
        let targetLauncherURL = launcherURL(for: updated.id, label: updated.label)
            .standardizedFileURL
        guard isAllowedManagedLauncherPath(
            targetLauncherURL,
            instanceID: updated.id,
            label: updated.label
        ) else {
            throw LauncherGeneratorError.materializationFailed
        }
        if targetLauncherURL != originalLauncherURL {
            try createPrivateDirectory(targetLauncherURL.deletingLastPathComponent())
            guard !itemExistsIncludingDanglingSymlink(at: targetLauncherURL) else {
                throw LauncherGeneratorError.alreadyExists
            }
            do {
                try fileManager.moveItem(at: originalLauncherURL, to: targetLauncherURL)
                refreshLaunchServicesUnregistration(for: originalLauncherURL)
            } catch {
                throw LauncherGeneratorError.materializationFailed
            }
        }
        let launcherURL = targetLauncherURL
        let infoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        let original = try Data(contentsOf: infoURL)
        guard var info = try PropertyListSerialization.propertyList(
            from: original,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw LauncherGeneratorError.materializationFailed
        }
        info["CFBundleDisplayName"] = updated.label
        info["CFBundleName"] = updated.label
        let updatedInfoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        do {
            try updatedInfoData.write(to: infoURL, options: .atomic)
            guard signLauncher(launcherURL) else {
                throw LauncherGeneratorError.materializationFailed
            }
            refreshLaunchServicesRegistration(for: launcherURL)
        } catch {
            try? original.write(to: infoURL, options: .atomic)
            _ = signLauncher(launcherURL)
            if targetLauncherURL != originalLauncherURL {
                try? fileManager.moveItem(at: targetLauncherURL, to: originalLauncherURL)
                refreshLaunchServicesRegistration(for: originalLauncherURL)
            }
            throw LauncherGeneratorError.materializationFailed
        }
        return launcherURL
    }

    // MARK: Custom icons

    /// Smallest accepted shortest-side for a user-chosen icon image. Anything
    /// smaller upscales visibly at Finder/Dock sizes and is rejected instead.
    static let customIconMinimumPixelSize = 256

    /// The persisted copy of a user-chosen icon, already converted to .icns.
    /// Existence of this file IS the "custom icon" intent: `buildLauncherBundle`
    /// prefers it over the source app's icon, so healing, adoption, and legacy
    /// conversion re-materialize the launcher with the custom icon intact.
    func customIconURL(for id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("CustomIcons", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased() + ".icns")
    }

    func hasCustomIcon(for id: UUID) -> Bool {
        fileManager.fileExists(atPath: customIconURL(for: id).path)
    }

    /// The per-instance advisory lock file (see `ManagedInstanceLock`). It is
    /// coordination metadata rather than owned data, so it is cleaned up
    /// best-effort only after an instance has been fully removed.
    func managedInstanceLockURL(for id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("Locks", isDirectory: true)
            .appendingPathComponent(id.uuidString.uppercased() + ".lock")
    }

    func removeManagedInstanceLock(for id: UUID) {
        try? fileManager.removeItem(at: managedInstanceLockURL(for: id))
    }

    /// Best-effort Launch Services unregistration for a removed managed launcher
    /// path, so Launchpad and Spotlight drop the stale entry. Guarded to the
    /// visible launchers root, exactly like the removal path's own cleanup.
    func unregisterLauncherFromLaunchServices(at url: URL) {
        refreshLaunchServicesUnregistration(for: url)
    }

    /// Reads a generated launcher's baked instance UUID from its bundle
    /// identifier (`local.klik-pro.launcher.i<uuid-no-dashes>`). Returns nil for
    /// anything that is not a Klik PRO-owned generated launcher.
    private func launcherInstanceID(at url: URL) -> UUID? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: infoURL.path),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        let prefix = "local.klik-pro.launcher.i"
        guard bundleID.hasPrefix(prefix) else { return nil }
        let hex = String(bundleID.dropFirst(prefix.count))
        guard hex.count == 32 else { return nil }
        let d = Array(hex)
        let dashed = "\(String(d[0..<8]))-\(String(d[8..<12]))-\(String(d[12..<16]))-\(String(d[16..<20]))-\(String(d[20..<32]))"
        return UUID(uuidString: dashed)
    }

    /// One Klik PRO-owned launcher/metadata leftover whose UUID has no active
    /// profile record. Data folders are surfaced separately by `scanOrphans`.
    struct LauncherLeftover: Equatable {
        enum Kind: Equatable { case customIcon, lock, launcher }
        let kind: Kind
        let instanceID: UUID
        let url: URL
        let sizeBytes: Int64
    }

    /// Read-only scan for orphaned launcher/metadata leftovers (custom-icon
    /// copies, lock files, and generated launcher bundles) keyed to UUIDs that
    /// are not in `activeIDs`. Each candidate is ownership-validated by an exact
    /// path match (icons/locks) or `isSafeGeneratedLauncher` (launchers), so a
    /// non-Klik-PRO file at these paths is never reported.
    func scanLauncherLeftovers(activeIDs: Set<UUID>) -> [LauncherLeftover] {
        var found: [LauncherLeftover] = []

        func entries(in dir: URL, ext: String) -> [URL] {
            ((try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension.lowercased() == ext }
        }

        let iconsDir = applicationSupportURL.appendingPathComponent("CustomIcons", isDirectory: true)
        for url in entries(in: iconsDir, ext: "icns") {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !activeIDs.contains(id),
                  url.standardizedFileURL == customIconURL(for: id).standardizedFileURL else { continue }
            found.append(.init(kind: .customIcon, instanceID: id, url: url.standardizedFileURL, sizeBytes: dataSize(at: url)))
        }

        let locksDir = applicationSupportURL.appendingPathComponent("Locks", isDirectory: true)
        for url in entries(in: locksDir, ext: "lock") {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !activeIDs.contains(id),
                  url.standardizedFileURL == managedInstanceLockURL(for: id).standardizedFileURL else { continue }
            found.append(.init(kind: .lock, instanceID: id, url: url.standardizedFileURL, sizeBytes: dataSize(at: url)))
        }

        for url in entries(in: visibleLaunchersRootURL, ext: "app") {
            guard let id = launcherInstanceID(at: url), !activeIDs.contains(id) else { continue }
            let expectedBundleID = "local.klik-pro.launcher.i"
                + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            guard (try? isSafeGeneratedLauncher(url, expectedBundleID: expectedBundleID)) == true else { continue }
            found.append(.init(kind: .launcher, instanceID: id, url: url.standardizedFileURL, sizeBytes: dataSize(at: url)))
        }

        return found.sorted { $0.url.path < $1.url.path }
    }

    /// Removes one scanned leftover, re-validating ownership immediately before
    /// the op. Launchers additionally unregister from Launch Services. Returns
    /// the Trash URL for a `.trash` op, or nil.
    @discardableResult
    func removeLauncherLeftover(_ leftover: LauncherLeftover, mode: DataRemovalMode) throws -> URL? {
        switch leftover.kind {
        case .customIcon:
            return try removeOwnedArtifact(
                at: leftover.url, kind: .customIcon,
                instanceID: leftover.instanceID, storage: .applicationSupport, mode: mode
            )
        case .lock:
            guard leftover.url.standardizedFileURL
                == managedInstanceLockURL(for: leftover.instanceID).standardizedFileURL else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            switch mode {
            case .trash: return try trashItem(leftover.url)
            case .permanent: try fileManager.removeItem(at: leftover.url); return nil
            }
        case .launcher:
            let expectedBundleID = "local.klik-pro.launcher.i"
                + leftover.instanceID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            guard (try? isSafeGeneratedLauncher(leftover.url, expectedBundleID: expectedBundleID)) == true else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            let result: URL?
            switch mode {
            case .trash: result = try trashItem(leftover.url)
            case .permanent: try fileManager.removeItem(at: leftover.url); result = nil
            }
            refreshLaunchServicesUnregistration(for: leftover.url)
            return result
        }
    }

    /// One UUID-keyed data root found on disk, before any record cross-check.
    /// `dataURL` is `Profiles/<UUID>` for Application Support storage or
    /// `<Vault>/Instances/<UUID>` for vault storage; `markerPresent` is true
    /// only when the owned-profile marker validates for that UUID.
    struct ProfileDataCandidate: Equatable {
        let instanceID: UUID
        let storage: AppProfileStorage
        let dataURL: URL
        let markerPresent: Bool
    }

    /// Read-only enumeration of every UUID-named data root under the Klik PRO
    /// Profiles root and, when a vault is configured, the vault `Instances`
    /// root. Never creates, moves, or modifies anything (invariant I5). A
    /// swapped-in symlink at a candidate node is skipped, not followed.
    func scanProfileDataCandidates() -> [ProfileDataCandidate] {
        var found: [ProfileDataCandidate] = []
        let profilesRoot = applicationSupportURL
            .appendingPathComponent("Profiles", isDirectory: true)
        found.append(contentsOf: candidates(in: profilesRoot, storage: .applicationSupport) { id in
            profileURL(for: id)
        })
        if let vaultRootURL {
            let instancesRoot = vaultRootURL.appendingPathComponent("Instances", isDirectory: true)
            found.append(contentsOf: candidates(in: instancesRoot, storage: .vault) { id in
                (try? vaultInstanceDirectoryURL(for: id)) ?? instancesRoot
                    .appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
            })
        }
        return found
    }

    private func candidates(
        in root: URL,
        storage: AppProfileStorage,
        dataURL: (UUID) -> URL
    ) -> [ProfileDataCandidate] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var result: [ProfileDataCandidate] = []
        for name in names {
            guard let id = UUID(uuidString: name), name == id.uuidString.uppercased() else {
                continue
            }
            let node = dataURL(id).standardizedFileURL
            guard let values = try? node.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ]),
                values.isDirectory == true,
                values.isSymbolicLink != true else {
                continue
            }
            let markerURL: URL
            switch storage {
            case .applicationSupport:
                markerURL = node.appendingPathComponent(Self.profileOwnershipMarkerName)
            case .vault:
                markerURL = node
                    .appendingPathComponent("user-data", isDirectory: true)
                    .appendingPathComponent(Self.profileOwnershipMarkerName)
            }
            let markerData = fileManager.contents(atPath: markerURL.path)
            let markerPresent = markerData
                .map { String(decoding: $0, as: UTF8.self) == id.uuidString.uppercased() }
                ?? false
            result.append(ProfileDataCandidate(
                instanceID: id,
                storage: storage,
                dataURL: node,
                markerPresent: markerPresent
            ))
        }
        return result
    }

    /// Best-effort recursive byte size of a data root, for the delete
    /// confirmation summary. Unreadable entries are skipped (size is advisory).
    func dataSize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
            ])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    func vaultCustomIconURL(for id: UUID) throws -> URL {
        try vaultInstanceDirectoryURL(for: id)
            .appendingPathComponent("custom-icon.icns", isDirectory: false)
    }

    func hasVaultCustomIcon(for id: UUID) -> Bool {
        guard let url = try? vaultCustomIconURL(for: id) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Keeps an exact portable copy beside a vault instance's owned data.
    /// Machine-local `iconPath` is never used as recovery truth.
    @discardableResult
    func synchronizeCustomIconToVault(for instance: AppProfileInstance) -> Bool {
        guard instance.storage == .vault,
              let durableURL = try? vaultCustomIconURL(for: instance.id) else {
            return false
        }
        if fileManager.fileExists(atPath: durableURL.path) { return true }
        let workingURL = customIconURL(for: instance.id)
        guard let data = fileManager.contents(atPath: workingURL.path) else { return false }
        do {
            try data.write(to: durableURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func restoreCustomIconFromVault(for instance: AppProfileInstance) -> Bool {
        guard instance.storage == .vault,
              let durableURL = try? vaultCustomIconURL(for: instance.id),
              let data = fileManager.contents(atPath: durableURL.path) else {
            return false
        }
        let workingURL = customIconURL(for: instance.id)
        do {
            try createPrivateDirectory(workingURL.deletingLastPathComponent())
            try data.write(to: workingURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func removeVaultCustomIcon(for instance: AppProfileInstance) {
        guard instance.storage == .vault,
              let durableURL = try? vaultCustomIconURL(for: instance.id) else { return }
        try? fileManager.removeItem(at: durableURL)
    }

    /// The square canvas tint/badge rendering composites onto before it is
    /// downsampled into the .icns element sizes.
    static let renderCanvasSize = 512

    /// An icon colour expressed as plain sRGB components (0…1). Foundation-only
    /// so the shared palette can live on `AppProfileMenuColor` without coupling
    /// the model to AppKit; both the renderer and the UI build from it.
    struct IconColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    /// Encodes one already-prepared square image into multi-size .icns data.
    /// ImageIO's icns encoder requires exact canonical dimensions, so each
    /// element is re-rendered aspect-fit (padded, never cropped).
    static func makeICNSData(from image: CGImage) throws -> Data {
        // Canonical standalone icns element sizes ImageIO's encoder accepts; 64
        // is deliberately omitted because ImageIO silently drops it (no
        // unambiguous standalone type), leaving a valid five-frame icon.
        let sizes = [16, 32, 128, 256, 512]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "com.apple.icns" as CFString, sizes.count, nil
        ) else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        for size in sizes {
            guard let scaled = renderAspectFit(image, into: size) else {
                throw LauncherGeneratorError.iconImageInvalid
            }
            CGImageDestinationAddImage(destination, scaled, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        return data as Data
    }

    /// Decodes a user-chosen PNG/ICO (largest frame) and encodes it as .icns.
    /// Rejects images whose shortest side is below `customIconMinimumPixelSize`.
    static func makeICNSData(fromImageAt imageURL: URL) throws -> Data {
        guard let image = largestImage(atFileURL: imageURL),
              min(image.width, image.height) >= customIconMinimumPixelSize else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        return try makeICNSData(from: image)
    }

    /// Loads the source app's own icon as a CGImage (largest frame), for tint
    /// and badge composition and for the Change Icon preview.
    func sourceIconImage(sourceBundleURL: URL) -> CGImage? {
        guard let iconURL = sourceIconURL(sourceBundleURL: sourceBundleURL) else { return nil }
        return Self.largestImage(atFileURL: iconURL)
    }

    private static func largestImage(atFileURL url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var largest: CGImage?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            if image.width > (largest?.width ?? 0) { largest = image }
        }
        return largest
    }

    /// Shapes an arbitrary image into a macOS-style app icon: the artwork is
    /// aspect-filled into a rounded-corner (squircle-like) tile, inset with the
    /// same proportional padding macOS uses (~10%), so a plain square logo reads
    /// as a real app icon instead of a flat square. Used for user-chosen images
    /// only — tint/badge derive from the source app icon, which is already shaped.
    static func macOSIconShaped(_ source: CGImage) -> CGImage? {
        let size = renderCanvasSize
        guard let context = squareContext(size) else { return nil }
        let s = CGFloat(size)
        let inset = (s * 0.098).rounded()
        let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let radius = tile.width * 0.2237   // macOS icon-grid corner ratio
        context.addPath(CGPath(
            roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil
        ))
        context.clip()
        // Aspect-fill so the rounded tile is fully covered (no transparent gaps).
        let scale = max(tile.width / CGFloat(source.width), tile.height / CGFloat(source.height))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        context.draw(source, in: CGRect(
            x: tile.midX - width / 2, y: tile.midY - height / 2, width: width, height: height
        ))
        return context.makeImage()
    }

    /// Loads a user-chosen image file and returns it shaped as a macOS app icon,
    /// for the Change Icon live preview (no size validation — that happens on apply).
    static func macOSShapedImage(fromImageAt url: URL) -> CGImage? {
        guard let image = largestImage(atFileURL: url) else { return nil }
        return macOSIconShaped(image)
    }

    /// Recolours the source icon: the colour's hue and saturation are applied
    /// while the icon's own shading (luminance) is kept, then the result is
    /// masked back to the icon's shape so transparent padding stays clear.
    static func tintedIcon(_ source: CGImage, color: IconColor) -> CGImage? {
        let size = renderCanvasSize
        guard let context = squareContext(size) else { return nil }
        let fitted = aspectFitRect(source, in: size)
        context.draw(source, in: fitted)
        context.setBlendMode(.color)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setBlendMode(.destinationIn)
        context.draw(source, in: fitted)
        return context.makeImage()
    }

    /// Draws the source icon with a coloured corner badge carrying `letter`
    /// (its first character, uppercased). A white ring separates the badge from
    /// the artwork behind it.
    static func badgedIcon(_ source: CGImage, color: IconColor, letter: String) -> CGImage? {
        let size = renderCanvasSize
        guard let context = squareContext(size) else { return nil }
        context.draw(source, in: aspectFitRect(source, in: size))
        let s = CGFloat(size)
        let diameter = s * 0.44
        let margin = s * 0.03
        // Origin is bottom-left, so this centre sits in the bottom-right corner.
        let center = CGPoint(x: s - diameter / 2 - margin, y: diameter / 2 + margin)
        let ring = s * 0.028
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        context.setFillColor(white)
        context.fillEllipse(in: CGRect(
            x: center.x - diameter / 2 - ring, y: center.y - diameter / 2 - ring,
            width: diameter + 2 * ring, height: diameter + 2 * ring
        ))
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2,
            width: diameter, height: diameter
        ))
        let trimmed = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.uppercased().first {
            let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, diameter * 0.56, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: white,
            ]
            guard let attributed = CFAttributedStringCreate(
                nil, String(first) as CFString, attributes as CFDictionary
            ) else {
                return context.makeImage()
            }
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetImageBounds(line, context)
            context.textPosition = CGPoint(
                x: center.x - bounds.width / 2 - bounds.minX,
                y: center.y - bounds.height / 2 - bounds.minY
            )
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }

    private static func squareContext(_ size: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        return context
    }

    private static func aspectFitRect(_ image: CGImage, in size: Int) -> CGRect {
        let scale = min(
            CGFloat(size) / CGFloat(image.width),
            CGFloat(size) / CGFloat(image.height)
        )
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(
            x: (CGFloat(size) - width) / 2,
            y: (CGFloat(size) - height) / 2,
            width: width, height: height
        )
    }

    private static func renderAspectFit(_ image: CGImage, into size: Int) -> CGImage? {
        guard let context = squareContext(size) else { return nil }
        context.draw(image, in: aspectFitRect(image, in: size))
        return context.makeImage()
    }

    /// Replaces the launcher's icon with a user-chosen PNG/ICO, shaped into the
    /// macOS app-icon squircle so it matches native icons in Finder/Dock.
    func setCustomIcon(
        fromImageAt imageURL: URL,
        for instance: AppProfileInstance
    ) throws -> URL {
        guard let image = Self.largestImage(atFileURL: imageURL),
              min(image.width, image.height) >= Self.customIconMinimumPixelSize else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        guard let shaped = Self.macOSIconShaped(image) else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        let icnsData = try Self.makeICNSData(from: shaped)
        return try persistAndStamp(icnsData: icnsData, for: instance)
    }

    /// Recolours the source app's icon with one of the shared palette colours.
    func setTintedIcon(
        color: IconColor,
        for instance: AppProfileInstance,
        sourceBundleURL: URL
    ) throws -> URL {
        guard let source = sourceIconImage(sourceBundleURL: sourceBundleURL),
              let tinted = Self.tintedIcon(source, color: color) else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        return try persistAndStamp(icnsData: try Self.makeICNSData(from: tinted), for: instance)
    }

    /// Adds a coloured, lettered corner badge to the source app's icon.
    func setBadgedIcon(
        color: IconColor,
        letter: String,
        for instance: AppProfileInstance,
        sourceBundleURL: URL
    ) throws -> URL {
        guard let source = sourceIconImage(sourceBundleURL: sourceBundleURL),
              let badged = Self.badgedIcon(source, color: color, letter: letter) else {
            throw LauncherGeneratorError.iconImageInvalid
        }
        return try persistAndStamp(icnsData: try Self.makeICNSData(from: badged), for: instance)
    }

    /// Persists the .icns under `CustomIcons/<UUID>.icns` first so a later
    /// re-materialization keeps it, then stamps the live bundle. If stamping
    /// fails, the persisted copy is rolled back so intent always matches what
    /// is visible.
    private func persistAndStamp(
        icnsData: Data,
        for instance: AppProfileInstance
    ) throws -> URL {
        let launcherURL = try validatedLauncherURL(for: instance)
        let customURL = customIconURL(for: instance.id)
        let previousCustom = fileManager.fileExists(atPath: customURL.path)
            ? try? Data(contentsOf: customURL)
            : nil
        try createPrivateDirectory(customURL.deletingLastPathComponent())
        do {
            try icnsData.write(to: customURL, options: .atomic)
        } catch {
            throw LauncherGeneratorError.materializationFailed
        }
        do {
            return try stampIcon(data: icnsData, into: launcherURL)
        } catch {
            if let previousCustom {
                try? previousCustom.write(to: customURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: customURL)
            }
            throw error
        }
    }

    /// Restores the source app's own icon and deletes the persisted custom
    /// copy, so future re-materializations follow the source again. Returns the
    /// bundle icon URL, or nil when the source app declares no icon.
    func resetCustomIcon(
        for instance: AppProfileInstance,
        sourceBundleURL: URL
    ) throws -> URL? {
        let launcherURL = try validatedLauncherURL(for: instance)
        // Drop the persisted copy FIRST and surface a failure: leaving it behind
        // would let the next heal/adopt/legacy-conversion silently resurrect the
        // old custom icon, so a reset that can't clear it must not report success.
        let customURL = customIconURL(for: instance.id)
        if fileManager.fileExists(atPath: customURL.path) {
            do {
                try fileManager.removeItem(at: customURL)
            } catch {
                throw LauncherGeneratorError.materializationFailed
            }
        }
        if let sourceIcon = sourceIconURL(sourceBundleURL: sourceBundleURL),
           let sourceData = try? Data(contentsOf: sourceIcon) {
            return try stampIcon(data: sourceData, into: launcherURL)
        }
        try removeIcon(from: launcherURL)
        return nil
    }

    /// Writes new icon bytes into an existing launcher bundle, re-signs it, and
    /// re-registers it so Finder and the Dock pick the change up. The previous
    /// bytes and Info.plist are restored if signing fails.
    private func stampIcon(data: Data, into launcherURL: URL) throws -> URL {
        let resources = launcherURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
        try createPrivateDirectory(resources)
        let iconURL = resources.appendingPathComponent("AppIcon.icns")
        let previousIcon = try? Data(contentsOf: iconURL)
        let infoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        guard let previousInfo = try? Data(contentsOf: infoURL),
              var info = try? PropertyListSerialization.propertyList(
                from: previousInfo, options: [], format: nil
              ) as? [String: Any] else {
            throw LauncherGeneratorError.materializationFailed
        }
        do {
            try data.write(to: iconURL, options: .atomic)
            if info["CFBundleIconFile"] as? String != "AppIcon" {
                info["CFBundleIconFile"] = "AppIcon"
                let updatedInfo = try PropertyListSerialization.data(
                    fromPropertyList: info, format: .xml, options: 0
                )
                try updatedInfo.write(to: infoURL, options: .atomic)
            }
            guard signLauncher(launcherURL) else {
                throw LauncherGeneratorError.materializationFailed
            }
            // Touch the bundle so Finder's icon cache notices the change.
            try? fileManager.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: launcherURL.path
            )
            refreshLaunchServicesRegistration(for: launcherURL)
            return iconURL
        } catch {
            if let previousIcon {
                try? previousIcon.write(to: iconURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: iconURL)
            }
            try? previousInfo.write(to: infoURL, options: .atomic)
            _ = signLauncher(launcherURL)
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Edge case for reset when the source app declares no icon at all: drop
    /// the bundle icon and its Info.plist reference, then re-sign.
    private func removeIcon(from launcherURL: URL) throws {
        let iconURL = launcherURL
            .appendingPathComponent("Contents/Resources/AppIcon.icns")
        let infoURL = launcherURL.appendingPathComponent("Contents/Info.plist")
        guard let previousInfo = try? Data(contentsOf: infoURL),
              var info = try? PropertyListSerialization.propertyList(
                from: previousInfo, options: [], format: nil
              ) as? [String: Any] else {
            throw LauncherGeneratorError.materializationFailed
        }
        let previousIcon = try? Data(contentsOf: iconURL)
        do {
            try? fileManager.removeItem(at: iconURL)
            info.removeValue(forKey: "CFBundleIconFile")
            let updatedInfo = try PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0
            )
            try updatedInfo.write(to: infoURL, options: .atomic)
            guard signLauncher(launcherURL) else {
                throw LauncherGeneratorError.materializationFailed
            }
            try? fileManager.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: launcherURL.path
            )
            refreshLaunchServicesRegistration(for: launcherURL)
        } catch {
            if let previousIcon {
                try? previousIcon.write(to: iconURL, options: .atomic)
            }
            try? previousInfo.write(to: infoURL, options: .atomic)
            _ = signLauncher(launcherURL)
            throw LauncherGeneratorError.materializationFailed
        }
    }

    /// Atomically hides a generated launcher before its config row is removed.
    /// If persistence fails, the caller can put the exact bundle back. Once the
    /// config write succeeds, commit deletes only the hidden, UUID-keyed bundle.
    func stageLauncherRemoval(for instance: AppProfileInstance) throws -> ManagedLauncherRemoval? {
        let spec = try specification(for: instance)
        guard itemExistsIncludingDanglingSymlink(at: spec.launcherURL) else { return nil }
        let launcherURL = try validatedLauncherURL(for: instance)
        let stagedURL = launcherURL.deletingLastPathComponent().appendingPathComponent(
            "." + instance.id.uuidString.uppercased() + "-removing-" + UUID().uuidString,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: stagedURL.path) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        do {
            try fileManager.moveItem(at: launcherURL, to: stagedURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
        return ManagedLauncherRemoval(
            instanceID: instance.id,
            originalURL: launcherURL,
            stagedURL: stagedURL
        )
    }

    func commitLauncherRemoval(
        _ removal: ManagedLauncherRemoval,
        preserveCustomIcon: Bool = false
    ) throws {
        guard isSafeRemovalStage(removal) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        guard fileManager.fileExists(atPath: removal.stagedURL.path) else { return }
        do {
            try fileManager.removeItem(at: removal.stagedURL)
            refreshLaunchServicesUnregistration(for: removal.originalURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
        if !preserveCustomIcon {
            // Permanent removal drops the working icon copy. Archive passes
            // preserveCustomIcon so Restore can reproduce the exact launcher.
            try? fileManager.removeItem(at: customIconURL(for: removal.instanceID))
        }
    }

    func rollbackLauncherRemoval(_ removal: ManagedLauncherRemoval) throws {
        guard isSafeRemovalStage(removal),
              fileManager.fileExists(atPath: removal.stagedURL.path),
              !fileManager.fileExists(atPath: removal.originalURL.path) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        do {
            try fileManager.moveItem(at: removal.stagedURL, to: removal.originalURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
    }

    /// Moves an owned profile to a UUID-keyed hidden sibling only after the caller
    /// holds the exclusive instance lock and has completed its process-reference
    /// checks. The ownership marker is revalidated before any rename.
    func stageProfileRemoval(for instance: AppProfileInstance) throws -> ManagedProfileRemoval {
        let spec = try specification(for: instance)
        try validateOwnedProfile(
            instanceID: instance.id,
            at: spec.profileURL,
            storage: instance.storage,
            rejectDescendantSymlinks: true
        )
        let stagedURL = spec.profileURL.deletingLastPathComponent().appendingPathComponent(
            "." + instance.id.uuidString.uppercased() + "-profile-removing-" + UUID().uuidString,
            isDirectory: true
        )
        guard !itemExistsIncludingDanglingSymlink(at: stagedURL) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        do {
            try fileManager.moveItem(at: spec.profileURL, to: stagedURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
        return ManagedProfileRemoval(
            instanceID: instance.id,
            originalURL: spec.profileURL,
            stagedURL: stagedURL,
            storage: instance.storage
        )
    }

    func commitProfileRemoval(_ removal: ManagedProfileRemoval) throws {
        guard isSafeProfileRemovalStage(removal),
              itemExistsIncludingDanglingSymlink(at: removal.stagedURL) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        try validateOwnedProfile(
            instanceID: removal.instanceID,
            at: removal.stagedURL,
            storage: removal.storage,
            rejectDescendantSymlinks: true
        )
        do {
            try fileManager.removeItem(at: removal.stagedURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
    }

    func rollbackProfileRemoval(_ removal: ManagedProfileRemoval) throws {
        guard isSafeProfileRemovalStage(removal),
              itemExistsIncludingDanglingSymlink(at: removal.stagedURL),
              !itemExistsIncludingDanglingSymlink(at: removal.originalURL) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        try validateOwnedProfile(
            instanceID: removal.instanceID,
            at: removal.stagedURL,
            storage: removal.storage,
            rejectDescendantSymlinks: true
        )
        do {
            try fileManager.moveItem(at: removal.stagedURL, to: removal.originalURL)
        } catch {
            throw LauncherGeneratorError.unsafeRemoval
        }
    }

    /// Reclaims a single owned data artifact — either to the Trash (reversible)
    /// or permanently. Every kind is re-validated against its exact Klik PRO
    /// root immediately before the op, so a swapped path, a symlink, or a
    /// non-UUID name fails closed and nothing is touched. Marker-bearing kinds
    /// (`profileRoot`, `vaultContainer` via its `user-data`) re-prove ownership;
    /// `codexHome`/`customIcon` are gated purely by their standardized position.
    /// Returns the resulting Trash URL for `.trash`, nil for `.permanent`.
    @discardableResult
    func removeOwnedArtifact(
        at candidateURL: URL,
        kind: OwnedArtifactKind,
        instanceID: UUID,
        storage: AppProfileStorage,
        mode: DataRemovalMode
    ) throws -> URL? {
        let standardized = candidateURL.standardizedFileURL
        switch kind {
        case .profileRoot:
            // Application Support profile root: marker-gated, symlink-rejecting.
            guard storage == .applicationSupport else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            try validateOwnedProfile(
                instanceID: instanceID,
                at: standardized,
                storage: .applicationSupport,
                rejectDescendantSymlinks: true
            )
        case .vaultContainer:
            // `<Vault>/Instances/<UUID>`: position-gated, and its `user-data`
            // must carry the ownership marker (that is the ownership proof).
            guard storage == .vault,
                  let expected = try? vaultInstanceDirectoryURL(for: instanceID),
                  standardized == expected.standardizedFileURL else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            try validateContainerNode(standardized)
            let userData = standardized.appendingPathComponent("user-data", isDirectory: true)
            try validateOwnedProfile(
                instanceID: instanceID,
                at: userData,
                storage: .vault,
                rejectDescendantSymlinks: true
            )
        case .codexHome:
            guard storage == .applicationSupport else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            let expected = codexHomeURL(for: instanceID).standardizedFileURL
            guard standardized == expected else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            try validateContainerNode(standardized)
        case .customIcon:
            // The custom-icon copy always lives at a storage-independent App
            // Support path (`CustomIcons/<UUID>.icns`), so it is reclaimable for
            // both vault and Application Support profiles. The exact-path match
            // below is the ownership proof.
            let expected = customIconURL(for: instanceID).standardizedFileURL
            guard standardized == expected else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            let values = try? standardized.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                throw LauncherGeneratorError.unsafeRemoval
            }
        }

        switch mode {
        case .trash:
            do {
                return try trashItem(standardized)
            } catch {
                throw LauncherGeneratorError.unsafeRemoval
            }
        case .permanent:
            do {
                try fileManager.removeItem(at: standardized)
                return nil
            } catch {
                throw LauncherGeneratorError.unsafeRemoval
            }
        }
    }

    /// A directory node that must sit exactly at its resolved path (no symlink
    /// redirection) and be a real directory, used for `codexHome` and the vault
    /// container before a reclaim.
    private func validateContainerNode(_ standardized: URL) throws {
        guard standardized.resolvingSymlinksInPath() == standardized,
              standardized.deletingLastPathComponent().resolvingSymlinksInPath()
                == standardized.deletingLastPathComponent(),
              let values = try? standardized.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
              ]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw LauncherGeneratorError.unsafeRemoval
        }
    }

    /// M1 removes only Klik PRO's generated launcher. Profile data is deliberately
    /// retained until M2 can prove the managed process has exited before deletion.
    func removeLauncher(for instance: AppProfileInstance) throws {
        guard let removal = try stageLauncherRemoval(for: instance) else { return }
        try commitLauncherRemoval(removal)
    }

    func validatedProfileURL(for instance: AppProfileInstance) throws -> URL {
        let spec = try specification(for: instance)
        try validateOwnedProfile(
            instanceID: instance.id,
            at: spec.profileURL,
            storage: instance.storage
        )
        return spec.profileURL
    }

    /// Rollback is used only before a newly created instance has ever been exposed
    /// or launched. The UUID marker must match before its fresh profile is removed.
    func rollbackNewMaterialization(for instance: AppProfileInstance) {
        guard let spec = try? specification(for: instance) else { return }
        if (try? isSafeGeneratedLauncher(
            spec.launcherURL,
            expectedBundleID: spec.bundleIdentifier
        )) == true {
            try? fileManager.removeItem(at: spec.launcherURL)
        }
        try? removeFreshProfile(
            instanceID: instance.id,
            at: spec.profileURL,
            storage: instance.storage
        )

        // A pre-created sibling home goes through the same validated
        // empty-only cleanup as the materialize catch paths; any visible home
        // symlink pointing at it is destination-verified before removal.
        guard let expectedCodexHome = try? codexHomeURL(
            for: instance.id,
            storage: instance.storage
        ) else {
            return
        }
        let needsCodexHome = instance.environmentOverrides.values.contains { value in
            value == expectedCodexHome.path
                || value.hasPrefix(expectedCodexHome.path + "/")
        }
        if needsCodexHome {
            removeHomeSymlinks(for: instance.id, storage: instance.storage)
            removeFreshCodexHome(for: instance.id, storage: instance.storage)
        }
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LauncherGeneratorError.materializationFailed
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func writeProfileMarker(instanceID: UUID, profileURL: URL) throws {
        let marker = profileURL.appendingPathComponent(Self.profileOwnershipMarkerName)
        try Data(instanceID.uuidString.uppercased().utf8).write(to: marker, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }

    private func removeFreshProfile(
        instanceID: UUID,
        at candidateProfileURL: URL,
        storage: AppProfileStorage = .applicationSupport
    ) throws {
        guard let expected = try? profileURL(for: instanceID, storage: storage),
              candidateProfileURL.standardizedFileURL == expected else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        try validateOwnedProfile(instanceID: instanceID, at: candidateProfileURL, storage: storage)
        try fileManager.removeItem(at: candidateProfileURL)
    }

    private func validateOwnedProfile(
        instanceID: UUID,
        at candidateProfileURL: URL,
        storage: AppProfileStorage = .applicationSupport,
        rejectDescendantSymlinks: Bool = false
    ) throws {
        let profilesRoot: URL
        switch storage {
        case .applicationSupport:
            profilesRoot = applicationSupportURL
                .appendingPathComponent("Profiles", isDirectory: true)
        case .vault:
            guard let container = try? vaultInstanceDirectoryURL(for: instanceID) else {
                throw LauncherGeneratorError.unsafeRemoval
            }
            profilesRoot = container
        }
        let standardized = candidateProfileURL.standardizedFileURL
        guard standardized.deletingLastPathComponent() == profilesRoot,
              profilesRoot.resolvingSymlinksInPath() == profilesRoot,
              standardized.resolvingSymlinksInPath() == standardized,
              let values = try? standardized.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
              ]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        let marker = standardized.appendingPathComponent(Self.profileOwnershipMarkerName)
        let markerValues = try? marker.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard markerValues?.isRegularFile == true,
              markerValues?.isSymbolicLink != true,
              let markerData = fileManager.contents(atPath: marker.path),
              String(decoding: markerData, as: UTF8.self)
                == instanceID.uuidString.uppercased() else {
            throw LauncherGeneratorError.unsafeRemoval
        }

        guard rejectDescendantSymlinks else { return }
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: standardized,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw LauncherGeneratorError.unsafeRemoval
        }
        for case let child as URL in enumerator {
            guard !enumerationFailed,
                  let childValues = try? child.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  childValues.isSymbolicLink != true else {
                throw LauncherGeneratorError.unsafeRemoval
            }
        }
        guard !enumerationFailed else { throw LauncherGeneratorError.unsafeRemoval }
    }

    private func isSafeGeneratedLauncher(_ url: URL, expectedBundleID: String) throws -> Bool {
        guard isAllowedGeneratedLauncherContainer(url.standardizedFileURL),
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink != true else {
            return false
        }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: infoURL.path),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return false
        }
        return info["CFBundleIdentifier"] as? String == expectedBundleID
            && info["CFBundleExecutable"] as? String == Self.executableName
    }

    private func isSafeRemovalStage(_ removal: ManagedLauncherRemoval) -> Bool {
        let originalParent = removal.originalURL.deletingLastPathComponent()
        let expectedPrefix = "." + removal.instanceID.uuidString.uppercased() + "-removing-"
        return isAllowedGeneratedLauncherContainer(removal.originalURL)
            && removal.stagedURL.deletingLastPathComponent() == originalParent
            && removal.stagedURL.lastPathComponent.hasPrefix(expectedPrefix)
            && removal.stagedURL.pathExtension.isEmpty
    }

    private func isAllowedManagedLauncherPath(
        _ url: URL,
        instanceID: UUID,
        label: String
    ) -> Bool {
        let path = url.standardizedFileURL.path
        return path == launcherURL(for: instanceID).standardizedFileURL.path
            || path == launcherURL(for: instanceID, label: label).standardizedFileURL.path
    }

    private func isAllowedGeneratedLauncherContainer(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let parentPath = standardized.deletingLastPathComponent().path
        return parentPath == applicationSupportURL
            .appendingPathComponent("Launchers", isDirectory: true)
            .standardizedFileURL.path
            || parentPath == visibleLaunchersRootURL.standardizedFileURL.path
    }

    private func refreshLaunchServicesRegistration(for url: URL) {
        guard shouldRefreshLaunchServices(for: url) else { return }
        Self.runLaunchServices(["-f", url.path])
    }

    private func refreshLaunchServicesUnregistration(for url: URL) {
        guard shouldRefreshLaunchServices(for: url) else { return }
        Self.runLaunchServices(["-u", url.path])
    }

    private func shouldRefreshLaunchServices(for url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(
            visibleLaunchersRootURL.standardizedFileURL.path + "/"
        ) && visibleLaunchersRootURL.standardizedFileURL.path.hasPrefix(
            NSHomeDirectory() + "/Applications/"
        )
    }

    private static func runLaunchServices(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        )
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private func isSafeProfileRemovalStage(_ removal: ManagedProfileRemoval) -> Bool {
        guard let expectedOriginal = try? profileURL(
            for: removal.instanceID,
            storage: removal.storage
        ) else {
            return false
        }
        let expectedPrefix = "." + removal.instanceID.uuidString.uppercased()
            + "-profile-removing-"
        return removal.originalURL == expectedOriginal
            && removal.stagedURL.deletingLastPathComponent()
                == expectedOriginal.deletingLastPathComponent()
            && removal.stagedURL.lastPathComponent.hasPrefix(expectedPrefix)
            && removal.stagedURL.pathExtension.isEmpty
    }

    private func itemExistsIncludingDanglingSymlink(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func copySourceIconIfAvailable(
        sourceBundleURL: URL,
        resourcesURL: URL
    ) throws -> URL? {
        guard let sourceIcon = sourceIconURL(sourceBundleURL: sourceBundleURL) else {
            return nil
        }
        let destination = resourcesURL.appendingPathComponent("AppIcon.icns")
        try fileManager.copyItem(at: sourceIcon, to: destination)
        return destination
    }

    /// Resolves the source app's declared .icns inside its own bundle, or nil
    /// when the app declares none (or declares an unsafe non-leaf name).
    private func sourceIconURL(sourceBundleURL: URL) -> URL? {
        let infoURL = sourceBundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: infoURL.path),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              var iconName = info["CFBundleIconFile"] as? String,
              !iconName.isEmpty else {
            return nil
        }
        if (iconName as NSString).pathExtension.isEmpty { iconName += ".icns" }
        guard (iconName as NSString).lastPathComponent == iconName else { return nil }
        let sourceIcon = sourceBundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(iconName)
        guard fileManager.fileExists(atPath: sourceIcon.path) else { return nil }
        return sourceIcon
    }

    private static func adHocSign(_ launcherURL: URL) -> Bool {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", launcherURL.path]
        do {
            try xattr.run()
            xattr.waitUntilExit()
            guard xattr.terminationStatus == 0 else { return false }
        } catch {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--timestamp=none", launcherURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
