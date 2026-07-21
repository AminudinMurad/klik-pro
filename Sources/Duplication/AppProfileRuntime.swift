import AppKit
import Darwin
import Foundation

enum ManagedProcessScan: Equatable {
    case complete([pid_t])
    case incomplete
}

/// A momentary process race — a second instance still spawning, or an old one
/// mid-exit — briefly makes a profile's scan report more than one root, or fail
/// to complete. Re-scan a bounded number of times, settling between attempts, so
/// launch/focus no longer hard-fails with `ambiguousProcesses` on a transient
/// double-process; only a result that persists across the whole budget is
/// returned. Mirrors the removal path's re-scan. `settle` runs between attempts,
/// never after the final one.
func settledManagedProcessScan(
    attempts: Int,
    scan: () -> ManagedProcessScan,
    settle: () -> Void
) -> ManagedProcessScan {
    var result = scan()
    var attemptsLeft = Swift.max(1, attempts) - 1
    while attemptsLeft > 0, managedProcessScanIsTransient(result) {
        settle()
        result = scan()
        attemptsLeft -= 1
    }
    return result
}

/// Transient = not yet a stable launch/focus decision: an incomplete scan, or
/// more than one root process for the profile. Exactly one root (focus) and zero
/// roots (launch fresh) are both stable and end the re-scan immediately.
func managedProcessScanIsTransient(_ scan: ManagedProcessScan) -> Bool {
    switch scan {
    case .incomplete:
        return true
    case .complete(let pids):
        return pids.count > 1
    }
}

/// Reads process identity without invoking `ps`, `pgrep`, a shell, or an external
/// focus utility. KERN_PROCARGS2 parsing stops after the declared argc so environment
/// variables are never inspected or exposed.
struct ManagedProcessInspector {
    private let listProcesses: () -> [pid_t]?
    private let executablePath: (pid_t) -> String?
    private let processArguments: (pid_t) -> [String]?

    init(
        listProcesses: @escaping () -> [pid_t]? = ManagedProcessInspector.livePIDs,
        executablePath: @escaping (pid_t) -> String? = ManagedProcessInspector.liveExecutablePath,
        processArguments: @escaping (pid_t) -> [String]? = ManagedProcessInspector.liveArguments
    ) {
        self.listProcesses = listProcesses
        self.executablePath = executablePath
        self.processArguments = processArguments
    }

    func verifies(
        pid: pid_t,
        executableURL: URL,
        profileURL: URL
    ) -> Bool {
        guard executablePath(pid) == executableURL.standardizedFileURL.path,
              let arguments = processArguments(pid) else {
            return false
        }
        return arguments.contains("--user-data-dir=" + profileURL.standardizedFileURL.path)
    }

    /// Finds exact root processes for one managed instance. An unreadable argument
    /// vector on the expected executable makes the whole result incomplete.
    func verifiedRoots(
        executableURL: URL,
        profileURL: URL
    ) -> ManagedProcessScan {
        guard let pids = listProcesses() else { return .incomplete }
        let expectedExecutable = executableURL.standardizedFileURL.path
        let expectedArgument = "--user-data-dir=" + profileURL.standardizedFileURL.path
        var matches: [pid_t] = []
        for pid in pids where pid > 0 && pid != getpid() {
            guard executablePath(pid) == expectedExecutable else { continue }
            guard let arguments = processArguments(pid) else { return .incomplete }
            if arguments.contains(expectedArgument) { matches.append(pid) }
        }
        return .complete(matches.sorted())
    }

    /// Scans only processes executing from the exact source bundle. Any candidate
    /// whose argv cannot be read blocks deletion because it may reference the profile.
    func profileReferences(
        sourceBundleURL: URL,
        profileURL: URL
    ) -> ManagedProcessScan {
        guard let pids = listProcesses() else { return .incomplete }
        let sourceRoot = sourceBundleURL.standardizedFileURL.path + "/"
        let profilePath = profileURL.standardizedFileURL.path
        let profileArgument = "--user-data-dir=" + profilePath
        var references: [pid_t] = []
        for pid in pids where pid > 0 && pid != getpid() {
            guard let path = executablePath(pid), path.hasPrefix(sourceRoot) else { continue }
            guard let arguments = processArguments(pid) else { return .incomplete }
            if arguments.contains(where: {
                $0 == profileArgument || $0 == profilePath || $0.hasPrefix(profilePath + "/")
            }) {
                references.append(pid)
            }
        }
        return .complete(references.sorted())
    }

    static func parseArguments(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: Int32.self)
        }
        guard argc > 0, argc < 65_536 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < bytes.count && bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { return nil }
        while index < bytes.count && bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < Int(argc) {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count && bytes[index] != 0 { index += 1 }
            guard index < bytes.count else { return nil }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    private static func livePIDs() -> [pid_t]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) * 2)
        let count = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard count > 0 else { return nil }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    private static func liveExecutablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func liveArguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseArguments(Data(buffer.prefix(size)))
    }
}

enum ManagedInstanceLockMode {
    case shared
    case exclusive
}

final class ManagedInstanceLock {
    private var descriptor: Int32

