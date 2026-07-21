import AppKit
import Carbon
import Foundation

// MARK: - KeyCombo

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16       // matches CGKeyCode / NSEvent.keyCode width exactly
    var keyDisplay: String    // human label captured at record time, e.g. "G", "7", "⌫" — display only
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    /// Equality ignoring `keyDisplay` (a cosmetic label). ALL conflict comparisons
    /// (duplicate check, reserved-list check, "unchanged from persisted" check) MUST
    /// use `.signature`, never `==`, so two combos that are the same physical shortcut
    /// but carry different captured display text are still recognized as identical.
    struct Signature: Equatable, Hashable {
        let keyCode: UInt16
        let command: Bool
        let option: Bool
        let control: Bool
        let shift: Bool
    }
    var signature: Signature {
        Signature(keyCode: keyCode, command: command, option: option, control: control, shift: shift)
    }

    var carbonModifiers: UInt32 {
        var mask = 0
        if command { mask |= cmdKey }
        if option  { mask |= optionKey }
        if control { mask |= controlKey }
        if shift   { mask |= shiftKey }
        return UInt32(mask)
    }

    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if command { flags.insert(.maskCommand) }
        if option  { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift   { flags.insert(.maskShift) }
        return flags
    }

    var hasAtLeastOneModifier: Bool { command || option || control || shift }

    /// Base glyph for a physical key, independent of Shift. Used when recording so that,
    /// e.g., ⇧⌘7 shows "7" rather than the shifted glyph "&" (NSEvent's
    /// charactersIgnoringModifiers still applies Shift). Covers the common keys a
    /// shortcut is likely to use; anything unmapped falls back to the recorder's
    /// charactersIgnoringModifiers capture.
    static func baseLabel(forKeyCode keyCode: UInt16) -> String? {
        keyCodeLabels[Int(keyCode)]
    }

    static func keyCode(forBaseLabel label: String) -> UInt16? {
        keyCodeLabels.first(where: { $0.value == label }).map { UInt16($0.key) }
    }

    private static let keyCodeLabels: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Help: "Insert", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Canonical macOS modifier order ⌃ ⌥ ⇧ ⌘, matching the existing drawShortcut()
    /// glyph convention already used in KlikProApp.swift (e.g. "⌃⌥⌘G").
    var displayString: String {
        var symbols = ""
        if control { symbols += "⌃" }
        if option  { symbols += "⌥" }
        if shift   { symbols += "⇧" }
        if command { symbols += "⌘" }
        return symbols + keyDisplay
    }

    init(keyCode: UInt16, keyDisplay: String, command: Bool, option: Bool, control: Bool, shift: Bool) {
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

// MARK: - Mapping and thumb-wheel model

struct ShortcutMapping: Codable, Equatable {
    var enabled: Bool
    var combo: KeyCombo
}

/// Physical buttons that can temporarily own one of the Special Feature launch
/// actions.
enum QuickLaunchMouseButton: String, Codable, CaseIterable, Equatable {
    case middle
    case gesture
    case forward
    case back

    var title: String {
        switch self {
        case .middle: return "Middle"
        case .gesture: return "Gesture"
        case .forward: return "Forward"
        case .back: return "Back"
        }
    }

    var shortcutSlot: ShortcutSlot {
        switch self {
        case .middle: return .middleButton
        case .gesture: return .gestureButton
        case .forward: return .forwardButton
        case .back: return .backButton
        }
    }
}

enum QuickLaunchTarget: Int, CaseIterable, Hashable {
    case chatGPT
    case claude

    var title: String {
        switch self {
        case .chatGPT: return "ChatGPT / Codex"
        case .claude: return "Claude"
        }
    }

    var shortcutSlot: ShortcutSlot {
        switch self {
        case .chatGPT: return .chatGPTHotkey
        case .claude: return .claudeHotkey
        }
    }

    var applicationBundleIdentifier: String {
        switch self {
        case .chatGPT: return "com.openai.codex"
        case .claude: return "com.anthropic.claudefordesktop"
        }
    }

    var standardApplicationPath: String {
        switch self {
        case .chatGPT: return "/Applications/ChatGPT.app"
        case .claude: return "/Applications/Claude.app"
        }
    }

    var launcherWrapperPath: String {
        switch self {
        case .chatGPT:
            return NSString(
                string: "~/Library/Application Support/ChatGPT Launchers/ChatGPT.app"
            ).expandingTildeInPath
        case .claude:
            return NSString(
                string: "~/Library/Application Support/Claude Launchers/Claude.app"
            ).expandingTildeInPath
        }
    }

    /// Stable migration identity. These UUIDs identify the two v1.x legacy wrapper
    /// rows and never depend on a user-editable label or filesystem spelling.
    var legacyInstanceID: UUID {
        switch self {
        case .chatGPT: return UUID(uuidString: "9E4FB42E-0D73-4D66-B94E-92E13934C53D")!
        case .claude: return UUID(uuidString: "6D7052E2-747A-448F-85D0-75E36DA46040")!
        }
    }
}

extension AppProfileInstance {
    var legacyQuickLaunchTarget: QuickLaunchTarget? {
        guard launcherKind == .legacyExternal else { return nil }
        return QuickLaunchTarget.allCases.first {
            $0.applicationBundleIdentifier == source.bundleIdentifier
                && $0.standardApplicationPath == source.bundleURL
        }
    }

}

let chatGPTQuickLauncherPath = QuickLaunchTarget.chatGPT.launcherWrapperPath
let claudeQuickLauncherPath = QuickLaunchTarget.claude.launcherWrapperPath

/// Preview-only availability seam. Production leaves this `nil`; deterministic
/// renderers can set it before constructing the settings view without consulting the
/// host's applications, launcher wrappers, or Launch Services database.
var quickLaunchInstalledTargetsPreviewOverride: Set<QuickLaunchTarget>?

/// Preview-only Special Feature state seam. Production leaves this `nil`; the
/// renderer uses it to preserve the public ON screenshot while keeping explicit
/// no-app/one-app fixtures deterministic.
var specialFeatureEnabledPreviewOverride: Bool?

/// Process-local guard used by the preview renderer. It prevents the UI snapshot
/// process from reading or mutating live services, browser profiles, and preferences.
/// The production app never changes the default value.
var previewRenderingIsActive = false

struct QuickLaunchBundleInspection: Equatable {
    let bundleIdentifier: String?
    let packageType: String?
    let executableName: String?
    let executableIsRegularFile: Bool
    let executableIsRunnable: Bool

    init(
        bundleIdentifier: String?,
        packageType: String?,
        executableName: String?,
        executableIsRegularFile: Bool = true,
        executableIsRunnable: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.packageType = packageType
        self.executableName = executableName
        self.executableIsRegularFile = executableIsRegularFile
        self.executableIsRunnable = executableIsRunnable
    }
}

/// Pure validation shared by the real filesystem probe and unit tests. Requiring an
/// APPL package, a safe executable basename, and an executable file prevents an empty
/// or partially removed `.app` directory from enabling or owning shortcuts.
func quickLaunchBundleIsRunnable(
    _ inspection: QuickLaunchBundleInspection?,
    expectedBundleIdentifier: String? = nil
) -> Bool {
    guard let inspection = inspection,
          let bundleIdentifier = inspection.bundleIdentifier,
          !bundleIdentifier.isEmpty,
          inspection.packageType == "APPL",
          let executableName = inspection.executableName,
          !executableName.isEmpty,
          executableName != ".",
          executableName != "..",
          (executableName as NSString).lastPathComponent == executableName,
          inspection.executableIsRegularFile,
          inspection.executableIsRunnable else {
        return false
    }
    return expectedBundleIdentifier == nil
        || bundleIdentifier == expectedBundleIdentifier
}

private func inspectQuickLaunchBundle(atPath path: String) -> QuickLaunchBundleInspection? {
    var isDirectory = ObjCBool(false)
    guard (path as NSString).pathExtension.lowercased() == "app",
          FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
          isDirectory.boolValue,
          let bundle = Bundle(path: path) else {
        return nil
    }

    let executableName = bundle.object(
        forInfoDictionaryKey: kCFBundleExecutableKey as String
    ) as? String
    let executablePath = executableName.map {
        URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent($0, isDirectory: false)
            .standardizedFileURL.path
    }
    let executableIsRegularFile = executablePath.flatMap { path -> Bool? in
        try? URL(fileURLWithPath: path, isDirectory: false)
            .resourceValues(forKeys: [.isRegularFileKey])
            .isRegularFile
    } ?? false
    return QuickLaunchBundleInspection(
        bundleIdentifier: bundle.bundleIdentifier,
        packageType: bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
        executableName: executableName,
        executableIsRegularFile: executableIsRegularFile,
        executableIsRunnable: executablePath.map {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? false
    )
}

func quickLaunchApplicationBundleIsValid(
    for target: QuickLaunchTarget,
    candidatePath: String,
    inspection: QuickLaunchBundleInspection?
) -> Bool {
    let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true)
        .standardizedFileURL.path
    let standard = URL(fileURLWithPath: target.standardApplicationPath, isDirectory: true)
        .standardizedFileURL.path
    return candidate == standard
        && quickLaunchBundleIsRunnable(
            inspection,
            expectedBundleIdentifier: target.applicationBundleIdentifier
        )
}

func quickLaunchTargetApplicationURL(_ target: QuickLaunchTarget) -> URL? {
    if let previewTargets = quickLaunchInstalledTargetsPreviewOverride {
        return previewTargets.contains(target)
            ? URL(fileURLWithPath: target.standardApplicationPath, isDirectory: true)
            : nil
    }

    let path = target.standardApplicationPath
    guard quickLaunchApplicationBundleIsValid(
        for: target,
        candidatePath: path,
        inspection: inspectQuickLaunchBundle(atPath: path)
    ) else {
        return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
}

func quickLaunchTargetIsInstalled(_ target: QuickLaunchTarget) -> Bool {
    quickLaunchTargetApplicationURL(target) != nil
}

func hasInstalledQuickLaunchTarget(
    resolver: (QuickLaunchTarget) -> URL? = { quickLaunchTargetApplicationURL($0) }
) -> Bool {
    QuickLaunchTarget.allCases.contains { resolver($0) != nil }
}

func quickLaunchTargetCanRun(installed: Bool, wrapperPresent: Bool) -> Bool {
    installed && wrapperPresent
}

enum QuickLaunchTargetReadiness: Equatable {
    case ready
    case appNotInstalled
    case launcherMissing

    var shortLabel: String? {
        switch self {
        case .ready: return nil
        case .appNotInstalled: return "Not installed"
        case .launcherMissing: return "Launcher missing"
        }
    }

    var explanation: String {
        switch self {
        case .ready:
            return "The desktop app and its launcher are ready."
        case .appNotInstalled:
            return "Install the desktop app in Applications to use this launcher."
        case .launcherMissing:
            return "The desktop app is installed, but its launcher is missing or cannot run."
        }
    }
}

func quickLaunchTargetReadiness(
    appInstalled: Bool,
    launcherRunnable: Bool
) -> QuickLaunchTargetReadiness {
    guard appInstalled else { return .appNotInstalled }
    return launcherRunnable ? .ready : .launcherMissing
}

func quickLaunchLauncherIsRunnable(_ target: QuickLaunchTarget) -> Bool {
    quickLaunchBundleIsRunnable(
        inspectQuickLaunchBundle(atPath: target.launcherWrapperPath)
    )
}

func quickLaunchTargetReadiness(
    _ target: QuickLaunchTarget
) -> QuickLaunchTargetReadiness {
    if let previewTargets = quickLaunchInstalledTargetsPreviewOverride {
        return previewTargets.contains(target) ? .ready : .appNotInstalled
    }
    return quickLaunchTargetReadiness(
        appInstalled: quickLaunchTargetIsInstalled(target),
        launcherRunnable: quickLaunchLauncherIsRunnable(target)
    )
}

func quickLaunchTargetIsAvailable(_ target: QuickLaunchTarget) -> Bool {
    if quickLaunchInstalledTargetsPreviewOverride != nil {
        return quickLaunchTargetReadiness(target) == .ready
    }
    return quickLaunchTargetCanRun(
        installed: quickLaunchTargetIsInstalled(target),
        wrapperPresent: quickLaunchLauncherIsRunnable(target)
    )
}

/// Unavailable targets may only be cleared. Keeping these rules pure lets the UI
/// expose a repair path for stale assignments without permitting a new dormant one.
func quickLaunchMouseSelectionIsAllowed(
    _ button: QuickLaunchMouseButton?,
    readiness: QuickLaunchTargetReadiness
) -> Bool {
    button == nil || readiness == .ready
}

func quickLaunchMousePickerIsEnabled(
    readiness: QuickLaunchTargetReadiness,
    selection: QuickLaunchMouseButton?
) -> Bool {
    readiness == .ready || selection != nil
}

struct ThumbWheelConfig: Codable, Equatable {
    var enabled: Bool                 // master switch for the whole feature
    var chromeEnabled: Bool           // com.google.Chrome  -> Command-Option-Arrow (fixed)
    var braveEnabled: Bool            // com.brave.Browser  -> Command-Option-Arrow (fixed)
    var firefoxEnabled: Bool          // org.mozilla.firefox -> Command-Option-Arrow (fixed)
    var safariEnabled: Bool           // com.apple.Safari   -> Command-Shift-Arrow  (fixed)
    var defaultFallbackEnabled: Bool  // anything else      -> Command-Option-Arrow (fixed)

    private enum CodingKeys: String, CodingKey {
        case enabled, chromeEnabled, braveEnabled, firefoxEnabled
        case safariEnabled, defaultFallbackEnabled
    }

    init(
        enabled: Bool,
        chromeEnabled: Bool,
        braveEnabled: Bool,
        firefoxEnabled: Bool,
        safariEnabled: Bool,
        defaultFallbackEnabled: Bool
    ) {
        self.enabled = enabled
        self.chromeEnabled = chromeEnabled
        self.braveEnabled = braveEnabled
        self.firefoxEnabled = firefoxEnabled
        self.safariEnabled = safariEnabled
        self.defaultFallbackEnabled = defaultFallbackEnabled
    }

    /// Firefox previously followed the generic fallback. Preserve that exact choice
    /// when decoding settings written before the dedicated Firefox option existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        chromeEnabled = try container.decode(Bool.self, forKey: .chromeEnabled)
        braveEnabled = try container.decode(Bool.self, forKey: .braveEnabled)
        safariEnabled = try container.decode(Bool.self, forKey: .safariEnabled)
        defaultFallbackEnabled = try container.decode(Bool.self, forKey: .defaultFallbackEnabled)
        firefoxEnabled = try container.decodeIfPresent(Bool.self, forKey: .firefoxEnabled)
            ?? defaultFallbackEnabled
    }
}

// MARK: - Top-level config

struct KlikProConfig: Codable, Equatable {
    var schemaVersion: Int
    // New schema-10 installations begin with onboarding pending. Configurations from
    // older releases migrate as already onboarded so an update never interrupts an
    // existing user with a first-run sheet.
    var onboardingCompleted: Bool
    // Controls only Klik PRO's persistent status icon. The optional quick-launch
    // icons keep their own Special Feature lifecycle.
    var showMenuBarIcon: Bool
    // Legacy schema compatibility only. Current UI controls App Profiles menu-bar
    // visibility per instance through `AppProfileInstance.pinToMenuBar`.
    var showQuickLaunchMenuIcons: Bool
    // The optional Quick Launch UI, global hotkeys, and mouse-button overlays now
    // live inside the same background helper as the ordinary mouse mappings. This
    // persisted switch controls those optional capabilities without creating a
    // second LaunchAgent or a duplicate Background Activity entry.
    var specialFeatureEnabled: Bool
    // Shows the Caffeinate submenu in the main menu-bar icon's right-click menu.
    // The helper runs macOS's own /usr/bin/caffeinate; presets self-expire and the
    // no-timer variant is tied to the helper's PID so it can never outlive Klik PRO.
    var caffeinateMenuEnabled: Bool
    var middleButton: ShortcutMapping      // recordable
    // The tested mouse's Gesture Button reports Command-Tab from its own composite
    // keyboard HID device. The input helper maps Tab to an F20 sentinel only on that
    // exact device, leaving keyboard Command-Tab native for normal app switching.
    var gestureButton: ShortcutMapping
    // Recordable global hotkeys, part of the Special Feature card. The combined
    // helper registers them only while `specialFeatureEnabled` is true, and restarting
    // that helper on a toggle transition genuinely frees or claims each combination.
    // Optional button links below are reversible overlays; every ordinary mouse
    // mapping remains stored independently underneath.
    var chatGPTHotkey: ShortcutMapping
    var claudeHotkey: ShortcutMapping
    // Optional reversible overlays. The four ordinary button mappings remain stored
    // untouched underneath, so None/OFF/unavailable restores the user's prior action.
    var chatGPTMouseButton: QuickLaunchMouseButton?
    var claudeMouseButton: QuickLaunchMouseButton?
    var forwardButton: ShortcutMapping
    var backButton: ShortcutMapping
    var thumbWheel: ThumbWheelConfig
    // Schema 10's data-driven App Profiles list. M0 migrates the two existing
    // Quick Launch targets as legacyExternal rows while retaining the v1 fields
    // above until the M1 settings UI becomes instance-native.
    var instances: [AppProfileInstance]
    // Explicit legacy conversion suppresses only the converted config row. The
    // external wrapper and its data remain untouched and may be restored by clearing
    // this UUID through a future explicit repair flow.
    var suppressedLegacyInstanceIDs: Set<UUID>
    // Schema 11: absolute path of the durable data vault for NEW App Profiles,
    // or nil (= Application Support, today's behavior exactly). Validated by
    // vaultPathRejectionReason before use; existing instances never move.
    var dataRoot: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, onboardingCompleted, showMenuBarIcon, showQuickLaunchMenuIcons
        case specialFeatureEnabled, caffeinateMenuEnabled
        case middleButton, gestureButton
        case chatGPTHotkey, claudeHotkey, chatGPTMouseButton, claudeMouseButton
        case forwardButton, backButton, thumbWheel, instances
        case suppressedLegacyInstanceIDs, dataRoot
    }

    /// `showMenuBarIcon` was added in schema 6. Quick Launch side-button defaults were
    /// added in schema 7. Schema 8 adds first-run onboarding state. Once a schema-7+
    /// user chooses None, the omitted optional field must continue decoding as None
    /// instead of being migrated again.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        onboardingCompleted = schemaVersion < 8
            ? true
            : (try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false)
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        showQuickLaunchMenuIcons = try container.decodeIfPresent(
            Bool.self,
            forKey: .showQuickLaunchMenuIcons
        ) ?? true
        specialFeatureEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .specialFeatureEnabled
        ) ?? false
        caffeinateMenuEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .caffeinateMenuEnabled
        ) ?? false
        middleButton = try container.decode(ShortcutMapping.self, forKey: .middleButton)
        gestureButton = try container.decode(ShortcutMapping.self, forKey: .gestureButton)
        chatGPTHotkey = try container.decode(ShortcutMapping.self, forKey: .chatGPTHotkey)
        claudeHotkey = try container.decode(ShortcutMapping.self, forKey: .claudeHotkey)
        let decodedChatGPTButton = try container.decodeIfPresent(
            QuickLaunchMouseButton.self, forKey: .chatGPTMouseButton
        )
        let decodedClaudeButton = try container.decodeIfPresent(
            QuickLaunchMouseButton.self, forKey: .claudeMouseButton
        )
        if schemaVersion < 7 {
            // Preserve any pre-existing assignment. Fill only an unconfigured side,
            // and never create a duplicate when the other launcher already owns that
            // side's new default button.
            chatGPTMouseButton = decodedChatGPTButton
                ?? (decodedClaudeButton == .forward ? nil : .forward)
            claudeMouseButton = decodedClaudeButton
                ?? (decodedChatGPTButton == .back ? nil : .back)
        } else {
            chatGPTMouseButton = decodedChatGPTButton
            claudeMouseButton = decodedClaudeButton
        }
        forwardButton = try container.decode(ShortcutMapping.self, forKey: .forwardButton)
        backButton = try container.decode(ShortcutMapping.self, forKey: .backButton)
        thumbWheel = try container.decode(ThumbWheelConfig.self, forKey: .thumbWheel)
        instances = try container.decodeIfPresent(
            [AppProfileInstance].self,
            forKey: .instances
        ) ?? []
        suppressedLegacyInstanceIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .suppressedLegacyInstanceIDs
        ) ?? []
        // Schema 10 → 11 migration is additive and decode-level: an older
        // config gets dataRoot = nil and every instance .applicationSupport,
        // reproducing today's layout exactly. Hand-edited vault markers in a
        // pre-11 file are deliberately ignored, fail-safe.
        if schemaVersion < 11 {
            dataRoot = nil
            for index in instances.indices {
                instances[index].storage = .applicationSupport
            }
        } else {
            dataRoot = try container.decodeIfPresent(String.self, forKey: .dataRoot)
        }
    }

    init(
        schemaVersion: Int,
        onboardingCompleted: Bool,
        showMenuBarIcon: Bool,
        showQuickLaunchMenuIcons: Bool,
        specialFeatureEnabled: Bool,
        caffeinateMenuEnabled: Bool = false,
        middleButton: ShortcutMapping,
        gestureButton: ShortcutMapping,
        chatGPTHotkey: ShortcutMapping,
        claudeHotkey: ShortcutMapping,
        chatGPTMouseButton: QuickLaunchMouseButton?,
        claudeMouseButton: QuickLaunchMouseButton?,
        forwardButton: ShortcutMapping,
        backButton: ShortcutMapping,
        thumbWheel: ThumbWheelConfig,
        instances: [AppProfileInstance] = [],
        suppressedLegacyInstanceIDs: Set<UUID> = [],
        dataRoot: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.onboardingCompleted = onboardingCompleted
        self.showMenuBarIcon = showMenuBarIcon
        self.showQuickLaunchMenuIcons = showQuickLaunchMenuIcons
        self.specialFeatureEnabled = specialFeatureEnabled
        self.caffeinateMenuEnabled = caffeinateMenuEnabled
        self.middleButton = middleButton
        self.gestureButton = gestureButton
        self.chatGPTHotkey = chatGPTHotkey
        self.claudeHotkey = claudeHotkey
        self.chatGPTMouseButton = chatGPTMouseButton
        self.claudeMouseButton = claudeMouseButton
        self.forwardButton = forwardButton
        self.backButton = backButton
        self.thumbWheel = thumbWheel
        self.instances = instances
        self.suppressedLegacyInstanceIDs = suppressedLegacyInstanceIDs
        self.dataRoot = dataRoot
    }
}

