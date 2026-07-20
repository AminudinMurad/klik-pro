import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private struct LaunchAgentInstallerTests {
    static func main() {
        let helperPath = "/Applications/Klik PRO.app/Contents/Helpers/Klik PRO Helper.app/Contents/MacOS/klik-pro-input"
        let logsPath = "/Users/tester/Library/Logs"

        let service = launchAgentPropertyList(
            helperExecutablePath: helperPath,
            logsDirectoryPath: logsPath
        )
        require(service["Label"] as? String == inputServiceLabel, "service label must be stable")
        require(
            service["ProgramArguments"] as? [String] == [helperPath],
            "combined helper must run without a mode argument"
        )
        require(
            service["StandardOutPath"] as? String == logsPath + "/klik-pro-input.log",
            "combined service stdout path must use the current home directory"
        )
        require(
            service["StandardErrorPath"] as? String == logsPath + "/klik-pro-input.error.log",
            "combined service stderr path must use the current home directory"
        )
        require(service["RunAtLoad"] as? Bool == true, "service must run at load")
        require(service["KeepAlive"] as? Bool == true, "service must stay alive")
        require(
            service["LimitLoadToSessionType"] as? String == "Aqua",
            "service must load in the user GUI session so status items can appear at login"
        )

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("klik-pro-launch-agent-tests-" + UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let appURL = temporaryRoot.appendingPathComponent("Klik PRO.app", isDirectory: true)
        let executableURL = appURL
            .appendingPathComponent("Contents/Helpers/Klik PRO Helper.app/Contents/MacOS", isDirectory: true)
            .appendingPathComponent("klik-pro-input", isDirectory: false)
        try! fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try! Data([0]).write(to: executableURL)
        try! fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let testHome = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        let launchAgentsURL = testHome.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try! fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
        let legacyURL = launchAgentsURL.appendingPathComponent(legacyMenuServiceLabel + ".plist")
        try! Data("legacy".utf8).write(to: legacyURL)

        require(
            installLaunchAgentPlist(appBundleURL: appURL, homeDirectoryURL: testHome),
            "automatic service installation must succeed for a valid app bundle"
        )

        let installedURL = launchAgentsURL.appendingPathComponent(inputServiceLabel + ".plist")
        guard let installedData = try? Data(contentsOf: installedURL),
              let installed = try? PropertyListSerialization.propertyList(
                  from: installedData,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            fputs("FAIL: automatic service installation must write the combined plist\n", stderr)
            exit(1)
        }
        require(
            installed["ProgramArguments"] as? [String] == [executableURL.path],
            "installed service must target the nested helper without a mode argument"
        )
        require(
            installed["Label"] as? String == inputServiceLabel,
            "installed service must use the combined service label"
        )
        require(
            !fileManager.fileExists(atPath: legacyURL.path),
            "automatic installation must remove the obsolete menu service"
        )

        print("LaunchAgent installer tests passed")
    }
}
