import AppKit
import CoreFoundation
import Foundation

@main
enum KlikProOriginalLauncher {
    static func main() {
        guard let target = targetFromBundleIdentifier() else { exit(20) }

        var completed = false
        var status: Int32 = 22
        AppProfileRuntime().launchOriginal(target) { result in
            switch result {
            case .success:
                status = 0
            case .failure(.processScanIncomplete):
                status = 23
            case .failure(.ambiguousProcesses):
                status = 24
            case .failure(.activationFailed):
                status = 25
            case .failure:
                status = 26
            }
            completed = true
            CFRunLoopStop(CFRunLoopGetMain())
        }

        while !completed {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        exit(status)
    }

    private static func targetFromBundleIdentifier() -> QuickLaunchTarget? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        return QuickLaunchTarget.allCases.first {
            $0.originalDockLauncherBundleIdentifier == bundleIdentifier
        }
    }
}