// MARK: - Defaults

let defaultBrowserBackCombo = KeyCombo(
    keyCode: UInt16(kVK_ANSI_LeftBracket), keyDisplay: "[",
    command: true, option: false, control: false, shift: false
)
let defaultBrowserForwardCombo = KeyCombo(
    keyCode: UInt16(kVK_ANSI_RightBracket), keyDisplay: "]",
    command: true, option: false, control: false, shift: false
)

extension KlikProConfig {
    static let `default`: KlikProConfig = {
        var config = KlikProConfig(
            schemaVersion: 11,
            onboardingCompleted: false,
            // Fresh installs begin with every Settings toggle OFF. First-run onboarding
            // asks the user to turn each on (or skip). Existing configs keep their stored
            // `showMenuBarIcon`; only brand-new installs use this OFF default.
            showMenuBarIcon: false,
            showQuickLaunchMenuIcons: true,
            specialFeatureEnabled: false,
            middleButton: ShortcutMapping(
            enabled: true,
            combo: KeyCombo(keyCode: UInt16(kVK_ANSI_7), keyDisplay: "7",
                            command: true, option: false, control: false, shift: true)
        ),
            gestureButton: ShortcutMapping(
            enabled: true,
            combo: KeyCombo(keyCode: UInt16(kVK_ANSI_6), keyDisplay: "6",
                            command: true, option: false, control: false, shift: true)
        ),
            chatGPTHotkey: ShortcutMapping(
            enabled: true,
            combo: KeyCombo(keyCode: UInt16(kVK_ANSI_G), keyDisplay: "G",
                            command: true, option: true, control: true, shift: false)
        ),
            claudeHotkey: ShortcutMapping(
            enabled: true,
            combo: KeyCombo(keyCode: UInt16(kVK_ANSI_C), keyDisplay: "C",
                            command: true, option: true, control: true, shift: false)
        ),
            chatGPTMouseButton: .forward,
            claudeMouseButton: .back,
            forwardButton: ShortcutMapping(
            enabled: true,
            combo: defaultBrowserForwardCombo
        ),
            backButton: ShortcutMapping(
            enabled: true,
            combo: defaultBrowserBackCombo
        ),
            thumbWheel: ThumbWheelConfig(
            enabled: true, chromeEnabled: true, braveEnabled: true,
            firefoxEnabled: true, safariEnabled: true, defaultFallbackEnabled: true
        ),
            instances: []
        )
        config.instances = synchronizedLegacyQuickLaunchInstances(in: config)
        return config
    }()
}

