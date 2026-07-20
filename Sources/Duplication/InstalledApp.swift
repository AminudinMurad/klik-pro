import Foundation

enum AppProfileEngine: String, Codable, CaseIterable, Hashable {
    case electron
    case chromium
    case gecko
    case native
}

enum AppProfileEligibilityKind: String, Codable, Equatable {
    case verified
    case experimental
    case unsupported
}

struct AppProfileEligibility: Equatable {
    let kind: AppProfileEligibilityKind
    let reason: String
    let compatibilityRuleID: String?

    static func verified(ruleID: String) -> AppProfileEligibility {
        AppProfileEligibility(
            kind: .verified,
            reason: "Verified for managed App Profiles.",
            compatibilityRuleID: ruleID
        )
    }

    static func experimental(
        _ reason: String,
        ruleID: String? = nil
    ) -> AppProfileEligibility {
        AppProfileEligibility(
            kind: .experimental,
            reason: reason,
            compatibilityRuleID: ruleID
        )
    }

    static func unsupported(_ reason: String) -> AppProfileEligibility {
        AppProfileEligibility(kind: .unsupported, reason: reason, compatibilityRuleID: nil)
    }
}

/// One result from an application scan. Its UUID identifies this scan result rather
/// than pretending that a bundle identifier uniquely identifies an installation.
struct InstalledApp: Identifiable, Codable, Hashable {
    var id: UUID
    var bundleIdentifier: String
    var bundleURL: URL
    var displayName: String
    var version: String?
    var buildVersion: String?
    var executableURL: URL?
    var teamIdentifier: String?
    var hasAppStoreReceipt: Bool
    var hasProvisioningProfile: Bool
    /// The validated signature's `com.apple.security.app-sandbox` entitlement.
    /// `nil` means the signature or entitlements could not be read; eligibility
    /// treats that as fail-closed for provisioned apps.
    var sandboxEntitlement: Bool?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        bundleURL: URL,
        displayName: String,
        version: String? = nil,
        buildVersion: String? = nil,
        executableURL: URL? = nil,
        teamIdentifier: String? = nil,
        hasAppStoreReceipt: Bool = false,
        hasProvisioningProfile: Bool = false,
        sandboxEntitlement: Bool? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL.standardizedFileURL
        self.displayName = displayName
        self.version = version
        self.buildVersion = buildVersion
        self.executableURL = executableURL?.standardizedFileURL
        self.teamIdentifier = teamIdentifier
        self.hasAppStoreReceipt = hasAppStoreReceipt
        self.hasProvisioningProfile = hasProvisioningProfile
        self.sandboxEntitlement = sandboxEntitlement
    }
}
