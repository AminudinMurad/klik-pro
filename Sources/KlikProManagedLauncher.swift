import AppKit
import Darwin
import Foundation

@main
enum KlikProManagedLauncher {
    private struct InstanceContext {
        let descriptor: Int32
        let instanceID: UUID
        let supportRoot: URL
    }

    static func main() {
        guard let context = acquireInstanceLock() else { exit(26) }
        defer {
            flock(context.descriptor, LOCK_UN)
            close(context.descriptor)
        }
        guard let payloadURL = Bundle.main.url(
            forResource: "LaunchSpec",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: payloadURL),
        let payload = try? PropertyListDecoder().decode(
            ManagedLauncherPayload.self,
            from: data
        ) else {
            exit(20)
        }

        let sourceURL = URL(fileURLWithPath: payload.sourceBundlePath, isDirectory: true)
            .standardizedFileURL
        guard let expectedProfileURL = payload.validatedProfileURL(
            instanceID: context.instanceID,
            applicationSupportURL: context.supportRoot
        ) else {
            exit(21)
        }
        let expectedProfileArgument = "--user-data-dir=" + expectedProfileURL.path
        guard sourceURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: sourceURL.path),
              payload.arguments == [expectedProfileArgument] else {
            exit(21)
        }
        let scanner = AppScanner()
        guard let current = scanner.inspect(sourceURL),
              EngineDetector().eligibility(
                for: current,
                registry: .production
              ).allowsManagedProfile(usingRuleID: payload.compatibilityRuleID) else {
            exit(27)
        }
        guard let expectedExecutablePath = Bundle(url: sourceURL)?.executableURL?
            .standardizedFileURL.path else {
            exit(27)
        }

