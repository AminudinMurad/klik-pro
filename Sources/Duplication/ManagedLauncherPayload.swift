import Foundation

enum ManagedLauncherProfileStorage: String, Codable, Equatable {
    case applicationSupport
    case vault
}

/// Structured contract between Klik PRO and its small generated launcher bundle.
/// Keeping it in a standalone source lets the launcher executable compile without
/// importing config, UI, mouse, or helper code.
struct ManagedLauncherPayload: Codable, Equatable {
    let sourceBundlePath: String
    let arguments: [String]
    let environment: [String: String]
    let compatibilityRuleID: String
    /// Signed absolute profile path. The runner validates this against the UUID,
    /// storage layout, ownership marker, and baked argument before using it.
    let profileDirectory: String
    let profileStorage: ManagedLauncherProfileStorage

    func validatedProfileURL(
        instanceID: UUID,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let profile = URL(fileURLWithPath: profileDirectory, isDirectory: true)
            .standardizedFileURL
        guard arguments == ["--user-data-dir=" + profile.path],
              profile.path == profileDirectory,
              profile.resolvingSymlinksInPath().standardizedFileURL == profile,
              let values = try? profile.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return nil
        }

        switch profileStorage {
        case .applicationSupport:
            let expected = applicationSupportURL.standardizedFileURL
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent(
                    instanceID.uuidString.uppercased(), isDirectory: true
                )
            guard profile == expected,
                  expected.deletingLastPathComponent().resolvingSymlinksInPath()
                    .standardizedFileURL == expected.deletingLastPathComponent() else {
                return nil
            }
        case .vault:
            let container = profile.deletingLastPathComponent()
            let instances = container.deletingLastPathComponent()
            guard profile.lastPathComponent == "user-data",
                  container.lastPathComponent.caseInsensitiveCompare(
                    instanceID.uuidString
                  ) == .orderedSame,
                  instances.lastPathComponent == "Instances",
                  container.resolvingSymlinksInPath().standardizedFileURL == container,
                  instances.resolvingSymlinksInPath().standardizedFileURL == instances else {
                return nil
            }
        }

        let marker = profile.appendingPathComponent(".klik-pro-owned-profile")
        guard let markerValues = try? marker.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              markerValues.isRegularFile == true,
              markerValues.isSymbolicLink != true,
              let data = fileManager.contents(atPath: marker.path),
              String(decoding: data, as: UTF8.self)
                == instanceID.uuidString.uppercased() else {
            return nil
        }
        return profile
    }
}
