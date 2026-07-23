import AppKit
import Carbon
import Foundation
import IOKit

// NOTE FOR MAINTAINERS: throughout this file, "chatGPT" / `launchPrimaryChatGPT` etc.
// refer to the **ChatGPT / Codex** desktop app. Current ChatGPT desktop builds install
// Codex (the `~/.codex` home), which is why all user-facing strings say "ChatGPT /
// Codex". The identifiers are kept short here purely for brevity — they are not a
// separate product from Codex.

private let eventLogPath = NSString(
    string: "~/Library/Logs/klik-pro-events.log"
).expandingTildeInPath
private let config = KlikProConfigStore.load()
// The runtime must be wired to the durable data-folder root, or vault-storage
// managed profiles fail every readiness check with `vaultUnavailable` and never
// receive a menu-bar icon. Mirror the app's `makeLauncherGenerator(forDataRoot:)`.
private let appProfileRuntime = AppProfileRuntime(
    generator: makeLauncherGenerator(forDataRoot: config.dataRoot)
)
// This process owns mouse mappings, the persistent status item, and optional
// Quick Launch. Its Special Feature state is read from config at startup; the settings
// app restarts the same helper after a saved toggle change.
private var specialFeatureActive = false
private var accessibilitySetupObserver: NSObjectProtocol?
private var accessibilityStatusCheckObserver: NSObjectProtocol?
// The persistent status icon reflects the real input path, not the optional launcher
// process. Green dots appear only after the Accessibility event tap is operational.
private var klikProInputIsActive = false
private var klikProInputStateHandler: ((Bool) -> Void)?

private func setKlikProInputActive(_ active: Bool) {
    guard Thread.isMainThread else {
        DispatchQueue.main.async { setKlikProInputActive(active) }
        return
    }
    guard klikProInputIsActive != active else { return }
    klikProInputIsActive = active
    klikProInputStateHandler?(active)
}

// Track both the real desktop apps and their launcher wrappers. A target is runnable
// only when both exist, but the master feature remains a user choice as long as at
// least one real app is installed.
private var chatGPTInstalled = quickLaunchTargetIsInstalled(.chatGPT)
private var claudeInstalled = quickLaunchTargetIsInstalled(.claude)
private var chatGPTAvailable = quickLaunchTargetIsAvailable(.chatGPT)
private var claudeAvailable = quickLaunchTargetIsAvailable(.claude)
private let appProfileAssignmentStateIsValid = appProfileAssignmentsAreValid(config)
private var activeAppProfileInstanceIDs: Set<UUID> = appProfileAssignmentStateIsValid
    ? Set(config.instances.compactMap { instance -> UUID? in
        guard instance.state == .active else { return nil }
        if let target = instance.legacyQuickLaunchTarget {
            return quickLaunchTargetIsAvailable(target) ? instance.id : nil
        }
        return appProfileRuntime.health(for: instance) == .ready ? instance.id : nil
    })
    : []

private struct QuickLaunchTargetStateChange {
    let installedChanged: Bool
    let runnableChanged: Bool
    let instancesChanged: Bool

    var anyChange: Bool { installedChanged || runnableChanged || instancesChanged }
}

private func refreshQuickLaunchAvailability() -> QuickLaunchTargetStateChange {
    let oldChatGPTInstalled = chatGPTInstalled
    let oldClaudeInstalled = claudeInstalled
    let oldChatGPT = chatGPTAvailable
    let oldClaude = claudeAvailable
    let oldActiveInstanceIDs = activeAppProfileInstanceIDs

    chatGPTInstalled = quickLaunchTargetIsInstalled(.chatGPT)
    claudeInstalled = quickLaunchTargetIsInstalled(.claude)
    chatGPTAvailable = quickLaunchTargetCanRun(
        installed: chatGPTInstalled,
        wrapperPresent: quickLaunchLauncherIsRunnable(.chatGPT)
    )
    claudeAvailable = quickLaunchTargetCanRun(
        installed: claudeInstalled,
        wrapperPresent: quickLaunchLauncherIsRunnable(.claude)
    )
    activeAppProfileInstanceIDs = appProfileAssignmentStateIsValid
        ? Set(config.instances.compactMap { instance -> UUID? in
            guard instance.state == .active else { return nil }
            if let target = instance.legacyQuickLaunchTarget {
                return quickLaunchTargetIsAvailable(target) ? instance.id : nil
            }
            return appProfileRuntime.health(for: instance) == .ready ? instance.id : nil
        })
        : []

    return QuickLaunchTargetStateChange(
        installedChanged: oldChatGPTInstalled != chatGPTInstalled
            || oldClaudeInstalled != claudeInstalled,
        runnableChanged: oldChatGPT != chatGPTAvailable
            || oldClaude != claudeAvailable,
        instancesChanged: oldActiveInstanceIDs != activeAppProfileInstanceIDs
    )
}

private func instance(withID id: UUID) -> AppProfileInstance? {
    config.instances.first { $0.id == id }
}

private func legacyInstance(for target: QuickLaunchTarget) -> AppProfileInstance? {
    config.instances.first { $0.legacyQuickLaunchTarget == target }
}

private func activeAppProfileInstance(for slot: ShortcutSlot) -> AppProfileInstance? {
    activeAppProfileInstance(
        for: slot,
        in: config,
        activeInstanceIDs: activeAppProfileInstanceIDs,
        specialFeatureActive: specialFeatureActive
    )
}

private func effectiveMapping(for slot: ShortcutSlot) -> ShortcutMapping {
    if let instance = activeAppProfileInstance(for: slot) {
        return ShortcutMapping(enabled: true, combo: instance.hotkey.combo)
    }
    return baseMapping(for: slot, in: config)
}

private func logMessage(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = Data("[\(timestamp)] \(message)\n".utf8)
    let fileManager = FileManager.default

    if !fileManager.fileExists(atPath: eventLogPath) {
        fileManager.createFile(atPath: eventLogPath, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: eventLogPath)) else {
        return
    }

    do {
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
    } catch {
        try? handle.close()
    }
}

private func launch(_ target: QuickLaunchTarget) {
    logMessage("Opening native \(target.title) app")
    appProfileRuntime.launchOriginal(target) { result in
        switch result {
        case .success(let pid):
            logMessage("Native \(target.title) action completed with pid \(pid)")
        case .failure(let error):
            logMessage("Native \(target.title) action failed: \(error)")
        }
    }
}