        // If a verified instance of THIS profile is already running, reopen its
        // window and focus it instead of spawning a duplicate. Codex-family apps
        // self-dedupe a repeat launch (their own per-profile single-instance
        // lock), but Claude for Desktop enforces no such lock — so without this
        // check createsNewApplicationInstance would create a second Claude on
        // every Dock/Launchpad/Finder click. The known-pid reopen matches the
        // menu-bar launch path and the normal Dock-click behavior.
        if let existing = NSWorkspace.shared.runningApplications.first(where: { app in
            app.bundleURL?.standardizedFileURL == sourceURL
                && verifies(
                    pid: app.processIdentifier,
                    expectedExecutablePath: expectedExecutablePath,
                    expectedProfileArgument: expectedProfileArgument
                )
        }) {
            sendReopenEvent(to: existing.processIdentifier)
            guard existing.activate(options: []) else { exit(24) }
            let deadline = Date(timeIntervalSinceNow: 1.5)
            while Date() < deadline,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    != existing.processIdentifier {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            exit(NSWorkspace.shared.frontmostApplication?.processIdentifier
                == existing.processIdentifier ? 0 : 25)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = payload.arguments
        configuration.environment = payload.environment
        configuration.createsNewApplicationInstance = true
        configuration.activates = false

        var completed = false
        var status: Int32 = 22
        NSWorkspace.shared.openApplication(at: sourceURL, configuration: configuration) {
            application, error in
            guard error == nil,
                  let application,
                  let expectedExecutable = Bundle(url: sourceURL)?.executableURL,
                  verifies(
                    pid: application.processIdentifier,
                    expectedExecutablePath: expectedExecutable.standardizedFileURL.path,
                    expectedProfileArgument: expectedProfileArgument
                  ) else {
                status = 23
                completed = true
                CFRunLoopStop(CFRunLoopGetMain())
                return
            }
            guard application.activate(options: []) else {
                status = 24
                completed = true
                CFRunLoopStop(CFRunLoopGetMain())
                return
            }
            let deadline = Date(timeIntervalSinceNow: 1.5)
            while Date() < deadline,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    != application.processIdentifier {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            status = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier ? 0 : 25
            completed = true
            CFRunLoopStop(CFRunLoopGetMain())
        }
        while !completed {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        exit(status)
    }

    private static func acquireInstanceLock() -> InstanceContext? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let supportRoot = URL(
            fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Klik PRO",
            isDirectory: true
        ).standardizedFileURL
        let internalLaunchersRoot = supportRoot
            .appendingPathComponent("Launchers", isDirectory: true)
        let visibleLaunchersRoot = URL(
            fileURLWithPath: NSHomeDirectory() + "/Applications/Klik PRO",
            isDirectory: true
        ).standardizedFileURL
        let bundleIdentifierPrefix = "local.klik-pro.launcher.i"
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              bundleIdentifier.hasPrefix(bundleIdentifierPrefix) else {
            return nil
        }
        let compactID = String(bundleIdentifier.dropFirst(bundleIdentifierPrefix.count))
        guard compactID.count == 32,
              compactID.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        let uuidText = [8, 4, 4, 4, 12].reduce(into: (parts: [String](), offset: 0)) {
            state, length in
            let start = compactID.index(compactID.startIndex, offsetBy: state.offset)
            let end = compactID.index(start, offsetBy: length)
            state.parts.append(String(compactID[start..<end]))
            state.offset += length
        }.parts.joined(separator: "-")
        guard let instanceID = UUID(uuidString: uuidText) else { return nil }
        let parent = bundleURL.deletingLastPathComponent()
        let isInternalLauncher = parent == internalLaunchersRoot
            && bundleURL.deletingPathExtension().lastPathComponent
                .caseInsensitiveCompare(instanceID.uuidString) == .orderedSame
        let isVisibleLauncher = parent == visibleLaunchersRoot
        guard bundleURL.pathExtension.lowercased() == "app",
              bundleURL.resolvingSymlinksInPath() == bundleURL,
              parent.resolvingSymlinksInPath() == parent,
              isInternalLauncher || isVisibleLauncher else {
            return nil
        }
        let locksRoot = supportRoot.appendingPathComponent("Locks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: locksRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let values = try locksRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                return nil
            }
            guard locksRoot.resolvingSymlinksInPath() == locksRoot else { return nil }
        } catch {
            return nil
        }
        let lockURL = locksRoot.appendingPathComponent(
            instanceID.uuidString.uppercased() + ".lock",
            isDirectory: false
        )
        let descriptor = open(
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
            return nil
        }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return InstanceContext(
            descriptor: descriptor,
            instanceID: instanceID,
            supportRoot: supportRoot
        )
    }

    /// Sends the Core "reopen" Apple event (`kAEReopenApplication`, 'rapp') to a
    /// specific already-running instance so an app whose window was closed
    /// recreates/restores it in THAT process — the same event LaunchServices
    /// sends on a Dock click. Best-effort: a failure just leaves the plain
    /// activate to raise whatever windows already exist.
    private static func sendReopenEvent(to pid: pid_t) {
        // Four-char codes: 'aevt' (kCoreEventClass) / 'rapp'
        // (kAEReopenApplication); return/transaction IDs use the documented
        // sentinels (kAutoGenerateReturnID = -1, kAnyTransactionID = 0).
        let event = NSAppleEventDescriptor(
            eventClass: 0x6165_7674,
            eventID: 0x7261_7070,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: -1,
            transactionID: 0
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }

    private static func verifies(
        pid: pid_t,
        expectedExecutablePath: String,
        expectedProfileArgument: String
    ) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0,
              String(cString: pathBuffer) == expectedExecutablePath else {
            return false
        }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return false
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              let arguments = parseArguments(buffer: Array(buffer.prefix(size))) else {
            return false
        }
        return arguments.contains(expectedProfileArgument)
    }

    private static func parseArguments(buffer: [UInt8]) -> [String]? {
        guard buffer.count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: Int32.self)
        }
        guard argc > 0, argc < 65_536 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        guard index < buffer.count else { return nil }
        while index < buffer.count && buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < Int(argc) {
            guard index < buffer.count else { return nil }
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            guard index < buffer.count else { return nil }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
