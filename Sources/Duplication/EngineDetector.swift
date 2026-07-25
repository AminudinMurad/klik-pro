import Foundation

enum AppCompatibilityRuleError: Error, Equatable {
    case unresolvedEnvironmentToken(String)
}

enum AppCompatibilityAssurance: Equatable {
    case verified
    case untested
}

struct AppCompatibilityRule: Equatable {
    let id: String
    let bundleIdentifier: String
    let teamIdentifier: String
    let engine: AppProfileEngine
    let testedVersions: Set<String>
    /// The approved catalogue is app-level. Evidence versions remain recorded,
    /// while an approved rule may accept vendor updates without weakening its
    /// pinned bundle, signing identity, engine, or isolation recipe.
    var assurance: AppCompatibilityAssurance = .verified
    var acceptsAnyVersion = false
    /// Extra environment an explicitly supported app requires for real profile isolation
    /// (e.g. CODEX_HOME for Codex-family apps). Values may contain the
    /// `{profileDir}` placeholder (the instance's UUID-keyed profile path) or
    /// the `{codexHomeDir}` placeholder (the instance's UUID-keyed sibling
    /// home under `CodexHomes/`, kept outside the profile so the app's own
    /// symlinks never enter the profile-deletion path) — never labels.
    /// Compiled-in only; never persisted.
    var requiredEnvironment: [String: String] = [:]
    /// Dot-folder family prefix for the instance's visible home symlink in `~`
    /// (e.g. "claude" → `~/.claude-a` for a "Claude A" profile). Multi-account
    /// scanners detect CLI homes by these dot-folder names; the symlink points
    /// at the real UUID-keyed sibling home. `nil` means no visible link.
    var homeSymlinkPrefix: String? = nil
    /// Electron and Chromium profiles are selected with `--user-data-dir=`.
    /// Native-engine apps that isolate purely through environment implement no
    /// such flag, and an unrecognised argument must not be assumed harmless, so
    /// those rules opt out of emitting it.
    var passesUserDataDirArgument = true
    /// Native apps whose credential store is Keychain-backed need the user's
    /// login keychain reachable *inside* the redirected home, because the
    /// keychain search path is home-relative. Without it the app silently sets
    /// `can_persist_config=0` and the sign-in is lost on quit rather than
    /// failing loudly. The launcher provisions `Library/Keychains` inside the
    /// isolated home as a symlink to the real `~/Library/Keychains`.
    ///
    /// SAFETY: that link points at the user's actual keychains. Every removal
    /// path that can reach the isolated home must delete the *link* and never
    /// follow it. Foundation's `removeItem` and `trashItem` both operate on the
    /// link itself, which is what this codebase uses.
    var requiresLoginKeychainLink = false

    /// Expands `{profileDir}` and `{codexHomeDir}` in each required value.
    /// Any other unresolved `{...}` token is a rule-authoring error and
    /// fails closed.
    func resolvedEnvironment(
        profileDirectory: String,
        codexHomeDirectory: String
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]
        for (key, template) in requiredEnvironment {
            let value = template
                .replacingOccurrences(of: "{profileDir}", with: profileDirectory)
                .replacingOccurrences(of: "{codexHomeDir}", with: codexHomeDirectory)
            if value.range(of: "\\{[^}]*\\}", options: .regularExpression) != nil {
                throw AppCompatibilityRuleError.unresolvedEnvironmentToken(key)
            }
            resolved[key] = value
        }
        return resolved
    }

    func matches(app: InstalledApp, detectedEngine: AppProfileEngine) -> Bool {
        guard app.bundleIdentifier == bundleIdentifier,
              app.teamIdentifier == teamIdentifier,
              detectedEngine == engine else {
            return false
        }
        if acceptsAnyVersion { return true }
        guard let version = app.version else { return false }
        return testedVersions.contains(version)
    }
}