// MARK: - Storage location + load/save

enum KlikProConfigStore {
    static var configDirectoryPath: String {
        if let override = ProcessInfo.processInfo.environment["KLIK_PRO_CONFIG_DIRECTORY"],
           !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/Library/Application Support/Klik PRO"
    }
    static var configFilePath: String { configDirectoryPath + "/config.json" }
    static var preV2BackupFilePath: String { configDirectoryPath + "/config.json.pre-v2" }

    private static func addingDiscoveredExternalDualApps(
        to config: KlikProConfig
    ) -> KlikProConfig {
        guard !previewRenderingIsActive,
              ProcessInfo.processInfo.environment["KLIK_PRO_CONFIG_DIRECTORY"] == nil else {
            return config
        }
        var updated = config
        let existingPaths = Set(updated.instances.map(\.launcherPath))
        updated.instances.append(contentsOf: discoveredExternalDualAppInstances().filter { discovered in
            !existingPaths.contains(discovered.launcherPath)
                && !updated.instances.contains(where: { existing in existing.id == discovered.id })
        })
        return updated
    }

    /// If config.json doesn't exist yet: writes `.default` to disk (so it exists next
    /// time the settings app opens) and returns `.default`.
    /// If it exists but fails to decode: falls back to `.default` IN MEMORY ONLY —
    /// does NOT overwrite the file on disk, so a human can inspect/fix/delete it.
    static func load() -> KlikProConfig {
        guard let data = FileManager.default.contents(atPath: configFilePath) else {
            var defaults = addingDiscoveredExternalDualApps(
                to: normalizedQuickLaunchConfig(KlikProConfig.default)
            )
            if let previewOverride = specialFeatureEnabledPreviewOverride {
                defaults.specialFeatureEnabled = previewOverride
            }
            // A fresh install already begins all-OFF, so record the one-time policy as
            // applied — otherwise the reset below would fire on a later launch and wipe a
            // brand-new user's onboarding choices.
            markAllTogglesOffPolicyApplied()
            _ = save(defaults)
            return defaults
        }
        guard let decoded = try? JSONDecoder().decode(KlikProConfig.self, from: data) else {
            // A file exists but can't be read, so keep it untouched (don't let onboarding
            // dismissal overwrite it) and don't run the all-OFF reset against an
            // unreadable config. Treat onboarding as done and keep the icon visible so a
            // corrupt-config user still has a usable, discoverable app.
            var fallback = KlikProConfig.default
            fallback.onboardingCompleted = true
            fallback.showMenuBarIcon = true
            return fallback
        }
        let requiresSingleServiceMigration = decoded.schemaVersion < 9
        let requiresAppProfilesMigration = decoded.schemaVersion < 10
        let requiresVaultMigration = decoded.schemaVersion < 11
        var normalized = addingDiscoveredExternalDualApps(
            to: normalizedQuickLaunchConfig(decoded)
        )
        if let previewOverride = specialFeatureEnabledPreviewOverride {
            normalized.specialFeatureEnabled = previewOverride
        }
        if requiresSingleServiceMigration {
            // In earlier releases the running state of local.klik-pro.menu was the
            // persisted Special Feature choice. Capture it before startup removes
            // that legacy job before writing schema 10 so later helper restarts do not
            // need to infer state from a service that no longer exists.
            normalized.specialFeatureEnabled = isLegacyMenuServiceRunning()
        }
        if requiresSingleServiceMigration || requiresAppProfilesMigration {
            // Preserve the exact pre-v2 bytes once. A backup failure or config-save
            // failure leaves the original file untouched while the helper continues
            // with the normalized in-memory model.
            if createPreV2BackupIfNeeded(originalData: data) {
                _ = save(normalized)
            }
        } else if requiresVaultMigration {
            // Schema 10 → 11 is purely additive (dataRoot defaults nil, every
            // instance defaults .applicationSupport), so the version bump is
            // rewritten without the destructive-migration backup convention.
            _ = save(normalized)
        }
        // The "all Settings toggles start OFF" policy applies once to existing users too.
        if applyAllTogglesOffPolicyIfNeeded(&normalized) {
            _ = save(normalized)
        }
        return normalized
    }

    /// Marker recording that the one-time "all Settings toggles OFF" policy has already
    /// been applied for this user, so the reset in `load()` runs exactly once.
    static let allTogglesOffPolicyKey = "klikpro.allTogglesOffPolicyApplied.v1"

    /// The reset touches real UserDefaults and rewrites config, so it must stay out of
    /// preview renders and the test harness (which drives an isolated config directory).
    private static var offPolicyMigrationEligible: Bool {
        !previewRenderingIsActive
            && ProcessInfo.processInfo.environment["KLIK_PRO_CONFIG_DIRECTORY"] == nil
    }

    static func markAllTogglesOffPolicyApplied() {
        guard offPolicyMigrationEligible else { return }
        UserDefaults.standard.set(true, forKey: allTogglesOffPolicyKey)
    }

    /// On the first production load after updating, reset the four Settings toggles OFF
    /// and re-arm first-run onboarding so existing users go through the same opt-in as a
    /// fresh install. Returns true when it changed the config (so the caller persists it).
    private static func applyAllTogglesOffPolicyIfNeeded(_ config: inout KlikProConfig) -> Bool {
        guard offPolicyMigrationEligible,
              !UserDefaults.standard.bool(forKey: allTogglesOffPolicyKey) else { return false }
        config.onboardingCompleted = false
        config.showMenuBarIcon = false
        config.caffeinateMenuEnabled = false
        // Clear the two UserDefaults-backed switches so they resolve OFF while onboarding
        // is pending; onboarding writes concrete values again when the user confirms.
        UserDefaults.standard.removeObject(forKey: launchAtLoginPreferenceKey)
        UserDefaults.standard.removeObject(forKey: "klikpro.autoCheckUpdates")
        UserDefaults.standard.set(true, forKey: allTogglesOffPolicyKey)
        return true
    }

