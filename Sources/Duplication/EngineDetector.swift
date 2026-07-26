import Foundation

enum AppCompatibilityRuleError: Error, Equatable {
    case unresolvedEnvironmentToken(String)
}

struct AppCompatibilityRule: Equatable {
    let id: String
    /// Exact display name used by `docs/COMPATIBILITY.md`.
    let catalogueName: String
    let bundleIdentifier: String
    let teamIdentifier: String
    let engine: AppProfileEngine
    /// Extra environment an explicitly supported app requires for real profile isolation
    /// (e.g. CODEX_HOME for Codex-family apps). Values may contain the
    /// `{profileDir}` placeholder (the instance's UUID-keyed profile path) or
    /// the `{codexHomeDir}` placeholder (the instance's UUID-keyed sibling
    /// home under `CodexHomes/`, kept outside the profile so the app's own
    /// symlinks never enter the profile-deletion path) — never labels.
    /// Compiled-in only; never persisted.
    var requiredEnvironment: [String: String] = [:]
    /// Extra profile-isolation arguments beyond `--user-data-dir`. Templates may
    /// contain `{profileDir}` and are compiled in with the exact app rule.
    var additionalArguments: [String] = []
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

    init(
        id: String,
        catalogueName: String,
        bundleIdentifier: String,
        teamIdentifier: String,
        engine: AppProfileEngine,
        requiredEnvironment: [String: String] = [:],
        additionalArguments: [String] = [],
        homeSymlinkPrefix: String? = nil,
        passesUserDataDirArgument: Bool = true,
        requiresLoginKeychainLink: Bool = false
    ) {
        self.id = id
        self.catalogueName = catalogueName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.engine = engine
        self.requiredEnvironment = requiredEnvironment
        self.additionalArguments = additionalArguments
        self.homeSymlinkPrefix = homeSymlinkPrefix
        self.passesUserDataDirArgument = passesUserDataDirArgument
        self.requiresLoginKeychainLink = requiresLoginKeychainLink
    }

    /// Evidence tooling may construct a temporary, non-production rule while it
    /// exercises an isolation recipe. The version set is deliberately discarded:
    /// evidence must never become catalogue or badge authority.
    init(
        id: String,
        bundleIdentifier: String,
        teamIdentifier: String,
        engine: AppProfileEngine,
        testedVersions: Set<String>
    ) {
        _ = testedVersions
        self.init(
            id: id,
            catalogueName: bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            engine: engine
        )
    }

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

    func resolvedLaunchArguments(profileDirectory: String) throws -> [String] {
        var arguments = passesUserDataDirArgument
            ? ["--user-data-dir=" + profileDirectory]
            : []
        for template in additionalArguments {
            let value = template.replacingOccurrences(
                of: "{profileDir}",
                with: profileDirectory
            )
            if value.range(of: "\\{[^}]*\\}", options: .regularExpression) != nil {
                throw AppCompatibilityRuleError.unresolvedEnvironmentToken(template)
            }
            arguments.append(value)
        }
        return arguments
    }

    func matches(app: InstalledApp, detectedEngine: AppProfileEngine) -> Bool {
        app.bundleIdentifier == bundleIdentifier
            && app.teamIdentifier == teamIdentifier
            && detectedEngine == engine
    }
}

