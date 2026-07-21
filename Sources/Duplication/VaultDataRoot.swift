import Foundation

// MARK: - Per-instance storage marker (schema 11)

/// Where an instance's generated data (profile + sibling config home) lives.
/// `.applicationSupport` is the unchanged pre-vault layout under
/// `~/Library/Application Support/Klik PRO/`; `.vault` marks a durable,
/// user-chosen data root that survives uninstalling Klik PRO.
enum AppProfileStorage: String, Codable, Equatable {
    case applicationSupport
    case vault
}

// MARK: - Vault location validation (fail closed)

/// Fail-closed vault location gate. Returns a user-facing reason when the
/// candidate path must be rejected, or nil when the path is acceptable.
/// Rejected: non-absolute paths, anything inside `~/Library/Application Support`
/// (uninstallers wipe it, defeating the vault's purpose), anything inside an
/// `.app` bundle (replaced on update), and unwritable locations.
/// Resolves symlinks and `/private` normalization on the deepest existing
/// ancestor of `path`, then re-appends any not-yet-created tail. Using the
/// deepest existing ancestor makes the result stable whether or not the leaf
/// exists, so a symlinked or case-variant path can't dodge the containment
/// check by pointing at a folder that hasn't been created yet.
private func canonicalizedPath(_ path: String, fileManager: FileManager) -> String {
    var existing = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    var tail: [String] = []
    while existing.path != "/", !fileManager.fileExists(atPath: existing.path) {
        tail.insert(existing.lastPathComponent, at: 0)
        existing = existing.deletingLastPathComponent()
    }
    var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
    for component in tail {
        resolved.appendPathComponent(component)
    }
    return resolved.standardizedFileURL.path
}

func vaultPathRejectionReason(
    _ path: String,
    homeDirectory: String = NSHomeDirectory(),
    fileManager: FileManager = .default
) -> String? {
    guard path.hasPrefix("/") else {
        return "The data folder must be an absolute path."
    }
    // Resolve symlinks before the containment check: a link that points into
    // Application Support must be rejected by where it physically lives, not
    // by its cosmetic path. `canonicalizedPath` resolves the deepest existing
    // ancestor consistently (so a not-yet-created leaf can't dodge the /private
    // normalization that an existing path gets), then re-appends the missing
    // tail.
    let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let candidateCanonical = canonicalizedPath(path, fileManager: fileManager)
    let applicationSupportCanonical = canonicalizedPath(
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true).path,
        fileManager: fileManager
    )
    // Default macOS volumes are case-insensitive, so compare case-folded to
    // stop a case-variant path (…/library/application support/…) from
    // slipping into the tree uninstallers wipe.
    let candidateKey = candidateCanonical.lowercased()
    let supportKey = applicationSupportCanonical.lowercased()
    if candidateKey == supportKey || candidateKey.hasPrefix(supportKey + "/") {
        return "The data folder cannot live inside Application Support; use Documents, your home folder, or an external disk."
    }
    // Check the .app-interior rule against the CANONICAL path too, not the
    // cosmetic one: a symlink resolving into an .app bundle would otherwise
    // carry no ".app" component in its literal path and dodge this rule the
    // same way a symlink into Application Support did before F2 (F3).
    if URL(fileURLWithPath: candidateCanonical, isDirectory: true).pathComponents
        .contains(where: { $0.lowercased().hasSuffix(".app") }) {
        return "The data folder cannot live inside an app bundle."
    }
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else {
            return "The data folder path exists but is not a folder."
        }
        guard fileManager.isWritableFile(atPath: standardized.path) else {
            return "The data folder is not writable."
        }
        return nil
    }
    // Not created yet: the nearest existing ancestor must be writable so the
    // folder can actually be created there.
    var ancestor = standardized.deletingLastPathComponent()
    while ancestor.path != "/", !fileManager.fileExists(atPath: ancestor.path) {
        ancestor = ancestor.deletingLastPathComponent()
    }
    guard fileManager.isWritableFile(atPath: ancestor.path) else {
        return "The data folder location is not writable."
    }
    return nil
}

// MARK: - Manifest (`vault.json`)

let vaultManifestFileName = "vault.json"

/// One re-adoptable instance record. Environment values are deliberately NOT
/// persisted here: the compatibility rule id is the re-derivable key, and every
/// adopt re-resolves the isolation environment against the vault's CURRENT
/// path (portability invariant — never trust a baked absolute path).
struct VaultManifestInstanceRecord: Codable, Equatable {
    var id: UUID
    var label: String
    var sourceBundleIdentifier: String
    var sourceTeamIdentifier: String?
    var sourceBundleURL: String
    var compatibilityRuleID: String
    /// Cached convenience only; adopt re-derives the prefix from the rule.
    var homeSymlinkPrefix: String?
    /// Manifest schema 2 lifecycle and portable icon recovery metadata.
    var archived: Bool
    var menuColor: AppProfileMenuColor?
    var customIcon: Bool

    private enum CodingKeys: String, CodingKey {
        case id, label, sourceBundleIdentifier, sourceTeamIdentifier
        case sourceBundleURL, compatibilityRuleID, homeSymlinkPrefix
        case archived, menuColor, customIcon
    }