@discardableResult
private func launchAndWait(_ target: QuickLaunchTarget, timeout: TimeInterval = 10) -> Bool {
    logMessage("Opening native \(target.title) app and waiting for launch result")
    var completed = false
    var succeeded = false
    appProfileRuntime.launchOriginal(target) { result in
        switch result {
        case .success(let pid):
            logMessage("Native \(target.title) action completed with pid \(pid)")
            succeeded = true
        case .failure(let error):
            logMessage("Native \(target.title) action failed: \(error)")
            succeeded = false
        }
        completed = true
    }

    let deadline = Date().addingTimeInterval(timeout)
    while !completed && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    if !completed {
        logMessage("Native \(target.title) action timed out before completion")
    }
    return completed && succeeded
}

private func launch(instanceID: UUID) {
    guard let instance = instance(withID: instanceID) else {
        logMessage("Ignored unknown App Profile UUID")
        return
    }
    appProfileRuntime.launchOrFocus(instance) { result in
        switch result {
        case .success(let pid):
            logMessage("App Profile action completed for UUID \(instance.id.uuidString), pid \(pid)")
        case .failure(let error):
            logMessage("App Profile action failed for UUID \(instance.id.uuidString): \(error)")
        }
    }
}

private func launchLegacyInstance(_ target: QuickLaunchTarget) {
    guard let instance = legacyInstance(for: target) else {
        logMessage("Ignored suppressed legacy target \(target.title)")
        return
    }
    launch(instanceID: instance.id)
}

/// The product's persistent status item belongs to the always-running input process,
/// not the optional ChatGPT/Claude menu process. That keeps Klik PRO discoverable when
/// the Special Feature is OFF and avoids coupling its lifecycle to launcher hotkeys.
private final class KlikProStatusIndicatorView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keeps the Mac awake by running macOS's own /usr/bin/caffeinate as a child process.
/// Timer presets self-expire through -t, and the unlimited preset is tied to this
/// helper's PID through -w, so a killed helper can never leave an orphaned wake
/// assertion behind. While active, a separate cup icon appears in the menu bar.
private final class CaffeinateController: NSObject, NSMenuDelegate {
    private var process: Process?
    private var cupItem: NSStatusItem?
    private var activeTitle: String?

    static let presets: [(title: String, minutes: Int?)] = [
        ("Keep Awake 30 Minutes", 30),
        ("Keep Awake 1 Hour", 60),
        ("Keep Awake 2 Hours", 120),
        ("Free flow ∞", nil),
    ]

    func buildSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self
        for (index, preset) in Self.presets.enumerated() {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(startPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
        offItem.target = self
        submenu.addItem(offItem)
        return submenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(startPreset(_:)) {
                item.state = activeTitle == Self.presets[item.tag].title ? .on : .off
            } else if item.action == #selector(turnOff) {
                item.isEnabled = process != nil
            }
        }
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        let preset = Self.presets[sender.tag]
        stop(log: false)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        if let minutes = preset.minutes {
            child.arguments = ["-di", "-t", String(minutes * 60)]
        } else {
            child.arguments = ["-di", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        }
        child.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.process = nil
                self.activeTitle = nil
                self.removeCupItem()
                logMessage("Caffeinate finished")
            }
        }
        do {
            try child.run()
        } catch {
            logMessage("Unable to start caffeinate: \(error)")
            return
        }
        process = child
        activeTitle = preset.title
        showCupItem(label: preset.title)
        logMessage("Caffeinate started: \(preset.title)")
    }

    @objc func turnOff() { stop(log: true) }

    func shutdown() { stop(log: false) }

    private func stop(log: Bool) {
        guard let running = process else { return }
        running.terminationHandler = nil
        running.terminate()
        process = nil
        activeTitle = nil
        removeCupItem()
        if log { logMessage("Caffeinate turned off") }
    }

    private func showCupItem(label: String) {
        removeCupItem()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "cup.and.saucer.fill",
                accessibilityDescription: "Caffeinate active"
            )
            button.toolTip = "Caffeinate — \(label)"
            button.setAccessibilityLabel("Caffeinate active — \(label)")
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let info = NSMenuItem(title: "Caffeinate — \(label)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let off = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
        off.target = self
        menu.addItem(off)
        item.menu = menu
        cupItem = item
    }

    private func removeCupItem() {
        if let cupItem { NSStatusBar.system.removeStatusItem(cupItem) }
        cupItem = nil
    }
}

private final class KlikProStatusController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let activeIndicatorView = KlikProStatusIndicatorView(frame: .zero)
    private let contextMenu = NSMenu()
    private let caffeinateController = CaffeinateController()

    init(caffeinateMenuEnabled: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        contextMenu.minimumWidth = 220
        contextMenu.delegate = self

        guard let button = statusItem.button else {
            logMessage("Unable to create Klik PRO menu-bar icon")
            return
        }

        button.image = klikProMenuBarIcon()
        button.image?.size = NSSize(width: 18, height: 18)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        activeIndicatorView.image = klikProMenuBarActiveIndicator()
        activeIndicatorView.image?.size = NSSize(width: 18, height: 18)
        activeIndicatorView.imageAlignment = .alignCenter
        activeIndicatorView.imageScaling = .scaleProportionallyDown
        activeIndicatorView.frame = button.bounds
        activeIndicatorView.autoresizingMask = [.width, .height]
        activeIndicatorView.isHidden = true
        button.addSubview(activeIndicatorView)

        klikProInputStateHandler = { [weak self] active in
            self?.setInputActive(active)
        }
        setInputActive(klikProInputIsActive)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openKlikPro),
            keyEquivalent: ""
        )
        settingsItem.target = self
        contextMenu.addItem(settingsItem)

        if caffeinateMenuEnabled {
            let caffeinateItem = NSMenuItem(title: "Caffeinate", action: nil, keyEquivalent: "")
            caffeinateItem.submenu = caffeinateController.buildSubmenu()
            contextMenu.addItem(caffeinateItem)
        }

        let updateItem = NSMenuItem(
            title: "Check for updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        contextMenu.addItem(updateItem)

        let aboutItem = NSMenuItem(
            title: "About Klik PRO",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        contextMenu.addItem(aboutItem)
        contextMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Klik PRO…",
            action: #selector(quitKlikPro),
            keyEquivalent: ""
        )
        quitItem.target = self
        contextMenu.addItem(quitItem)
        logMessage("Klik PRO menu-bar icon ready")
    }

    private func setInputActive(_ active: Bool) {
        activeIndicatorView.isHidden = !active
        let accessibilityLabel = "Klik PRO \(active ? "Active" : "Inactive") — Open Settings"
        statusItem.button?.toolTip = accessibilityLabel
        statusItem.button?.setAccessibilityLabel(accessibilityLabel)
    }

    private func resolvedKlikProAppURL() -> URL? {
        if let enclosing = enclosingKlikProAppURL(for: Bundle.main.bundleURL),
           FileManager.default.fileExists(atPath: enclosing.path) {
            return enclosing
        }
        if let registered = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "local.klik-pro"
        ) {
            return registered
        }
        let standard = URL(fileURLWithPath: "/Applications/Klik PRO.app", isDirectory: true)
        return FileManager.default.fileExists(atPath: standard.path) ? standard : nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = contextMenu
            sender.performClick(nil)
        } else {
            openKlikPro()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func openKlikPro() {
        guard let appURL = resolvedKlikProAppURL() else {
            logMessage("Unable to locate Klik PRO.app from menu-bar icon")
            return
        }
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: openConfiguration) {
            _, error in
            if let error = error {
                logMessage("Unable to open Klik PRO from menu bar: \(error)")
            } else {
                logMessage("Opened Klik PRO from menu bar")
            }
        }
    }

    @objc private func checkForUpdates() {
        guard let appURL = resolvedKlikProAppURL() else {
            logMessage("Unable to locate Klik PRO.app for update check")
            return
        }
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: openConfiguration) {
            _, error in
            if let error = error {
                logMessage("Unable to open Klik PRO for update check: \(error)")
                return
            }
            logMessage("Requested update check from menu bar")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                DistributedNotificationCenter.default().post(
                    name: updateCheckRequestedNotification,
                    object: nil
                )
            }
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        let icon = resolvedKlikProAppURL().map {
            NSWorkspace.shared.icon(forFile: $0.path)
        } ?? NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 128, height: 128))

        NSApp.activate(ignoringOtherApps: true)
        let alert = makeKlikProAboutAlert(version: version, build: build, icon: icon)
        alert.runModal()
    }

    @objc private func quitKlikPro() {
        let alert = NSAlert()
        alert.messageText = "Quit Klik PRO?"
        alert.informativeText = "Klik PRO will stop, and Launch at login will be turned off. Open Klik PRO from Applications when you want to start it again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        logMessage("Quit requested from the Klik PRO menu-bar icon")
        caffeinateController.shutdown()
        _ = clearGestureSentinelMappingIfOwned()
        _ = run(["disable", inputTarget])

        // Booting out the process that is executing this action terminates it, so the
        // final launchctl call must be started asynchronously rather than waited on.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", domain, inputPlistPath]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            logMessage("Unable to stop Klik PRO input service: \(error)")
            NSSound.beep()
        }
    }
}