struct AppCompatibilityRegistry {
    /// `docs/COMPATIBILITY.md` is the sole product authority for the shipping
    /// catalogue and badge (owner decision 2026-07-26). Every exact rule in
    /// `production` is therefore Verified. Bundle ID, Team ID and engine remain
    /// pinned as security/identity gates, but version or test evidence never
    /// promotes or demotes an app. Change the document first, then mirror it here.
    static let production = AppCompatibilityRegistry(rules: [
        AppCompatibilityRule(
            id: "com-anthropic-claudefordesktop-verified",
            catalogueName: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            teamIdentifier: "Q6L2SF6YDW",
            engine: .electron,
            requiredEnvironment: [
                "CLAUDE_CONFIG_DIR": "{codexHomeDir}",
            ],
            homeSymlinkPrefix: "claude"
        ),
        AppCompatibilityRule(
            // Persisted/frozen ID: the historical suffix does not control the badge.
            id: "com-openai-codex-untested",
            catalogueName: "ChatGPT / Codex",
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "2DC432GLL2",
            engine: .electron,
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
        AppCompatibilityRule(
            // Persisted/frozen ID: the historical suffix does not control the badge.
            id: "com-google-geminimacos-native-untested",
            catalogueName: "Gemini",
            bundleIdentifier: "com.google.GeminiMacOS",
            teamIdentifier: "EQHXZ8M8AV",
            engine: .native,
            requiredEnvironment: [
                "CFFIXED_USER_HOME": "{profileDir}",
            ],
            homeSymlinkPrefix: nil,
            passesUserDataDirArgument: false,
            requiresLoginKeychainLink: true
        ),
        // Canva (com.canva.CanvaDesktop) — Electron, unsandboxed. Isolation is the
        // stock `--user-data-dir`, verified 2026-07-25: a second instance built its
        // own cookie jar and ran alongside the first, each signed in separately.
        // Its sign-in is brokered through the default browser, so the callback can
        // land on whichever instance LaunchServices picks.
        AppCompatibilityRule(
            id: "com-canva-canvadesktop",
            catalogueName: "Canva",
            bundleIdentifier: "com.canva.CanvaDesktop",
            teamIdentifier: "5HD2ARTBFS",
            engine: .electron
        ),
        // Zoom (us.zoom.xos) — native and unsandboxed, so isolation is
        // CFFIXED_USER_HOME. Verified 2026-07-25: a redirected instance built its own
        // encrypted stores and left the real profile untouched. It implements no
        // profile flag, so the user-data-dir argument is suppressed.
        AppCompatibilityRule(
            id: "com-zoom-xos",
            catalogueName: "Zoom",
            bundleIdentifier: "us.zoom.xos",
            teamIdentifier: "BJ4HAAB9B3",
            engine: .native,
            requiredEnvironment: ["CFFIXED_USER_HOME": "{profileDir}"],
            passesUserDataDirArgument: false,
            requiresLoginKeychainLink: true
        ),
        // Spotify (com.spotify.client) — CEF, detected as native here, unsandboxed.
        // Verified 2026-07-25 with nothing else running: 181 files landed in the
        // redirected home and the real profile was untouched. Note it enforces an
        // app-level single instance, so profiles switch rather than run side by side.
        AppCompatibilityRule(
            id: "com-spotify-client",
            catalogueName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            teamIdentifier: "2FNC3A47ZF",
            engine: .native,
            requiredEnvironment: ["CFFIXED_USER_HOME": "{profileDir}"],
            passesUserDataDirArgument: false,
            requiresLoginKeychainLink: true
        ),
        // Antigravity and its IDE (Google, team EQHXZ8M8AV) — both Electron and
        // unsandboxed, with `user-data-dir` present in their bundled framework, so
        // the stock argument is the whole recipe. The IDE is a VS Code fork, so a
        // profile isolates settings and extensions along with the sign-in.
        AppCompatibilityRule(
            id: "com-google-antigravity",
            catalogueName: "Antigravity",
            bundleIdentifier: "com.google.antigravity",
            teamIdentifier: "EQHXZ8M8AV",
            engine: .electron
        ),
        AppCompatibilityRule(
            id: "com-google-antigravity-ide",
            catalogueName: "Antigravity IDE",
            bundleIdentifier: "com.google.antigravity-ide",
            teamIdentifier: "EQHXZ8M8AV",
            engine: .electron
        ),
        // Chromium browsers. `--user-data-dir` is the same flag Chrome has always
        // taken, and both are already recognised as `.chromium` by the detector.
        // Note both ship their own concurrent profile switcher, so a Klik PRO profile
        // mainly adds a separate Dock tile rather than new capability.
        AppCompatibilityRule(
            id: "com-google-chrome",
            catalogueName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            teamIdentifier: "EQHXZ8M8AV",
            engine: .chromium
        ),
        AppCompatibilityRule(
            id: "com-brave-browser",
            catalogueName: "Brave",
            bundleIdentifier: "com.brave.Browser",
            teamIdentifier: "KL8N8XSYF4",
            engine: .chromium
        ),
        // Identity metadata for Cursor and VS Code was read from the signed apps
        // installed on this Mac on 2026-07-26. The remaining four identities were
        // read from each vendor's official signed macOS disk image the same day.
        AppCompatibilityRule(
            id: "com-todesktop-230313mzl4w4u92",
            catalogueName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            teamIdentifier: "VDXQ22DGB9",
            engine: .electron,
            additionalArguments: ["--extensions-dir={profileDir}/extensions"]
        ),
        AppCompatibilityRule(
            id: "com-hnc-discord",
            catalogueName: "Discord",
            bundleIdentifier: "com.hnc.Discord",
            teamIdentifier: "53Q6R32WPB",
            engine: .electron
        ),
        AppCompatibilityRule(
            id: "notion-id",
            catalogueName: "Notion",
            bundleIdentifier: "notion.id",
            teamIdentifier: "LBQJ96FQ8D",
            engine: .electron
        ),
        AppCompatibilityRule(
            id: "md-obsidian",
            catalogueName: "Obsidian",
            bundleIdentifier: "md.obsidian",
            teamIdentifier: "6JSW4SJWN9",
            engine: .electron
        ),
        AppCompatibilityRule(
            id: "com-tinyspeck-slackmacgap",
            catalogueName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            teamIdentifier: "BQR82RBBHL",
            engine: .electron
        ),
        AppCompatibilityRule(
            id: "com-microsoft-vscode",
            catalogueName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            teamIdentifier: "UBF8T346G9",
            engine: .electron,
            additionalArguments: ["--extensions-dir={profileDir}/extensions"]
        ),
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
            return .verified(ruleID: rule.id)
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