struct AppCompatibilityRegistry {
    /// Verified entries require the full evidence protocol. Untested entries
    /// require an explicit owner decision and remain visibly labelled Untested.
    ///
    /// Claude (com.anthropic.claudefordesktop): both gates passed 2026-07-16
    /// against the real vendor update 1.21459.0 → 1.21459.1; evidence record
    /// and emitted draft rule preserved in the evidence workspace. App-level
    /// isolation is `--user-data-dir`. Owner decision 2026-07-19: the rule
    /// additionally points CLAUDE_CONFIG_DIR at the instance's sibling home so
    /// the embedded Claude Code CLI side is isolated per instance and visible
    /// to multi-account scanners via the home symlink; this environment
    /// addition still needs its own on-machine re-attestation (login
    /// persistence + update survival) before the next release gate.
    ///
    /// ChatGPT is owner-enabled as Untested. Its known isolation recipe is
    /// retained, but no vendor-update verification claim is made.
    static let production = AppCompatibilityRegistry(rules: [
        AppCompatibilityRule(
            id: "com-anthropic-claudefordesktop-verified",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            teamIdentifier: "Q6L2SF6YDW",
            engine: .electron,
            testedVersions: ["1.21459.0", "1.21459.1"],
            acceptsAnyVersion: true,
            requiredEnvironment: [
                "CLAUDE_CONFIG_DIR": "{codexHomeDir}",
            ],
            homeSymlinkPrefix: "claude"
        ),
        AppCompatibilityRule(
            id: "com-openai-codex-untested",
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "2DC432GLL2",
            engine: .electron,
            testedVersions: [],
            assurance: .untested,
            acceptsAnyVersion: true,
            requiredEnvironment: [
                "CODEX_HOME": "{codexHomeDir}",
                "CODEX_ELECTRON_USER_DATA_PATH": "{profileDir}",
            ],
            homeSymlinkPrefix: "codex"
        ),
        // Gemini (com.google.GeminiMacOS) — the first native-engine entry.
        //
        // Evidence 2026-07-25 on 1.86.7.600: five accounts isolated
        // simultaneously, each with its own account slot, cookie jar and chat
        // store; cold start restored a sign-in with `StartNewOAuth` count 0 and
        // `new=0`; verified again after relocating a live profile into the vault.
        //
        // Isolation is CFFIXED_USER_HOME *only*. Plain HOME does nothing —
        // macOS Foundation resolves the home directory from the password
        // database and ignores the variable (probe-verified), and unsetting HOME
        // entirely still restored the login. The app implements no
        // profile/user-data flag, so `--user-data-dir=` is suppressed here.
        //
        // Known residual leak: `~/Library/Preferences/com.google.GeminiMacOS.plist`
        // stays shared, because cfprefsd resolves the per-user domain and
        // ignores CFFIXED_USER_HOME. That covers feature flags and window
        // frames; accounts do not collide, since every isolated profile names
        // its own slot `user1`.
        //
        // Untested, not verified: login persistence and cold start are proven,
        // but this rule has not yet survived a real vendor update, which is the
        // second gate the catalogue requires before a `.verified` claim.
        AppCompatibilityRule(
            id: "com-google-geminimacos-native-untested",
            bundleIdentifier: "com.google.GeminiMacOS",
            teamIdentifier: "EQHXZ8M8AV",
            engine: .native,
            testedVersions: ["1.86.7.600"],
            assurance: .untested,
            acceptsAnyVersion: true,
            requiredEnvironment: [
                "CFFIXED_USER_HOME": "{profileDir}",
            ],
            homeSymlinkPrefix: nil,
            passesUserDataDirArgument: false,
            requiresLoginKeychainLink: true
        )
    ])

    let rules: [AppCompatibilityRule]

    func matchingRule(for app: InstalledApp, engine: AppProfileEngine) -> AppCompatibilityRule? {
        rules.first { $0.matches(app: app, detectedEngine: engine) }
    }

    func rule(withID id: String) -> AppCompatibilityRule? {
        rules.first { $0.id == id }
    }
}

struct EngineDetector {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detect(_ app: InstalledApp) -> AppProfileEngine {
        let contents = app.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)

        if fileManager.fileExists(atPath: macOS.appendingPathComponent("XUL").path)
            || fileManager.fileExists(atPath: macOS.appendingPathComponent("omni.ja").path) {
            return .gecko
        }

        let chromiumBundleIdentifiers: Set<String> = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.vivaldi.Vivaldi"
        ]
        if chromiumBundleIdentifiers.contains(app.bundleIdentifier) {
            return .chromium
        }

        if fileManager.fileExists(
            atPath: frameworks.appendingPathComponent("Electron Framework.framework").path
        ) || hasRenamedElectronFramework(in: frameworks, app: app) {
            return .electron
        }

        return .native
    }

    func eligibility(
        for app: InstalledApp,
        registry: AppCompatibilityRegistry = .production
    ) -> AppProfileEligibility {
        if app.hasAppStoreReceipt {
            return .unsupported("App Store apps are not supported.")
        }
        if app.sandboxEntitlement == true {
            return .unsupported("Sandboxed apps cannot reach an isolated profile directory.")
        }
        if app.hasProvisioningProfile && app.sandboxEntitlement == nil {
            // A provisioning profile is only a problem when the app is sandboxed
            // (push-notification profiles on regular apps are harmless), but an
            // unverifiable sandbox entitlement must stay fail-closed.
            return .unsupported("This provisioned app's sandbox entitlement could not be verified.")
        }

        let engine = detect(app)
        if let rule = registry.matchingRule(for: app, engine: engine) {
            switch rule.assurance {
            case .verified:
                return .verified(ruleID: rule.id)
            case .untested:
                return .experimental(
                    "Known isolation method; enabled without update-survival verification.",
                    ruleID: rule.id
                )
            }
        }

        switch engine {
        case .electron, .chromium:
            return .experimental("Engine detected; testing is required before creation is enabled.")
        case .gecko:
            return .experimental("Firefox-family profile creation is planned for v2.1.")
        case .native:
            return .unsupported("This app does not expose a supported profile-isolation engine.")
        }
    }

    private func hasRenamedElectronFramework(in frameworks: URL, app: InstalledApp) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: frameworks,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let hasFrameworkCandidate = entries.contains { url in
            url.pathExtension == "framework"
                && url.lastPathComponent.hasSuffix(" Framework.framework")
        }
        // ChatGPT/Codex currently renames Electron Framework.framework to
        // Codex Framework.framework. Keep this an engine hint only; registry
        // identity and signing checks still gate compatibility below.
        let hasCodexFramework = entries.contains { url in
            url.lastPathComponent == "Codex Framework.framework"
        }
        let infoURL = app.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard hasFrameworkCandidate || hasCodexFramework,
              let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return false
        }

        // A renamed framework by itself never grants compatibility. It is only an
        // engine hint, and eligibility remains Experimental without a registry rule.
        return info.keys.contains { $0.localizedCaseInsensitiveContains("electron") }
            || info.values.contains { value in
                String(describing: value).localizedCaseInsensitiveContains("electron")
            }
    }
}