private func appProfileNSColor(_ color: AppProfileMenuColor?) -> NSColor? {
    switch color {
    case .blue: return .systemBlue
    case .green: return .systemGreen
    case .orange: return .systemOrange
    case .purple: return .systemPurple
    case .pink: return .systemPink
    case .gray: return .systemGray
    case .yellow: return .systemYellow
    case .white: return .white
    case .black: return .black
    case nil: return nil
    }
}

private func appProfileMenuColorMarkerImage(
    _ color: AppProfileMenuColor?,
    side: CGFloat
) -> NSImage? {
    guard let nsColor = appProfileNSColor(color) else { return nil }
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let bounds = NSRect(x: 1, y: 1, width: side - 2, height: side - 2)
    nsColor.withAlphaComponent(0.18).setFill()
    NSBezierPath(ovalIn: bounds).fill()
    nsColor.setStroke()
    let outline = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
    outline.lineWidth = 1
    outline.stroke()
    image.unlockFocus()
    image.isTemplate = false
    return image
}

/// Draw an application icon edge-to-edge on a compact 21pt canvas. Workspace icons
/// often include their own transparent margin; trimming that margin and using a
/// variable-length status item makes both quick-launch icons visibly larger without
/// increasing the amount of menu-bar space they occupy.
private func compactMenuBarApplicationIcon(_ source: NSImage) -> NSImage {
    compactMenuBarApplicationIcon(source, markerColor: nil)
}

private func compactMenuBarApplicationIcon(
    _ source: NSImage,
    markerColor: AppProfileMenuColor?
) -> NSImage {
    let rasterSide = 128
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: rasterSide,
        pixelsHigh: rasterSide,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        let fallback = source.copy() as? NSImage ?? source
        fallback.size = NSSize(width: 21, height: 21)
        return fallback
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: rasterSide, height: rasterSide))
    NSGraphicsContext.restoreGraphicsState()

    var minX = rasterSide
    var minY = rasterSide
    var maxX = -1
    var maxY = -1
    for y in 0..<rasterSide {
        for x in 0..<rasterSide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY,
          let cgImage = bitmap.cgImage?.cropping(to: CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
          )) else {
        let fallback = source.copy() as? NSImage ?? source
        fallback.size = NSSize(width: 21, height: 21)
        return fallback
    }

    let size = NSSize(width: 21, height: 21)
    let output = NSImage(size: size)
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: cgImage, size: size).draw(in: NSRect(origin: .zero, size: size))
    if let nsColor = appProfileNSColor(markerColor) {
        let markerRect = NSRect(x: 13.5, y: 1.5, width: 6, height: 6)
        nsColor.setFill()
        NSBezierPath(ovalIn: markerRect).fill()
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setStroke()
        let outline = NSBezierPath(ovalIn: markerRect.insetBy(dx: -0.75, dy: -0.75))
        outline.lineWidth = 1
        outline.stroke()
    }
    output.unlockFocus()
    output.isTemplate = false
    return output
}

private final class MenuBarController: NSObject {
    private var statusItemsByInstanceID: [UUID: NSStatusItem] = [:]
    private var instanceIDsByButtonTag: [Int: UUID] = [:]
    private var statusItemsByTarget: [QuickLaunchTarget: NSStatusItem] = [:]
    private var targetsByButtonTag: [Int: QuickLaunchTarget] = [:]