    @discardableResult
    static func save(_ config: KlikProConfig) -> Bool {
        let normalized = normalizedQuickLaunchConfig(config)
        guard quickLaunchMouseAssignmentsAreValid(normalized),
              appProfileAssignmentsAreValid(normalized) else { return false }
        do {
            try FileManager.default.createDirectory(
                atPath: configDirectoryPath, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(normalized)
            try data.write(to: URL(fileURLWithPath: configFilePath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Create-once backup using O_EXCL so repeated launches can never overwrite the
    /// original pre-v2 bytes. The file is flushed and closed before migration saves.
    static func createPreV2BackupIfNeeded(originalData: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(
                atPath: configDirectoryPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return false
        }

        let descriptor = open(preV2BackupFilePath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if descriptor == -1 {
            return errno == EEXIST
        }

        var succeeded = true
        originalData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if result <= 0 {
                    succeeded = false
                    break
                }
                written += result
            }
        }
        if succeeded && fsync(descriptor) != 0 { succeeded = false }
        if close(descriptor) != 0 { succeeded = false }

        if !succeeded {
            try? FileManager.default.removeItem(atPath: preV2BackupFilePath)
        }
        return succeeded
    }
}

// MARK: - Shared Carbon helper (moved from KlikProInput.swift)

func fourCharacterCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}

// MARK: - Klik PRO menu-bar identity

/// Enlarges the glyph about the 18pt canvas centre so it fills the status item
/// with minimal padding (the tiles+toggle otherwise occupy only ~13 of 18pt).
/// Applied identically to the base template and the active green knob so they
/// stay aligned.
private func applyMenuBarGlyphScale() {
    let scale: CGFloat = 1.32
    let transform = NSAffineTransform()
    transform.translateX(by: 9, yBy: 9)
    transform.scale(by: scale)
    transform.translateX(by: -9, yBy: -9)
    transform.concat()
}

/// A resolution-independent, monochrome status icon that echoes the app icon:
/// two overlapping App Profile tiles (a back tile, a transparent seam gap, and a
/// solid front tile) carrying a toggle. The toggle track is knocked out
/// (transparent) with a solid knob on the "on" (right) side. AppKit tints this
/// base template automatically for light, dark, selected, and inactive menu
/// bars. The active-state green knob is a separate non-template overlay below,
/// sized and positioned to sit exactly over this knob.
func klikProMenuBarIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { _ in
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        applyMenuBarGlyphScale()

        let back = NSBezierPath(
            roundedRect: NSRect(x: 2.4, y: 6.1, width: 8.2, height: 8.2),
            xRadius: 2.0,
            yRadius: 2.0
        )
        // Slightly inflated front outline punched out of the back tile so the two
        // tiles keep a clean seam gap when they overlap.
        let frontGap = NSBezierPath(
            roundedRect: NSRect(x: 7.0, y: 3.3, width: 9.0, height: 9.0),
            xRadius: 2.4,
            yRadius: 2.4
        )
        let front = NSBezierPath(
            roundedRect: NSRect(x: 7.6, y: 3.9, width: 8.2, height: 8.2),
            xRadius: 2.0,
            yRadius: 2.0
        )
        let track = NSBezierPath(
            roundedRect: NSRect(x: 8.2, y: 6.4, width: 5.4, height: 2.9),
            xRadius: 1.45,
            yRadius: 1.45
        )
        let knob = NSBezierPath(ovalIn: NSRect(x: 11.0, y: 6.8, width: 2.1, height: 2.1))

        NSColor.black.setFill()
        back.fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        frontGap.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        front.fill()
        // Knock the toggle track out of the front tile, then lay the knob back in
        // so it reads as a switch. The knob shares its rect with the green overlay.
        NSGraphicsContext.current?.compositingOperation = .clear
        track.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        knob.fill()

        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    image.isTemplate = true
    return image
}

/// The brand-green toggle knob that sits exactly over the base template's knob on
/// the "on" (right) side. Keeping the green in a separate non-template overlay
/// preserves AppKit's adaptive tint for the tiles while lighting the switch green
/// as an unambiguous active-state indicator. Slightly larger than the template
/// knob so it fully covers it (the same technique the mouse icon used for its
/// button dots).
func klikProMenuBarActiveIndicator() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { _ in
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        applyMenuBarGlyphScale()

        // Brand green #19BB13 (matches KlikProBrand.green and the app icon).
        NSColor(calibratedRed: 25 / 255, green: 187 / 255, blue: 19 / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 10.75, y: 6.55, width: 2.6, height: 2.6)).fill()

        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    image.isTemplate = false
    return image
}

/// Resolve the main app when this code is running from the nested helper bundle. The
/// name-based ancestor is deterministic and testable; runtime callers can still fall
/// back to Launch Services or /Applications when developing from an unbundled binary.
func enclosingKlikProAppURL(for bundleURL: URL) -> URL? {
    var candidate = bundleURL.standardizedFileURL
    while candidate.path != "/" {
        if candidate.pathExtension == "app", candidate.lastPathComponent == "Klik PRO.app" {
            return candidate
        }
        let parent = candidate.deletingLastPathComponent()
        guard parent != candidate else { break }
        candidate = parent
    }
    return nil
}

// MARK: - Shared background-service helpers (moved from KlikProApp.swift)
//
// One per-user LaunchAgent owns ordinary mouse input, the persistent Klik PRO status
// icon, and the optional Quick Launch UI/hotkeys. The legacy menu constants remain
// only long enough to migrate an existing ON state and remove the obsolete second job.

let accessibilitySetupRequestedNotification = Notification.Name(
    "local.klik-pro.accessibility-setup-requested"
)
let accessibilityStatusCheckRequestedNotification = Notification.Name(
    "local.klik-pro.accessibility-status-check-requested"
)
let updateCheckRequestedNotification = Notification.Name(
    "local.klik-pro.update-check-requested"
)
let uid = getuid()
let domain = "gui/\(uid)"
let inputServiceLabel = "local.klik-pro.input"
let inputTarget = "\(domain)/\(inputServiceLabel)"
let inputPlistPath = NSHomeDirectory() + "/Library/LaunchAgents/" + inputServiceLabel + ".plist"
let launchAtLoginPreferenceKey = "klikpro.launchAtLoginEnabled"
let legacyMenuServiceLabel = "local.klik-pro.menu"
let legacyMenuTarget = "\(domain)/\(legacyMenuServiceLabel)"
let legacyMenuPlistPath = NSHomeDirectory()
    + "/Library/LaunchAgents/" + legacyMenuServiceLabel + ".plist"

/// Test/preview seam used while migrating the schema-8 process state through schema 9.
/// Production leaves this nil and asks launchd whether the old menu job is loaded.
var legacyMenuServiceRunningPreviewOverride: Bool?

func run(_ arguments: [String], timeout: TimeInterval = 8) -> Int32 {
    guard !previewRenderingIsActive else { return 1 }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let completion = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in completion.signal() }
    do {
        try process.run()
    } catch {
        return -1
    }
    guard completion.wait(timeout: .now() + timeout) == .success else {
        process.terminate()
        if completion.wait(timeout: .now() + 0.5) != .success {
            kill(process.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + 0.5)
        }
        return 124
    }
    return process.terminationStatus
}

func launchAtLoginPreference(defaultValue: Bool) -> Bool {
    guard !previewRenderingIsActive else { return true }
    return UserDefaults.standard.object(forKey: launchAtLoginPreferenceKey) as? Bool
        ?? defaultValue
}

/// Start the helper for this session without changing the user's "Launch at login"
/// preference. macOS may refuse to bootstrap a disabled launchd job, so when startup
/// is disabled we temporarily enable only long enough to load/restart the already
/// installed helper, then disable the login item again.
@discardableResult
func ensureInputHelperRunning(launchAtLoginEnabled: Bool? = nil) -> Bool {
    guard !previewRenderingIsActive else { return true }

    let shouldDisableAfter = (launchAtLoginEnabled ?? launchAtLoginPreference(defaultValue: true)) == false
    if !shouldDisableAfter {
        // Launch at login ON must clear any disabled override left by an earlier OFF
        // period even while the helper is already running: launchd keeps the override
        // across reboots, silently ignores RunAtLoad, and rejects bootstrap with EIO.
        _ = run(["enable", inputTarget])
    }
    if run(["print", inputTarget]) == 0 { return true }

    if shouldDisableAfter {
        _ = run(["enable", inputTarget])
    }

    let bootstrapped = run(["bootstrap", domain, inputPlistPath]) == 0
        || run(["print", inputTarget]) == 0

    if shouldDisableAfter {
        _ = run(["disable", inputTarget])
    }
    return bootstrapped
}

func isLegacyMenuServiceRunning() -> Bool {
    if let previewState = legacyMenuServiceRunningPreviewOverride {
        return previewState
    }
    guard !previewRenderingIsActive else { return false }
    return run(["print", legacyMenuTarget]) == 0
}

func launchAgentPropertyList(
    helperExecutablePath: String,
    logsDirectoryPath: String
) -> [String: Any] {
    return [
        "Label": inputServiceLabel,
        "ProgramArguments": [helperExecutablePath],
        "RunAtLoad": true,
        "KeepAlive": true,
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "StandardOutPath": logsDirectoryPath + "/klik-pro-input.log",
        "StandardErrorPath": logsDirectoryPath + "/klik-pro-input.error.log"
    ]
}

/// Installs the single per-user LaunchAgent needed by a normal drag-to-Applications
/// installation and removes the obsolete schema-8 menu job. Release DMGs still include
/// a readable template for manual repair, but onboarding must not depend on copying or
/// editing it by hand.
@discardableResult
func installLaunchAgentPlist(
    appBundleURL: URL,
    homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
) -> Bool {
    guard !previewRenderingIsActive else { return true }

    let fileManager = FileManager.default
    let helperExecutableURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Helpers", isDirectory: true)
        .appendingPathComponent("Klik PRO Helper.app", isDirectory: true)
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("klik-pro-input", isDirectory: false)
    guard fileManager.isExecutableFile(atPath: helperExecutableURL.path) else { return false }

    let launchAgentsURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
    let logsURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
    do {
        try fileManager.createDirectory(
            at: launchAgentsURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true
        )

        let propertyList = launchAgentPropertyList(
            helperExecutablePath: helperExecutableURL.path,
            logsDirectoryPath: logsURL.path
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        let destinationURL = launchAgentsURL
            .appendingPathComponent(inputServiceLabel + ".plist", isDirectory: false)
        if (try? Data(contentsOf: destinationURL)) != data {
            try data.write(to: destinationURL, options: .atomic)
        }

        let legacyURL = launchAgentsURL
            .appendingPathComponent(legacyMenuServiceLabel + ".plist", isDirectory: false)
        let actualHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
        if homeDirectoryURL.standardizedFileURL == actualHome {
            _ = run(["bootout", domain, legacyURL.path])
            _ = run(["disable", legacyMenuTarget])
        }
        if fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
        return true
    } catch {
        return false
    }
}

/// Restart the single helper so it re-reads `config.json` and applies mappings,
/// Quick Launch state, icons, and hotkeys immediately. `kickstart -k` restarts the
/// same signed nested app, so the Accessibility grant is preserved.
@discardableResult
func applySavedConfig(launchAtLoginEnabled: Bool? = nil) -> Bool {
    guard !previewRenderingIsActive else { return true }

    let shouldDisableAfter = (launchAtLoginEnabled ?? launchAtLoginPreference(defaultValue: true)) == false
    // Enable in both directions: OFF needs the service temporarily loadable for the
    // kickstart/bootstrap below, and ON must clear a stale disabled override so
    // RunAtLoad works again at the next login (see ensureInputHelperRunning).
    _ = run(["enable", inputTarget])

    let kicked = run(["kickstart", "-k", inputTarget]) == 0
    var running = kicked || run(["print", inputTarget]) == 0
    if !running {
        running = run(["bootstrap", domain, inputPlistPath]) == 0
            || run(["print", inputTarget]) == 0
    }

    if shouldDisableAfter {
        _ = run(["disable", inputTarget])
    }
    return running
}

// MARK: - Transient hot-key availability probe

private let probeHotKeySignature = fourCharacterCode("PBPX")
private let probeHotKeyID = EventHotKeyID(signature: probeHotKeySignature, id: 9999)

/// Registers a transient, throwaway hot key purely to test OS-level availability, then
/// ALWAYS unregisters it — success or failure — via `defer`, before returning. No event
/// handler is installed or needed for this ID: RegisterEventHotKey's return status alone
/// reflects whether the combo is already claimed system-wide.
func probeHotKeyAvailability(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
    if previewRenderingIsActive { return true }
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
        UInt32(keyCode),
        carbonModifiers,
        probeHotKeyID,
        GetApplicationEventTarget(),
        0,
        &reference
    )
    defer {
        if let ref = reference {
            UnregisterEventHotKey(ref)   // runs on every exit path, success or failure
        }
    }
    return status == noErr
}

// MARK: - Browser-extension shortcut discovery

/// Chrome extension commands are application-local, so Carbon's global hot-key probe
/// cannot see them. Chrome records the effective macOS accelerators in each profile's
/// Preferences file (for example `mac:Command+E`). Parse those read-only values so the
/// settings UI can warn before a mouse assignment is swallowed inside the browser.
func parseChromeExtensionAccelerator(_ preferenceKey: String) -> KeyCombo.Signature? {
    guard preferenceKey.hasPrefix("mac:") else { return nil }
    let components = preferenceKey.dropFirst(4).split(separator: "+").map(String.init)
    guard let keyToken = components.last, components.count >= 2 else { return nil }

    var command = false
    var option = false
    var control = false
    var shift = false
    for modifier in components.dropLast() {
        switch modifier {
        case "Command": command = true
        case "Alt", "Option": option = true
        case "Ctrl", "Control", "MacCtrl": control = true
        case "Shift": shift = true
        default: return nil
        }
    }

    let baseLabel: String
    switch keyToken {
    case "Left": baseLabel = "←"
    case "Right": baseLabel = "→"
    case "Up": baseLabel = "↑"
    case "Down": baseLabel = "↓"
    case "Comma": baseLabel = ","
    case "Period": baseLabel = "."
    case "Space": baseLabel = "Space"
    case "Tab": baseLabel = "⇥"
    case "Home": baseLabel = "↖"
    case "End": baseLabel = "↘"
    case "PageUp": baseLabel = "⇞"
    case "PageDown": baseLabel = "⇟"
    case "Delete": baseLabel = "⌦"
    case "Insert": baseLabel = "Insert"
    default:
        guard keyToken.count == 1 else { return nil }
        baseLabel = keyToken.uppercased()
    }
    guard let keyCode = KeyCombo.keyCode(forBaseLabel: baseLabel) else { return nil }
    return KeyCombo.Signature(
        keyCode: keyCode,
        command: command,
        option: option,
        control: control,
        shift: shift
    )
}

func chromeExtensionShortcutSignatures(fromPreferencesData data: Data) -> Set<KeyCombo.Signature> {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let extensions = root["extensions"] as? [String: Any],
          let commands = extensions["commands"] as? [String: Any] else {
        return []
    }
    return Set(commands.keys.compactMap(parseChromeExtensionAccelerator))
}

func installedChromeExtensionShortcutSignatures(
    homeDirectory: String = NSHomeDirectory()
) -> Set<KeyCombo.Signature> {
    guard !previewRenderingIsActive else { return [] }
    let roots = [
        "Library/Application Support/Google/Chrome",
        "Library/Application Support/BraveSoftware/Brave-Browser",
        "Library/Application Support/Chromium",
    ].map { URL(fileURLWithPath: homeDirectory).appendingPathComponent($0) }

    var signatures: Set<KeyCombo.Signature> = []
    for root in roots {
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for profile in profiles {
            let name = profile.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { continue }
            let preferences = profile.appendingPathComponent("Preferences")
            guard let data = try? Data(contentsOf: preferences) else { continue }
            signatures.formUnion(chromeExtensionShortcutSignatures(fromPreferencesData: data))
        }
    }
    return signatures
}

// MARK: - Conflict-check engine

enum ShortcutConflictStatus: String {
    case ok, duplicate, mayConflict, unavailable
    var badgeText: String {
        switch self {
        case .ok: return "OK"
        case .duplicate: return "Duplicate"
        case .mayConflict: return "May Conflict"
        case .unavailable: return "Unavailable"
        }
    }
}

enum ShortcutSlot: CaseIterable, Equatable {
    case middleButton, gestureButton, forwardButton, backButton
    case chatGPTHotkey, claudeHotkey
}

/// Maps macOS's zero-based CGEvent mouse-button numbers to the semantic shortcut
/// slots shown in the settings UI. Mouse Button 4 is reported as 3 and is Back;
/// Mouse Button 5 is reported as 4 and is Forward.
func shortcutSlot(forMouseButtonNumber buttonNumber: Int64) -> ShortcutSlot? {
    switch buttonNumber {
    case 2: return .middleButton
    case 3: return .backButton
    case 4: return .forwardButton
    default: return nil
    }
}

enum MouseButtonShortcutDispatch: Equatable {
    /// Let the original down/up CGEvent continue. Chromium and Firefox translate
    /// side buttons 3/4 into browser-history Back/Forward without any keystroke.
    case nativePassThrough
    /// Consume the mouse pair and invoke the linked Special Feature target directly.
    /// Direct dispatch prevents the mirrored keyboard combo leaking into the frontmost
    /// app if a menu hotkey is temporarily unavailable.
    case launch(QuickLaunchTarget)
    /// UUID-keyed M2 dispatch. The helper resolves and revalidates the persisted
    /// instance immediately before managed launch/focus.
    case launchInstance(UUID)
    /// Consume the mouse event and emit the user's recorded keyboard shortcut.
    case synthesize(KeyCombo)
}

/// A button press must keep one dispatch decision from down through up. Re-evaluating
/// the frontmost app on mouse-up can split the pair if focus changes while held.
struct MouseButtonDispatchState {
    private var activeByButtonNumber: [Int64: MouseButtonShortcutDispatch] = [:]