    init(
        id: UUID,
        label: String,
        sourceBundleIdentifier: String,
        sourceTeamIdentifier: String?,
        sourceBundleURL: String,
        compatibilityRuleID: String,
        homeSymlinkPrefix: String?,
        archived: Bool = false,
        menuColor: AppProfileMenuColor? = nil,
        customIcon: Bool = false
    ) {
        self.id = id
        self.label = label
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceTeamIdentifier = sourceTeamIdentifier
        self.sourceBundleURL = sourceBundleURL
        self.compatibilityRuleID = compatibilityRuleID
        self.homeSymlinkPrefix = homeSymlinkPrefix
        self.archived = archived
        self.menuColor = menuColor
        self.customIcon = customIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        sourceBundleIdentifier = try container.decode(String.self, forKey: .sourceBundleIdentifier)
        sourceTeamIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceTeamIdentifier)
        sourceBundleURL = try container.decode(String.self, forKey: .sourceBundleURL)
        compatibilityRuleID = try container.decode(String.self, forKey: .compatibilityRuleID)
        homeSymlinkPrefix = try container.decodeIfPresent(String.self, forKey: .homeSymlinkPrefix)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        menuColor = try container.decodeIfPresent(AppProfileMenuColor.self, forKey: .menuColor)
        customIcon = try container.decodeIfPresent(Bool.self, forKey: .customIcon) ?? false
    }
}

/// The vault's self-describing manifest. The manifest is the authority for
/// which instances a vault holds; Application Support keeps only a cache copy
/// of the active config.
struct VaultManifest: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var instances: [VaultManifestInstanceRecord]

    static func manifestURL(vaultRoot: URL) -> URL {
        vaultRoot.appendingPathComponent(vaultManifestFileName, isDirectory: false)
    }

    /// Fail-closed read: any missing, unreadable, or undecodable manifest is
    /// nil. Adopt refuses folders without a valid vault.json, so arbitrary
    /// folders can never be adopted.
    static func read(
        vaultRoot: URL,
        fileManager: FileManager = .default
    ) -> VaultManifest? {
        let url = manifestURL(vaultRoot: vaultRoot)
        guard let data = fileManager.contents(atPath: url.path),
              let manifest = try? JSONDecoder().decode(VaultManifest.self, from: data),
              manifest.schemaVersion >= 1,
              manifest.schemaVersion <= VaultManifest.currentSchemaVersion else {
            return nil
        }
        return manifest
    }

    /// Atomic write (temp + rename via `.atomic`). A read-only or absent
    /// volume makes this a surfaced no-op (returns false), never a crash.
    @discardableResult
    func write(to vaultRoot: URL, fileManager: FileManager = .default) -> Bool {
        do {
            try fileManager.createDirectory(
                at: vaultRoot,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.manifestURL(vaultRoot: vaultRoot), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Reinstall discovery ladder (automatic steps)

/// Automatic vault discovery: remembered pointer → surviving `~` dot-symlinks
/// whose destination is `…/Instances/<UUID>/config-home` → default candidate
/// locations. Every candidate must carry a valid `vault.json` to qualify.
/// Asking the user (an open-folder panel) remains the UI's final fallback.
func discoverVaultRootCandidates(
    rememberedPath: String?,
    homeSymlinkRootURL: URL,
    defaultCandidatePaths: [String] = [
        NSHomeDirectory() + "/Documents/Klik PRO Data",
    ],
    fileManager: FileManager = .default
) -> [URL] {
    var results: [URL] = []
    var seen = Set<String>()
    func addIfVault(_ candidate: URL) {
        let root = candidate.standardizedFileURL
        guard !seen.contains(root.path),
              VaultManifest.read(vaultRoot: root, fileManager: fileManager) != nil else {
            return
        }
        seen.insert(root.path)
        results.append(root)
    }

    if let rememberedPath, rememberedPath.hasPrefix("/") {
        addIfVault(URL(fileURLWithPath: rememberedPath, isDirectory: true))
    }
    if let entries = try? fileManager.contentsOfDirectory(atPath: homeSymlinkRootURL.path) {
        for entry in entries.sorted() where entry.hasPrefix(".") {
            let link = homeSymlinkRootURL.appendingPathComponent(entry, isDirectory: false)
            guard let destination = try? fileManager.destinationOfSymbolicLink(
                atPath: link.path
            ) else {
                continue
            }
            let destinationURL = URL(fileURLWithPath: destination, isDirectory: true)
                .standardizedFileURL
            let components = destinationURL.pathComponents
            // A surviving link into <Vault>/Instances/<UUID>/config-home
            // recovers the vault root with zero user action.
            guard components.count >= 4,
                  destinationURL.lastPathComponent == "config-home",
                  UUID(uuidString: components[components.count - 2]) != nil,
                  components[components.count - 3] == "Instances" else {
                continue
            }
            addIfVault(
                destinationURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            )
        }
    }
    for path in defaultCandidatePaths {
        addIfVault(URL(fileURLWithPath: path, isDirectory: true))
    }
    return results
}