    init?(applicationSupportURL: URL, instanceID: UUID, mode: ManagedInstanceLockMode) {
        let root = applicationSupportURL.standardizedFileURL
            .appendingPathComponent("Locks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  root.resolvingSymlinksInPath() == root else { return nil }
        } catch {
            return nil
        }

        let lockURL = root.appendingPathComponent(
            instanceID.uuidString.uppercased() + ".lock",
            isDirectory: false
        )
        descriptor = open(
            lockURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { return nil }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              fchmod(descriptor, 0o600) == 0 else {
            close(descriptor)
            descriptor = -1
            return nil
        }
        let operation = (mode == .shared ? LOCK_SH : LOCK_EX) | LOCK_NB
        guard flock(descriptor, operation) == 0 else {
            close(descriptor)
            descriptor = -1
            return nil
        }
    }

    deinit {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

enum AppProfileRuntimeHealth: Equatable {
    case ready
    case sourceUnavailable
    case verificationRequired(String)
    case launcherUnavailable
    case externalUnavailable

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .sourceUnavailable: return "Source missing"
        case .verificationRequired: return "Unavailable"
        case .launcherUnavailable: return "Launcher invalid"
        case .externalUnavailable: return "External launcher missing"
        }
    }
}

enum AppProfileRuntimeError: Error, Equatable {
    case unavailable(AppProfileRuntimeHealth)
    case processScanIncomplete
    case ambiguousProcesses
    case launchFailed
    case processVerificationFailed
    case activationFailed
}

/// Runtime service shared by Settings and the existing unified helper. Every managed
/// action re-inspects the source and exact Verified rule before looking up, launching,
/// or activating an exact PID. Labels and process names never participate in routing.
struct AppProfileRuntime {
    private struct ManagedContext {
        let app: InstalledApp
        let profileURL: URL
        let executableURL: URL
    }

    private let inspectApplication: (URL) -> InstalledApp?
    private let detector: EngineDetector
    private let registry: AppCompatibilityRegistry
    private let generator: LauncherGenerator
    private let processInspector: ManagedProcessInspector
    private let applicationSupportURL: URL

    init(
        scanner: AppScanner = AppScanner(),
        detector: EngineDetector = EngineDetector(),
        registry: AppCompatibilityRegistry = .production,
        generator: LauncherGenerator = LauncherGenerator(),
        processInspector: ManagedProcessInspector = ManagedProcessInspector(),
        inspectApplication: ((URL) -> InstalledApp?)? = nil
    ) {
        self.inspectApplication = inspectApplication ?? { scanner.inspect($0) }
        self.detector = detector
        self.registry = registry
        self.generator = generator
        self.processInspector = processInspector
        applicationSupportURL = generator.applicationSupportURL
    }

    func health(for instance: AppProfileInstance) -> AppProfileRuntimeHealth {
        if instance.launcherKind == .legacyExternal {
            let url = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
                .standardizedFileURL
            guard url.pathExtension.lowercased() == "app",
                  FileManager.default.fileExists(atPath: url.path) else {
                return .externalUnavailable
            }
            if let target = instance.legacyQuickLaunchTarget,
               (url.path != target.launcherWrapperPath || !quickLaunchTargetIsAvailable(target)) {
                return .externalUnavailable
            }
            return .ready
        }
        do {
            _ = try managedContext(for: instance)
            return .ready
        } catch let error as AppProfileRuntimeError {
            guard case .unavailable(let health) = error else { return .launcherUnavailable }
            return health
        } catch {
            return .launcherUnavailable
        }
    }

    func launchOrFocus(
        _ instance: AppProfileInstance,
        completion: @escaping (Result<pid_t, AppProfileRuntimeError>) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.launchOrFocus(instance, completion: completion)
            }
            return
        }
        if instance.launcherKind == .legacyExternal {
            launchExternal(instance, completion: completion)
            return
        }