    override init() {
        super.init()

        // Only generated (managed) profiles pin to the menu bar here. Legacy-external
        // rows represent the original/native apps; their menu-bar presence is owned by
        // the App Profiles card toggle (config.menuBarPinnedOriginals) below — otherwise
        // a legacy row's stale pinToMenuBar draws an icon the UI has no toggle to clear.
        for (index, instance) in config.instances.enumerated()
            where instance.state == .active && instance.pinToMenuBar
                && instance.launcherKind == .managed {
            guard activeAppProfileInstanceIDs.contains(instance.id) else { continue }
            let item = NSStatusBar.system.statusItem(withLength: 22)
            let tag = index + 1
            configure(
                statusItem: item,
                tooltip: "Launch or focus \(instance.label)",
                instance: instance,
                tag: tag
            )
            statusItemsByInstanceID[instance.id] = item
            instanceIDsByButtonTag[tag] = instance.id
        }

        // Original vendor apps the user pinned via the App Profiles card toggle. These
        // are not profile instances; clicking one opens the original app. Only shown
        // for an installed target. Tags use a separate 1000+ range so they never
        // collide with the profile-instance tags above.
        for target in QuickLaunchTarget.allCases
            where config.menuBarPinnedOriginals.contains(target) {
            guard let applicationURL = quickLaunchTargetApplicationURL(target) else { continue }
            let item = NSStatusBar.system.statusItem(withLength: 22)
            let tag = 1000 + target.rawValue
            let launcherURL = URL(
                fileURLWithPath: target.originalDockLauncherPath, isDirectory: true
            ).standardizedFileURL
            configureOriginal(
                statusItem: item,
                applicationURL: applicationURL,
                launcherURL: launcherURL,
                tooltip: "Open \(target.title)",
                tag: tag
            )
            statusItemsByTarget[target] = item
            targetsByButtonTag[tag] = target
        }

        let labels = config.instances.compactMap { instance -> String? in
            guard statusItemsByInstanceID[instance.id] != nil else { return nil }
            return instance.label
        }
        let originalLabels = QuickLaunchTarget.allCases.compactMap { target -> String? in
            statusItemsByTarget[target] != nil ? "\(target.title) (native)" : nil
        }
        logMessage(
            "Menu-bar buttons ready (instances=\((labels + originalLabels).joined(separator: ", ")))"
        )
    }

    private func configure(
        statusItem: NSStatusItem,
        tooltip: String,
        instance: AppProfileInstance,
        tag: Int
    ) {
        guard let button = statusItem.button else {
            logMessage("Unable to create menu-bar button: \(tooltip)")
            return
        }

        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = #selector(openInstance(_:))
        button.tag = tag
        button.sendAction(on: [.leftMouseUp])

        // Prefer the profile launcher's own icon so a Change-Icon choice (custom
        // PNG/ICO, tint, or badge) shows in the menu bar too. Read the launcher's
        // AppIcon.icns directly to bypass NSWorkspace's per-path cache, then fall
        // back to the launcher bundle icon, then the source app icon.
        let launcherURL = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
            .standardizedFileURL
        let sourceURL = URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true)
            .standardizedFileURL
        let launcherIcns = launcherURL
            .appendingPathComponent("Contents/Resources/AppIcon.icns")
        let icon: NSImage
        if let custom = NSImage(contentsOf: launcherIcns) {
            icon = custom
        } else if FileManager.default.fileExists(atPath: launcherURL.path) {
            icon = NSWorkspace.shared.icon(forFile: launcherURL.path)
        } else if FileManager.default.fileExists(atPath: sourceURL.path) {
            icon = NSWorkspace.shared.icon(forFile: sourceURL.path)
        } else {
            logMessage("No launcher or source app before menu icon setup for UUID \(instance.id)")
            return
        }
        let baseIcon = compactMenuBarApplicationIcon(icon)
        button.image = compactMenuBarApplicationIcon(baseIcon, markerColor: instance.menuColor)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    private func configureOriginal(
        statusItem: NSStatusItem,
        applicationURL: URL,
        launcherURL: URL,
        tooltip: String,
        tag: Int
    ) {
        guard let button = statusItem.button else {
            logMessage("Unable to create menu-bar button: \(tooltip)")
            return
        }
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = #selector(openOriginal(_:))
        button.tag = tag
        button.sendAction(on: [.leftMouseUp])
        // Prefer the green-star launcher's badged AppIcon.icns so the menu-bar icon
        // matches the green-star Dock icon (read directly to bypass NSWorkspace's
        // per-path cache). Fall back to the launcher bundle icon, then the plain native
        // app icon only if no green-star launcher has been created yet.
        let launcherIcns = launcherURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let icon: NSImage
        if let badged = NSImage(contentsOf: launcherIcns) {
            icon = badged
        } else if FileManager.default.fileExists(atPath: launcherURL.path) {
            icon = NSWorkspace.shared.icon(forFile: launcherURL.path)
        } else {
            icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        button.image = compactMenuBarApplicationIcon(icon)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    @objc private func openInstance(_ sender: NSStatusBarButton) {
        guard let instanceID = instanceIDsByButtonTag[sender.tag] else {
            logMessage("Ignored menu-bar instance with unknown tag \(sender.tag)")
            return
        }
        logMessage("UUID-keyed App Profile menu-bar button clicked")
        launch(instanceID: instanceID)
    }

    @objc private func openOriginal(_ sender: NSStatusBarButton) {
        guard let target = targetsByButtonTag[sender.tag] else {
            logMessage("Ignored menu-bar native app with unknown tag \(sender.tag)")
            return
        }
        logMessage("Native-app menu-bar button clicked")
        launch(target)
    }
}

// ChatGPT/Claude hotkey references belong to this same helper. The settings app
// restarts the helper after a saved Special Feature change, which releases or claims
// the combinations as a single process.
private var chatGPTHotKeyReference: EventHotKeyRef?
private var claudeHotKeyReference: EventHotKeyRef?
private var managedHotKeyReferences: [EventHotKeyRef] = []
private var managedInstanceIDByHotKeyID: [UInt32: UUID] = [:]
private var gestureHotKeyReference: EventHotKeyRef?
private var eventHandlerReference: EventHandlerRef?
private var mouseEventTap: CFMachPort?
private var mouseRunLoopSource: CFRunLoopSource?
private var mouseButtonDispatchState = MouseButtonDispatchState()
private var gestureWakeObserver: NSObjectProtocol?
private var gestureMappingRetryTimer: Timer?
private var gestureServiceNotificationPort: IONotificationPortRef?
private var gestureServiceMatchIterator: io_iterator_t = IO_OBJECT_NULL
private var terminationSignalSource: DispatchSourceSignal?
private var gestureTerminationCleanupAttempts = 0
private var accessibilityRetryTimer: Timer?
private var didPromptForAccessibility = false
private let chatGPTHotKeyID = EventHotKeyID(
    signature: fourCharacterCode("CGP1"),
    id: 1
)
private let claudeHotKeyID = EventHotKeyID(
    signature: fourCharacterCode("CLD1"),
    id: 1
)
private let gestureHotKeyID = EventHotKeyID(
    signature: fourCharacterCode("GST1"),
    id: 1
)
private let managedHotKeySignature = fourCharacterCode("APF2")
private let commandShiftFlags = CGEventFlags.maskCommand.union(.maskShift)
private let commandOptionFlags = CGEventFlags.maskCommand.union(.maskAlternate)
private let leftArrowKeyCode: CGKeyCode = CGKeyCode(kVK_LeftArrow)
private let rightArrowKeyCode: CGKeyCode = CGKeyCode(kVK_RightArrow)
private let chromeBundleIdentifier = "com.google.Chrome"
private let braveBundleIdentifier = "com.brave.Browser"
private let safariBundleIdentifier = "com.apple.Safari"
private let thumbWheelAppOverrides: [String: CGEventFlags] = [
    chromeBundleIdentifier: commandOptionFlags,
    braveBundleIdentifier: commandOptionFlags,
    "org.mozilla.firefox": commandOptionFlags,
    "org.mozilla.firefoxdeveloperedition": commandOptionFlags,
    safariBundleIdentifier: commandShiftFlags,
]

private let handler: EventHandlerUPP = { _, event, _ in
    var receivedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &receivedID
    )

    if status == noErr,
       receivedID.signature == gestureHotKeyID.signature,
       receivedID.id == gestureHotKeyID.id {
        let shortcut = effectiveMapping(for: .gestureButton)
        guard shortcut.enabled,
              !isGestureSentinelOutput(shortcut.combo),
              configuredSlotUsingGestureSentinel(in: config) == nil else {
            logMessage("Ignored disabled or reserved Command-F20 Gesture sentinel")
            return noErr
        }
        if let instance = activeAppProfileInstance(for: .gestureButton) {
            logMessage("Physical Gesture Button received; launching UUID-keyed instance")
            DispatchQueue.main.async { launch(instanceID: instance.id) }
        } else {
            logMessage("Physical Gesture Button received; sending \(shortcut.combo.displayString)")
            postKeyStroke(
                keyCode: CGKeyCode(shortcut.combo.keyCode),
                flags: shortcut.combo.cgEventFlags
            )
        }
    } else if status == noErr,
       receivedID.signature == chatGPTHotKeyID.signature,
       receivedID.id == chatGPTHotKeyID.id {
        logMessage("ChatGPT shortcut received")
        launchLegacyInstance(.chatGPT)
    } else if status == noErr,
              receivedID.signature == claudeHotKeyID.signature,
              receivedID.id == claudeHotKeyID.id {
        logMessage("Claude shortcut received")
        launchLegacyInstance(.claude)
    } else if status == noErr,
              receivedID.signature == managedHotKeySignature,
              let instanceID = managedInstanceIDByHotKeyID[receivedID.id] {
        logMessage("Managed App Profile shortcut received")
        launch(instanceID: instanceID)
    } else {
        logMessage("Ignored keyboard event with status \(status)")
    }

    return noErr
}

private func postKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
        logMessage("Unable to create synthetic key event for key code \(keyCode)")
        return
    }

    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