    mutating func begin(
        buttonNumber: Int64,
        dispatch: MouseButtonShortcutDispatch
    ) -> MouseButtonShortcutDispatch {
        activeByButtonNumber[buttonNumber] = dispatch
        return dispatch
    }

    mutating func end(
        buttonNumber: Int64,
        orphanFallback: @autoclosure () -> MouseButtonShortcutDispatch
    ) -> MouseButtonShortcutDispatch {
        activeByButtonNumber.removeValue(forKey: buttonNumber) ?? orphanFallback()
    }

    mutating func cancel(buttonNumber: Int64) {
        activeByButtonNumber.removeValue(forKey: buttonNumber)
    }

}

let firefoxBrowserBundleIdentifiers: Set<String> = [
    "org.mozilla.firefox",
    "org.mozilla.firefoxdeveloperedition",
]

func thumbWheelMappingIsEnabled(
    for bundleIdentifier: String?,
    config: ThumbWheelConfig
) -> Bool {
    guard let bundleIdentifier = bundleIdentifier else {
        return config.defaultFallbackEnabled
    }
    switch bundleIdentifier {
    case "com.google.Chrome": return config.chromeEnabled
    case "com.brave.Browser": return config.braveEnabled
    case "com.apple.Safari": return config.safariEnabled
    case let identifier where firefoxBrowserBundleIdentifiers.contains(identifier):
        return config.firefoxEnabled
    default: return config.defaultFallbackEnabled
    }
}

private let nativeBrowserHistoryBundleIdentifiers: Set<String> = Set([
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "org.chromium.Chromium",
    "com.brave.Browser",
    "com.microsoft.edgemac",
    "com.vivaldi.Vivaldi",
]).union(firefoxBrowserBundleIdentifiers)

/// Default Back/Forward are semantic browser-history actions. Chromium and Firefox
/// already understand the original side-button events, which avoids exposing synthetic
/// Command-[ / Command-] to browser extensions. Safari's documented history shortcuts
/// remain the fallback because its raw side-button behavior is not documented. Any
/// non-default recorded combo is synthesized exactly as configured.
func mouseButtonShortcutDispatch(
    slot: ShortcutSlot,
    shortcut: ShortcutMapping,
    frontmostBundleIdentifier: String?,
    quickLaunchTarget: QuickLaunchTarget? = nil,
    appProfileInstanceID: UUID? = nil
) -> MouseButtonShortcutDispatch {
    if let appProfileInstanceID = appProfileInstanceID {
        return .launchInstance(appProfileInstanceID)
    }
    if let quickLaunchTarget = quickLaunchTarget {
        return .launch(quickLaunchTarget)
    }

    let isUntouchedBrowserDefault: Bool
    switch slot {
    case .backButton:
        isUntouchedBrowserDefault = shortcut.combo.signature == defaultBrowserBackCombo.signature
    case .forwardButton:
        isUntouchedBrowserDefault = shortcut.combo.signature == defaultBrowserForwardCombo.signature
    default:
        isUntouchedBrowserDefault = false
    }

    if isUntouchedBrowserDefault,
       let bundleIdentifier = frontmostBundleIdentifier,
       nativeBrowserHistoryBundleIdentifiers.contains(bundleIdentifier) {
        return .nativePassThrough
    }
    return .synthesize(shortcut.combo)
}

func browserHistoryDisplayOverride(slot: ShortcutSlot, combo: KeyCombo) -> String? {
    switch slot {
    case .backButton where combo.signature == defaultBrowserBackCombo.signature:
        return "Browser ←"
    case .forwardButton where combo.signature == defaultBrowserForwardCombo.signature:
        return "Browser →"
    default:
        return nil
    }
}

/// The tested thumb wheel reports discrete, non-continuous axis-2 ticks. Continuous
/// axis-2 input is normally a trackpad or precision scrolling gesture and must remain
/// native instead of being converted into browser-tab switches.
func shouldMapThumbWheel(axis2: Int64, isContinuous: Bool) -> Bool {
    axis2 != 0 && !isContinuous
}

// MARK: - Device-specific Gesture Button isolation

let gestureSentinelKeyCode = UInt32(kVK_F20)
let gestureSentinelModifiers = UInt32(cmdKey)

func isGestureSentinelOutput(_ combo: KeyCombo) -> Bool {
    combo.keyCode == UInt16(kVK_F20)
        && combo.command
        && !combo.option
        && !combo.control
        && !combo.shift
}

/// The physical keyboard's Command-Tab shortcut remains reserved for normal app
/// switching. Klik PRO may emit that combo from a deliberately configured mouse
/// button, but it must never claim it as a Special Feature global keyboard hotkey.
func isReservedKeyboardCommandTab(_ combo: KeyCombo) -> Bool {
    combo.keyCode == UInt16(kVK_Tab)
        && combo.command
        && !combo.option
        && !combo.control
        && !combo.shift
}

func configuredGlobalHotKeyUsingReservedCommandTab(in config: KlikProConfig) -> ShortcutSlot? {
    let globalSlots: [ShortcutSlot] = [.chatGPTHotkey, .claudeHotkey]
    return globalSlots.first { slot in
        let shortcut = mapping(for: slot, in: config)
        return shortcut.enabled && isReservedKeyboardCommandTab(shortcut.combo)
    }
}

func configuredSlotUsingGestureSentinel(in config: KlikProConfig) -> ShortcutSlot? {
    ShortcutSlot.allCases.first { slot in
        // Scan persisted source mappings, not reversible overlays. A reserved base
        // combo must not be hidden by a temporary link and re-emerge when that link is
        // OFF, removed, or unavailable.
        let shortcut = baseMapping(for: slot, in: config)
        return shortcut.enabled && isGestureSentinelOutput(shortcut.combo)
    }
}

private let gestureHIDUtilMatching =
    "{\"VendorID\":0x046d,\"ProductID\":0xb023,\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"
private let gestureSourceUsage = "30064771115" // 0x70000002B, USB HID Tab
private let gestureSentinelUsage = "30064771183" // 0x70000006F, USB HID F20
private let gestureSentinelMapping =
    "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000002B,\"HIDKeyboardModifierMappingDst\":0x70000006F}]}"
private let emptyGestureMapping = "{\"UserKeyMapping\":[]}"

enum GestureSentinelMappingState: Equatable {
    case absent
    case installed
    case ownedConflict
    case conflicting
    case deviceAbsent
    case unavailable
}

private var gestureSentinelOwnershipMarkerPath: String {
    KlikProConfigStore.configDirectoryPath + "/gesture-sentinel-owned"
}

private func gestureSentinelOwnershipMarkerExists() -> Bool {
    FileManager.default.fileExists(atPath: gestureSentinelOwnershipMarkerPath)
}

private func createGestureSentinelOwnershipMarker() -> Bool {
    do {
        try FileManager.default.createDirectory(
            atPath: KlikProConfigStore.configDirectoryPath,
            withIntermediateDirectories: true
        )
        try Data("Klik PRO owns the MX Master 3 Tab-to-F20 sentinel.\n".utf8).write(
            to: URL(fileURLWithPath: gestureSentinelOwnershipMarkerPath),
            options: .atomic
        )
        return true
    } catch {
        return false
    }
}

private func removeGestureSentinelOwnershipMarker() {
    try? FileManager.default.removeItem(atPath: gestureSentinelOwnershipMarkerPath)
}

/// Parses `hidutil property --get UserKeyMapping` output. Klik PRO only owns the
/// exact one-entry Tab -> F20 mapping; any other non-empty map is left untouched.
func parseGestureSentinelMappingState(output: String, commandSucceeded: Bool) -> GestureSentinelMappingState {
    guard commandSucceeded else { return .unavailable }
    let mappingRowCount = output.components(separatedBy: "UserKeyMapping").count - 1
    guard mappingRowCount > 0 else { return .deviceAbsent }

    let value = output.components(separatedBy: "UserKeyMapping").dropFirst().joined()
    let compactValue = value.filter { !$0.isWhitespace }
    if mappingRowCount == 1,
       compactValue == "(null)" || compactValue == "<null>" || compactValue == "()" {
        return .absent
    }

    func decimalValues(for key: String, in text: String) -> [String] {
        let pattern = NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*([0-9]+)\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    let entryPattern = #"\{([^{}]*)\}"#
    let entryRegex = try? NSRegularExpression(pattern: entryPattern)
    let valueRange = NSRange(value.startIndex..<value.endIndex, in: value)
    let entries = entryRegex?.matches(in: value, range: valueRange).compactMap { match -> String? in
        guard let entryRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[entryRange])
    } ?? []
    let sentinelEntryCount = entries.filter { entry in
        decimalValues(for: "HIDKeyboardModifierMappingSrc", in: entry) == [gestureSourceUsage]
            && decimalValues(for: "HIDKeyboardModifierMappingDst", in: entry) == [gestureSentinelUsage]
    }.count

    if mappingRowCount == 1, entries.count == 1, sentinelEntryCount == 1 {
        return .installed
    }
    if sentinelEntryCount > 0 {
        // The exact Klik PRO entry is still present, but another matching service or
        // mapping appeared. Runtime ownership depends on the marker checked below.
        return .ownedConflict
    }
    return .conflicting
}

private struct HIDUtilResult {
    let status: Int32
    let output: String
}

private func runHIDUtil(_ arguments: [String]) -> HIDUtilResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        guard completion.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            if completion.wait(timeout: .now() + 0.5) != .success {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 0.5)
            }
            return HIDUtilResult(status: 124, output: "hidutil timed out")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
            + stderr.fileHandleForReading.readDataToEndOfFile()
        return HIDUtilResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return HIDUtilResult(status: -1, output: String(describing: error))
    }
}

