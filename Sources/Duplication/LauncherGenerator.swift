import Foundation

enum LauncherGeneratorError: Error, Equatable {
    case notManaged
    case invalidProfileOwnership
    case sourceMismatch
    case disallowedEnvironmentKey(String)
    case launcherExecutableUnavailable
    case alreadyExists
    case materializationFailed
    case unsafeRemoval
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
        signLauncher: @escaping (URL) -> Bool = LauncherGenerator.adHocSign
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
            compatibilityRuleID: compatibilityRuleID
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
            environment: instance.environmentOverrides
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
        guard !itemExistsIncludingDanglingSymlink(at: spec.launcherURL) else {
            throw LauncherGeneratorError.alreadyExists
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
    }

    /// Shared launcher-bundle construction: builds the .app via a hidden
    /// temporary bundle, signs it, moves it into place, and registers it.
    /// Returns the copied icon's final URL, if the source app provided one.
    private func buildLauncherBundle(
        spec: ManagedLauncherSpecification,
        compatibilityRuleID: String
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
                compatibilityRuleID: compatibilityRuleID
            )
            let payloadData = try PropertyListEncoder().encode(payload)
            try payloadData.write(
                to: resources.appendingPathComponent(Self.payloadResourceName),
                options: .atomic
            )

            let copiedIcon = try copySourceIconIfAvailable(
                sourceBundleURL: spec.sourceBundleURL,
                resourcesURL: resources
            )
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
            try fileManager.moveItem(at: temporaryLauncher, to: spec.launcherURL)
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

    func commitLauncherRemoval(_ removal: ManagedLauncherRemoval) throws {
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
        let destination = resourcesURL.appendingPathComponent("AppIcon.icns")
        try fileManager.copyItem(at: sourceIcon, to: destination)
        return destination
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