private enum TabSwitchDirection {
    case next
    case previous
}

private let thumbWheelCooldownSeconds: CFAbsoluteTime = 0.15
private var thumbWheelLastFireTime: CFAbsoluteTime = 0

private func flagsDescription(_ flags: CGEventFlags) -> String {
    switch flags {
    case commandShiftFlags: return "Command-Shift"
    default: return "Command-Option"
    }
}

private func postTabSwitch(direction: TabSwitchDirection) {
    let now = CFAbsoluteTimeGetCurrent()
    guard now - thumbWheelLastFireTime >= thumbWheelCooldownSeconds else {
        return
    }
    thumbWheelLastFireTime = now

    let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    let flags = frontmostBundleIdentifier.flatMap { thumbWheelAppOverrides[$0] } ?? commandOptionFlags
    let keyCode = direction == .next ? rightArrowKeyCode : leftArrowKeyCode

    logMessage(
        "Thumb wheel \(direction == .next ? "right" : "left") for \(frontmostBundleIdentifier ?? "unknown app"); "
        + "sending \(flagsDescription(flags))-\(direction == .next ? "Right" : "Left")"
    )
    postKeyStroke(keyCode: keyCode, flags: flags)
}

private func setupMouseMappings() {
    if let tap = mouseEventTap {
        setKlikProInputActive(CGEvent.tapIsEnabled(tap: tap))
        return
    }

    let trusted = AXIsProcessTrustedWithOptions([
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !didPromptForAccessibility
    ] as CFDictionary)
    didPromptForAccessibility = true

    if !trusted {
        setKlikProInputActive(false)
        logMessage("Accessibility permission is required for button mappings")
        if accessibilityRetryTimer == nil {
            accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                setupMouseMappings()
            }
        }
        return
    }

    let eventMask =
        (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    mouseEventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mouseEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    setKlikProInputActive(CGEvent.tapIsEnabled(tap: tap))
                }
                return Unmanaged.passRetained(event)
            }

            if type == .otherMouseDown {
                let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
                logMessage("Other mouse down received with button number \(buttonNumber)")
                guard let slot = shortcutSlot(forMouseButtonNumber: buttonNumber) else {
                    return Unmanaged.passRetained(event)
                }
                let shortcut = effectiveMapping(for: slot)
                let linkedInstance = activeAppProfileInstance(for: slot)
                guard shortcut.enabled else {
                    _ = mouseButtonDispatchState.begin(
                        buttonNumber: buttonNumber,
                        dispatch: .nativePassThrough
                    )
                    return Unmanaged.passRetained(event)
                }
                let buttonName: String
                switch slot {
                case .middleButton: buttonName = "Button 3 (Middle)"
                case .backButton: buttonName = "Button 4 (Back)"
                case .forwardButton: buttonName = "Button 5 (Forward)"
                default: return Unmanaged.passRetained(event)
                }
                let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let dispatch = mouseButtonDispatchState.begin(
                    buttonNumber: buttonNumber,
                    dispatch: mouseButtonShortcutDispatch(
                        slot: slot,
                        shortcut: shortcut,
                        frontmostBundleIdentifier: frontmostBundleIdentifier,
                        appProfileInstanceID: linkedInstance?.id
                    )
                )
                switch dispatch {
                case .nativePassThrough:
                    logMessage(
                        "\(buttonName) received for \(frontmostBundleIdentifier ?? "unknown app"); "
                        + "passing native browser-history event through"
                    )
                    return Unmanaged.passRetained(event)
                case .launch(let target):
                    logMessage("\(buttonName) received; launching \(target.title)")
                    DispatchQueue.main.async { launch(target) }
                    return nil
                case .launchInstance(let instanceID):
                    logMessage("\(buttonName) received; launching UUID-keyed instance")
                    DispatchQueue.main.async { launch(instanceID: instanceID) }
                    return nil
                case .synthesize(let combo):
                    logMessage("\(buttonName) received; sending \(combo.displayString)")
                    postKeyStroke(keyCode: CGKeyCode(combo.keyCode), flags: combo.cgEventFlags)
                    return nil
                }
            }

            if type == .otherMouseUp {
                let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
                guard let slot = shortcutSlot(forMouseButtonNumber: buttonNumber) else {
                    return Unmanaged.passRetained(event)
                }
                let shortcut = effectiveMapping(for: slot)
                let linkedInstance = activeAppProfileInstance(for: slot)
                let orphanFallback: MouseButtonShortcutDispatch = shortcut.enabled
                    ? mouseButtonShortcutDispatch(
                        slot: slot,
                        shortcut: shortcut,
                        frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                        appProfileInstanceID: linkedInstance?.id
                    )
                    : .nativePassThrough
                let dispatch = mouseButtonDispatchState.end(
                    buttonNumber: buttonNumber,
                    orphanFallback: orphanFallback
                )
                return dispatch == .nativePassThrough ? Unmanaged.passRetained(event) : nil
            }

            if type == .scrollWheel {
                // Confirmed on-device, no vendor driver installed (see diagnostics/):
                // the thumb wheel reports as discrete +-1 deltas on axis2 with
                // scrollWheelEventIsContinuous == 0, one event per physical tick — with
                // no accumulation/threshold needed. This is a raw CGEventTap read; the
                // horizontal scroll didn't do anything useful at all until this app
                // mapped it, since no vendor configuration software was ever installed.
                // Sign-to-direction mapping may need to flip if macOS "Natural
                // Scrolling" affects this device.
                let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
                guard shouldMapThumbWheel(axis2: axis2, isContinuous: isContinuous) else {
                    return Unmanaged.passRetained(event)
                }
                guard config.thumbWheel.enabled else { return Unmanaged.passRetained(event) }

                let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                guard thumbWheelMappingIsEnabled(
                    for: frontmostBundleIdentifier,
                    config: config.thumbWheel
                ) else { return Unmanaged.passRetained(event) }

                postTabSwitch(direction: axis2 > 0 ? .next : .previous)
                return nil
            }

            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    )

    guard let tap = mouseEventTap else {
        setKlikProInputActive(false)
        logMessage("Unable to create mouse event tap")
        fputs("Unable to create mouse event tap. Check Accessibility permission.\n", stderr)
        return
    }

    mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    if let source = mouseRunLoopSource {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setKlikProInputActive(CGEvent.tapIsEnabled(tap: tap))
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
        logMessage("Button mappings ready: middle and Forward/Back -> configured combos; thumb wheel -> tab switch; keyboard Command-Tab is never intercepted")
    } else {
        setKlikProInputActive(false)
    }
}

