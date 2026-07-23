import Foundation

enum AppProfileLauncherKind: String, Codable, Equatable {
    case managed
    case legacyExternal
}

enum AppProfileOwnership: String, Codable, Equatable {
    case managed
    case adopted
    case external
}

enum AppProfileState: String, Codable, Equatable {
    case active
    case archived
}

enum AppProfileMenuColor: String, Codable, CaseIterable, Equatable {
    case blue
    case green
    case orange
    case purple
    case pink
    case gray
    case yellow
    case white
    case black

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .gray: return "Gray"
        case .yellow: return "Yellow"
        case .white: return "White"
        case .black: return "Black"
        }
    }

    /// The shared swatch colour reused for the menu-bar tint, the Change Icon
    /// tint, and the badge. Kept as plain sRGB components so this model type
    /// stays AppKit-free; the generator renders from it and the UI builds an
    /// NSColor from the same values, so all three always match.
    var iconColor: LauncherGenerator.IconColor {
        switch self {
        case .blue: return .init(red: 0.216, green: 0.541, blue: 0.867)
        case .green: return .init(red: 0.388, green: 0.600, blue: 0.133)
        case .orange: return .init(red: 0.937, green: 0.624, blue: 0.153)
        case .purple: return .init(red: 0.498, green: 0.467, blue: 0.867)
        case .pink: return .init(red: 0.831, green: 0.325, blue: 0.494)
        case .gray: return .init(red: 0.533, green: 0.529, blue: 0.502)
        case .yellow: return .init(red: 1.000, green: 0.800, blue: 0.000)
        case .white: return .init(red: 1.000, green: 1.000, blue: 1.000)
        case .black: return .init(red: 0.000, green: 0.000, blue: 0.000)
        }
    }
}

struct AppProfileSource: Codable, Equatable {
    var bundleIdentifier: String
    var bundleURL: String

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundleId"
        case bundleURL
    }
}

/// Persisted schema-10/11 instance model. Detection and eligibility fields are
/// hints; callers must re-inspect the source app before any managed lifecycle
/// action.
struct AppProfileInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var launcherKind: AppProfileLauncherKind
    var launcherPath: String
    var profileDirectory: String?
    var profileOwnership: AppProfileOwnership
    /// Schema 12 lifecycle state. Archived rows retain their full recipe and
    /// assignments, but every runtime consumer must treat them as ineligible.
    var state: AppProfileState
    var archivedAt: Date?
    var source: AppProfileSource
    /// Schema 11: marks where this instance's data lives so healing and path
    /// derivation pick the right root. `profileDirectory` and
    /// `environmentOverrides` remain the stored absolute truth; derivation must
    /// reproduce them, and a mismatch means the vault moved and needs healing.
    var storage: AppProfileStorage
    var environmentOverrides: [String: String]
    var iconPath: String?
    /// The one-character badge chosen for the current generated icon. Optional
    /// so configurations written before v1.3.2 decode without migration.
    var badgeCharacter: String?
    var menuColor: AppProfileMenuColor?
    var pinToMenuBar: Bool
    var hotkey: ShortcutMapping
    var mouseButton: QuickLaunchMouseButton?
    var lastDetectedEngine: AppProfileEngine?
    var lastVerifiedAppVersion: String?
    var lastVerifiedTeamIdentifier: String?
    var compatibilityRuleID: String?

    private enum CodingKeys: String, CodingKey {
        case id, label, launcherKind, launcherPath, profileOwnership, state, archivedAt, source
        case profileDirectory = "profileDir"
        case storage
        case environmentOverrides = "envOverrides"
        case iconPath, badgeCharacter, menuColor, pinToMenuBar, hotkey, mouseButton
        case lastDetectedEngine, lastVerifiedAppVersion
        case lastVerifiedTeamIdentifier, compatibilityRuleID
    }

    /// `storage` was added in schema 11. Every earlier row decodes as
    /// `.applicationSupport`, so the schema 10 → 11 migration is purely
    /// additive and never re-keys an existing instance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        launcherKind = try container.decode(AppProfileLauncherKind.self, forKey: .launcherKind)
        launcherPath = try container.decode(String.self, forKey: .launcherPath)
        profileDirectory = try container.decodeIfPresent(String.self, forKey: .profileDirectory)
        profileOwnership = try container.decode(
            AppProfileOwnership.self,
            forKey: .profileOwnership
        )
        state = try container.decodeIfPresent(AppProfileState.self, forKey: .state) ?? .active
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        source = try container.decode(AppProfileSource.self, forKey: .source)
        storage = try container.decodeIfPresent(AppProfileStorage.self, forKey: .storage)
            ?? .applicationSupport
        environmentOverrides = try container.decode(
            [String: String].self,
            forKey: .environmentOverrides
        )
        iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
        badgeCharacter = try container.decodeIfPresent(String.self, forKey: .badgeCharacter)
        menuColor = try container.decodeIfPresent(AppProfileMenuColor.self, forKey: .menuColor)
        pinToMenuBar = try container.decode(Bool.self, forKey: .pinToMenuBar)
        hotkey = try container.decode(ShortcutMapping.self, forKey: .hotkey)
        mouseButton = try container.decodeIfPresent(
            QuickLaunchMouseButton.self,
            forKey: .mouseButton
        )
        lastDetectedEngine = try container.decodeIfPresent(
            AppProfileEngine.self,
            forKey: .lastDetectedEngine
        )
        lastVerifiedAppVersion = try container.decodeIfPresent(
            String.self,
            forKey: .lastVerifiedAppVersion
        )
        lastVerifiedTeamIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .lastVerifiedTeamIdentifier
        )
        compatibilityRuleID = try container.decodeIfPresent(
            String.self,
            forKey: .compatibilityRuleID
        )
    }

    init(
        id: UUID,
        label: String,
        launcherKind: AppProfileLauncherKind,
        launcherPath: String,
        profileDirectory: String?,
        profileOwnership: AppProfileOwnership,
        state: AppProfileState = .active,
        archivedAt: Date? = nil,
        source: AppProfileSource,
        storage: AppProfileStorage = .applicationSupport,
        environmentOverrides: [String: String] = [:],
        iconPath: String? = nil,
        badgeCharacter: String? = nil,
        menuColor: AppProfileMenuColor? = nil,
        pinToMenuBar: Bool,
        hotkey: ShortcutMapping,
        mouseButton: QuickLaunchMouseButton?,
        lastDetectedEngine: AppProfileEngine? = nil,
        lastVerifiedAppVersion: String? = nil,
        lastVerifiedTeamIdentifier: String? = nil,
        compatibilityRuleID: String? = nil
    ) {
        self.id = id
        self.label = label
        self.launcherKind = launcherKind
        self.launcherPath = launcherPath
        self.profileDirectory = profileDirectory
        self.profileOwnership = profileOwnership
        self.state = state
        self.archivedAt = archivedAt
        self.source = source
        self.storage = storage
        self.environmentOverrides = environmentOverrides
        self.iconPath = iconPath
        self.badgeCharacter = badgeCharacter
        self.menuColor = menuColor
        self.pinToMenuBar = pinToMenuBar
        self.hotkey = hotkey
        self.mouseButton = mouseButton
        self.lastDetectedEngine = lastDetectedEngine
        self.lastVerifiedAppVersion = lastVerifiedAppVersion
        self.lastVerifiedTeamIdentifier = lastVerifiedTeamIdentifier
        self.compatibilityRuleID = compatibilityRuleID
    }
}
