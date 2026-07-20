import AppKit
import Foundation

private enum EvidenceError: Error, CustomStringConvertible {
    case usage(String)
    case appUnavailable(String)
    case unsupportedIdentity(String)
    case workspaceUnavailable(String)
    case missingEvidence(String)
    case lifecycle(String)

    var description: String {
        switch self {
        case .usage(let value): return value
        case .appUnavailable(let value): return value
        case .unsupportedIdentity(let value): return value
        case .workspaceUnavailable(let value): return value
        case .missingEvidence(let value): return value
        case .lifecycle(let value): return value
        }
    }
}

private struct EvidenceApp: Codable {
    var bundleIdentifier: String
    var teamIdentifier: String
    var engine: AppProfileEngine
    var displayName: String
    var bundlePath: String
}

private struct EvidencePhase: Codable {
    var phase: String
    var date: String
    var version: String?
    var build: String?
    var pid: Int32?
    var verified: Bool?
    var loginPersisted: Bool?
    var primaryUntouched: Bool?
}

private struct EvidenceRecord: Codable {
    var app: EvidenceApp?
    var instanceID: UUID?
    var initialVersion: String?
    var phases: [EvidencePhase]
}

private struct DraftRule: Codable {
    var id: String
    var bundleIdentifier: String
    var teamIdentifier: String
    var engine: AppProfileEngine
    var testedVersions: [String]
}

private struct ParsedArguments {
    let command: String
    let appPath: String?
    let workspacePath: String
    let phase: String?
    let loginPersisted: Bool?
    let primaryUntouched: Bool?
    let environmentOverrides: [String: String]
}

private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()

private let decoder = JSONDecoder()

private func usage() -> String {
    """
    Usage:
      EvidenceMain inspect --app /Applications/App.app --workspace /tmp/ws
      EvidenceMain create --app /Applications/App.app --workspace /tmp/ws [--env KEY=VALUE ...]
      EvidenceMain launch --workspace /tmp/ws
      EvidenceMain attest --workspace /tmp/ws --phase relaunch --login-persisted yes|no
      EvidenceMain attest --workspace /tmp/ws --phase post-update --login-persisted yes|no --primary-untouched yes|no
      EvidenceMain report --workspace /tmp/ws
    """
}

private func parse(_ raw: [String]) throws -> ParsedArguments {
    guard let command = raw.dropFirst().first else { throw EvidenceError.usage(usage()) }
    var appPath: String?
    var workspacePath: String?
    var phase: String?
    var loginPersisted: Bool?
    var primaryUntouched: Bool?
    var environmentOverrides: [String: String] = [:]
    var index = 2

    func boolValue(_ value: String) throws -> Bool {
        switch value.lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: throw EvidenceError.usage("Expected yes or no, got \(value)")
        }
    }

    while index < raw.count {
        let flag = raw[index]
        guard index + 1 < raw.count else { throw EvidenceError.usage(usage()) }
        let value = raw[index + 1]
        switch flag {
        case "--app": appPath = value
        case "--workspace": workspacePath = value
        case "--phase": phase = value
        case "--login-persisted": loginPersisted = try boolValue(value)
        case "--primary-untouched": primaryUntouched = try boolValue(value)
        case "--env":
            guard let separatorIndex = value.firstIndex(of: "=") else {
                throw EvidenceError.usage("Expected --env KEY=VALUE, got \(value)")
            }
            let key = String(value[value.startIndex..<separatorIndex])
            let envValue = String(value[value.index(after: separatorIndex)...])
            environmentOverrides[key] = envValue
        default: throw EvidenceError.usage("Unknown argument: \(flag)")
        }
        index += 2
    }

    guard let workspacePath else { throw EvidenceError.usage("Missing --workspace\n" + usage()) }
    return ParsedArguments(
        command: command,
        appPath: appPath,
        workspacePath: workspacePath,
        phase: phase,
        loginPersisted: loginPersisted,
        primaryUntouched: primaryUntouched,
        environmentOverrides: environmentOverrides
    )
}

private func evidenceURL(in workspace: URL) -> URL {
    workspace.appendingPathComponent("evidence.json", isDirectory: false)
}

private func configURL(in workspace: URL) -> URL {
    workspace.appendingPathComponent("instances.json", isDirectory: false)
}