private func installAccessibilitySetupObserver() {
    accessibilitySetupObserver = DistributedNotificationCenter.default().addObserver(
        forName: accessibilitySetupRequestedNotification,
        object: nil,
        queue: .main
    ) { _ in
        didPromptForAccessibility = true
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        logMessage("Accessibility setup requested from Klik PRO Settings")
        if trusted {
            setupMouseMappings()
        } else {
            setKlikProInputActive(false)
            logMessage("Accessibility permission is required for button mappings")
        }
    }
}

/// Answers the Settings app's manual status check without displaying a macOS prompt.
/// The main app cannot query this helper's TCC identity directly, so the result is
/// written to the shared event log that already backs the permission status pill.
private func installAccessibilityStatusCheckObserver() {
    accessibilityStatusCheckObserver = DistributedNotificationCenter.default().addObserver(
        forName: accessibilityStatusCheckRequestedNotification,
        object: nil,
        queue: .main
    ) { _ in
        let trusted = AXIsProcessTrusted()
        logMessage("Accessibility status recheck: \(trusted ? "granted" : "required")")
        if trusted {
            setupMouseMappings()
        } else {
            setKlikProInputActive(false)
        }
    }
}

private func installGestureLifecycleHooks() {
    gestureWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
    ) { _ in
        configureGestureSentinel()
    }

    installGestureServiceArrivalObserver()

    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler {
        cancelGestureMappingCheck()
        gestureTerminationCleanupAttempts = 0
        attemptGestureTerminationCleanup()
    }
    source.resume()
    terminationSignalSource = source
}

private func gestureServiceMatchingDictionary() -> CFMutableDictionary? {
    guard let matching = IOServiceMatching("AppleUserHIDEventService") else { return nil }
    let properties: CFDictionary = [
        "VendorID": NSNumber(value: 0x046d),
        "ProductID": NSNumber(value: 0xb023),
        "PrimaryUsagePage": NSNumber(value: 1),
        "PrimaryUsage": NSNumber(value: 6),
    ] as CFDictionary
    let key = kIOPropertyMatchKey as CFString
    CFDictionarySetValue(
        matching,
        Unmanaged.passUnretained(key).toOpaque(),
        Unmanaged.passUnretained(properties).toOpaque()
    )
    return matching
}

@discardableResult
private func drainGestureServiceMatches(_ iterator: io_iterator_t) -> Bool {
    var foundService = false
    while true {
        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else { break }
        foundService = true
        IOObjectRelease(service)
    }
    return foundService
}

private func gestureServiceDidMatch(
    _ refCon: UnsafeMutableRawPointer?,
    _ iterator: io_iterator_t
) {
    guard drainGestureServiceMatches(iterator) else { return }
    logMessage("MX Master 3 Gesture service arrived; restoring device isolation")
    configureGestureSentinel()
}

/// Watches only IORegistry service arrival. It never opens the keyboard service or
/// subscribes to key reports, so keyboard Command-Tab remains outside Klik PRO.
private func installGestureServiceArrivalObserver() {
    guard gestureServiceNotificationPort == nil else { return }
    guard let matching = gestureServiceMatchingDictionary() else {
        logMessage("Unable to create Gesture service matching dictionary")
        return
    }
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
        logMessage("Unable to create Gesture service notification port")
        return
    }
    guard let unmanagedSource = IONotificationPortGetRunLoopSource(port) else {
        IONotificationPortDestroy(port)
        logMessage("Unable to create Gesture service run-loop source")
        return
    }

    var iterator: io_iterator_t = IO_OBJECT_NULL
    let status = IOServiceAddMatchingNotification(
        port,
        kIOFirstMatchNotification,
        matching,
        gestureServiceDidMatch,
        nil,
        &iterator
    )
    guard status == KERN_SUCCESS else {
        if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) }
        IONotificationPortDestroy(port)
        logMessage("Unable to observe Gesture service arrivals: \(status)")
        return
    }

    gestureServiceNotificationPort = port
    gestureServiceMatchIterator = iterator
    CFRunLoopAddSource(
        CFRunLoopGetMain(),
        unmanagedSource.takeUnretainedValue(),
        .commonModes
    )
    // Draining arms future first-match notifications. Startup configures separately.
    _ = drainGestureServiceMatches(iterator)
}

