import Foundation

/// Structured contract between Klik PRO and its small generated launcher bundle.
/// Keeping it in a standalone source lets the launcher executable compile without
/// importing config, UI, mouse, or helper code.
struct ManagedLauncherPayload: Codable, Equatable {
    let sourceBundlePath: String
    let arguments: [String]
    let environment: [String: String]
    let compatibilityRuleID: String
}