private func runnerURL(in workspace: URL) throws -> URL {
    let envPath = ProcessInfo.processInfo.environment["KLIK_PRO_EVIDENCE_RUNNER"]
    let url = URL(fileURLWithPath: envPath ?? "", isDirectory: false).standardizedFileURL
    guard !url.path.isEmpty, FileManager.default.isExecutableFile(atPath: url.path) else {
        throw EvidenceError.workspaceUnavailable("Missing compiled evidence runner")
    }
    return url
}

private func ensureWorkspace(_ path: String) throws -> URL {
    // Mirror the shell wrapper's guard so invoking this binary directly can
    // never place a workspace inside live Klik PRO state, and expand a literal
    // "~" the same way the wrapper's realpath step does.
    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    let liveSupport = URL(
        fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Klik PRO",
        isDirectory: true
    ).standardizedFileURL.resolvingSymlinksInPath()
    let resolved = url.resolvingSymlinksInPath()
    guard resolved != liveSupport,
          !resolved.path.hasPrefix(liveSupport.path + "/") else {
        throw EvidenceError.workspaceUnavailable(
            "Evidence workspace must not be inside live Klik PRO Application Support"
        )
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func loadEvidence(from workspace: URL) throws -> EvidenceRecord {
    let url = evidenceURL(in: workspace)
    guard FileManager.default.fileExists(atPath: url.path) else {
        return EvidenceRecord(app: nil, instanceID: nil, initialVersion: nil, phases: [])
    }
    return try decoder.decode(EvidenceRecord.self, from: Data(contentsOf: url))
}

private func saveEvidence(_ record: EvidenceRecord, to workspace: URL) throws {
    try encoder.encode(record).write(to: evidenceURL(in: workspace), options: .atomic)
}

private func loadConfig(from workspace: URL) throws -> KlikProConfig {
    let url = configURL(in: workspace)
    if FileManager.default.fileExists(atPath: url.path) {
        return try decoder.decode(KlikProConfig.self, from: Data(contentsOf: url))
    }
    var config = KlikProConfig.default
    config.instances = []
    config.suppressedLegacyInstanceIDs = []
    return config
}

private func saveConfig(_ config: KlikProConfig, to workspace: URL) -> Bool {
    do {
        try encoder.encode(config).write(to: configURL(in: workspace), options: .atomic)
        return true
    } catch {
        return false
    }
}

private func inspectApp(at path: String) throws -> (InstalledApp, AppProfileEngine) {
    let scanner = AppScanner()
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    guard let app = scanner.inspect(url) else {
        throw EvidenceError.appUnavailable("Unable to inspect app at \(path)")
    }
    guard app.teamIdentifier?.isEmpty == false else {
        throw EvidenceError.unsupportedIdentity("App signature Team ID is unavailable")
    }
    let engine = scanner.engine(for: app)
    guard engine == .electron || engine == .chromium else {
        throw EvidenceError.unsupportedIdentity("Evidence harness only covers Electron/Chromium")
    }
    guard app.version?.isEmpty == false else {
        throw EvidenceError.unsupportedIdentity("App version is unavailable")
    }
    return (app, engine)
}

private func rule(for app: InstalledApp, engine: AppProfileEngine) throws -> AppCompatibilityRule {
    guard let teamIdentifier = app.teamIdentifier,
          let version = app.version else {
        throw EvidenceError.unsupportedIdentity("Missing Team ID or version")
    }
    let id = app.bundleIdentifier
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        + "-evidence"
    return AppCompatibilityRule(
        id: id,
        bundleIdentifier: app.bundleIdentifier,
        teamIdentifier: teamIdentifier,
        engine: engine,
        testedVersions: [version]
    )
}

private func manager(
    workspace: URL,
    app: InstalledApp,
    engine: AppProfileEngine
) throws -> AppProfileManager {
    let generator = LauncherGenerator(
        applicationSupportURL: workspace,
        launcherExecutableURL: try runnerURL(in: workspace)
    )
    let registry = AppCompatibilityRegistry(rules: [try rule(for: app, engine: engine)])
    return AppProfileManager(
        registry: registry,
        generator: generator,
        persist: { saveConfig($0, to: workspace) },
        scanApplications: { _ in [app] },
        inspectApplication: { url in
            url.standardizedFileURL == app.bundleURL ? app : nil
        }
    )
}

private func runtime(
    workspace: URL,
    app: InstalledApp,
    engine: AppProfileEngine
) throws -> AppProfileRuntime {
    let generator = LauncherGenerator(
        applicationSupportURL: workspace,
        launcherExecutableURL: try runnerURL(in: workspace)
    )
    return AppProfileRuntime(
        registry: AppCompatibilityRegistry(rules: [try rule(for: app, engine: engine)]),
        generator: generator,
        inspectApplication: { url in
            url.standardizedFileURL == app.bundleURL ? app : nil
        }
    )
}

private func phase(
    _ name: String,
    app: InstalledApp,
    pid: pid_t? = nil,
    verified: Bool? = nil,
    loginPersisted: Bool? = nil,
    primaryUntouched: Bool? = nil
) -> EvidencePhase {
    EvidencePhase(
        phase: name,
        date: ISO8601DateFormatter().string(from: Date()),
        version: app.version,
        build: app.buildVersion,
        pid: pid,
        verified: verified,
        loginPersisted: loginPersisted,
        primaryUntouched: primaryUntouched
    )
}

private func evidenceApp(from app: InstalledApp, engine: AppProfileEngine) throws -> EvidenceApp {
    guard let teamIdentifier = app.teamIdentifier else {
        throw EvidenceError.unsupportedIdentity("Missing Team ID")
    }
    return EvidenceApp(
        bundleIdentifier: app.bundleIdentifier,
        teamIdentifier: teamIdentifier,
        engine: engine,
        displayName: app.displayName,
        bundlePath: app.bundleURL.path
    )
}

private func commandInspect(_ args: ParsedArguments, workspace: URL) throws {
    guard let appPath = args.appPath else { throw EvidenceError.usage("inspect requires --app") }
    let (app, engine) = try inspectApp(at: appPath)
    var record = try loadEvidence(from: workspace)
    record.app = try evidenceApp(from: app, engine: engine)
    record.phases.append(phase("inspect", app: app))
    try saveEvidence(record, to: workspace)
    print("Inspected \(app.displayName) \(app.version ?? "unknown") [\(engine.rawValue)]")
}

private func commandCreate(_ args: ParsedArguments, workspace: URL) throws {
    guard let appPath = args.appPath else { throw EvidenceError.usage("create requires --app") }
    let (app, engine) = try inspectApp(at: appPath)
    let lifecycle = try manager(workspace: workspace, app: app, engine: engine)
    let candidate = lifecycle.candidate(for: app)
    var config = try loadConfig(from: workspace)
    config.instances.removeAll()
    let id = UUID()
    let result = try lifecycle.create(
        from: candidate,
        label: app.displayName + " Evidence",
        environmentOverrides: args.environmentOverrides,
        config: config,
        instanceID: id
    )
    var record = try loadEvidence(from: workspace)
    record.app = try evidenceApp(from: app, engine: engine)
    record.instanceID = result.instance.id
    record.initialVersion = app.version
    record.phases.append(phase("create", app: app))
    try saveEvidence(record, to: workspace)
    print("Created evidence instance \(result.instance.id.uuidString)")
}

private func existingInstance(in workspace: URL) throws -> AppProfileInstance {
    let config = try loadConfig(from: workspace)
    guard let instance = config.instances.first(where: { $0.launcherKind == .managed }) else {
        throw EvidenceError.missingEvidence("No managed evidence instance in workspace")
    }
    return instance
}

private func inspectedAppFromEvidence(_ record: EvidenceRecord) throws -> (InstalledApp, AppProfileEngine) {
    guard let recorded = record.app else {
        throw EvidenceError.missingEvidence("Evidence record has no inspected app")
    }
    let (app, engine) = try inspectApp(at: recorded.bundlePath)
    // The protocol fails a record on any identity change. A pass attested against
    // a different bundle ID, Team ID, or engine must never reach draft-rule.json.
    guard app.bundleIdentifier == recorded.bundleIdentifier,
          app.teamIdentifier == recorded.teamIdentifier,
          engine == recorded.engine else {
        throw EvidenceError.unsupportedIdentity(
            "App identity changed since inspect/create; evidence record is failed. "
            + "Recorded \(recorded.bundleIdentifier) / \(recorded.teamIdentifier) / "
            + "\(recorded.engine.rawValue); found \(app.bundleIdentifier) / "
            + "\(app.teamIdentifier ?? "-") / \(engine.rawValue). Start a fresh workspace."
        )
    }
    return (app, engine)
}

private func commandLaunch(workspace: URL) throws {
    let record = try loadEvidence(from: workspace)
    let (app, engine) = try inspectedAppFromEvidence(record)
    let instance = try existingInstance(in: workspace)
    let launcher = try runtime(workspace: workspace, app: app, engine: engine)

    var completed = false
    var result: Result<pid_t, AppProfileRuntimeError>?
    DispatchQueue.main.async {
        launcher.launchOrFocus(instance) {
            result = $0
            completed = true
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
    while !completed {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    switch result {
    case .success(let pid):
        var updated = record
        updated.phases.append(phase("launch", app: app, pid: pid, verified: true))
        try saveEvidence(updated, to: workspace)
        print("Launched evidence instance pid \(pid)")
    case .failure(let error):
        throw EvidenceError.lifecycle("Launch failed: \(error)")
    case nil:
        throw EvidenceError.lifecycle("Launch did not complete")
    }
}

private func commandAttest(_ args: ParsedArguments, workspace: URL) throws {
    guard let phaseName = args.phase,
          phaseName == "relaunch" || phaseName == "post-update",
          let loginPersisted = args.loginPersisted else {
        throw EvidenceError.usage("attest requires --phase relaunch|post-update and --login-persisted")
    }
    if phaseName == "post-update", args.primaryUntouched == nil {
        throw EvidenceError.usage("post-update attest requires --primary-untouched")
    }
    let record = try loadEvidence(from: workspace)
    let (app, _) = try inspectedAppFromEvidence(record)
    var updated = record
    updated.phases.append(
        phase(
            phaseName,
            app: app,
            loginPersisted: loginPersisted,
            primaryUntouched: args.primaryUntouched
        )
    )
    try saveEvidence(updated, to: workspace)
    print("Recorded \(phaseName) attestation")
}

private func commandReport(workspace: URL) throws {
    let record = try loadEvidence(from: workspace)
    let relaunch = record.phases.last {
        $0.phase == "relaunch" && $0.loginPersisted == true
    }
    let postUpdate = record.phases.last {
        $0.phase == "post-update"
            && $0.loginPersisted == true
            && $0.primaryUntouched == true
    }
    guard let app = record.app,
          let initialVersion = record.initialVersion,
          let relaunch,
          let postUpdate,
          let updatedVersion = postUpdate.version,
          updatedVersion != initialVersion else {
        print(String(data: try encoder.encode(record), encoding: .utf8) ?? "{}")
        throw EvidenceError.lifecycle("Evidence is not a full pass; draft rule not emitted")
    }
    let testedVersions = Array(Set([initialVersion, relaunch.version, updatedVersion].compactMap { $0 }))
        .sorted()
    let draft = DraftRule(
        id: app.bundleIdentifier
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            + "-verified",
        bundleIdentifier: app.bundleIdentifier,
        teamIdentifier: app.teamIdentifier,
        engine: app.engine,
        testedVersions: testedVersions
    )
    try encoder.encode(draft).write(
        to: workspace.appendingPathComponent("draft-rule.json"),
        options: .atomic
    )
    print(String(data: try encoder.encode(record), encoding: .utf8) ?? "{}")
}

@main
private enum EvidenceMain {
    static func main() {
        do {
            let args = try parse(CommandLine.arguments)
            let workspace = try ensureWorkspace(args.workspacePath)
            switch args.command {
            case "inspect": try commandInspect(args, workspace: workspace)
            case "create": try commandCreate(args, workspace: workspace)
            case "launch": try commandLaunch(workspace: workspace)
            case "attest": try commandAttest(args, workspace: workspace)
            case "report": try commandReport(workspace: workspace)
            default: throw EvidenceError.usage("Unknown command: \(args.command)\n" + usage())
            }
        } catch let error as EvidenceError {
            fputs("ERROR: \(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("ERROR: \(error)\n", stderr)
            exit(1)
        }
    }
}