private func removeGestureServiceArrivalObserver() {
    if gestureServiceMatchIterator != IO_OBJECT_NULL {
        IOObjectRelease(gestureServiceMatchIterator)
        gestureServiceMatchIterator = IO_OBJECT_NULL
    }
    if let port = gestureServiceNotificationPort {
        if let unmanagedSource = IONotificationPortGetRunLoopSource(port) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                unmanagedSource.takeUnretainedValue(),
                .commonModes
            )
        }
        IONotificationPortDestroy(port)
        gestureServiceNotificationPort = nil
    }
}

private func attemptGestureTerminationCleanup() {
    if clearGestureSentinelMappingIfOwned() {
        removeGestureServiceArrivalObserver()
        NSApp.terminate(nil)
        return
    }

    gestureTerminationCleanupAttempts += 1
    guard gestureTerminationCleanupAttempts >= 4 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            attemptGestureTerminationCleanup()
        }
        return
    }

    // Refuse a graceful exit rather than knowingly strand an owned Tab-to-F20 map
    // without its receiver. A later SIGTERM retries the cleanup transaction.
    logMessage("Gesture cleanup could not be verified; keeping helper alive safely")
    scheduleGestureMappingCheck(after: 5)
}

private func unregisterGestureHotKey() {
    if let reference = gestureHotKeyReference {
        UnregisterEventHotKey(reference)
        gestureHotKeyReference = nil
    }
}

private func cancelGestureMappingCheck() {
    gestureMappingRetryTimer?.invalidate()
    gestureMappingRetryTimer = nil
}

private func scheduleGestureMappingCheck(after interval: TimeInterval) {
    cancelGestureMappingCheck()
    gestureMappingRetryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
        gestureMappingRetryTimer = nil
        configureGestureSentinel()
    }
}

private func registerGestureHotKeyIfNeeded() -> Bool {
    guard gestureHotKeyReference == nil else { return true }
    let status = RegisterEventHotKey(
        gestureSentinelKeyCode,
        gestureSentinelModifiers,
        gestureHotKeyID,
        GetApplicationEventTarget(),
        0,
        &gestureHotKeyReference
    )
    guard status == noErr else {
        logMessage("Unable to register device-isolated Gesture sentinel: \(status)")
        return false
    }
    return true
}

private func disableOrRetryGestureSentinel(reason: String) {
    if clearGestureSentinelMappingIfOwned() {
        cancelGestureMappingCheck()
        unregisterGestureHotKey()
        logMessage(reason)
        return
    }

    // Cleanup state is uncertain. Keep a no-op F20 receiver registered until the
    // exact owned mapping is confirmed absent, then try again shortly.
    _ = registerGestureHotKeyIfNeeded()
    scheduleGestureMappingCheck(after: 5)
    logMessage("\(reason); owned mapping cleanup will retry")
}

/// Registers Command-F20 before installing the MX Master 3's device-scoped
/// Tab -> F20 sentinel. A physical keyboard Command-Tab never enters this path.
private func configureGestureSentinel() {
    let shortcut = effectiveMapping(for: .gestureButton)
    guard shortcut.enabled else {
        disableOrRetryGestureSentinel(reason: "Gesture mapping disabled by configuration")
        return
    }

    guard let reservedSlot = configuredSlotUsingGestureSentinel(in: config) else {
        return configureGestureSentinelWithoutReservedOutput()
    }

    disableOrRetryGestureSentinel(
        reason: "Gesture mapping disabled: Command-F20 is reserved internally (configured slot: \(reservedSlot))"
    )
}

private func configureGestureSentinelWithoutReservedOutput() {
    switch currentGestureSentinelMappingState() {
    case .ownedConflict:
        _ = registerGestureHotKeyIfNeeded()
        scheduleGestureMappingCheck(after: 5)
        logMessage("Gesture service overlap detected; retaining owned mapping and F20 receiver")
        return
    case .conflicting:
        cancelGestureMappingCheck()
        unregisterGestureHotKey()
        _ = clearGestureSentinelMappingIfOwned()
        logMessage("Gesture mapping disabled: MX Master 3 already has a custom UserKeyMapping")
        return
    case .deviceAbsent:
        unregisterGestureHotKey()
        scheduleGestureMappingCheck(after: 300)
        logMessage("Gesture device not available; waiting for its service to reconnect")
        return
    case .unavailable:
        _ = registerGestureHotKeyIfNeeded()
        scheduleGestureMappingCheck(after: 5)
        logMessage("Gesture mapping state unavailable; retrying safely")
        return
    case .absent, .installed:
        break
    }

    guard registerGestureHotKeyIfNeeded() else {
        let cleared = clearGestureSentinelMappingIfOwned()
        if !cleared { logMessage("Warning: unable to clear owned Gesture sentinel after registration failure") }
        scheduleGestureMappingCheck(after: 5)
        return
    }

    guard applyGestureSentinelMappingIfSafe() else {
        let cleared = clearGestureSentinelMappingIfOwned()
        if cleared { unregisterGestureHotKey() }
        scheduleGestureMappingCheck(after: 5)
        logMessage("Unable to install device-isolated Gesture sentinel")
        if !cleared { logMessage("Warning: unable to clear owned Gesture sentinel after setup failure") }
        return
    }

    // Arrival notifications handle normal Bluetooth reconnects; this low-frequency
    // verification catches an in-place property reset on a still-live service.
    scheduleGestureMappingCheck(after: 300)
    let shortcut = effectiveMapping(for: .gestureButton)
    let destination = activeAppProfileInstance(for: .gestureButton)?.label
        ?? shortcut.combo.displayString
    logMessage("Gesture mapping ready: MX Master 3 Command-F20 sentinel -> \(destination); keyboard Command-Tab remains native")
}

/// Refresh target availability without consulting or mutating LaunchAgents. The
/// combined helper is restarted by the settings app when its saved Special Feature
/// state changes; this monitor only updates the process-local availability used by
/// mouse-button overlays and retries device setup after an app/wrapper appears.
private func installQuickLaunchAvailabilityMonitor() {
    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        let stateChange = refreshQuickLaunchAvailability()
        guard stateChange.anyChange else { return }

        logMessage("Quick-launch installed/runnable target state changed")
        let shouldBeActive = config.specialFeatureEnabled
            && !activeAppProfileInstanceIDs.isEmpty
        if specialFeatureActive != shouldBeActive {
            specialFeatureActive = shouldBeActive
            logMessage("Special Feature mouse assignments \(shouldBeActive ? "active" : "inactive")")
            configureGestureSentinel()
        }
        if config.specialFeatureEnabled {
            // Rebuild the same process so newly available or removed launcher wrappers
            // update menu icons and global hotkey registrations together. This is a
            // single-service kickstart; no optional second LaunchAgent is needed.
            logMessage("Restarting combined helper after Quick Launch availability change")
            _ = applySavedConfig()
        }
    }
}