func currentGestureSentinelMappingState() -> GestureSentinelMappingState {
    let result = runHIDUtil([
        "property", "--matching", gestureHIDUtilMatching,
        "--get", "UserKeyMapping",
    ])
    let parsed = parseGestureSentinelMappingState(
        output: result.output,
        commandSucceeded: result.status == 0
    )
    if (parsed == .installed || parsed == .ownedConflict),
       !gestureSentinelOwnershipMarkerExists() {
        return .conflicting
    }
    return parsed
}

/// Applies the exact device-scoped Tab -> F20 sentinel only when the MX Master 3
/// has no custom map already. This never modifies the physical keyboard service.
@discardableResult
func applyGestureSentinelMappingIfSafe() -> Bool {
    switch currentGestureSentinelMappingState() {
    case .installed:
        return gestureSentinelOwnershipMarkerExists()
    case .absent:
        guard createGestureSentinelOwnershipMarker() else { return false }
        _ = runHIDUtil([
            "property", "--matching", gestureHIDUtilMatching,
            "--set", gestureSentinelMapping,
        ])
        let stateAfterSet = currentGestureSentinelMappingState()
        if stateAfterSet == .installed { return true }

        // A failed verification can still follow a successful property write. Keep
        // the marker while state is unavailable or the exact entry overlaps another
        // service, so retry never abandons an installed map. Confirmed non-owned
        // states release it.
        if stateAfterSet != .unavailable && stateAfterSet != .ownedConflict {
            removeGestureSentinelOwnershipMarker()
        }
        return false
    case .ownedConflict, .conflicting, .deviceAbsent, .unavailable:
        return false
    }
}

/// Clears only Klik PRO's own exact sentinel. An unknown user-supplied device map
/// is never replaced or removed.
@discardableResult
func clearGestureSentinelMappingIfOwned() -> Bool {
    switch currentGestureSentinelMappingState() {
    case .absent:
        removeGestureSentinelOwnershipMarker()
        return true
    case .installed:
        guard gestureSentinelOwnershipMarkerExists() else { return false }
        let result = runHIDUtil([
            "property", "--matching", gestureHIDUtilMatching,
            "--set", emptyGestureMapping,
        ])
        let cleared = result.status == 0 && currentGestureSentinelMappingState() == .absent
        if cleared { removeGestureSentinelOwnershipMarker() }
        return cleared
    case .deviceAbsent:
        // hidutil maps are tied to the live service and disappear when that device
        // service is gone, so no system mapping remains to clear.
        removeGestureSentinelOwnershipMarker()
        return true
    case .conflicting:
        // The live map is no longer the exact one-entry map Klik PRO installed, so
        // relinquish the stale marker without modifying the user's current mapping.
        removeGestureSentinelOwnershipMarker()
        return true
    case .ownedConflict:
        // At least one matched service still contains Klik PRO's exact entry, but
        // clearing every matched service would overwrite another map. Retain both
        // ownership and receiver until the service overlap resolves.
        return false
    case .unavailable:
        return false
    }
}

func quickLaunchMouseButton(
    for target: QuickLaunchTarget,
    in config: KlikProConfig
) -> QuickLaunchMouseButton? {
    switch target {
    case .chatGPT: return config.chatGPTMouseButton
    case .claude: return config.claudeMouseButton
    }
}

func quickLaunchMouseAssignmentsAreValid(_ config: KlikProConfig) -> Bool {
    guard let chatGPT = config.chatGPTMouseButton,
          let claude = config.claudeMouseButton else {
        return true
    }
    return chatGPT != claude
}

private func legacyQuickLaunchInstance(
    for target: QuickLaunchTarget,
    in config: KlikProConfig,
    preserving existing: AppProfileInstance?
) -> AppProfileInstance {
    let defaultLabel = target == .claude ? "Claude P" : target.title
    let preservedLabel = existing?.label
    let displayLabel = target == .claude && preservedLabel == target.title
        ? defaultLabel
        : (preservedLabel ?? defaultLabel)

    return AppProfileInstance(
        id: existing?.id ?? target.legacyInstanceID,
        label: displayLabel,
        launcherKind: .legacyExternal,
        launcherPath: target.launcherWrapperPath,
        profileDirectory: nil,
        profileOwnership: .external,
        source: AppProfileSource(
            bundleIdentifier: target.applicationBundleIdentifier,
            bundleURL: target.standardApplicationPath
        ),
        environmentOverrides: [:],
        iconPath: nil,
        menuColor: existing?.menuColor,
        pinToMenuBar: existing?.pinToMenuBar ?? config.showQuickLaunchMenuIcons,
        hotkey: baseMapping(for: target.shortcutSlot, in: config),
        mouseButton: quickLaunchMouseButton(for: target, in: config),
        lastDetectedEngine: existing?.lastDetectedEngine,
        lastVerifiedAppVersion: existing?.lastVerifiedAppVersion,
        lastVerifiedTeamIdentifier: existing?.lastVerifiedTeamIdentifier,
        compatibilityRuleID: existing?.compatibilityRuleID
    )
}

