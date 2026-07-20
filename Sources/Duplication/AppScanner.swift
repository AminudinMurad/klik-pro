import Foundation
import Security

struct AppScanner {
    private let fileManager: FileManager
    private let engineDetector: EngineDetector

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        engineDetector = EngineDetector(fileManager: fileManager)
    }

    func scan(searchRoots: [URL]? = nil) -> [InstalledApp] {
        let roots = searchRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]

        var seen = Set<String>()
        return roots.flatMap { root -> [InstalledApp] in
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return entries.compactMap { inspect($0) }
        }
        .filter { seen.insert($0.bundleURL.path).inserted }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func inspect(_ url: URL) -> InstalledApp? {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.pathExtension.lowercased() == "app",
              !isManagedLauncher(standardizedURL),
              let bundle = Bundle(url: standardizedURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let executableURL = bundle.executableURL?.standardizedFileURL
        guard executableURL.map({ fileManager.isExecutableFile(atPath: $0.path) }) == true else {
            return nil
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? standardizedURL.deletingPathExtension().lastPathComponent
        let receiptURL = standardizedURL
            .appendingPathComponent("Contents/_MASReceipt/receipt", isDirectory: false)
        let provisioningURL = standardizedURL
            .appendingPathComponent("Contents/embedded.provisionprofile", isDirectory: false)

        let signing = validatedSigningIdentity(at: standardizedURL)
        return InstalledApp(
            bundleIdentifier: bundleIdentifier,
            bundleURL: standardizedURL,
            displayName: displayName,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
            executableURL: executableURL,
            teamIdentifier: signing.teamIdentifier,
            hasAppStoreReceipt: fileManager.fileExists(atPath: receiptURL.path),
            hasProvisioningProfile: fileManager.fileExists(atPath: provisioningURL.path),
            sandboxEntitlement: signing.sandboxEntitlement
        )
    }

    func isManagedLauncher(_ url: URL) -> Bool {
        Bundle(url: url)?.bundleIdentifier?.hasPrefix("local.klik-pro.launcher.") == true
    }

    func engine(for app: InstalledApp) -> AppProfileEngine {
        engineDetector.detect(app)
    }

    private struct ValidatedSigningIdentity {
        let teamIdentifier: String?
        let sandboxEntitlement: Bool?
    }

    private func validatedSigningIdentity(at bundleURL: URL) -> ValidatedSigningIdentity {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return ValidatedSigningIdentity(teamIdentifier: nil, sandboxEntitlement: nil)
        }
        let validationFlags = SecCSFlags(
            rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures
        )
        guard SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess else {
            // Signing metadata is not an identity proof when the bundle no longer
            // validates. Returning neither a Team ID nor a sandbox verdict keeps
            // registry matching and provisioned-app eligibility fail-closed.
            return ValidatedSigningIdentity(teamIdentifier: nil, sandboxEntitlement: nil)
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let info = signingInformation as? [String: Any] else {
            return ValidatedSigningIdentity(teamIdentifier: nil, sandboxEntitlement: nil)
        }
        // With a validated signature, an absent entitlements dictionary or an
        // absent app-sandbox key is proof of "not sandboxed", not an unknown.
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let sandboxEntitlement =
            (entitlements?["com.apple.security.app-sandbox"] as? Bool) ?? false
        return ValidatedSigningIdentity(
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            sandboxEntitlement: sandboxEntitlement
        )
    }
}