// NOTE: With KlikProConfig.swift compiled alongside this file, Swift no
// longer treats this file as an implicit script entry point (that special case only
// applies when a single file is passed to swiftc), so the executable startup sequence
// below is wrapped in an `@main` type rather than living as bare top-level statements.
@main
private struct KlikProInputMain {
    private static var klikProStatusController: KlikProStatusController?
    private static var quickLaunchMenuBarController: MenuBarController?

    static func main() {
        // Releases before the combined helper used a second LaunchAgent with this
        // argument. If that stale job starts before the settings app can migrate it,
        // remove it immediately instead of running a duplicate status/menu process.
        if CommandLine.arguments.contains("--menu-only") {
            logMessage("Obsolete menu helper invocation detected; removing legacy service")
            _ = run(["bootout", domain, legacyMenuPlistPath])
            exit(0)
        }

        if CommandLine.arguments.contains("--trigger") {
            logMessage("Manual trigger requested")
            exit(launchAndWait(.chatGPT) ? 0 : 1)
        }

        if CommandLine.arguments.contains("--trigger-claude") {
            logMessage("Manual Claude trigger requested")
            exit(launchAndWait(.claude) ? 0 : 1)
        }

        if CommandLine.arguments.contains("--clear-gesture-map") {
            exit(clearGestureSentinelMappingIfOwned() ? 0 : 1)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        specialFeatureActive = config.specialFeatureEnabled
            && !activeAppProfileInstanceIDs.isEmpty
        logMessage("Listener starting; combined input service, Special Feature active=\(specialFeatureActive)")

        installAccessibilitySetupObserver()
        installAccessibilityStatusCheckObserver()
        installQuickLaunchAvailabilityMonitor()
        if config.showMenuBarIcon {
            klikProStatusController = KlikProStatusController(
                caffeinateMenuEnabled: config.caffeinateMenuEnabled
            )
        } else {
            logMessage("Klik PRO menu-bar icon hidden by Settings")
        }
        // App Profile menu-bar icons are independent of the retired Special
        // Feature toggle (see activeAppProfileInstance). Create the controller
        // whenever any instance is active so pinned, ready profiles show their
        // icons regardless of specialFeatureActive.
        if !activeAppProfileInstanceIDs.isEmpty {
            quickLaunchMenuBarController = MenuBarController()
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            logMessage("Unable to install event handler: \(handlerStatus)")
            fputs("Unable to install hotkey handler: \(handlerStatus)\n", stderr)
            exit(1)
        }

        setupMouseMappings()
        installGestureLifecycleHooks()
        configureGestureSentinel()
        print("Button mappings ready: middle, device-isolated Gesture, and Forward/Back -> configured combos; keyboard Command-Tab remains native")

        if specialFeatureActive {
            // The combined helper claims optional global hotkeys only while the saved
            // Special Feature toggle is active. Restarting this same helper on a saved
            // toggle change releases or claims them without a second service.
            let activeChatGPT = legacyInstance(for: .chatGPT).flatMap { instance in
                activeAppProfileInstanceIDs.contains(instance.id) ? instance : nil
            }
            let activeClaude = legacyInstance(for: .claude).flatMap { instance in
                activeAppProfileInstanceIDs.contains(instance.id) ? instance : nil
            }
            if activeChatGPT != nil && isReservedKeyboardCommandTab(config.chatGPTHotkey.combo) {
                logMessage("Refused ChatGPT / Codex global Command-Tab hotkey; keyboard app switching remains native")
            } else if let activeChatGPT, activeChatGPT.hotkey.enabled {
                let chatGPTRegistrationStatus = RegisterEventHotKey(
                    UInt32(activeChatGPT.hotkey.combo.keyCode),
                    activeChatGPT.hotkey.combo.carbonModifiers,
                    chatGPTHotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &chatGPTHotKeyReference
                )
                guard chatGPTRegistrationStatus == noErr else {
                    logMessage("Unable to register ChatGPT / Codex shortcut: \(chatGPTRegistrationStatus)")
                    fputs("Unable to register ChatGPT / Codex shortcut: \(chatGPTRegistrationStatus)\n", stderr)
                    exit(1)
                }
            }

            if activeClaude != nil && isReservedKeyboardCommandTab(config.claudeHotkey.combo) {
                logMessage("Refused Claude global Command-Tab hotkey; keyboard app switching remains native")
            } else if let activeClaude, activeClaude.hotkey.enabled {
                let claudeRegistrationStatus = RegisterEventHotKey(
                    UInt32(activeClaude.hotkey.combo.keyCode),
                    activeClaude.hotkey.combo.carbonModifiers,
                    claudeHotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &claudeHotKeyReference
                )
                guard claudeRegistrationStatus == noErr else {
                    logMessage("Unable to register Claude shortcut: \(claudeRegistrationStatus)")
                    fputs("Unable to register Claude shortcut: \(claudeRegistrationStatus)\n", stderr)
                    exit(1)
                }
            }

            let managedInstances = config.instances.filter {
                $0.state == .active
                    && $0.launcherKind == .managed
                    && $0.hotkey.enabled
                    && activeAppProfileInstanceIDs.contains($0.id)
            }
            for (index, instance) in managedInstances.enumerated() {
                guard !isReservedKeyboardCommandTab(instance.hotkey.combo) else {
                    logMessage("Refused managed App Profile Command-Tab hotkey")
                    continue
                }
                let hotKeyID = UInt32(index + 1)
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    UInt32(instance.hotkey.combo.keyCode),
                    instance.hotkey.combo.carbonModifiers,
                    EventHotKeyID(signature: managedHotKeySignature, id: hotKeyID),
                    GetApplicationEventTarget(),
                    0,
                    &reference
                )
                guard status == noErr, let reference else {
                    logMessage("Managed App Profile hotkey registration failed: \(status)")
                    continue
                }
                managedHotKeyReferences.append(reference)
                managedInstanceIDByHotKeyID[hotKeyID] = instance.id
            }

            logMessage("Special Feature hotkeys ready (instances=\(activeAppProfileInstanceIDs.count))")
            print("Menu buttons ready")
        }

        fflush(stdout)
        application.run()
    }
}