/// Finds the small external launcher bundles used by Klik PRO 1.x and by the
/// owner's earlier multi-login setup. Discovery is deliberately narrow: only
/// known ChatGPT/Claude launcher bundle identifiers in the two launcher locations
/// are considered. The launcher bundles and their profile data are never changed.
func discoveredExternalDualAppInstances(
    homeDirectory: String = NSHomeDirectory(),
    fileManager: FileManager = .default
) -> [AppProfileInstance] {
    struct KnownLauncher {
        let path: String
        let label: String
        let bundleIdentifier: String
        let sourceBundleIdentifier: String
        let sourcePath: String
        let id: UUID
    }

    let systemApplicationsDirectory = homeDirectory == NSHomeDirectory()
        ? "/Applications"
        : homeDirectory + "/Applications"
    let known: [KnownLauncher] = [
        KnownLauncher(
            path: homeDirectory + "/Applications/ChatGPT P.app",
            label: "ChatGPT P",
            bundleIdentifier: "local.chatgpt.profile1",
            sourceBundleIdentifier: QuickLaunchTarget.chatGPT.applicationBundleIdentifier,
            sourcePath: QuickLaunchTarget.chatGPT.standardApplicationPath,
            id: UUID(uuidString: "2EE034C7-2511-4A31-AFC3-A8DF9E659DA1")!
        ),
        KnownLauncher(
            path: homeDirectory + "/Applications/ChatGPT G.app",
            label: "ChatGPT G",
            bundleIdentifier: "local.chatgpt.profile2",
            sourceBundleIdentifier: QuickLaunchTarget.chatGPT.applicationBundleIdentifier,
            sourcePath: QuickLaunchTarget.chatGPT.standardApplicationPath,
            id: UUID(uuidString: "B20A6010-02D5-4AC5-B9F2-2FB0D5B3776C")!
        ),
        KnownLauncher(
            path: homeDirectory + "/Applications/ChatGPT A.app",
            label: "ChatGPT A",
            bundleIdentifier: "local.chatgpt.profile3",
            sourceBundleIdentifier: QuickLaunchTarget.chatGPT.applicationBundleIdentifier,
            sourcePath: QuickLaunchTarget.chatGPT.standardApplicationPath,
            id: UUID(uuidString: "468E61E1-8E8E-460F-9178-EA57D6FD7764")!
        ),
        KnownLauncher(
            path: systemApplicationsDirectory + "/Claude 2.app",
            label: "Claude G",
            bundleIdentifier: "local.claude.profile2",
            sourceBundleIdentifier: QuickLaunchTarget.claude.applicationBundleIdentifier,
            sourcePath: QuickLaunchTarget.claude.standardApplicationPath,
            id: UUID(uuidString: "6CDA06DD-E376-4D58-91F4-8DF11A189A12")!
        ),
    ]

    return known.compactMap { launcher in
        let infoURL = URL(fileURLWithPath: launcher.path, isDirectory: true)
            .appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: launcher.path),
              let info = NSDictionary(contentsOf: infoURL),
              info["CFBundleIdentifier"] as? String == launcher.bundleIdentifier else {
            return nil
        }
        return AppProfileInstance(
            id: launcher.id,
            label: launcher.label,
            launcherKind: .legacyExternal,
            launcherPath: launcher.path,
            profileDirectory: nil,
            profileOwnership: .external,
            source: AppProfileSource(
                bundleIdentifier: launcher.bundleIdentifier,
                bundleURL: launcher.sourcePath
            ),
            environmentOverrides: [:],
            pinToMenuBar: false,
            hotkey: ShortcutMapping(
                enabled: false,
                combo: KeyCombo(
                    keyCode: 0,
                    keyDisplay: "A",
                    command: false,
                    option: false,
                    control: true,
                    shift: false
                )
            ),
            mouseButton: nil,
            lastDetectedEngine: .electron,
            compatibilityRuleID: nil
        )
    }
}

/// Mirrors the v1 fields into the two schema-10 legacy rows while preserving every
/// managed/future instance. M0 keeps the existing Settings bindings authoritative so
/// saving behaves exactly as it did before the UI becomes instance-native in M1.
func synchronizedLegacyQuickLaunchInstances(in config: KlikProConfig) -> [AppProfileInstance] {
    let legacyIDs = Set(QuickLaunchTarget.allCases.map(\.legacyInstanceID))
    let legacyBundleIdentifiers = Set(
        QuickLaunchTarget.allCases.map(\.applicationBundleIdentifier)
    )
    let nonLegacy = config.instances.filter { instance in
        guard instance.launcherKind == .legacyExternal else { return true }
        return !legacyIDs.contains(instance.id)
            && !legacyBundleIdentifiers.contains(instance.source.bundleIdentifier)
    }
    let legacy = QuickLaunchTarget.allCases.compactMap { target -> AppProfileInstance? in
        guard !config.suppressedLegacyInstanceIDs.contains(target.legacyInstanceID) else {
            return nil
        }
        let existing = config.instances.first { instance in
            instance.id == target.legacyInstanceID
                || instance.legacyQuickLaunchTarget == target
        }
        return legacyQuickLaunchInstance(for: target, in: config, preserving: existing)
    }
    return legacy + nonLegacy
}

/// Managed and unsuppressed legacy rows share one assignment namespace. Ambiguous
/// mouse ownership, duplicate enabled hotkeys, or Command-Tab all fail closed before
/// config persistence or helper registration.
func appProfileAssignmentsAreValid(_ config: KlikProConfig) -> Bool {
    var mouseOwners = Set<QuickLaunchMouseButton>()
    var hotkeyOwners = Set([
        config.middleButton,
        config.gestureButton,
        config.forwardButton,
        config.backButton,
    ].filter(\.enabled).map { $0.combo.signature })
    var instanceIDs = Set<UUID>()
    for instance in config.instances {
        guard instanceIDs.insert(instance.id).inserted else { return false }
        if let button = instance.mouseButton,
           !mouseOwners.insert(button).inserted {
            return false
        }
        if instance.hotkey.enabled {
            guard instance.hotkey.combo.hasAtLeastOneModifier,
                  !isReservedKeyboardCommandTab(instance.hotkey.combo),
                  !reservedSystemShortcuts.contains(instance.hotkey.combo.signature),
                  hotkeyOwners.insert(instance.hotkey.combo.signature).inserted else {
                return false
            }
        }
    }
    return true
}

func activeAppProfileInstance(
    for slot: ShortcutSlot,
    in config: KlikProConfig,
    activeInstanceIDs: Set<UUID>,
    specialFeatureActive: Bool
) -> AppProfileInstance? {
    // App Profile mouse assignments are a normal mapping action in v2.0. They no
    // longer depend on the retired Special Feature master toggle. The parameter is
    // retained for source compatibility with the v1 hotkey/menu lifecycle.
    _ = specialFeatureActive
    let matches = config.instances.filter {
        activeInstanceIDs.contains($0.id) && $0.mouseButton?.shortcutSlot == slot
    }
    return matches.count == 1 ? matches[0] : nil
}

/// The launchable *managed* instance that owns `slot`, if any. Legacy target mirrors are
/// handled separately by `activeQuickLaunchTarget`; this covers the schema-10+ managed
/// App Profiles whose mouse ownership lives on the instance rather than on the legacy
/// `chatGPTMouseButton` / `claudeMouseButton` fields, so the conflict checker can mirror
/// the runtime's `activeAppProfileInstance` dispatch for them.
func activeManagedAppProfileInstance(
    for slot: ShortcutSlot,
    in config: KlikProConfig,
    activeInstanceIDs: Set<UUID>,
    specialFeatureActive: Bool
) -> AppProfileInstance? {
    guard let instance = activeAppProfileInstance(
        for: slot,
        in: config,
        activeInstanceIDs: activeInstanceIDs,
        specialFeatureActive: specialFeatureActive
    ), instance.launcherKind == .managed else {
        return nil
    }
    return instance
}

/// The App Profile instances the runtime would treat as launchable, computed exactly
/// like the input helper's `activeAppProfileInstanceIDs`: legacy rows defer to their
/// external launcher wrapper, while managed rows defer to `instanceIsLaunchable` (the
/// helper passes `AppProfileRuntime.health(for:) == .ready`). Ambiguous assignments fail
/// closed to an empty set so no phantom launch capability is inferred.
func launchableAppProfileInstanceIDs(
    in config: KlikProConfig,
    legacyTargetIsAvailable: (QuickLaunchTarget) -> Bool = { quickLaunchTargetIsAvailable($0) },
    instanceIsLaunchable: (AppProfileInstance) -> Bool
) -> Set<UUID> {
    guard appProfileAssignmentsAreValid(config) else { return [] }
    return Set(config.instances.compactMap { instance -> UUID? in
        if let target = instance.legacyQuickLaunchTarget {
            return legacyTargetIsAvailable(target) ? instance.id : nil
        }
        return instanceIsLaunchable(instance) ? instance.id : nil
    })
}

/// Upgrades older decoded files in memory. A hand-edited duplicate assignment is kept
/// visible for correction, while `assignedQuickLaunchTarget` makes its runtime overlay
/// fail closed. The on-disk file is not rewritten until the user explicitly saves.
func normalizedQuickLaunchConfig(_ config: KlikProConfig) -> KlikProConfig {
    var normalized = config
    normalized.schemaVersion = 11
    normalized.instances = synchronizedLegacyQuickLaunchInstances(in: normalized)
    return normalized
}

func assignedQuickLaunchTarget(
    for slot: ShortcutSlot,
    in config: KlikProConfig
) -> QuickLaunchTarget? {
    guard quickLaunchMouseAssignmentsAreValid(config) else { return nil }
    return QuickLaunchTarget.allCases.first { target in
        quickLaunchMouseButton(for: target, in: config)?.shortcutSlot == slot
    }
}

func activeQuickLaunchTarget(
    for slot: ShortcutSlot,
    in config: KlikProConfig,
    specialFeatureActive: Bool,
    chatGPTAvailable: Bool,
    claudeAvailable: Bool
) -> QuickLaunchTarget? {
    guard specialFeatureActive,
          let target = assignedQuickLaunchTarget(for: slot, in: config) else {
        return nil
    }
    switch target {
    case .chatGPT: return chatGPTAvailable ? target : nil
    case .claude: return claudeAvailable ? target : nil
    }
}

func baseMapping(for slot: ShortcutSlot, in config: KlikProConfig) -> ShortcutMapping {
    switch slot {
    case .middleButton: return config.middleButton
    case .gestureButton: return config.gestureButton
    case .forwardButton: return config.forwardButton
    case .backButton: return config.backButton
    case .chatGPTHotkey: return config.chatGPTHotkey
    case .claudeHotkey: return config.claudeHotkey
    }
}