        let context: ManagedContext
        do {
            context = try managedContext(for: instance)
        } catch let error as AppProfileRuntimeError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.unavailable(.launcherUnavailable)))
            return
        }
        guard let operationLock = ManagedInstanceLock(
            applicationSupportURL: applicationSupportURL,
            instanceID: instance.id,
            mode: .shared
        ) else {
            completion(.failure(.processScanIncomplete))
            return
        }

        // A menu-bar click can land during a launch/exit race where the profile
        // momentarily shows two roots (or an unreadable arg vector). A single scan
        // then hard-fails with ambiguousProcesses even though it settles a moment
        // later — the reported regression. Re-scan with a short settle so a
        // transient race resolves to focus/launch; genuine, persistent ambiguity
        // still fails closed. Bounded and only on a transient, so the common
        // (clean first scan) path adds no delay. This helper runs on the main
        // thread (menu-bar/hotkey), so the settle is deliberately short.
        let processScan = settledManagedProcessScan(
            attempts: 3,
            scan: {
                self.processInspector.verifiedRoots(
                    executableURL: context.executableURL,
                    profileURL: context.profileURL
                )
            },
            settle: { Thread.sleep(forTimeInterval: 0.1) }
        )
        switch processScan {
        case .incomplete:
            withExtendedLifetime(operationLock) {
                completion(.failure(.processScanIncomplete))
            }
        case .complete(let pids) where pids.count > 1:
            withExtendedLifetime(operationLock) {
                completion(.failure(.ambiguousProcesses))
            }
        case .complete:
            // Zero processes → launch fresh; exactly one → reopen the existing
            // instance. Both go through openApplication with the profile's
            // --user-data-dir and createsNewApplicationInstance, so an already-
            // running (possibly windowless) Electron instance is told by its own
            // single-instance lock to restore/create a window — matching the
            // Dock/Launchpad launcher. A raw NSRunningApplication.activate only
            // raised the app without reopening a window, so a menu-bar click on a
            // windowless instance appeared to do nothing. The brief extra process
            // a reopen spawns is absorbed by the settled re-scan above.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--user-data-dir=" + context.profileURL.path]
            configuration.environment = instance.environmentOverrides
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            NSWorkspace.shared.openApplication(
                at: context.app.bundleURL,
                configuration: configuration
            ) { application, error in
                guard error == nil, let application else {
                    withExtendedLifetime(operationLock) {
                        completion(.failure(.launchFailed))
                    }
                    return
                }
                self.activate(
                    pid: application.processIdentifier,
                    context: context,
                    operationLock: operationLock,
                    completion: completion
                )
            }
        }
    }

    private func managedContext(for instance: AppProfileInstance) throws -> ManagedContext {
        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        guard let current = inspectApplication(sourceURL),
              current.bundleURL == sourceURL,
              current.bundleIdentifier == instance.source.bundleIdentifier,
              let executableURL = current.executableURL else {
            throw AppProfileRuntimeError.unavailable(.sourceUnavailable)
        }
        let eligibility = detector.eligibility(for: current, registry: registry)
        guard eligibility.kind != .unsupported,
              eligibility.compatibilityRuleID != nil else {
            throw AppProfileRuntimeError.unavailable(
                .verificationRequired(eligibility.reason)
            )
        }
        guard let profileDirectory = instance.profileDirectory else {
            throw AppProfileRuntimeError.unavailable(.launcherUnavailable)
        }
        do {
            _ = try generator.validatedLauncherURL(for: instance)
            let spec = try generator.specification(for: instance)
            let validatedProfileURL = try generator.validatedProfileURL(for: instance)
            let profileURL = URL(fileURLWithPath: profileDirectory, isDirectory: true)
                .standardizedFileURL
            guard profileURL == spec.profileURL,
                  profileURL == validatedProfileURL else {
                throw AppProfileRuntimeError.unavailable(.launcherUnavailable)
            }
            return ManagedContext(
                app: current,
                profileURL: profileURL,
                executableURL: executableURL.standardizedFileURL
            )
        } catch let error as AppProfileRuntimeError {
            throw error
        } catch {
            throw AppProfileRuntimeError.unavailable(.launcherUnavailable)
        }
    }

    private func activate(
        pid: pid_t,
        context: ManagedContext,
        operationLock: ManagedInstanceLock,
        completion: @escaping (Result<pid_t, AppProfileRuntimeError>) -> Void
    ) {
        guard processInspector.verifies(
            pid: pid,
            executableURL: context.executableURL,
            profileURL: context.profileURL
        ), let application = NSRunningApplication(processIdentifier: pid) else {
            withExtendedLifetime(operationLock) {
                completion(.failure(.processVerificationFailed))
            }
            return
        }
        guard application.activate(options: []) else {
            withExtendedLifetime(operationLock) {
                completion(.failure(.activationFailed))
            }
            return
        }
        confirmFrontmost(
            pid: pid,
            remainingAttempts: 15,
            operationLock: operationLock,
            completion: completion
        )
    }

    private func confirmFrontmost(
        pid: pid_t,
        remainingAttempts: Int,
        operationLock: ManagedInstanceLock,
        completion: @escaping (Result<pid_t, AppProfileRuntimeError>) -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            withExtendedLifetime(operationLock) { completion(.success(pid)) }
            return
        }
        guard remainingAttempts > 0 else {
            withExtendedLifetime(operationLock) {
                completion(.failure(.activationFailed))
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.confirmFrontmost(
                pid: pid,
                remainingAttempts: remainingAttempts - 1,
                operationLock: operationLock,
                completion: completion
            )
        }
    }

    private func launchExternal(
        _ instance: AppProfileInstance,
        completion: @escaping (Result<pid_t, AppProfileRuntimeError>) -> Void
    ) {
        let launcherURL = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
            .standardizedFileURL
        guard launcherURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: launcherURL.path) else {
            completion(.failure(.unavailable(.externalUnavailable)))
            return
        }
        if let target = instance.legacyQuickLaunchTarget,
           (launcherURL.path != target.launcherWrapperPath || !quickLaunchTargetIsAvailable(target)) {
            completion(.failure(.unavailable(.externalUnavailable)))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: launcherURL, configuration: configuration) {
            application, error in
            guard error == nil, let application else {
                completion(.failure(.launchFailed))
                return
            }
            completion(.success(application.processIdentifier))
        }
    }
}