/// Returns the runtime/UI mapping after applying a reversible Special Feature overlay.
/// When active and available, the assigned mouse row is forced on and mirrors the
/// launcher's displayed combo. Direct launcher dispatch is selected separately so the
/// keyboard combo never leaks into the frontmost app.
func mapping(
    for slot: ShortcutSlot,
    in config: KlikProConfig,
    specialFeatureActive: Bool = true,
    chatGPTAvailable: Bool = true,
    claudeAvailable: Bool = true
) -> ShortcutMapping {
    guard let target = activeQuickLaunchTarget(
        for: slot,
        in: config,
        specialFeatureActive: specialFeatureActive,
        chatGPTAvailable: chatGPTAvailable,
        claudeAvailable: claudeAvailable
    ) else {
        return baseMapping(for: slot, in: config)
    }
    return ShortcutMapping(
        enabled: true,
        combo: baseMapping(for: target.shortcutSlot, in: config).combo
    )
}

func linkedShortcutCounterpart(
    of slot: ShortcutSlot,
    in config: KlikProConfig,
    specialFeatureActive: Bool = true,
    chatGPTAvailable: Bool = true,
    claudeAvailable: Bool = true
) -> ShortcutSlot? {
    guard quickLaunchMouseAssignmentsAreValid(config) else { return nil }
    if let target = activeQuickLaunchTarget(
        for: slot,
        in: config,
        specialFeatureActive: specialFeatureActive,
        chatGPTAvailable: chatGPTAvailable,
        claudeAvailable: claudeAvailable
    ) {
        return target.shortcutSlot
    }
    return QuickLaunchTarget.allCases.first { target in
        guard target.shortcutSlot == slot,
              let button = quickLaunchMouseButton(for: target, in: config) else {
            return false
        }
        return activeQuickLaunchTarget(
            for: button.shortcutSlot,
            in: config,
            specialFeatureActive: specialFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        ) == target
    }.flatMap { quickLaunchMouseButton(for: $0, in: config)?.shortcutSlot }
}

/// True when this slot's physical mouse button is assigned to an App Profile
/// instance (Open-App mode). The button then launches that profile instead of
/// sending its stored keyboard shortcut, so that shortcut is dormant and must
/// not count as an active shortcut in conflict/duplicate detection. This mirrors
/// how the legacy ChatGPT/Claude quick-launch is already treated as dormant, but
/// covers App Profile instances (which are not QuickLaunchTargets).
func slotOpensAppProfileInstance(_ slot: ShortcutSlot, in config: KlikProConfig) -> Bool {
    guard let button = QuickLaunchMouseButton.allCases.first(where: { $0.shortcutSlot == slot })
    else { return false }
    // Only managed App Profile instances count here. The legacy ChatGPT/Claude
    // mirrors are `.legacyExternal` and are already handled (with Special Feature
    // gating) by activeQuickLaunchTarget; including them would wrongly silence a
    // forward/back shortcut conflict while the Special Feature is off.
    return config.instances.contains {
        $0.mouseButton == button && $0.launcherKind == .managed
    }
}

private let reservedSystemShortcuts: [KeyCombo.Signature] = [
    KeyCombo.Signature(keyCode: UInt16(kVK_Space), command: true, option: false, control: false, shift: false),           // Cmd-Space
    KeyCombo.Signature(keyCode: UInt16(kVK_Tab), command: true, option: false, control: false, shift: false),             // Cmd-Tab
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_Q), command: true, option: false, control: false, shift: false),          // Cmd-Q
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_W), command: true, option: false, control: false, shift: false),          // Cmd-W
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_H), command: true, option: false, control: false, shift: false),          // Cmd-H
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_M), command: true, option: false, control: false, shift: false),          // Cmd-M
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_3), command: true, option: false, control: false, shift: true),           // Cmd-Shift-3
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_4), command: true, option: false, control: false, shift: true),           // Cmd-Shift-4
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_5), command: true, option: false, control: false, shift: true),           // Cmd-Shift-5
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_Q), command: true, option: false, control: true, shift: false),           // Control-Command-Q
    KeyCombo.Signature(keyCode: UInt16(kVK_ANSI_Comma), command: true, option: false, control: false, shift: false),      // Cmd-Comma
    KeyCombo.Signature(keyCode: UInt16(kVK_F20), command: true, option: false, control: false, shift: false),             // Klik PRO Gesture sentinel
]

/// Recomputes all visible shortcut badges together (a change to one slot can affect duplicate
/// status of the others). `candidate` is the in-memory config currently being edited
/// in the UI; `persisted` is the config last loaded from / saved to disk (i.e. what
/// the CURRENTLY RUNNING input helper process, if any, actually has registered).
///
/// Precedence per slot: Duplicate > Reserved ("May Conflict") > Unavailable > OK.
///
/// False-positive mitigation (this is the subtle, important part): if the input
/// helper is running with e.g. today's default Control-Option-Command-G, that combo
/// is ALREADY registered system-wide by our own other process. A live probe of that
/// identical combo from the settings app would then legitimately fail — RegisterEventHotKey
/// enforces combos system-wide regardless of which process/EventHotKeyID holds them —
/// which would incorrectly show "Unavailable" for a shortcut that is in fact working
/// fine. To avoid this, the live probe is SKIPPED (treated as `.ok`) whenever the
/// candidate's combo for a slot is unchanged from that same slot's persisted, enabled
/// combo. The probe only runs for a slot when the user is proposing something new
/// (a changed combo, or newly enabling a previously-disabled slot).
///
/// Known limitation (acceptable for a personal utility, not fixed here): this mitigation
/// is per-slot. If the user disables slot A in the editor while the running input
/// helper still holds slot A's old registration (because Save doesn't restart the
/// helper), and then assigns that same combo to slot B, the live probe for slot B will
/// still see it as claimed and report "Unavailable" until the helper is restarted. This
/// is a rare edge case and does not need to be solved.
func evaluateShortcutConflicts(
    candidate: KlikProConfig,
    persisted: KlikProConfig,
    browserExtensionShortcuts: Set<KeyCombo.Signature> = installedChromeExtensionShortcutSignatures(),
    specialFeatureActive: Bool = true,
    chatGPTAvailable: Bool = true,
    claudeAvailable: Bool = true,
    activeInstanceIDs: Set<UUID> = []
) -> [ShortcutSlot: ShortcutConflictStatus] {
    var result: [ShortcutSlot: ShortcutConflictStatus] = [:]

    // Slots served by a launchable managed App Profile instance are pure launch actions,
    // mirroring the input helper's `.launchInstance` dispatch: the mouse-down opens the
    // managed app and no keyboard combo is ever synthesized. Such a slot therefore cannot
    // conflict with, nor be duplicated by, any keyboard combo — so it resolves to `.ok`
    // and is excluded from the combo-duplicate comparison. Without this, the slot's stored
    // base combo would leak in and manufacture a phantom Duplicate (and two managed rows
    // sharing a placeholder hotkey would falsely duplicate each other). A managed instance
    // that cannot launch is absent from `activeInstanceIDs`, so its slot falls through to
    // its base combo here and any genuine conflict it produces still surfaces.
    let managedLaunchSlots = Set(ShortcutSlot.allCases.filter { slot in
        activeManagedAppProfileInstance(
            for: slot,
            in: candidate,
            activeInstanceIDs: activeInstanceIDs,
            specialFeatureActive: specialFeatureActive
        ) != nil
    })

    for slot in ShortcutSlot.allCases {
        if managedLaunchSlots.contains(slot) { result[slot] = .ok; continue }

        let mine = mapping(
            for: slot,
            in: candidate,
            specialFeatureActive: specialFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        )
        guard mine.enabled else { result[slot] = .ok; continue }

        // A button that opens an App Profile instance is in Open-App mode: its
        // stored shortcut is dormant (the button launches the app, never emits
        // the combo), so it is neither a conflict itself nor a source of one.
        if slotOpensAppProfileInstance(slot, in: candidate) { result[slot] = .ok; continue }

        let intentionalCounterpart = linkedShortcutCounterpart(
            of: slot,
            in: candidate,
            specialFeatureActive: specialFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        )
        let isDuplicate = ShortcutSlot.allCases.contains { other in
            guard other != slot else { return false }
            guard other != intentionalCounterpart else { return false }
            guard !managedLaunchSlots.contains(other) else { return false }
            let otherMapping = mapping(
                for: other,
                in: candidate,
                specialFeatureActive: specialFeatureActive,
                chatGPTAvailable: chatGPTAvailable,
                claudeAvailable: claudeAvailable
            )
            return otherMapping.enabled && otherMapping.combo.signature == mine.combo.signature
        }
        if isDuplicate { result[slot] = .duplicate; continue }

        if isGestureSentinelOutput(mine.combo) {
            result[slot] = .unavailable
            continue
        }

        if (slot == .chatGPTHotkey || slot == .claudeHotkey),
           isReservedKeyboardCommandTab(mine.combo) {
            result[slot] = .unavailable
            continue
        }

        if reservedSystemShortcuts.contains(mine.combo.signature)
            || browserExtensionShortcuts.contains(mine.combo.signature) {
            result[slot] = .mayConflict
            continue
        }

        // The mouse mirror is not another Carbon registration. Its source launcher is
        // probed once below and this row inherits that exact result after the pass.
        if activeQuickLaunchTarget(
            for: slot,
            in: candidate,
            specialFeatureActive: specialFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        ) != nil {
            result[slot] = .ok
            continue
        }

        let previouslyPersisted = mapping(
            for: slot,
            in: persisted,
            specialFeatureActive: specialFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        )
        let unchangedFromOurOwnRunningRegistration =
            previouslyPersisted.enabled && previouslyPersisted.combo.signature == mine.combo.signature
        if unchangedFromOurOwnRunningRegistration { result[slot] = .ok; continue }

        let available = probeHotKeyAvailability(
            keyCode: mine.combo.keyCode,
            carbonModifiers: mine.combo.carbonModifiers
        )
        result[slot] = available ? .ok : .unavailable
    }

    // A linked physical row is one logical shortcut with its launcher source. This
    // also propagates Duplicate when a third active mapping shares the same combo.
    for target in QuickLaunchTarget.allCases {
        guard let button = quickLaunchMouseButton(for: target, in: candidate),
              quickLaunchMouseAssignmentsAreValid(candidate),
              activeQuickLaunchTarget(
                for: button.shortcutSlot,
                in: candidate,
                specialFeatureActive: specialFeatureActive,
                chatGPTAvailable: chatGPTAvailable,
                claudeAvailable: claudeAvailable
              ) == target else { continue }
        result[button.shortcutSlot] = result[target.shortcutSlot] ?? .ok
    }

    return result
}
