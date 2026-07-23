import AppKit
import Carbon
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// NOTE: LaunchAgent identifiers and installer helpers live in KlikProConfig.swift,
// shared with the combined background helper.

// MARK: - ToggleSwitchView

final class ToggleSwitchView: NSView {
    var isOn: Bool {
        didSet {
            setAccessibilityValue(NSNumber(value: isOn))
            needsDisplay = true
        }
    }
    var isEnabled: Bool = true {
        didSet {
            setAccessibilityEnabled(isEnabled)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool, frame: NSRect) {
        self.isOn = isOn
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(NSNumber(value: isOn))
        setAccessibilityEnabled(true)
        setAccessibilityLabel("Toggle")
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { needsDisplay = true }
        return resigned
    }

    private func activate() {
        guard isEnabled else { return }
        isOn.toggle()
        onChange?(isOn)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        activate()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
            activate()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim: CGFloat = isEnabled ? 1 : 0.30
        let pill = bounds.insetBy(dx: 1, dy: 1)
        (isOn ? NSColor.systemGreen : NSColor.tertiaryLabelColor)
            .withAlphaComponent(dim).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        let knobDiameter = pill.height - 6
        let knobX = isOn ? pill.maxX - knobDiameter - 3 : pill.minX + 3
        NSColor.white.withAlphaComponent(dim).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: pill.minY + 3, width: knobDiameter, height: knobDiameter)).fill()
        if isEnabled && window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

// MARK: - CheckboxView (compact box + label, for the thumb-wheel row)

final class CheckboxView: NSView {
    var isOn: Bool { didSet { needsDisplay = true } }
    // Greyed + non-interactive when false (e.g. browser options while Tab Switching is off).
    var isEnabled: Bool = true { didSet { needsDisplay = true } }
    let label: String
    var onChange: ((Bool) -> Void)?

    init(label: String, isOn: Bool, frame: NSRect) {
        self.label = label
        self.isOn = isOn
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        onChange?(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim: CGFloat = isEnabled ? 1.0 : 0.3
        let side: CGFloat = 16
        let box = NSRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        if isOn {
            NSColor.systemGreen.withAlphaComponent(dim).setFill()
            path.fill()
            // checkmark
            let check = NSBezierPath()
            check.move(to: NSPoint(x: box.minX + 4, y: box.midY + 0.5))
            check.line(to: NSPoint(x: box.minX + 7, y: box.maxY - 5))
            check.line(to: NSPoint(x: box.maxX - 3.5, y: box.minY + 4.5))
            NSColor.white.withAlphaComponent(dim).setStroke()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.withAlphaComponent(dim).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary.withAlphaComponent(dim)
        ]
        label.draw(at: NSPoint(x: box.maxX + 6, y: (bounds.height - 15) / 2), withAttributes: attrs)
    }
}

// MARK: - ConflictBadgeView

final class ConflictBadgeView: NSView {
    var status: ShortcutConflictStatus { didSet { needsDisplay = true } }

    init(status: ShortcutConflictStatus, frame: NSRect) {
        self.status = status
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch status {
        case .ok: color = .systemGreen
        case .duplicate: color = .systemRed
        case .mayConflict: color = .systemOrange
        case .unavailable: color = .systemGray
        }
        // All four statuses are a tinted pill for a consistent column. OK additionally
        // gets a green checkmark before the label so it reads as "good" at a glance.
        // The pill hugs its content (checkmark + label) rather than filling the full
        // slot, so "OK" stays small and only "May Conflict" grows — left-aligned so the
        // status column lines up.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: color
        ]
        let text = status.badgeText as NSString
        let textSize = text.size(withAttributes: attrs)
        let hpad: CGFloat = 9
        let checkW: CGFloat = 11, gap: CGFloat = 4
        let contentW = (status == .ok) ? (checkW + gap + textSize.width) : textSize.width
        let ph = bounds.height
        let pill = NSRect(x: 0, y: 0, width: contentW + hpad * 2, height: ph)
        color.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: pill, xRadius: ph / 2, yRadius: ph / 2).fill()

        let midY = pill.midY
        if status == .ok {
            let cx = hpad
            let check = NSBezierPath()
            check.move(to: NSPoint(x: cx, y: midY + checkW * 0.04))
            check.line(to: NSPoint(x: cx + checkW * 0.36, y: midY - checkW * 0.30))
            check.line(to: NSPoint(x: cx + checkW, y: midY + checkW * 0.40))
            color.setStroke()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
            text.draw(at: NSPoint(x: cx + checkW + gap, y: midY - textSize.height / 2), withAttributes: attrs)
        } else {
            text.draw(at: NSPoint(x: hpad, y: midY - textSize.height / 2), withAttributes: attrs)
        }
    }
}

// MARK: - ShortcutRecorderView

final class ShortcutRecorderView: NSView {
    var combo: KeyCombo {
        didSet {
            setAccessibilityValue(combo.displayString)
            needsDisplay = true
        }
    }
    private var displayOverride: String?
    private let displayOverrideResolver: ((KeyCombo) -> String?)?
    var onChange: ((KeyCombo) -> Void)?

    private var isRecording = false
    private var localMonitor: Any?
    private var blinkTimer: Timer?
    private var caretVisible = true
    private static weak var activeRecorder: ShortcutRecorderView?
    var isEnabled: Bool = true {
        didSet {
            setAccessibilityEnabled(isEnabled)
            if !isEnabled {
                cancelRecording()
                if window?.firstResponder === self {
                    window?.makeFirstResponder(nil)
                }
            }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    init(
        combo: KeyCombo,
        displayOverride: String? = nil,
        displayOverrideResolver: ((KeyCombo) -> String?)? = nil,
        frame: NSRect
    ) {
        self.combo = combo
        self.displayOverride = displayOverride
        self.displayOverrideResolver = displayOverrideResolver
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Shortcut recorder")
        setAccessibilityValue(displayOverride ?? combo.displayString)
        setAccessibilityEnabled(true)
        setAccessibilityHelp("Press to record a shortcut, then type a key with at least one modifier.")
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { needsDisplay = true }
        return resigned
    }

    deinit {
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        blinkTimer?.invalidate()
        if ShortcutRecorderView.activeRecorder === self { ShortcutRecorderView.activeRecorder = nil }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        if isRecording { cancelRecording() } else { beginRecording() }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if !isRecording,
           event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
            beginRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        if isRecording { cancelRecording() } else { beginRecording() }
        return true
    }

    private func beginRecording() {
        guard isEnabled else { return }
        ShortcutRecorderView.activeRecorder?.cancelRecording()
        ShortcutRecorderView.activeRecorder = self
        isRecording = true
        caretVisible = true
        needsDisplay = true
        // Blinking caret while recording, in place of any placeholder text.
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.caretVisible.toggle()
            self.needsDisplay = true
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleRecordingEvent(event)
        }
    }

    /// Returns the event to let it keep propagating, or nil to swallow it. Swallowing
    /// keyDown here (returning nil) is what prevents standard menu key equivalents
    /// (Cmd-Q, Cmd-W, Cmd-Comma, etc.) from firing while a recorder is active — those
    /// are normally dispatched by NSApplication/NSMenu BEFORE the responder chain's
    /// keyDown(_:), so overriding keyDown alone would not intercept them.
    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        // A click anywhere outside this recorder cancels recording and tears down the
        // monitor, then lets the click through — otherwise clicking a footer button or
        // empty chrome without pressing a key would leave the monitor installed,
        // swallowing all subsequent keyboard input (including Cmd-Q/Cmd-W) app-wide.
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let pointInView = convert(event.locationInWindow, from: nil)
            if !bounds.contains(pointInView) {
                cancelRecording()
            }
            return event
        }
        if event.type == .flagsChanged {
            needsDisplay = true   // live modifier preview while held, still swallowed
            return nil
        }
        guard event.type == .keyDown else { return event }

        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            return nil
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else {
            // Bare key with no modifier: reject, stay in recording mode, beep.
            NSSound.beep()
            return nil
        }

        let displayChar = KeyCombo.baseLabel(forKeyCode: event.keyCode)
            ?? event.charactersIgnoringModifiers.flatMap { $0.isEmpty ? nil : $0.uppercased() }
            ?? "#\(event.keyCode)"

        let newCombo = KeyCombo(
            keyCode: event.keyCode,
            keyDisplay: displayChar,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        combo = newCombo
        displayOverride = displayOverrideResolver?(newCombo)
        setAccessibilityValue(displayOverride ?? newCombo.displayString)
        endRecording()
        onChange?(newCombo)
        return nil
    }

    private func cancelRecording() { endRecording() }

    func setCombo(_ newCombo: KeyCombo) {
        cancelRecording()
        combo = newCombo
        displayOverride = displayOverrideResolver?(newCombo)
        setAccessibilityValue(displayOverride ?? newCombo.displayString)
    }

    private func endRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        blinkTimer?.invalidate()
        blinkTimer = nil
        if ShortcutRecorderView.activeRecorder === self { ShortcutRecorderView.activeRecorder = nil }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // While recording, show only a blinking caret (no placeholder text). Otherwise
        // show the current combo.
        let text = isRecording ? (caretVisible ? "|" : "") : (displayOverride ?? combo.displayString)
        let dim: CGFloat = isEnabled ? 1 : 0.35
        let borderColor = isRecording
            ? NSColor.controlAccentColor
            : NSColor.controlAccentColor.withAlphaComponent(0.22 * dim)
        NSColor.controlAccentColor.withAlphaComponent((isRecording ? 0.16 : 0.10) * dim).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        borderColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()
        if isEnabled && window?.firstResponder === self && !isRecording {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
            focus.lineWidth = 2
            focus.stroke()
        }
        // Proportional font + letter-spacing so the ⌘⌥⌃⇧ glyphs breathe (monospaced
        // crammed them together), vertically centered with comfortable left padding.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: displayOverride == nil ? 14 : 13, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary.withAlphaComponent(dim),
            .kern: displayOverride == nil ? 2.5 : 0.4
        ]
        let ts = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: bounds.minX + 12, y: bounds.midY - ts.height / 2), withAttributes: attrs)
    }
}

// MARK: - Row containers

/// Compact reset affordance placed directly after each shortcut field.
final class ShortcutResetButton: NSButton {
    var onPress: (() -> Void)?

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        self.title = ""
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        image = NSImage(
            systemSymbolName: "arrow.counterclockwise",
            accessibilityDescription: "Reset to default"
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        contentTintColor = .appTextSecondary
        toolTip = "Reset to default shortcut"
        setAccessibilityLabel("Reset \(title) shortcut to default")
        setAccessibilityHelp("Restore the original Klik PRO key combination.")
        target = self
        action = #selector(pressed)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    @objc private func pressed() {
        onPress?()
    }
}

/// Native footer action used while the user temporarily reviews Mappings from the
/// welcome sheet. Keeping this as an NSButton provides keyboard/VoiceOver behavior
/// without adding another layer-backed custom control to deterministic previews.
final class FooterActionButton: NSButton {
    var onPress: (() -> Void)?

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        self.title = title
        bezelStyle = .rounded
        controlSize = .regular
        font = .systemFont(ofSize: 12, weight: .semibold)
        contentTintColor = .controlAccentColor
        target = self
        action = #selector(pressed)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pressed() {
        onPress?()
    }
}

/// Primary footer button with a branded pointer-hover treatment. It remains a native
/// NSButton for keyboard and VoiceOver activation: blue at rest, Klik PRO green with
/// a black outline while hovered.
final class PrimaryHoverButton: NSButton {
    var onPress: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        self.title = title
        isBordered = false
        font = .boldSystemFont(ofSize: 14)
        target = self
        action = #selector(pressed)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea = hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    func showHoverPreview() {
        guard previewRenderingIsActive else { return }
        setHovered(true)
    }

    @objc private func pressed() {
        onPress?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let fill = !isEnabled
            ? accent.withAlphaComponent(0.42)
            : (isHovered ? KlikProBrand.green : accent)
        fill.setFill()
        let pill = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: (bounds.height - 2) / 2,
            yRadius: (bounds.height - 2) / 2
        )
        pill.fill()

        if isHovered && isEnabled {
            NSColor.black.setStroke()
            pill.lineWidth = 1.5
            pill.stroke()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.78),
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

private enum ShortcutRowLayout {
    static let actionX: CGFloat = 158
    static let actionWidth: CGFloat = 156
    static let recorderX: CGFloat = 330
    static let recorderWidth: CGFloat = 104
    static let resetX: CGFloat = 438
    static let resetWidth: CGFloat = 20
    static let badgeX: CGFloat = 464
    static let badgeWidth: CGFloat = 90
    static let linkedFieldWidth: CGFloat = 360
    static let linkedLockSize: CGFloat = 12
    static let linkedLockGap: CGFloat = 6
    static let dormantLinkIconSize: CGFloat = 10
    static let dormantLinkGap: CGFloat = 6
    static var dormantLinkX: CGFloat {
        recorderX - dormantLinkGap - dormantLinkIconSize
    }
}

final class RecordableShortcutRowView: NSView {
    let titleLabel: String
    let toggle: ToggleSwitchView
    let recorder: ShortcutRecorderView
    let resetButton: ShortcutResetButton
    let badge: ConflictBadgeView
    let actionPicker = NSPopUpButton(frame: .zero)
    let appPicker = NSPopUpButton(frame: .zero)
    var onToggleChange: ((Bool) -> Void)?
    var onComboChange: ((KeyCombo) -> Void)?
    var onOpenAppChange: ((LaunchAssignmentTarget?) -> Void)?
    private let defaultCombo: KeyCombo
    private var linkedTarget: QuickLaunchTarget?
    private var linkedCombo: KeyCombo?
    private var linkedFeatureActive = false
    private var linkedTargetReadiness: QuickLaunchTargetReadiness = .appNotInstalled
    private var appTargets: [(target: LaunchAssignmentTarget, label: String)] = []
    private var assignedAppTarget: LaunchAssignmentTarget?
    private var updatingActionControls = false
    private var usesCompactTwoLineLayout = false

    init(
        title: String,
        mapping: ShortcutMapping,
        defaultCombo: KeyCombo,
        status: ShortcutConflictStatus,
        displayOverride: String? = nil,
        displayOverrideResolver: ((KeyCombo) -> String?)? = nil,
        frame: NSRect
    ) {
        self.titleLabel = title
        self.defaultCombo = defaultCombo
        // Compact layout so a full row (toggle + title + recorder + badge) fits in a
        // half-width (~400pt) column.
        self.toggle = ToggleSwitchView(isOn: mapping.enabled, frame: NSRect(x: 0, y: (frame.height - 22) / 2, width: 40, height: 22))
        self.recorder = ShortcutRecorderView(
            combo: mapping.combo,
            displayOverride: displayOverride,
            displayOverrideResolver: displayOverrideResolver,
            frame: NSRect(
                x: ShortcutRowLayout.recorderX,
                y: (frame.height - 32) / 2,
                width: ShortcutRowLayout.recorderWidth,
                height: 32
            )
        )
        self.resetButton = ShortcutResetButton(
            title: title,
            frame: NSRect(
                x: ShortcutRowLayout.resetX,
                y: (frame.height - 28) / 2,
                width: ShortcutRowLayout.resetWidth,
                height: 28
            )
        )
        self.badge = ConflictBadgeView(
            status: status,
            frame: NSRect(
                x: ShortcutRowLayout.badgeX,
                y: (frame.height - 22) / 2,
                width: ShortcutRowLayout.badgeWidth,
                height: 22
            )
        )
        super.init(frame: frame)
        actionPicker.frame = NSRect(
            x: ShortcutRowLayout.actionX, y: (frame.height - 30) / 2,
            width: ShortcutRowLayout.actionWidth, height: 30
        )
        actionPicker.addItems(withTitles: ["Shortcut", "Open App"])
        // A keyboard glyph stands in for "Keyboard" so the option reads "⌨ Shortcut"
        // in full instead of truncating, letting the picker be narrower.
        actionPicker.item(at: 0)?.image = NSImage(
            systemSymbolName: "keyboard", accessibilityDescription: "Keyboard shortcut"
        )
        // Pair a "launch app" glyph with the keyboard glyph so both options read
        // as icon + label rather than one icon and one bare word.
        actionPicker.item(at: 1)?.image = NSImage(
            systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Open app"
        )
        actionPicker.target = self
        actionPicker.action = #selector(actionModeChanged)
        appPicker.frame = NSRect(
            x: ShortcutRowLayout.recorderX, y: (frame.height - 30) / 2,
            width: 260, height: 30
        )
        appPicker.target = self
        appPicker.action = #selector(appTargetChanged)
        appPicker.isHidden = true
        addSubview(toggle); addSubview(actionPicker); addSubview(recorder)
        addSubview(resetButton); addSubview(badge); addSubview(appPicker)
        toggle.setAccessibilityLabel("\(title) enabled")
        recorder.setAccessibilityLabel("\(title) shortcut")
        toggle.onChange = { [weak self] on in self?.onToggleChange?(on) }
        recorder.onChange = { [weak self] combo in self?.onComboChange?(combo) }
        resetButton.onPress = { [weak self] in
            guard let self = self,
                  self.recorder.combo.signature != self.defaultCombo.signature else { return }
            self.recorder.setCombo(self.defaultCombo)
            self.onComboChange?(self.defaultCombo)
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    /// Fits the complete action picker, shortcut/app target, reset, and conflict state
    /// inside the approved half-width Mappings column without removing behavior.
    func applyCompactTwoLineLayout() {
        usesCompactTwoLineLayout = true
        toggle.frame = NSRect(x: 0, y: 6, width: 40, height: 22)
        badge.frame = NSRect(x: 273, y: 6, width: 86, height: 22)
        actionPicker.frame = NSRect(x: 48, y: 34, width: 120, height: 30)
        recorder.frame = NSRect(x: 176, y: 33, width: 145, height: 32)
        resetButton.frame = NSRect(x: 329, y: 34, width: 20, height: 28)
        appPicker.frame = NSRect(x: 176, y: 34, width: 173, height: 30)
        needsDisplay = true
    }

    func setOpenAppOptions(
        _ targets: [(target: LaunchAssignmentTarget, label: String)],
        assignedTarget: LaunchAssignmentTarget?
    ) {
        updatingActionControls = true
        appTargets = targets
        assignedAppTarget = assignedTarget
        appPicker.removeAllItems()
        targets.forEach { appPicker.addItem(withTitle: $0.label) }
        if let assignedTarget,
           let index = targets.firstIndex(where: { $0.target == assignedTarget }) {
            actionPicker.selectItem(at: 1)
            appPicker.selectItem(at: index)
            recorder.isHidden = true
            resetButton.isHidden = true
            badge.isHidden = true
            appPicker.isHidden = false
        } else {
            actionPicker.selectItem(at: 0)
            recorder.isHidden = false
            resetButton.isHidden = false
            badge.isHidden = false
            appPicker.isHidden = true
        }
        toggle.isHidden = false
        updatingActionControls = false
        needsDisplay = true
    }

    @objc private func actionModeChanged() {
        guard !updatingActionControls else { return }
        if actionPicker.indexOfSelectedItem == 0 {
            onOpenAppChange?(nil)
        } else if let first = appTargets.first {
            appPicker.selectItem(at: 0)
            onOpenAppChange?(first.target)
        } else {
            NSSound.beep()
            actionPicker.selectItem(at: 0)
        }
    }

    @objc private func appTargetChanged() {
        guard !updatingActionControls,
              appPicker.indexOfSelectedItem >= 0,
              appPicker.indexOfSelectedItem < appTargets.count else { return }
        onOpenAppChange?(appTargets[appPicker.indexOfSelectedItem].target)
    }

    func setLinked(
        to target: QuickLaunchTarget?,
        combo: KeyCombo? = nil,
        specialFeatureActive: Bool = false,
        targetReadiness: QuickLaunchTargetReadiness = .appNotInstalled
    ) {
        guard assignedAppTarget == nil else { return }
        linkedTarget = target
        linkedCombo = combo
        linkedFeatureActive = specialFeatureActive
        linkedTargetReadiness = targetReadiness
        toggle.isHidden = false
        recorder.isHidden = false
        resetButton.isHidden = false
        badge.isHidden = false
        setAccessibilityElement(false)
        if let target = target {
            let state = targetReadiness == .ready
                ? "Special Feature is off."
                : targetReadiness.explanation
            let help = "Normal action is active; assigned to \(target.title) when available and enabled. \(state)"
            toolTip = "\(target.title) assignment dormant — \(state) Normal action is active."
            toggle.setAccessibilityHelp(help)
            recorder.setAccessibilityHelp(help)
        } else {
            toolTip = nil
            toggle.setAccessibilityHelp("Enable or disable \(titleLabel).")
            recorder.setAccessibilityHelp("Record the keyboard shortcut for \(titleLabel).")
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary
        ]
        let titleY = usesCompactTwoLineLayout ? 9 : (bounds.height - 15) / 2
        titleLabel.draw(at: NSPoint(x: 48, y: titleY), withAttributes: attrs)
        guard linkedTarget != nil,
              let link = NSImage(systemSymbolName: "link", accessibilityDescription: nil) else { return }
        let iconSize = ShortcutRowLayout.dormantLinkIconSize
        link.draw(
            in: NSRect(
                x: ShortcutRowLayout.dormantLinkX,
                y: bounds.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: linkedFeatureActive && linkedTargetReadiness == .ready ? 0.72 : 0.42
        )
    }
}

// Like RecordableShortcutRowView but with no enable/disable toggle — the combo is
// always active (its on/off is governed elsewhere, e.g. by the Special Feature master
// toggle). Still editable via the recorder, and still shows a conflict badge.
final class RecorderOnlyRowView: NSView {
    let titleLabel: String
    let recorder: ShortcutRecorderView
    let resetButton: ShortcutResetButton
    let badge: ConflictBadgeView
    var onComboChange: ((KeyCombo) -> Void)?
    private let defaultCombo: KeyCombo
    private var readiness: QuickLaunchTargetReadiness = .ready
    private var conflictStatus: ShortcutConflictStatus

    init(
        title: String,
        mapping: ShortcutMapping,
        defaultCombo: KeyCombo,
        status: ShortcutConflictStatus,
        frame: NSRect
    ) {
        self.titleLabel = title
        self.defaultCombo = defaultCombo
        self.conflictStatus = status
        // Same recorder/badge x-positions as RecordableShortcutRowView so rows line up
        // in the same column; the title just starts where the toggle would have been.
        self.recorder = ShortcutRecorderView(
            combo: mapping.combo,
            frame: NSRect(
                x: ShortcutRowLayout.recorderX,
                y: (frame.height - 32) / 2,
                width: ShortcutRowLayout.recorderWidth,
                height: 32
            )
        )
        self.resetButton = ShortcutResetButton(
            title: title,
            frame: NSRect(
                x: ShortcutRowLayout.resetX,
                y: (frame.height - 28) / 2,
                width: ShortcutRowLayout.resetWidth,
                height: 28
            )
        )
        self.badge = ConflictBadgeView(
            status: status,
            frame: NSRect(
                x: ShortcutRowLayout.badgeX,
                y: (frame.height - 22) / 2,
                width: ShortcutRowLayout.badgeWidth,
                height: 22
            )
        )
        super.init(frame: frame)
        addSubview(recorder); addSubview(resetButton); addSubview(badge)
        recorder.setAccessibilityLabel("\(title) shortcut")
        recorder.onChange = { [weak self] combo in self?.onComboChange?(combo) }
        resetButton.onPress = { [weak self] in
            guard let self = self,
                  self.recorder.combo.signature != self.defaultCombo.signature else { return }
            self.recorder.setCombo(self.defaultCombo)
            self.onComboChange?(self.defaultCombo)
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func setReadiness(_ readiness: QuickLaunchTargetReadiness) {
        self.readiness = readiness
        let ready = readiness == .ready
        recorder.isEnabled = ready
        resetButton.isEnabled = ready
        window?.invalidateCursorRects(for: resetButton)
        recorder.toolTip = readiness.explanation
        recorder.setAccessibilityHelp(readiness.explanation)
        badge.status = ready ? conflictStatus : .unavailable
        needsDisplay = true
    }

    func setConflictStatus(_ status: ShortcutConflictStatus) {
        conflictStatus = status
        badge.status = readiness == .ready ? status : .unavailable
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim: CGFloat = readiness == .ready ? 1 : 0.45
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary.withAlphaComponent(dim)
        ]
        titleLabel.draw(at: NSPoint(x: 0, y: (bounds.height - 15) / 2), withAttributes: attrs)
    }
}

/// Native, keyboard-accessible selector for assigning one Special Feature launcher to
/// a physical mouse button. A button already owned by the other launcher is disabled.
final class QuickLaunchButtonPickerView: NSView {
    private let titleLabel: String
    private let target: QuickLaunchTarget
    private var readiness: QuickLaunchTargetReadiness = .ready
    private var conflictingButton: QuickLaunchMouseButton?
    private var conflictingOwner: QuickLaunchTarget?
    let popup: NSPopUpButton
    var onSelectionChange: ((QuickLaunchMouseButton?) -> Void)?

    init(
        title: String,
        target: QuickLaunchTarget,
        selection: QuickLaunchMouseButton?,
        frame: NSRect
    ) {
        titleLabel = title
        self.target = target
        // Leave a deliberate visual gap below the label. The previous 1pt gap made
        // the title and native pop-up control read as though they were touching.
        popup = NSPopUpButton(frame: NSRect(x: 0, y: 20, width: frame.width, height: 26), pullsDown: false)
        super.init(frame: frame)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.addItem(withTitle: "None")
        popup.lastItem?.tag = 0
        for (index, button) in QuickLaunchMouseButton.allCases.enumerated() {
            popup.addItem(withTitle: button.title)
            popup.lastItem?.tag = index + 1
        }
        popup.target = self
        popup.action = #selector(selectionDidChange)
        popup.setAccessibilityLabel("\(target.title) mouse button")
        popup.setAccessibilityHelp("Choose which mouse button opens \(target.title).")
        addSubview(popup)
        setSelection(selection)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    var selection: QuickLaunchMouseButton? {
        let tag = popup.selectedTag()
        guard tag > 0 else { return nil }
        return QuickLaunchMouseButton.allCases[tag - 1]
    }

    func setSelection(_ selection: QuickLaunchMouseButton?) {
        let tag = selection.flatMap { QuickLaunchMouseButton.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        popup.selectItem(withTag: tag)
        refreshAvailability()
    }

    func setReadiness(_ readiness: QuickLaunchTargetReadiness) {
        self.readiness = readiness
        refreshAvailability()
        needsDisplay = true
    }

    func setUnavailable(_ button: QuickLaunchMouseButton?, owner: QuickLaunchTarget) {
        conflictingButton = button
        conflictingOwner = owner
        refreshAvailability()
    }

    private func refreshAvailability() {
        let currentSelection = selection
        let ready = readiness == .ready
        let repairOnly = !ready && currentSelection != nil
        let help: String
        if repairOnly {
            help = "\(readiness.explanation) Choose None to clear this assignment."
        } else if ready {
            help = "Choose which mouse button opens \(target.title)."
        } else {
            help = readiness.explanation
        }

        popup.isEnabled = quickLaunchMousePickerIsEnabled(
            readiness: readiness,
            selection: currentSelection
        )
        popup.toolTip = help
        popup.setAccessibilityHelp(help)
        popup.setAccessibilityLabel(
            ready
                ? "\(target.title) mouse button"
                : "\(target.title) mouse button, \(readiness.shortLabel ?? "unavailable")"
        )

        let noneItem = popup.itemArray.first { $0.tag == 0 }
        noneItem?.isEnabled = true
        noneItem?.toolTip = repairOnly ? "Clear this assignment" : nil
        for item in popup.itemArray where item.tag > 0 {
            let value = QuickLaunchMouseButton.allCases[item.tag - 1]
            if !ready {
                item.isEnabled = value == currentSelection
                item.toolTip = value == currentSelection
                    ? "Current assignment; choose None to clear it"
                    : readiness.explanation
                continue
            }
            let conflicts = value == conflictingButton && value != currentSelection
            item.isEnabled = !conflicts
            item.toolTip = conflicts
                ? "Already assigned to \(conflictingOwner?.title ?? "the other launcher")"
                : nil
        }
    }

    @objc private func selectionDidChange() {
        onSelectionChange?(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        let status = readiness.shortLabel
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let statusSize = status.map {
            ($0 as NSString).size(withAttributes: statusAttrs)
        } ?? .zero
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: status == nil ? 11.5 : 9.5, weight: .semibold),
            .foregroundColor: NSColor.appTextPrimary.withAlphaComponent(
                readiness == .ready ? 1 : 0.58
            ),
            .paragraphStyle: titleStyle
        ]
        let reservedStatusWidth = status == nil ? 0 : statusSize.width + 7
        (titleLabel as NSString).draw(
            in: NSRect(x: 0, y: 0, width: bounds.width - reservedStatusWidth, height: 14),
            withAttributes: titleAttrs
        )
        guard let status = status else { return }
        (status as NSString).draw(
            at: NSPoint(x: bounds.maxX - statusSize.width, y: 1),
            withAttributes: statusAttrs
        )
    }
}

// MARK: - InfoLinkView + Special Feature details popup

/// A small link-styled, clickable label. Clicking it opens a modal popup that
/// explains the Special Feature in full (what it is, settings, restrictions, why it
/// exists, and a use-case scenario).
final class InfoLinkView: NSView {
    private let text = "What is this? Requirements & use cases ›"

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        SpecialFeatureInfo.showPopup()
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        (text as NSString).draw(at: NSPoint(x: 0, y: (bounds.height - 14) / 2), withAttributes: attrs)
    }
}

// Renders the GitHub "Invertocat" mark from its official path (nominative use — links to
// the project's repo). Drawn at runtime, not bundled as an asset file. GitHub and Ko-fi
// are trademarks of their respective owners — see NOTICE.md.
enum BrandMarks {
    private static let githubMarkD = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"

    static func github(size: CGFloat, color: NSColor) -> NSImage {
        let path = parseSVGPath(githubMarkD)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let t = NSAffineTransform()
            t.translateX(by: 0, yBy: size)
            t.scaleX(by: size / 24, yBy: -size / 24)   // 24×24 viewBox; flip y (SVG is y-down)
            t.concat()
            color.setFill()
            path.fill()
            return true
        }
    }
}

// Minimal SVG path parser — supports M/m L/l C/c Z/z, enough for the marks used here.
private func parseSVGPath(_ d: String) -> NSBezierPath {
    let path = NSBezierPath()
    let chars = Array(d); var i = 0; var cur = NSPoint.zero; var cmd: Character = " "
    func skipSep() { while i < chars.count, chars[i] == " " || chars[i] == "," { i += 1 } }
    func num() -> CGFloat {
        skipSep(); var s = ""
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
        var dot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c); i += 1 }
            else if c == "." && !dot { dot = true; s.append(c); i += 1 }
            else { break }
        }
        return CGFloat(Double(s) ?? 0)
    }
    while i < chars.count {
        skipSep(); guard i < chars.count else { break }
        if chars[i].isLetter { cmd = chars[i]; i += 1; skipSep() }
        switch cmd {
        case "M", "m":
            let x = num(), y = num()
            cur = cmd == "M" ? NSPoint(x: x, y: y) : NSPoint(x: cur.x + x, y: cur.y + y)
            path.move(to: cur); cmd = cmd == "M" ? "L" : "l"
        case "L", "l":
            let x = num(), y = num()
            cur = cmd == "L" ? NSPoint(x: x, y: y) : NSPoint(x: cur.x + x, y: cur.y + y)
            path.line(to: cur)
        case "C", "c":
            let a = num(), b = num(), c = num(), dd = num(), e = num(), f = num()
            let c1: NSPoint, c2: NSPoint, end: NSPoint
            if cmd == "C" { c1 = NSPoint(x: a, y: b); c2 = NSPoint(x: c, y: dd); end = NSPoint(x: e, y: f) }
            else { c1 = NSPoint(x: cur.x + a, y: cur.y + b); c2 = NSPoint(x: cur.x + c, y: cur.y + dd); end = NSPoint(x: cur.x + e, y: cur.y + f) }
            path.curve(to: end, controlPoint1: c1, controlPoint2: c2); cur = end
        case "Z", "z":
            path.close()
        default:
            _ = num()   // unknown param — consume to avoid an infinite loop
        }
    }
    return path
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        guard let img = self.copy() as? NSImage else { return self }
        img.lockFocus(); color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus(); img.isTemplate = false
        return img
    }
}

// A small clickable footer element (optionally with an icon) that opens a URL — used for
// the GitHub repo link and the Ko-fi support button in the bottom-right of the window.
final class URLLinkView: NSView {
    enum Style { case link, pill, outline }
    var title: String {
        didSet {
            setAccessibilityLabel(title)
            needsDisplay = true
        }
    }
    private let url: URL?
    private let style: Style
    private let fill: NSColor
    private let icon: NSImage?
    var onClick: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    private let alignRight: Bool

    init(title: String, urlString: String, style: Style, fill: NSColor = .controlAccentColor,
         icon: NSImage? = nil, alignRight: Bool = true, frame: NSRect) {
        self.title = title; self.url = URL(string: urlString); self.style = style
        self.fill = fill; self.icon = icon; self.alignRight = alignRight
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        if style == .outline {
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerCurve = .continuous
        }
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        if style == .outline {
            layer?.cornerRadius = bounds.height / 2
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea = hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        guard style == .outline else {
            hoverTrackingArea = nil
            return
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard style == .outline else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = hoverBackgroundColor
        CATransaction.commit()
    }

    private var hoverBackgroundColor: CGColor {
        (isHovered
            ? NSColor.appTextPrimary.withAlphaComponent(0.085)
            : NSColor.clear
        ).cgColor
    }

    private func setHovered(_ hovered: Bool) {
        guard style == .outline, isHovered != hovered else { return }
        isHovered = hovered

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        animation.toValue = hoverBackgroundColor
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(animation, forKey: "supportButtonHover")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = hoverBackgroundColor
        CATransaction.commit()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick = onClick {
            onClick()
        } else if let url = url {
            NSWorkspace.shared.open(url)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let textColor: NSColor
        switch style {
        case .pill: textColor = .white
        case .outline: textColor = .appTextPrimary
        case .link: textColor = .appTextSecondary
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: textColor
        ]
        let iconSize: CGFloat = 15, gap: CGFloat = 6
        let textSize = (title as NSString).size(withAttributes: attrs)
        let iconW: CGFloat = icon != nil ? iconSize + gap : 0
        let groupW = iconW + textSize.width
        switch style {
        case .pill:
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        case .outline:
            (isHovered
                ? NSColor.appTextPrimary.withAlphaComponent(0.22)
                : NSColor.separatorColor
            ).setStroke()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            p.lineWidth = 1; p.stroke()
        case .link:
            break
        }
        let centered = style == .pill || style == .outline
        let startX = centered ? (bounds.width - groupW) / 2 : (alignRight ? (bounds.width - groupW) : 0)
        let midY = bounds.height / 2
        if let icon = icon {
            icon.draw(in: NSRect(x: startX, y: midY - iconSize / 2, width: iconSize, height: iconSize),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        (title as NSString).draw(at: NSPoint(x: startX + iconW, y: midY - textSize.height / 2), withAttributes: attrs)
    }
}

// Small icon-only gear button in the footer (after the support links). Runs an action
// closure rather than opening a URL — wired by ToggleView to open the Settings tab.
final class IconActionButton: NSView {
    private let icon: NSImage?
    var onClick: (() -> Void)?

    init(symbolName: String, accessibility: String, frame: NSRect) {
        self.icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)?
            .tinted(.appTextSecondary)
        super.init(frame: frame)
        setAccessibilityLabel(accessibility)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let icon = icon else { return }
        let s: CGFloat = 17
        icon.draw(in: NSRect(x: bounds.midX - s / 2, y: bounds.height / 2 - s / 2, width: s, height: s),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

enum SpecialFeatureInfo {
    static func showPopup() {
        let alert = NSAlert()
        alert.messageText = "Special Feature — ChatGPT / Codex & Claude Quick Launch"
        alert.informativeText = "An optional, opt-in feature. Everything else in Klik PRO works without it."

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false
        let textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textStorage?.setAttributedString(content())
        scroll.documentView = textView

        alert.accessoryView = scroll
        alert.addButton(withTitle: "Close")
        alert.runModal()
    }

    private static func content() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.appTextPrimary
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.appTextPrimary
        ]
        func section(_ header: String, _ body: String) {
            result.append(NSAttributedString(string: header + "\n", attributes: headerAttrs))
            result.append(NSAttributedString(string: body + "\n\n", attributes: bodyAttrs))
        }

        section("What it is",
            "A one-toggle shortcut for opening a dedicated second instance of ChatGPT / Codex "
            + "and/or Claude — from a keyboard hotkey, assigned mouse button, or menu-bar icon — without disturbing the "
            + "window you already have open. It works with both apps or with just one: if only "
            + "ChatGPT / Codex is set up you get its icon and hotkey alone, and the same for Claude.")

        section("The settings",
            "• Master toggle (ON/OFF): available only when the real ChatGPT / Codex or Claude "
            + "desktop app is installed. With neither installed it stays OFF and disabled; a "
            + "leftover launcher wrapper alone does not enable it. ON registers the launch "
            + "hotkey(s) and assigned mouse buttons. Its launcher menu-bar icons can be shown or "
            + "hidden separately in Settings without disabling those shortcuts. OFF releases the hotkeys "
            + "system-wide. Klik PRO's own menu-bar icon is independent and has no hotkey; "
            + "its two green dots report the main input helper's active state and do not follow this toggle.\n"
            + "• ChatGPT / Codex Hotkey & Claude Hotkey: the global keyboard shortcuts "
            + "(defaults ⌃⌥⌘G and ⌃⌥⌘C). They have no separate on/off switch — the master toggle "
            + "governs them — and each stays editable whenever its app and launcher are ready.\n"
            + "• ChatGPT / Codex button & Claude button: optionally link each launcher to Middle, "
            + "Gesture, Forward, or Back. The linked row is enabled and mirrors its launch hotkey "
            + "while ON. OFF, None, or a missing launcher restores the untouched normal button "
            + "mapping. If a side becomes unavailable, its existing dropdown remains available "
            + "only so None can clear the old assignment. One physical button cannot be assigned "
            + "to both launchers.\n"
            + "• The Settings tab can hide all ready launcher icons while keeping the Special "
            + "Feature active. Unavailable sides stay hidden, and there is no per-icon option.")

        section("Restrictions",
            "This is the one part of Klik PRO that is not portable as-is. It requires:\n"
            + "• The ChatGPT / Codex and/or Claude desktop app installed in /Applications.\n"
            + "• Small wrapper \"launcher\" apps present on this machine that open each app under "
            + "its own separate profile. A missing app or launcher disables that side's hotkey "
            + "and new button choices with an exact status; a stale dropdown assignment can still "
            + "be changed to None, and its mouse button keeps its normal action. The master toggle "
            + "itself stays disabled until at least one real app is "
            + "installed.\n"
            + "The launch targets are hardcoded in the source and can be repointed to any app(s) "
            + "you like. Every other Klik PRO control is independent of this launcher setup; "
            + "actual button and wheel support still varies by mouse hardware.")

        section("Why it exists",
            "The user runs two independent profiles of an app side by side — for example a "
            + "personal ChatGPT / Codex signed into one account and a separate work one, or a "
            + "normal Claude and a project-scoped Claude — each using its own user-data directory "
            + "(and a separate Codex home for ChatGPT / Codex). macOS won't open a second instance "
            + "of an already-running app on its own, so a wrapper is needed to spawn or focus the "
            + "second profile. This feature puts that one keystroke or click away.")

        section("Use case",
            "You're coding with your work ChatGPT / Codex instance open and want to ask your "
            + "personal account something — without logging out or losing your work session. Press "
            + "⌃⌥⌘G, click the ChatGPT / Codex menu-bar icon when shown, or press its assigned mouse button, "
            + "and your second ChatGPT / Codex "
            + "profile opens or comes to the front. ⌃⌥⌘C does the same for Claude. You don't need "
            + "both apps — a single-app setup (two instances of just one of them) works too.")

        return result
    }
}

// MARK: - ToggleOnlyRowView (master on/off switch, e.g. the Special Feature toggle)

final class ToggleOnlyRowView: NSView {
    let titleLabel: String
    let detailLabel: String
    let disabledDetailLabel: String?
    let toggle: ToggleSwitchView
    var onToggleChange: ((Bool) -> Void)?
    var isEnabled: Bool = true {
        didSet {
            toggle.isEnabled = isEnabled
            let help = isEnabled
                ? detailLabel
                : (disabledDetailLabel ?? detailLabel)
            toggle.toolTip = help
            toggle.setAccessibilityHelp(help)
            needsDisplay = true
        }
    }

    init(
        title: String,
        detail: String,
        disabledDetail: String? = nil,
        isOn: Bool,
        frame: NSRect
    ) {
        self.titleLabel = title
        self.detailLabel = detail
        self.disabledDetailLabel = disabledDetail
        self.toggle = ToggleSwitchView(isOn: isOn, frame: NSRect(x: 0, y: (frame.height - 22) / 2, width: 44, height: 22))
        super.init(frame: frame)
        addSubview(toggle)
        toggle.setAccessibilityLabel(title)
        toggle.onChange = { [weak self] on in self?.onToggleChange?(on) }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let titleDim: CGFloat = isEnabled ? 1 : 0.38
        // The disabled detail is the action the user must take, so keep it readable
        // even while the title and switch correctly look unavailable.
        let detailDim: CGFloat = isEnabled ? 1 : 0.88
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary.withAlphaComponent(titleDim)
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.appTextSecondary.withAlphaComponent(detailDim)
        ]
        let effectiveDetail = isEnabled
            ? detailLabel
            : (disabledDetailLabel ?? detailLabel)
        titleLabel.draw(at: NSPoint(x: 60, y: (bounds.height - 16) / 2 - 8), withAttributes: titleAttrs)
        effectiveDetail.draw(at: NSPoint(x: 60, y: (bounds.height - 16) / 2 + 10), withAttributes: detailAttrs)
    }
}

// MARK: - Scrollable settings content (device diagram + all mapping rows)

final class SettingsContentView: NSView {
    private let image: NSImage?

    let middleButtonRow: RecordableShortcutRowView
    let gestureButtonRow: RecordableShortcutRowView
    let forwardRow: RecordableShortcutRowView
    let backRow: RecordableShortcutRowView
    // Thumb wheel is a single row of one master switch and four browser options.
    let thumbWheelToggle: ToggleSwitchView
    let chromeCheck: CheckboxView
    let braveCheck: CheckboxView
    let firefoxCheck: CheckboxView
    let safariCheck: CheckboxView
    // Special Feature card: master on/off toggle (applied by the combined helper) plus
    // the two hotkeys it gates. The hotkey rows have no per-row toggle — the master
    // toggle governs them — and each recorder is editable while its launch side is ready.
    let specialFeatureToggleRow: ToggleOnlyRowView
    let chatGPTButtonPicker: QuickLaunchButtonPickerView
    let claudeButtonPicker: QuickLaunchButtonPickerView
    let chatGPTHotkeyRow: RecorderOnlyRowView
    let claudeHotkeyRow: RecorderOnlyRowView
    let infoLink = InfoLinkView(frame: .zero)
    // Bottom-right support row: GitHub plus the three support buttons.
    let githubLink = URLLinkView(title: "GitHub",
                                 urlString: "https://github.com/AminudinMurad/klik-pro",
                                 style: .outline,
                                 icon: BrandMarks.github(size: 15, color: .appTextSecondary),
                                 alignRight: false, frame: .zero)
    let sponsorsLink = URLLinkView(title: "GitHub Sponsors",
                                 urlString: "https://github.com/sponsors/aminudinmurad",
                                 style: .outline,
                                 icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?.tinted(.systemPink),
                                 alignRight: false, frame: .zero)
    let kofiButton = URLLinkView(title: "Ko-fi",
                                 urlString: "https://ko-fi.com/aminudinmurad",
                                 style: .outline,
                                 icon: NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                                     .tinted(NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.36, alpha: 1)),
                                 alignRight: false, frame: .zero)
    let paypalLink = URLLinkView(title: "PayPal",
                                 urlString: "https://www.paypal.com/paypalme/aminudinmurad",
                                 style: .outline,
                                 icon: NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: nil)?
                                     .tinted(NSColor(calibratedRed: 0, green: 0.44, blue: 0.73, alpha: 1)),
                                 alignRight: false, frame: .zero)
    let settingsButton = IconActionButton(
        symbolName: "gearshape.fill",
        accessibility: "Open Settings",
        frame: .zero
    )
    let mappingProfilesView: MappingAppProfilesView
    // App icons shown in the Special Feature card, loaded at runtime from the user's
    // installed apps (never bundled — avoids shipping third-party logos). The preview
    // process uses generated letter tiles so fixtures do not depend on the host Mac.
    private var chatGPTIcon: NSImage?
    private var claudeIcon: NSImage?
    var specialFeatureOn: Bool { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    // Two-column, single-page layout (no scrolling). Each of the 2 config groups sits in
    // its own rounded card. Cards are 420pt wide with 18pt inner padding; rows are inset
    // to the padded content box.
    static let leftCardX: CGFloat = 0
    // Asymmetric columns: the left mouse-shortcut card is trimmed to hug its
    // content (the Safari thumb-wheel checkbox ends at x≈399) so the right
    // app-list card can be wider and hold longer profile names. 16pt gap,
    // total width stays 872 (0..420, gap, 436..872).
    static let rightCardX: CGFloat = 436
    static let cardW: CGFloat = 420            // left column width
    static let rightCardW: CGFloat = 436       // right (app list) column width
    static let pad: CGFloat = 18
    static var innerLeftX: CGFloat { leftCardX + pad }      // 18
    static var innerRightX: CGFloat { rightCardX + pad }    // 518
    static var innerW: CGFloat { cardW - pad * 2 }          // 448

    // Mappings starts with a full-width device guide, then switches to the
    // two-column controls/profile layout underneath.
    static let deviceCard         = NSRect(x: 0, y: 0, width: rightCardX + rightCardW, height: 214)
    static let recordableCard     = NSRect(x: leftCardX, y: 232, width: cardW, height: 370)
    static let thumbWheelCard     = NSRect(x: leftCardX, y: 618, width: cardW, height: 84)
    static let specialFeatureCard = NSRect(x: rightCardX, y: 232, width: rightCardW, height: 470)

    private static func previewAppIcon(for target: QuickLaunchTarget) -> NSImage {
        let label = target == .chatGPT ? "G" : "C"
        let background = target == .chatGPT
            ? NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.34, alpha: 1)
            : NSColor(calibratedRed: 0.78, green: 0.37, blue: 0.20, alpha: 1)
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
            return true
        }
    }

    private static func installedAppIcon(_ target: QuickLaunchTarget) -> NSImage? {
        guard let applicationURL = quickLaunchTargetApplicationURL(target) else { return nil }
        let useInstalledPreviewIcon = ProcessInfo.processInfo.environment[
            "KLIK_PRO_PREVIEW_USE_INSTALLED_APP_ICONS"
        ] == "1"
        if previewRenderingIsActive && !useInstalledPreviewIcon {
            return previewAppIcon(for: target)
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    init(
        config: KlikProConfig,
        statuses: [ShortcutSlot: ShortcutConflictStatus],
        specialFeatureOn: Bool,
        specialFeatureAvailable: Bool,
        width: CGFloat
    ) {
        image = Bundle.main.url(forResource: "device-reference", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        chatGPTIcon = Self.installedAppIcon(.chatGPT)
        claudeIcon = Self.installedAppIcon(.claude)
        self.specialFeatureOn = specialFeatureAvailable && specialFeatureOn

        let ix = SettingsContentView.innerLeftX
        let rxi = SettingsContentView.innerRightX
        let iw = SettingsContentView.innerW
        let mappingW = iw

        // LEFT card — recordable mouse controls. Gesture is device-isolated through an
        // MX Master 3-only F20 sentinel, so keyboard Command-Tab remains native for
        // normal app switching. Four rows are spread evenly down the card.
        middleButtonRow = RecordableShortcutRowView(
            title: "Middle Button",
            mapping: config.middleButton,
            defaultCombo: KlikProConfig.default.middleButton.combo,
            status: statuses[.middleButton] ?? .ok,
            frame: NSRect(x: ix, y: 272, width: mappingW, height: 66)
        )
        gestureButtonRow = RecordableShortcutRowView(
            title: "Gesture Button",
            mapping: config.gestureButton,
            defaultCombo: KlikProConfig.default.gestureButton.combo,
            status: statuses[.gestureButton] ?? .ok,
            frame: NSRect(x: ix, y: 356, width: mappingW, height: 66)
        )
        let forwardDisplay = browserHistoryDisplayOverride(
            slot: .forwardButton,
            combo: config.forwardButton.combo
        )
        let backDisplay = browserHistoryDisplayOverride(
            slot: .backButton,
            combo: config.backButton.combo
        )
        forwardRow = RecordableShortcutRowView(
            title: "Forward Button", mapping: config.forwardButton,
            defaultCombo: KlikProConfig.default.forwardButton.combo,
            status: statuses[.forwardButton] ?? .ok, displayOverride: forwardDisplay,
            displayOverrideResolver: { combo in
                browserHistoryDisplayOverride(slot: .forwardButton, combo: combo)
            },
            frame: NSRect(x: ix, y: 440, width: mappingW, height: 66)
        )
        backRow = RecordableShortcutRowView(
            title: "Back Button", mapping: config.backButton,
            defaultCombo: KlikProConfig.default.backButton.combo,
            status: statuses[.backButton] ?? .ok, displayOverride: backDisplay,
            displayOverrideResolver: { combo in
                browserHistoryDisplayOverride(slot: .backButton, combo: combo)
            },
            frame: NSRect(x: ix, y: 524, width: mappingW, height: 66)
        )
        [middleButtonRow, gestureButtonRow, forwardRow, backRow].forEach {
            $0.applyCompactTwoLineLayout()
        }

        // LEFT card — thumb-wheel checkboxes, all in one row below mouse shortcuts.
        thumbWheelToggle = ToggleSwitchView(isOn: config.thumbWheel.enabled, frame: NSRect(x: ix, y: 663, width: 44, height: 22))
        thumbWheelToggle.setAccessibilityLabel("Tab Switching")
        chromeCheck = CheckboxView(label: "Chrome", isOn: config.thumbWheel.chromeEnabled, frame: NSRect(x: ix + 102, y: 660, width: 65, height: 28))
        braveCheck = CheckboxView(label: "Brave", isOn: config.thumbWheel.braveEnabled, frame: NSRect(x: ix + 179, y: 660, width: 57, height: 28))
        firefoxCheck = CheckboxView(label: "Firefox", isOn: config.thumbWheel.firefoxEnabled, frame: NSRect(x: ix + 248, y: 660, width: 63, height: 28))
        safariCheck = CheckboxView(label: "Safari", isOn: config.thumbWheel.safariEnabled, frame: NSRect(x: ix + 323, y: 660, width: 58, height: 28))
        // Browser options are gated by the master "Tab Switching" toggle — greyed until it's on.
        let tabSwitchingOn = config.thumbWheel.enabled
        chromeCheck.isEnabled = tabSwitchingOn
        braveCheck.isEnabled = tabSwitchingOn
        firefoxCheck.isEnabled = tabSwitchingOn
        safariCheck.isEnabled = tabSwitchingOn

        // RIGHT card — each launcher owns one clear column for its mouse-button
        // selector, followed by full-width hotkey rows below.
        specialFeatureToggleRow = ToggleOnlyRowView(
            title: "ChatGPT / Codex & Claude Quick Launch",
            detail: "Enables menu icons, hotkeys, and assigned mouse buttons",
            disabledDetail: "Install ChatGPT or Claude to enable",
            isOn: specialFeatureAvailable && specialFeatureOn,
            frame: NSRect(x: rxi, y: 278, width: iw, height: 44)
        )
        let pickerGap: CGFloat = 24
        let pickerWidth = (iw - pickerGap) / 2
        chatGPTButtonPicker = QuickLaunchButtonPickerView(
            title: "ChatGPT / Codex button",
            target: .chatGPT,
            selection: config.chatGPTMouseButton,
            frame: NSRect(x: rxi, y: 330, width: pickerWidth, height: 46)
        )
        claudeButtonPicker = QuickLaunchButtonPickerView(
            title: "Claude button",
            target: .claude,
            selection: config.claudeMouseButton,
            frame: NSRect(x: rxi + pickerWidth + pickerGap, y: 330, width: pickerWidth, height: 46)
        )
        // v1.3 moves original-app mouse assignment into the same Assign Button
        // flow as App Profiles. Keep these objects for source/config compatibility,
        // but remove the duplicate picker UI from the Special Feature card.
        chatGPTButtonPicker.isHidden = true
        claudeButtonPicker.isHidden = true
        chatGPTHotkeyRow = RecorderOnlyRowView(
            title: "ChatGPT / Codex Hotkey",
            mapping: config.chatGPTHotkey,
            defaultCombo: KlikProConfig.default.chatGPTHotkey.combo,
            status: statuses[.chatGPTHotkey] ?? .ok,
            frame: NSRect(x: rxi, y: 385, width: iw, height: 36)
        )
        claudeHotkeyRow = RecorderOnlyRowView(
            title: "Claude Hotkey",
            mapping: config.claudeHotkey,
            defaultCombo: KlikProConfig.default.claudeHotkey.combo,
            status: statuses[.claudeHotkey] ?? .ok,
            frame: NSRect(x: rxi, y: 429, width: iw, height: 36)
        )
        infoLink.frame = NSRect(x: rxi, y: 477, width: iw, height: 18)
        // Four support links, justified across the right column's bottom area. Each
        // badge is sized to its own content (icon + gap + label + padding) so the outline
        // never crops the text, and the leftover space is shared as equal gaps — this
        // avoids the old fixed-width cramping where long labels ("GitHub Sponsors")
        // overflowed their pill. Measured at runtime so it stays correct if labels change.
        let footerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let footerIconSpan: CGFloat = 15 + 6   // iconSize + gap, matches URLLinkView.draw
        func footerContentW(_ title: String) -> CGFloat {
            (title as NSString).size(withAttributes: [.font: footerFont]).width + footerIconSpan
        }
        let footerLinks = [githubLink, sponsorsLink, kofiButton, paypalLink]
        let footerTitles = ["GitHub", "GitHub Sponsors", "Ko-fi", "PayPal"]
        let footerContent = footerTitles.map(footerContentW)
        let footerTrackX = SettingsContentView.rightCardX + 6
        let settingsButtonW: CGFloat = 32
        let settingsButtonGap: CGFloat = 8
        let fullTrackW = SettingsContentView.cardW - 12 - settingsButtonW - settingsButtonGap
        // Fit: badgeWidth = content + 2*innerPad; 4 badges + 3 gaps span the track.
        // Prefer 10pt inner padding; if that overflows, shrink padding down to a floor.
        var footerPad: CGFloat = 10
        var footerGap = (fullTrackW - (footerContent.reduce(0, +) + footerPad * 2 * 4)) / 3
        if footerGap < 7 {
            footerGap = 7
            footerPad = max(3, (fullTrackW - footerContent.reduce(0, +) - footerGap * 3) / 8)
        }
        var footerX = footerTrackX
        for (i, link) in footerLinks.enumerated() {
            let w = footerContent[i] + footerPad * 2
            link.frame = NSRect(x: footerX, y: 528, width: w, height: 32)
            footerX += w + footerGap
        }
        settingsButton.frame = NSRect(
            x: footerTrackX + fullTrackW + settingsButtonGap,
            y: 528,
            width: settingsButtonW,
            height: 32
        )

        mappingProfilesView = MappingAppProfilesView(
            instances: config.instances,
            frame: SettingsContentView.specialFeatureCard
        )

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 702))

        [middleButtonRow, gestureButtonRow, forwardRow, backRow,
         thumbWheelToggle, chromeCheck, braveCheck, firefoxCheck, safariCheck,
         mappingProfilesView].forEach { addSubview($0) }
        setSpecialFeatureAvailability(specialFeatureAvailable, isOn: specialFeatureOn)
        updateQuickLaunchAssignments(config: config, featureActive: self.specialFeatureOn)
    }

    required init?(coder: NSCoder) { nil }

    func setSpecialFeatureAvailability(_ available: Bool, isOn: Bool) {
        chatGPTIcon = Self.installedAppIcon(.chatGPT)
        claudeIcon = Self.installedAppIcon(.claude)
        specialFeatureOn = available && isOn
        specialFeatureToggleRow.toggle.isOn = specialFeatureOn
        specialFeatureToggleRow.isEnabled = available
        let chatGPTReadiness = quickLaunchTargetReadiness(.chatGPT)
        let claudeReadiness = quickLaunchTargetReadiness(.claude)
        chatGPTButtonPicker.setReadiness(chatGPTReadiness)
        claudeButtonPicker.setReadiness(claudeReadiness)
        chatGPTHotkeyRow.setReadiness(chatGPTReadiness)
        claudeHotkeyRow.setReadiness(claudeReadiness)
        needsDisplay = true
    }

    func updateQuickLaunchAssignments(config: KlikProConfig, featureActive: Bool) {
        chatGPTButtonPicker.setSelection(config.chatGPTMouseButton)
        claudeButtonPicker.setSelection(config.claudeMouseButton)
        chatGPTButtonPicker.setUnavailable(config.claudeMouseButton, owner: .claude)
        claudeButtonPicker.setUnavailable(config.chatGPTMouseButton, owner: .chatGPT)

        let availableInstances = config.instances.filter {
            guard $0.state == .active else { return false }
            // In preview rendering the seeded legacy instances have no on-disk
            // launcher, so include them anyway to keep the rows consistent with
            // the App Profiles chips in screenshots.
            return previewRenderingIsActive
                || $0.launcherKind == .managed
                || FileManager.default.fileExists(atPath: $0.launcherPath)
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        let originalTargets: [(target: LaunchAssignmentTarget, label: String)] =
            QuickLaunchTarget.allCases.compactMap { target in
                guard quickLaunchTargetIsInstalled(target) else { return nil }
                return (.original(target), target.title)
            }
        let appTargets = originalTargets + availableInstances.map {
            (target: LaunchAssignmentTarget.profile($0.id), label: $0.label)
        }
        let rows: [(QuickLaunchMouseButton, RecordableShortcutRowView)] = [
            (.middle, middleButtonRow), (.gesture, gestureButtonRow),
            (.forward, forwardRow), (.back, backRow),
        ]
        rows.forEach { button, row in
            row.setLinked(to: nil)
            row.setOpenAppOptions(
                appTargets,
                assignedTarget: launchAssignmentOwner(of: button, in: config)
            )
        }
        _ = featureActive
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Full-width mouse guide on top; controls and App Profiles list underneath.
        drawDeviceCard(in: SettingsContentView.deviceCard)
        drawCard(SettingsContentView.thumbWheelCard)
        drawCard(SettingsContentView.recordableCard)

        // Section labels, inset into each card (16pt below the card's top edge)
        let ix = SettingsContentView.innerLeftX
        drawSectionLabel("Mouse Button Shortcuts", x: ix, y: SettingsContentView.recordableCard.minY + 16)
        drawSectionLabel("Thumb Wheel Tab Switching", x: ix, y: SettingsContentView.thumbWheelCard.minY + 16)
        // The section title already names the feature; keep the master label compact
        // enough to leave comfortable spacing for all four browser options.
        ("Enabled" as NSString).draw(at: NSPoint(x: ix + 50, y: 666), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.appTextPrimary])
    }

    // The two quick-launch app icons, right-aligned in the Special Feature card header.
    // Full-colour when the feature is ON, faded when OFF. Icons come from the user's own
    // installed apps at runtime; a missing app shows a neutral placeholder.
    private func drawSpecialFeatureIcons() {
        let card = SettingsContentView.specialFeatureCard
        let iconSize: CGFloat = 26
        let gap: CGFloat = 10
        let y = card.minY + 8
        let rightX = card.maxX - SettingsContentView.pad
        let icons = [chatGPTIcon, claudeIcon]
        var x = rightX - CGFloat(icons.count) * iconSize - CGFloat(icons.count - 1) * gap
        for icon in icons {
            let rect = NSRect(x: x, y: y, width: iconSize, height: iconSize)
            if let icon = icon {
                icon.draw(in: rect, from: .zero, operation: .sourceOver,
                          fraction: specialFeatureOn ? 1.0 : 0.28,
                          respectFlipped: true, hints: nil)
            } else {
                NSColor.separatorColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            x += iconSize + gap
        }
    }

    private func drawCard(_ rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawSectionLabel(_ text: String, x: CGFloat, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.appTextSecondary
        ]
        text.uppercased().draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private func drawDeviceCard(in card: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: card).fill()

        guard let image = image else { return }
        let imageAspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let available = card.insetBy(dx: 190, dy: 8)
        let drawHeight = min(available.height, available.width / imageAspect)
        let drawWidth = drawHeight * imageAspect
        let rect = NSRect(
            x: card.midX - drawWidth / 2,
            y: card.midY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        // respectFlipped: true is required because this view is isFlipped — without it
        // NSImage.draw renders upside-down in the flipped coordinate system.
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
                   respectFlipped: true, hints: nil)

        drawDeviceCallouts(in: rect)
    }

    // Callouts mapped to the controls in assets/Klik PRO mouse.png. Target = fraction of
    // the drawn mouse rect; labels sit in the wide card's left/right margins so they don't
    // overlap the mouse or grow the card height (keeping the single-page layout).
    private struct DeviceCallout {
        let title: String
        let fx: CGFloat   // target x as fraction of mouse rect
        let fy: CGFloat   // target y as fraction of mouse rect
        let onLeft: Bool  // label sits in the left margin (else right)
        let labelY: CGFloat
    }

    // fx/fy are fractions of the drawn mouse rect (top-left origin). Re-tuned 2026-07-20
    // for the reframed device artwork — the crop now centers the whole mouse in the
    // 1000x742 canvas (assets/Klik PRO mouse.png via tools/crop-device.swift), so the
    // targets are the dark control centroids measured in the regenerated reference.
    private static let deviceCallouts: [DeviceCallout] = [
        DeviceCallout(title: "Middle Button (Scroll Wheel)", fx: 0.245, fy: 0.413, onLeft: true, labelY: 100),
        DeviceCallout(title: "Forward Button", fx: 0.584, fy: 0.546, onLeft: true, labelY: 172),
        DeviceCallout(title: "Horizontal Thumb Wheel", fx: 0.594, fy: 0.422, onLeft: false, labelY: 40),
        DeviceCallout(title: "Back Button", fx: 0.692, fy: 0.447, onLeft: false, labelY: 110),
        DeviceCallout(title: "Gesture Button", fx: 0.755, fy: 0.745, onLeft: false, labelY: 180),
    ]

    private func drawDeviceCallouts(in mouseRect: NSRect) {
        let teal = NSColor(calibratedRed: 0.04, green: 0.70, blue: 0.68, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.appTextPrimary
        ]
        let leftEdge = mouseRect.minX - 18
        let rightEdge = mouseRect.maxX + 18

        for c in SettingsContentView.deviceCallouts {
            let target = NSPoint(x: mouseRect.minX + c.fx * mouseRect.width,
                                 y: mouseRect.minY + c.fy * mouseRect.height)
            let size = (c.title as NSString).size(withAttributes: attrs)
            let labelPoint: NSPoint
            let anchor: NSPoint
            if c.onLeft {
                labelPoint = NSPoint(x: leftEdge - size.width, y: c.labelY)
                anchor = NSPoint(x: leftEdge, y: c.labelY + size.height / 2)
            } else {
                labelPoint = NSPoint(x: rightEdge, y: c.labelY)
                anchor = NSPoint(x: rightEdge, y: c.labelY + size.height / 2)
            }

            let path = NSBezierPath()
            path.move(to: anchor)
            path.line(to: NSPoint(x: (anchor.x + target.x) / 2, y: anchor.y))
            path.line(to: target)
            teal.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            teal.setFill()
            NSBezierPath(ovalIn: NSRect(x: target.x - 3.5, y: target.y - 3.5, width: 7, height: 7)).fill()
            (c.title as NSString).draw(at: labelPoint, withAttributes: attrs)
        }
    }
}

// Reads the input helper's most recent Accessibility status from its event log — the
// settings app can't query the helper's TCC grant directly, but the helper logs
// an explicit recheck result (or the legacy mapping-ready/permission-required messages).
func helperAccessibilityGranted() -> Bool {
    if let previewValue = ProcessInfo.processInfo.environment[
        "KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED"
    ] {
        return previewValue == "1"
    }
    if previewRenderingIsActive { return true }
    let path = NSString(string: "~/Library/Logs/klik-pro-events.log").expandingTildeInPath
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
    for line in text.split(separator: "\n").reversed() {
        if line.contains("Accessibility status recheck: granted") { return true }
        if line.contains("Accessibility status recheck: required") { return false }
        if line.contains("Button mappings ready") { return true }
        if line.contains("Accessibility permission is required") { return false }
    }
    return false
}

// Compact, accessible status row for the one macOS permission Klik PRO requires.
final class PermissionStatusRowView: NSView {
    private let title: String
    private var statusText: String
    private var statusColor: NSColor

    override var isFlipped: Bool { true }

    init(title: String, statusText: String, statusColor: NSColor, frame: NSRect) {
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        updateAccessibilityLabel()
    }

    required init?(coder: NSCoder) { nil }

    func setStatus(_ text: String, color: NSColor) {
        guard statusText != text || statusColor != color else { return }
        statusText = text
        statusColor = color
        updateAccessibilityLabel()
        needsDisplay = true
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel("\(title): \(statusText)")
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.appTextPrimary,
        ]
        (title as NSString).draw(
            at: NSPoint(x: 0, y: bounds.midY - 8),
            withAttributes: titleAttributes
        )

        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10.5),
            .foregroundColor: statusColor,
        ]
        let statusSize = (statusText as NSString).size(withAttributes: statusAttributes)
        let pill = NSRect(
            x: bounds.maxX - statusSize.width - 18,
            y: bounds.midY - 10,
            width: statusSize.width + 18,
            height: 20
        )
        let pillPath = NSBezierPath(
            roundedRect: pill.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 9.5,
            yRadius: 9.5
        )
        statusColor.withAlphaComponent(0.14).setFill()
        pillPath.fill()
        statusColor.withAlphaComponent(0.42).setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()
        (statusText as NSString).draw(
            at: NSPoint(x: pill.minX + 9, y: pill.midY - statusSize.height / 2),
            withAttributes: statusAttributes
        )
    }
}

// MARK: - PreferencesContentView (the "Settings" tab)

final class PreferencesContentView: NSView {
    let launchAtLoginRow: ToggleOnlyRowView
    let autoUpdateRow: ToggleOnlyRowView
    let showMenuBarIconRow: ToggleOnlyRowView
    let caffeinateRow: ToggleOnlyRowView
    let openAccessibilityLink: URLLinkView
    let recheckAccessibilityLink: URLLinkView
    let resetAccessibilityLink: URLLinkView
    let openSourceLink: URLLinkView
    let openLogsLink: URLLinkView
    let settingsGithubLink: URLLinkView
    let settingsSponsorsLink: URLLinkView
    let settingsKofiLink: URLLinkView
    let settingsPayPalLink: URLLinkView
    let accessibilityPermissionRow: PermissionStatusRowView
    private var accessibilityGranted: Bool

    override var isFlipped: Bool { true }

    private static let leftX: CGFloat = 0
    // Tighter 16pt inter-column gap (was 32); total width stays 872.
    private static let rightX: CGFloat = 444
    private static let cardW: CGFloat = 428
    private static let pad: CGFloat = 18
    private static let generalCard = NSRect(x: leftX, y: 20, width: cardW, height: 300)
    private static let permCard    = NSRect(x: rightX, y: 20, width: cardW, height: 132)
    private static let aboutCard   = NSRect(x: rightX, y: 168, width: cardW, height: 126)
    private static let supportCard = NSRect(x: rightX, y: 310, width: cardW, height: 92)
    private static let headingContentGap: CGFloat = 8
    private static let permissionRecheckXOffset: CGFloat = 168

    init(
        accessibilityGranted: Bool,
        launchAtLogin: Bool,
        autoCheck: Bool,
        showMenuBarIcon: Bool,
        caffeinateMenu: Bool,
        width: CGFloat
    ) {
        self.accessibilityGranted = accessibilityGranted
        let ix = PreferencesContentView.leftX + PreferencesContentView.pad
        let rxi = PreferencesContentView.rightX + PreferencesContentView.pad
        let iw = PreferencesContentView.cardW - PreferencesContentView.pad * 2
        launchAtLoginRow = ToggleOnlyRowView(title: "Launch at login",
            detail: "Start Klik PRO automatically after you log in",
            isOn: launchAtLogin, frame: NSRect(x: ix, y: 64, width: iw, height: 46))
        autoUpdateRow = ToggleOnlyRowView(title: "Automatically check for updates",
            detail: "Check GitHub for a newer version at launch",
            isOn: autoCheck, frame: NSRect(x: ix, y: 124, width: iw, height: 46))
        showMenuBarIconRow = ToggleOnlyRowView(title: "Show menu bar icon",
            detail: "Show the main Klik PRO status icon",
            isOn: showMenuBarIcon, frame: NSRect(x: ix, y: 184, width: iw, height: 46))
        caffeinateRow = ToggleOnlyRowView(title: "Caffeinate",
            detail: "Keep the Mac awake from the menu bar icon",
            isOn: caffeinateMenu, frame: NSRect(x: ix, y: 244, width: iw, height: 46))
        // The Caffeinate menu lives inside the main menu-bar icon's right-click menu, so
        // it stays tappable but prompts to turn the icon on first when it is hidden.
        accessibilityPermissionRow = PermissionStatusRowView(
            title: "Accessibility",
            statusText: accessibilityGranted ? "Granted" : "Needs permission",
            statusColor: accessibilityGranted ? .systemGreen : .systemOrange,
            frame: NSRect(
                x: rxi,
                y: 54 + PreferencesContentView.headingContentGap,
                width: iw,
                height: 28
            )
        )
        openAccessibilityLink = URLLinkView(
            title: accessibilityGranted ? "Open Accessibility…" : "Set Up Accessibility…",
            urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            style: .outline,
            alignRight: false,
            frame: NSRect(
                x: rxi,
                y: 96 + PreferencesContentView.headingContentGap,
                width: 164,
                height: 28
            )
        )
        recheckAccessibilityLink = URLLinkView(
            title: "Recheck",
            urlString: "",
            style: .outline,
            alignRight: false,
            frame: NSRect(
                x: rxi + PreferencesContentView.permissionRecheckXOffset,
                y: 56 + PreferencesContentView.headingContentGap,
                width: 80,
                height: 24
            )
        )
        resetAccessibilityLink = URLLinkView(
            title: "Reset Access…",
            urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            style: .outline,
            alignRight: false,
            frame: NSRect(
                x: rxi + 172,
                y: 96 + PreferencesContentView.headingContentGap,
                width: 116,
                height: 28
            )
        )
        openAccessibilityLink.toolTip =
            "Open the Accessibility permission list in System Settings."
        recheckAccessibilityLink.toolTip =
            "Re-check whether Klik PRO Helper currently has Accessibility permission."
        resetAccessibilityLink.toolTip =
            "Clear Klik PRO Helper's Accessibility permission and restart guided setup."
        openSourceLink = URLLinkView(
            title: "© 2026 Aminudin Murad · GPL-3.0",
            urlString: "https://github.com/AminudinMurad/klik-pro/blob/main/LICENSE",
            style: .link,
            alignRight: false,
            frame: NSRect(
                x: rxi,
                y: 248 + PreferencesContentView.headingContentGap,
                width: 260,
                height: 24
            )
        )
        openLogsLink = URLLinkView(title: "Open Logs",
            urlString: "file://" + NSString(string: "~/Library/Logs").expandingTildeInPath,
            style: .outline,
            alignRight: false,
            frame: NSRect(
                x: rxi + 296,
                y: 96 + PreferencesContentView.headingContentGap,
                width: 88,
                height: 28
            ))
        settingsGithubLink = URLLinkView(
            title: "GitHub",
            urlString: "https://github.com/AminudinMurad/klik-pro",
            style: .outline,
            icon: BrandMarks.github(size: 15, color: .appTextSecondary),
            alignRight: false,
            frame: .zero
        )
        settingsSponsorsLink = URLLinkView(
            title: "GitHub Sponsors",
            urlString: "https://github.com/sponsors/aminudinmurad",
            style: .outline,
            icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
                .tinted(.systemPink),
            alignRight: false,
            frame: .zero
        )
        settingsKofiLink = URLLinkView(
            title: "Ko-fi",
            urlString: "https://ko-fi.com/aminudinmurad",
            style: .outline,
            icon: NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                .tinted(NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.36, alpha: 1)),
            alignRight: false,
            frame: .zero
        )
        settingsPayPalLink = URLLinkView(
            title: "PayPal",
            urlString: "https://www.paypal.com/paypalme/aminudinmurad",
            style: .outline,
            icon: NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: nil)?
                .tinted(NSColor(calibratedRed: 0, green: 0.44, blue: 0.73, alpha: 1)),
            alignRight: false,
            frame: .zero
        )

        let supportFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let supportIconSpan: CGFloat = 15 + 6
        func supportContentWidth(_ title: String) -> CGFloat {
            (title as NSString).size(withAttributes: [.font: supportFont]).width
                + supportIconSpan
        }
        let supportLinks = [
            settingsGithubLink,
            settingsSponsorsLink,
            settingsKofiLink,
            settingsPayPalLink,
        ]
        let supportTitles = ["GitHub", "GitHub Sponsors", "Ko-fi", "PayPal"]
        let supportContentWidths = supportTitles.map(supportContentWidth)
        let supportTrackX = PreferencesContentView.supportCard.minX + 6
        let supportTrackWidth = PreferencesContentView.cardW - 12
        var supportPadding: CGFloat = 10
        var supportGap = (
            supportTrackWidth
                - (supportContentWidths.reduce(0, +) + supportPadding * 2 * 4)
        ) / 3
        if supportGap < 7 {
            supportGap = 7
            supportPadding = max(
                3,
                (supportTrackWidth - supportContentWidths.reduce(0, +) - supportGap * 3) / 8
            )
        }
        var supportX = supportTrackX
        for (index, link) in supportLinks.enumerated() {
            let buttonWidth = supportContentWidths[index] + supportPadding * 2
            link.frame = NSRect(
                x: supportX,
                y: 351 + PreferencesContentView.headingContentGap,
                width: buttonWidth,
                height: 32
            )
            supportX += buttonWidth + supportGap
        }

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 432))
        [
            launchAtLoginRow,
            autoUpdateRow,
            showMenuBarIconRow,
            caffeinateRow,
            accessibilityPermissionRow,
            openAccessibilityLink,
            recheckAccessibilityLink,
            resetAccessibilityLink,
            openSourceLink,
            openLogsLink,
            settingsGithubLink,
            settingsSponsorsLink,
            settingsKofiLink,
            settingsPayPalLink,
        ].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { nil }

    func setAccessibilityGranted(_ granted: Bool) {
        guard accessibilityGranted != granted else { return }
        accessibilityGranted = granted
        accessibilityPermissionRow.setStatus(
            granted ? "Granted" : "Needs permission",
            color: granted ? .systemGreen : .systemOrange
        )
        openAccessibilityLink.title = granted ? "Open Accessibility…" : "Set Up Accessibility…"
        needsDisplay = true
    }

    private func drawCard(_ rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        let b = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        b.lineWidth = 1; b.stroke()
    }
    private func drawSectionLabel(_ text: String, x: CGFloat, y: CGFloat) {
        text.uppercased().draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.appTextSecondary])
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCard(PreferencesContentView.generalCard)
        drawCard(PreferencesContentView.permCard)
        drawCard(PreferencesContentView.aboutCard)
        drawCard(PreferencesContentView.supportCard)
        let ix = PreferencesContentView.leftX + PreferencesContentView.pad
        let rxi = PreferencesContentView.rightX + PreferencesContentView.pad
        drawSectionLabel("General", x: ix, y: PreferencesContentView.generalCard.minY + 16)
        drawSectionLabel("Permissions", x: rxi, y: PreferencesContentView.permCard.minY + 16)
        drawSectionLabel("About", x: rxi, y: PreferencesContentView.aboutCard.minY + 16)
        drawSectionLabel(
            "Support open-source development",
            x: rxi,
            y: PreferencesContentView.supportCard.minY + 12
        )

        ("Open-source mouse shortcuts and App Profiles for macOS." as NSString).draw(
            at: NSPoint(
                x: rxi,
                y: PreferencesContentView.aboutCard.minY
                    + 40
                    + PreferencesContentView.headingContentGap
            ),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.appTextSecondary,
            ]
        )

        // About: one clear description, version detail, and the open-source action.
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Version unavailable"
        (ver as NSString).draw(at: NSPoint(
            x: rxi,
            y: PreferencesContentView.aboutCard.minY
                + 62
                + PreferencesContentView.headingContentGap
        ), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor])
    }
}

// MARK: - First-launch onboarding

/// Draws a lightweight accent outline over a native alert button while the pointer
/// is inside it. Hit testing remains with the original NSButton, preserving its
/// standard click, keyboard, and accessibility behavior.
final class ButtonHoverOutlineView: NSView {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea = hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    func showHoverPreview() {
        guard previewRenderingIsActive else { return }
        setHovered(true)
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        let outlineBounds = bounds.insetBy(dx: 1.25, dy: 1.25)
        let outline = NSBezierPath(
            roundedRect: outlineBounds,
            xRadius: outlineBounds.height / 2,
            yRadius: outlineBounds.height / 2
        )
        NSColor.controlAccentColor.withAlphaComponent(0.82).setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

/// The native first-launch sheet. Every Settings toggle starts OFF; the user turns on
/// what they want (or skips) and `ToggleView` applies and persists those choices when
/// the sheet is confirmed. Kept to one screen at a fixed 430×252 size so the rendered
/// onboarding fixtures stay dimensionally stable across releases.
/// The three first-launch pages. Toggles and actions never share a page: Welcome
/// introduces the app, Preferences holds only the four setting toggles, and
/// Accessibility holds the one macOS permission plus the finishing actions. Steps
/// can always go Back; there is no Cancel — the flow completes on the last page.
enum OnboardingStep: Int {
    case welcome = 1
    case preferences = 2
    case accessibility = 3
}

private func makeOnboardingStepLabel(_ step: OnboardingStep, y: CGFloat, width: CGFloat) -> NSTextField {
    let label = NSTextField(labelWithString: "Step \(step.rawValue) of 3")
    label.frame = NSRect(x: 0, y: y, width: width, height: 16)
    label.alignment = .center
    label.font = .systemFont(ofSize: 11)
    label.textColor = .tertiaryLabelColor
    return label
}

final class OnboardingWelcomePageView: NSView {
    override var isFlipped: Bool { true }

    init() {
        let contentWidth: CGFloat = 430
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 128))

        let welcome = KlikProWordmarkView(
            prefix: "Welcome to ",
            centered: true,
            frame: NSRect(x: 0, y: 0, width: contentWidth, height: 30)
        )
        let introduction = NSTextField(
            wrappingLabelWithString: "Klik PRO remaps the extra buttons on a pro mouse to recordable shortcuts, switches browser tabs with the thumb wheel, and generates isolated App Profiles."
        )
        introduction.frame = NSRect(x: 28, y: 38, width: contentWidth - 56, height: 52)
        introduction.font = .systemFont(ofSize: 13)
        introduction.alignment = .center
        introduction.textColor = .appTextSecondary
        introduction.maximumNumberOfLines = 3

        addSubview(welcome)
        addSubview(introduction)
        addSubview(makeOnboardingStepLabel(.welcome, y: 102, width: contentWidth))
    }

    required init?(coder: NSCoder) { nil }
}

final class OnboardingAccessibilityPageView: NSView {
    override var isFlipped: Bool { true }

    init(accessibilityGranted: Bool) {
        let contentWidth: CGFloat = 430
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 140))

        let heading = NSTextField(labelWithString: "One macOS permission")
        heading.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 22)
        heading.alignment = .center
        heading.font = .boldSystemFont(ofSize: 15)

        let body = NSTextField(
            wrappingLabelWithString: "Klik PRO uses the Accessibility permission to read the mouse's extra buttons and wheel. Grant it now, or any time later from Settings."
        )
        body.frame = NSRect(x: 28, y: 30, width: contentWidth - 56, height: 52)
        body.font = .systemFont(ofSize: 13)
        body.alignment = .center
        body.textColor = .appTextSecondary
        body.maximumNumberOfLines = 3

        let status = NSTextField(
            labelWithString: accessibilityGranted
                ? "Accessibility: Granted"
                : "Accessibility: Needs permission"
        )
        status.frame = NSRect(x: 0, y: 88, width: contentWidth, height: 20)
        status.alignment = .center
        status.font = .systemFont(ofSize: 13, weight: .semibold)
        status.textColor = accessibilityGranted ? .systemGreen : .systemOrange

        addSubview(heading)
        addSubview(body)
        addSubview(status)
        addSubview(makeOnboardingStepLabel(.accessibility, y: 114, width: contentWidth))
    }

    required init?(coder: NSCoder) { nil }
}

final class OnboardingChecklistView: NSView {
    override var isFlipped: Bool { true }

    let launchAtLoginRow: ToggleOnlyRowView
    let autoUpdateRow: ToggleOnlyRowView
    let showMenuBarIconRow: ToggleOnlyRowView
    let caffeinateRow: ToggleOnlyRowView

    // Caffeinate reads as OFF whenever the menu-bar icon is off, since it only lives in
    // that icon's menu — matching the Settings dependency.
    var launchAtLoginOn: Bool { launchAtLoginRow.toggle.isOn }
    var autoUpdateOn: Bool { autoUpdateRow.toggle.isOn }
    var showMenuBarIconOn: Bool { showMenuBarIconRow.toggle.isOn }
    var caffeinateOn: Bool { showMenuBarIconRow.toggle.isOn && caffeinateRow.toggle.isOn }

    init() {
        let contentWidth: CGFloat = 430
        let rowX: CGFloat = 20
        let rowWidth = contentWidth - rowX * 2
        let firstRowY: CGFloat = 44
        let rowHeight: CGFloat = 46

        launchAtLoginRow = ToggleOnlyRowView(
            title: "Launch at login",
            detail: "Start Klik PRO automatically after you log in",
            isOn: false,
            frame: NSRect(x: rowX, y: firstRowY, width: rowWidth, height: rowHeight)
        )
        autoUpdateRow = ToggleOnlyRowView(
            title: "Automatically check for updates",
            detail: "Check GitHub for a newer version at launch",
            isOn: false,
            frame: NSRect(x: rowX, y: firstRowY + rowHeight, width: rowWidth, height: rowHeight)
        )
        showMenuBarIconRow = ToggleOnlyRowView(
            title: "Show menu bar icon",
            detail: "Show the main Klik PRO status icon",
            isOn: false,
            frame: NSRect(x: rowX, y: firstRowY + rowHeight * 2, width: rowWidth, height: rowHeight)
        )
        caffeinateRow = ToggleOnlyRowView(
            title: "Caffeinate",
            detail: "Keep the Mac awake from the menu bar icon",
            disabledDetail: "Turn on Show menu bar icon to use Caffeinate",
            isOn: false,
            frame: NSRect(x: rowX, y: firstRowY + rowHeight * 3, width: rowWidth, height: rowHeight)
        )

        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 256))

        let introduction = NSTextField(
            wrappingLabelWithString: "Turn on what you'd like now — you can change any of these later in Settings."
        )
        introduction.frame = NSRect(x: 28, y: 0, width: contentWidth - 56, height: 34)
        introduction.font = .systemFont(ofSize: 13)
        introduction.alignment = .center
        introduction.textColor = .appTextSecondary
        introduction.maximumNumberOfLines = 2

        addSubview(introduction)
        addSubview(makeOnboardingStepLabel(.preferences, y: 234, width: contentWidth))

        // Caffeinate is only reachable through the menu-bar icon's menu. It stays
        // tappable, but turning it on while the icon is off asks the user to enable the
        // icon first; turning the icon back off clears Caffeinate with it.
        showMenuBarIconRow.onToggleChange = { [weak self] on in
            guard let self = self, !on else { return }
            self.caffeinateRow.toggle.isOn = false
        }
        caffeinateRow.onToggleChange = { [weak self] on in
            guard let self = self, on, !self.showMenuBarIconRow.toggle.isOn else { return }
            if confirmEnableMenuBarIconForCaffeinate() {
                self.showMenuBarIconRow.toggle.isOn = true
            } else {
                self.caffeinateRow.toggle.isOn = false
            }
        }

        addSubview(launchAtLoginRow)
        addSubview(autoUpdateRow)
        addSubview(showMenuBarIconRow)
        addSubview(caffeinateRow)
    }

    required init?(coder: NSCoder) { nil }
}

/// Prompt shown when Caffeinate is switched on while "Show menu bar icon" is off.
/// Caffeinate lives in that icon's menu, so the icon must be visible to use it. Returns
/// true if the user chose to turn the menu-bar icon on (so both can be enabled together).
func confirmEnableMenuBarIconForCaffeinate() -> Bool {
    guard !previewRenderingIsActive else { return false }
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Turn on the menu bar icon?"
    alert.informativeText = "Caffeinate lives in the Klik PRO menu bar icon's menu, so the icon has to be shown to use it. Turn on Show menu bar icon too?"
    alert.addButton(withTitle: "Turn On Menu Bar Icon")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

/// Confirms unlocking the Advanced tab. Its options change where App Profile data
/// is stored on disk, so unlocking is gated behind an explicit acknowledgement of
/// the risk. Returns true only if the user chose to proceed.
func confirmUnlockAdvancedSettings() -> Bool {
    guard !previewRenderingIsActive else { return false }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Unlock Advanced settings?"
    alert.informativeText = "These options change where your App Profile data is stored on disk. "
        + "Choosing the wrong folder can leave profiles unfindable or split across locations, and "
        + "existing profiles are never moved. Only continue if you understand the consequences."
    alert.addButton(withTitle: "Unlock")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

func makeOnboardingAlert(
    step: OnboardingStep,
    accessibilityGranted: Bool,
    checklist: OnboardingChecklistView
) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    // With no native message fields, NSAlert centers its app icon above the custom
    // welcome header instead of reserving the usual left-hand icon column.
    if previewRenderingIsActive,
       let previewIconURL = Bundle.main.url(
           forResource: "OnboardingPreviewIcon",
           withExtension: "png"
       ),
       let previewIcon = NSImage(contentsOf: previewIconURL) {
        // The fixed PNG avoids nondeterministic ICNS representation selection in
        // repeated visual-regression renders. The shipped app still uses its icon.
        previewIcon.size = NSSize(width: 64, height: 64)
        alert.icon = previewIcon
    } else {
        alert.icon = NSApp.applicationIconImage
    }
    alert.messageText = ""
    alert.informativeText = ""
    // Toggles and finishing actions never share a page, steps can go Back, and
    // there is deliberately no Cancel: the flow completes on the last page.
    switch step {
    case .welcome:
        alert.accessoryView = OnboardingWelcomePageView()
        alert.addButton(withTitle: "Continue")
    case .preferences:
        alert.accessoryView = checklist
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Back")
    case .accessibility:
        alert.accessoryView = OnboardingAccessibilityPageView(
            accessibilityGranted: accessibilityGranted
        )
        if accessibilityGranted {
            alert.addButton(withTitle: "Start Using Klik PRO")
        } else {
            // Opt-in: grant now, or "Skip for Now" to finish and grant later in
            // Settings. Skipping still completes onboarding — it is not a Cancel.
            alert.addButton(withTitle: "Set Up Accessibility…")
            alert.addButton(withTitle: "Skip for Now")
        }
        let backButton = alert.addButton(withTitle: "Back")
        let backHoverOutline = ButtonHoverOutlineView(frame: backButton.bounds)
        backHoverOutline.autoresizingMask = [.width, .height]
        backButton.addSubview(backHoverOutline)
        if ProcessInfo.processInfo.environment["KLIK_PRO_PREVIEW_ONBOARDING_BACK_HOVER"] == "1" {
            backHoverOutline.showHoverPreview()
        }
    }
    return alert
}

// MARK: - Top-level window chrome (fixed header + scroll view + fixed footer)

final class ToggleWindowController: NSWindowController {
    private let content = ToggleView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 934),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Klik PRO"
        window.center()
        window.contentView = content
        super.init(window: window)
        content.onClose = { [weak self] in
            self?.close()
            NSApp.terminate(nil)
        }
    }

    func showFirstLaunchOnboardingIfNeeded() {
        content.showFirstLaunchOnboardingIfNeeded()
    }

    func checkForUpdatesFromMenuBar() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        content.checkForUpdatesFromMenuBar()
    }

    func ensureBackgroundHelperRunningAtLaunch() {
        content.ensureBackgroundHelperRunningAtLaunch()
    }

    func guideAccessibilityRegrantAfterUpdateIfNeeded() {
        content.guideAccessibilityRegrantAfterUpdateIfNeeded()
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class ToggleView: NSView {
    private struct AppControlState: Equatable {
        var launchAtLogin: Bool
        var automaticUpdateChecks: Bool
        var specialFeatureEnabled: Bool
    }

    var onClose: (() -> Void)?

    private var menuRunning: Bool
    private var config: KlikProConfig
    private var persistedConfig: KlikProConfig   // snapshot as-loaded, for conflict-engine's false-positive check
    private var controlState: AppControlState
    private var persistedControlState: AppControlState
    private let browserExtensionShortcuts: Set<KeyCombo.Signature>
    private var saveStatusMessage: String?
    private let saveApplyQueue = DispatchQueue(
        label: "local.klik-pro.settings.save-apply",
        qos: .userInitiated
    )
    private var saveInProgress = false
    private var appProfileLifecycleInProgress = false
    private var appProfileInteractionShield: NSView?
    private var unsavedChangesPreviewOverride = false
    private let headerWordmark: KlikProWordmarkView = {
        let scale: CGFloat = 2
        let size = KlikProBrand.wordmarkSize(prefix: "", scale: scale)
        return KlikProWordmarkView(
            centered: false,
            scale: scale,
            frame: NSRect(x: 38, y: 14, width: size.width, height: 60)
        )
    }()
    private let scrollView = NSScrollView()
    private let contentView: SettingsContentView
    private let preferencesView: PreferencesContentView
    private let appProfilesView: AppProfilesContentView
    private let advancedView: AdvancedSettingsContentView
    // Rebuilt whenever `config.dataRoot` changes (Advanced tab pick/clear, or an
    // on-launch adopt), so the generator's wired vault root and `config.dataRoot`
    // never drift apart — the equality `newInstanceStorage` requires before it
    // will ever create a `.vault` instance. `nil`/invalid dataRoot ⇒ no-vault
    // generator ⇒ byte-for-byte the pre-vault app.
    private var appProfileManager = AppProfileManager()
    private let appProfileRuntime = AppProfileRuntime()
    private let appProfileQueue = DispatchQueue(
        label: "local.klik-pro.settings.app-profiles",
        qos: .userInitiated
    )
    // Health reconciliation may block while macOS/File Provider opens a vault
    // marker. Keep it off the lifecycle/discovery queue so a slow read cannot
    // freeze Generate, Remove, Archive, Repair, or app discovery.
    private let appProfileHealthQueue = DispatchQueue(
        label: "local.klik-pro.settings.app-profile-health",
        qos: .utility
    )
    private var supportedAppCandidateCache: [AppProfileCandidate]?
    private var supportedAppDiscoveryInProgress = false
    private let saveButton = PrimaryHoverButton(
        title: "Save",
        frame: NSRect(x: 48, y: 854, width: 120, height: 42)
    )
    // Check-for-updates button, top-right of the header (where the status pill used to be).
    private let updateButtonRect = NSRect(x: 732, y: 30, width: 156, height: 30)
    private var updateButtonTrackingArea: NSTrackingArea?
    private var updateButtonHovered = false
    private let closeButtonRect = NSRect(x: 808, y: 854, width: 90, height: 42)
    private var closeButtonTrackingArea: NSTrackingArea?
    private var closeButtonHovered = false
    // Set by a successful check when a newer release exists; lights up the header button.
    private var updateAvailableURL: URL?
    static let autoCheckKey = "klikpro.autoCheckUpdates"
    // Pill tab bar. Segment frames are recomputed each draw from measured label
    // widths (even padding, centered as a group) and stored back into these named
    // rects, so mouseDown/selectTab stay in sync. Indices are unchanged: Mappings=0,
    // Settings=1, App Profiles=2, Advanced=3 — only the on-screen order/position differ.
    private var activeTab = 0
    private var mappingsTabRect = NSRect.zero
    private var settingsTabRect = NSRect.zero
    private var appProfilesTabRect = NSRect.zero
    private var advancedTabRect = NSRect.zero
    private var appActivationObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        let loadedConfig = KlikProConfigStore.load()
        if !previewRenderingIsActive {
            _ = installLaunchAgentPlist(appBundleURL: Bundle.main.bundleURL)
        }
        let specialFeatureAvailable = hasInstalledQuickLaunchTarget()
        let detectedBrowserExtensionShortcuts = installedChromeExtensionShortcutSignatures()
        // A fresh install has onboarding pending: every Settings toggle defaults OFF until
        // the user chooses in the first-run sheet. Existing users (onboarding already
        // completed, or migrated) keep their prior implicit defaults, so nothing an
        // updater relied on silently flips off.
        let onboardingPending = !previewRenderingIsActive && !loadedConfig.onboardingCompleted
        let autoCheckEnabled = previewRenderingIsActive
            ? true
            : (UserDefaults.standard.object(forKey: ToggleView.autoCheckKey) as? Bool
                ?? !onboardingPending)
        let helperRunning = previewRenderingIsActive
            ? true
            : run(["print", inputTarget]) == 0
        let launchAtLoginEnabled = previewRenderingIsActive
            ? true
            : launchAtLoginPreference(defaultValue: onboardingPending ? false : helperRunning)
        menuRunning = loadedConfig.specialFeatureEnabled
            && specialFeatureAvailable
            && helperRunning
        config = loadedConfig
        persistedConfig = loadedConfig
        appProfileManager = makeAppProfileManager(forDataRoot: loadedConfig.dataRoot)
        controlState = AppControlState(
            launchAtLogin: launchAtLoginEnabled,
            automaticUpdateChecks: autoCheckEnabled,
            specialFeatureEnabled: menuRunning
        )
        persistedControlState = controlState
        browserExtensionShortcuts = detectedBrowserExtensionShortcuts
        // `self.appProfileRuntime` is unreachable during phase-1 initialization, so probe
        // managed launchability through a locally constructed runtime (it is stateless).
        // Preview rendering must stay off the filesystem, so it never consults health.
        let initialRuntime = AppProfileRuntime(
            generator: makeLauncherGenerator(forDataRoot: loadedConfig.dataRoot)
        )
        let initialLaunchableInstanceIDs = launchableAppProfileInstanceIDs(
            in: loadedConfig,
            instanceIsLaunchable: { instance in
                !previewRenderingIsActive && initialRuntime.health(for: instance) == .ready
            }
        )
        let statuses = evaluateShortcutConflicts(
            candidate: loadedConfig,
            persisted: loadedConfig,
            browserExtensionShortcuts: detectedBrowserExtensionShortcuts,
            specialFeatureActive: menuRunning,
            chatGPTAvailable: quickLaunchTargetIsAvailable(.chatGPT),
            claudeAvailable: quickLaunchTargetIsAvailable(.claude),
            activeInstanceIDs: initialLaunchableInstanceIDs
        )
        contentView = SettingsContentView(
            config: loadedConfig,
            statuses: statuses,
            specialFeatureOn: menuRunning,
            specialFeatureAvailable: specialFeatureAvailable,
            width: 872
        )
        preferencesView = PreferencesContentView(
            accessibilityGranted: helperAccessibilityGranted(),
            launchAtLogin: launchAtLoginEnabled,
            autoCheck: autoCheckEnabled,
            showMenuBarIcon: loadedConfig.showMenuBarIcon,
            caffeinateMenu: loadedConfig.caffeinateMenuEnabled,
            width: 872)
        appProfilesView = AppProfilesContentView(instances: loadedConfig.instances, width: 872)
        advancedView = AdvancedSettingsContentView(dataRoot: loadedConfig.dataRoot, width: 872)

        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(headerWordmark)
        scrollView.frame = NSRect(x: 34, y: 122, width: 872, height: 702)
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = contentView
        addSubview(scrollView)
        saveButton.onPress = { [weak self] in
            self?.saveConfiguration()
        }
        addSubview(saveButton)

        wireRowCallbacks()
        recomputeConflictBadges()   // badges correct on first paint
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSpecialFeatureAvailability()
            self?.refreshAccessibilityStatus()
            self?.refreshAppProfileHealth()
        }
        refreshAppProfileHealth()
        refreshSupportedAppCandidates()
        healManagedAppProfilesIfNeeded()
        recoverVaultOnLaunchIfNeeded()
        reconcileAppProfileDerivedState()
        refreshAppProfileHealth()

        // Launch at login controls only the next login. The helper may still be
        // running now to provide mouse shortcuts and menu-bar icons.
        preferencesView.launchAtLoginRow.onToggleChange = { on in
            if on {
                UserDefaults.standard.set(true, forKey: launchAtLoginPreferenceKey)
                guard self.ensureLaunchAgentSetup() else {
                    UserDefaults.standard.set(false, forKey: launchAtLoginPreferenceKey)
                    self.preferencesView.launchAtLoginRow.toggle.isOn = false
                    self.configurationDidChange()
                    return
                }
                _ = run(["enable", inputTarget])
                _ = ensureInputHelperRunning(launchAtLoginEnabled: true)
            } else {
                UserDefaults.standard.set(false, forKey: launchAtLoginPreferenceKey)
                guard self.ensureLaunchAgentSetup() else {
                    UserDefaults.standard.set(true, forKey: launchAtLoginPreferenceKey)
                    self.preferencesView.launchAtLoginRow.toggle.isOn = true
                    NSSound.beep()
                    self.configurationDidChange()
                    return
                }
                _ = ensureInputHelperRunning(launchAtLoginEnabled: false)
                _ = run(["disable", inputTarget])
            }
            self.configurationDidChange()
        }
        preferencesView.autoUpdateRow.onToggleChange = { [weak self] on in
            UserDefaults.standard.set(on, forKey: ToggleView.autoCheckKey)
            self?.configurationDidChange()
        }
        preferencesView.openAccessibilityLink.onClick = { [weak self] in
            self?.beginAccessibilitySetup()
        }
        preferencesView.recheckAccessibilityLink.onClick = { [weak self] in
            self?.recheckAccessibilityStatus()
        }
        preferencesView.resetAccessibilityLink.onClick = { [weak self] in
            self?.confirmAccessibilityReset()
        }
        // Auto-check for updates on launch (app-only; lights up the header button if newer).
        if !previewRenderingIsActive && autoCheckEnabled {
            checkForUpdates(silent: true)
        }
    }

    deinit {
        if let appActivationObserver = appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
    }

    /// Switch between Mappings (0), Settings (1), App Profiles (2), Advanced (3).
    func selectTab(_ index: Int) {
        let previousTab = activeTab
        activeTab = index
        // Crossfade the swapped content only; the window and scroll frame never resize.
        // Previews must stay deterministic, so fixture rendering swaps instantly.
        if !previewRenderingIsActive && index != previousTab && scrollView.documentView != nil {
            scrollView.contentView.wantsLayer = true
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.layer?.add(fade, forKey: "tabContentFade")
        }
        switch index {
        case 1: scrollView.documentView = preferencesView
        case 2:
            scrollView.documentView = appProfilesView
            refreshSupportedAppCandidates(showLoading: supportedAppCandidateCache == nil)
        case 3:
            // Always re-lock and re-sync the shown data folder on entry, so the
            // controls can't be reached without a deliberate unlock each visit.
            advancedView.setDataRoot(persistedConfig.dataRoot)
            advancedView.setLocked(true)
            scrollView.documentView = advancedView
        default: scrollView.documentView = contentView
        }
        needsDisplay = true
    }

    /// Deterministic preview-only state used to verify the pending-save affordance.
    func showUnsavedChangesPreview() {
        guard previewRenderingIsActive else { return }
        unsavedChangesPreviewOverride = true
        saveStatusMessage = nil
        needsDisplay = true
    }

    func showSaveButtonHoverPreview() {
        guard previewRenderingIsActive else { return }
        saveButton.showHoverPreview()
    }

    func showUpdateButtonHoverPreview() {
        guard previewRenderingIsActive else { return }
        setUpdateButtonHovered(true)
    }

    func showCloseButtonHoverPreview() {
        guard previewRenderingIsActive else { return }
        setCloseButtonHovered(true)
    }

    func showUnlockedAdvancedPreview() {
        guard previewRenderingIsActive else { return }
        advancedView.setLocked(false)
        guard let base = persistedConfig.instances.first else { return }
        let fixtures: [(String, AppProfileState, AppProfileMaintenanceHealth)] = [
            ("Claude Work", .active, .healthy),
            ("ChatGPT Test", .active, .missingLauncher),
            ("Claude Archive", .archived, .recoverableArchived),
            ("Old ChatGPT", .active, .missingData),
        ]
        let instances = fixtures.enumerated().map { index, fixture -> AppProfileInstance in
            var instance = base
            instance.id = UUID(uuidString: String(
                format: "10000000-0000-0000-0000-%012d", index + 1
            ))!
            instance.label = fixture.0
            instance.launcherKind = .managed
            instance.profileOwnership = .managed
            instance.state = fixture.1
            instance.archivedAt = fixture.1 == .archived ? Date(timeIntervalSince1970: 1) : nil
            return instance
        }
        let orphans: [OrphanFinding] = [
            OrphanFinding(
                instanceID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                storage: .applicationSupport,
                state: .orphanedData,
                dataPaths: [URL(fileURLWithPath: "/Users/you/Library/Application Support/Klik PRO/Profiles/20000000-0000-0000-0000-000000000001")],
                sizeBytes: 48_312_320,
                markerPresent: true
            ),
            OrphanFinding(
                instanceID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                storage: .applicationSupport,
                state: .needsManualReview,
                dataPaths: [URL(fileURLWithPath: "/Users/you/Library/Application Support/Klik PRO/Profiles/20000000-0000-0000-0000-000000000002")],
                sizeBytes: 1_048_576,
                markerPresent: false
            ),
        ]
        advancedView.setMaintenanceInstances(
            instances,
            health: Dictionary(uniqueKeysWithValues: zip(instances, fixtures).map {
                ($0.0.id, $0.1.2)
            }),
            orphans: orphans
        )
    }

    func showSupportedAppProfilesPreview() {
        guard previewRenderingIsActive else { return }
        let legacyInstances = persistedConfig.instances.filter {
            $0.launcherKind == .legacyExternal
        }
        let candidates = legacyInstances.compactMap { instance -> AppProfileCandidate? in
            guard instance.launcherKind == .legacyExternal else { return nil }
            let displayName = instance.source.bundleIdentifier == "com.openai.codex"
                ? "ChatGPT" : "Claude"
            let app = InstalledApp(
                bundleIdentifier: instance.source.bundleIdentifier,
                bundleURL: URL(fileURLWithPath: instance.source.bundleURL, isDirectory: true),
                displayName: displayName,
                version: "preview"
            )
            return AppProfileCandidate(
                app: app,
                engine: .electron,
                eligibility: .verified(ruleID: "preview-approved")
            )
        }
        let chatGPT = legacyInstances.first {
            $0.source.bundleIdentifier == "com.openai.codex"
        }
        let claude = legacyInstances.first {
            $0.source.bundleIdentifier == "com.anthropic.claudefordesktop"
        }
        let previewSeeds: [(String, AppProfileInstance?, AppProfileLauncherKind, QuickLaunchMouseButton?)] = [
            ("ChatGPT P", chatGPT, .legacyExternal, .forward),
            ("ChatGPT G", chatGPT, .legacyExternal, nil),
            ("ChatGPT A", chatGPT, .legacyExternal, nil),
            ("Claude P", claude, .legacyExternal, .back),
            ("Claude G", claude, .legacyExternal, nil),
            ("Claude 3", claude, .managed, nil),
        ]
        let previewLauncherRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KlikPROPreviewLaunchers-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let expandedInstances = previewSeeds.enumerated().compactMap { index, seed -> AppProfileInstance? in
            let (label, base, _, button) = seed
            guard var instance = base else { return nil }
            instance.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            instance.label = label
            // Public v1.2 previews deliberately use managed rows so the new gear
            // menu and per-profile icon identity are both visible. The temporary
            // launcher resources never touch the user's real profiles.
            instance.launcherKind = .managed
            instance.profileOwnership = .managed
            instance.mouseButton = button
            let launcherURL = previewLauncherRoot.appendingPathComponent("\(label).app", isDirectory: true)
            let resourcesURL = launcherURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            instance.launcherPath = launcherURL.path
            if let source = NSWorkspace.shared.icon(forFile: instance.source.bundleURL)
                .cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let palette: [AppProfileMenuColor] = [.purple, .green, .blue, .orange, .pink, .gray]
                let rendered = index.isMultiple(of: 2)
                    ? LauncherGenerator.badgedIcon(
                        source,
                        color: palette[index].iconColor,
                        letter: label.components(separatedBy: " ").last ?? label
                    )
                    : LauncherGenerator.tintedIcon(source, color: palette[index].iconColor)
                if let rendered,
                   let data = try? LauncherGenerator.makeICNSData(from: rendered) {
                    try? FileManager.default.createDirectory(
                        at: resourcesURL,
                        withIntermediateDirectories: true
                    )
                    try? data.write(to: resourcesURL.appendingPathComponent("AppIcon.icns"))
                }
            }
            return instance
        }
        appProfilesView.setInstances(expandedInstances)
        appProfilesView.setSupportedCandidates(candidates)
        // Preview only: mirror the seeded assignments into `config` so the Mouse
        // Button Shortcuts rows agree with the App Profiles chips in the rendered
        // screenshots (the running app already shares one config between them).
        // Sync persistedConfig too so this doesn't read as an unsaved change.
        config.instances = expandedInstances
        config.chatGPTMouseButton = nil
        config.claudeMouseButton = nil
        persistedConfig = config
        refreshOriginalAssignmentViews()
        refreshQuickLaunchAssignments()
    }

    func showEmptyAppProfilesPreview() {
        guard previewRenderingIsActive else { return }
        appProfilesView.setInstances([])
        appProfilesView.setSupportedCandidates([])
        appProfilesView.setStatus("")
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func wireRowCallbacks() {
        // Footer gear → open the Settings tab.
        contentView.settingsButton.onClick = { [weak self] in
            self?.selectTab(1)
        }
        preferencesView.showMenuBarIconRow.onToggleChange = { [weak self] on in
            guard let self = self else { return }
            self.config.showMenuBarIcon = on
            // Caffeinate cannot exist without the icon, so hiding the icon clears it.
            if !on && self.preferencesView.caffeinateRow.toggle.isOn {
                self.preferencesView.caffeinateRow.toggle.isOn = false
                self.config.caffeinateMenuEnabled = false
            }
            self.configurationDidChange()
            // Turning the icon on relies on the helper; if it is not trusted
            // (typically a stale grant after an update), explain the re-grant
            // instead of leaving only the bare system prompt.
            if on { self.guideAccessibilityRegrantIfStillMissing() }
        }
        preferencesView.caffeinateRow.onToggleChange = { [weak self] on in
            guard let self = self else { return }
            if on && !self.preferencesView.showMenuBarIconRow.toggle.isOn {
                // Ask to turn the menu-bar icon on first; enable both or revert.
                if confirmEnableMenuBarIconForCaffeinate() {
                    self.preferencesView.showMenuBarIconRow.toggle.isOn = true
                    self.config.showMenuBarIcon = true
                    self.config.caffeinateMenuEnabled = true
                } else {
                    self.preferencesView.caffeinateRow.toggle.isOn = false
                    self.config.caffeinateMenuEnabled = false
                }
            } else {
                self.config.caffeinateMenuEnabled = on
            }
            self.configurationDidChange()
        }
        appProfilesView.onGenerate = { [weak self] candidate in
            self?.createManagedAppProfile(from: candidate)
        }
        appProfilesView.onOpenOriginal = { [weak self] target in
            self?.launchOriginalApp(target)
        }
        appProfilesView.onAssignOriginal = { [weak self] target in
            self?.assignMouseButton(to: .original(target), label: target.title)
        }
        appProfilesView.onCreateOriginalDock = { [weak self] target in
            self?.createOriginalDockIcon(for: target)
        }
        appProfilesView.onDeleteOriginalDock = { [weak self] target in
            self?.deleteOriginalDockIcon(for: target)
        }
        appProfilesView.onRemoveNativeOriginalDock = { [weak self] target in
            self?.removeNativeOriginalDockTile(for: target)
        }
        appProfilesView.onToggleOriginalMenuBar = { [weak self] target in
            self?.toggleOriginalMenuBarPin(for: target)
        }
        appProfilesView.onOpen = { [weak self] instance in
            self?.launchAppProfile(instance)
        }
        appProfilesView.onAssign = { [weak self] instance in
            self?.assignMouseButton(to: instance)
        }
        appProfilesView.onToggleMenuBar = { [weak self] instance in
            self?.toggleMenuBarPin(for: instance)
        }
        appProfilesView.onRename = { [weak self] instance in
            self?.renameAppProfile(instance)
        }
        appProfilesView.onRemove = { [weak self] instance in
            self?.confirmRemoveAppProfile(instance)
        }
        appProfilesView.onChangeIcon = { [weak self] instance in
            self?.changeAppProfileIcon(instance)
        }
        appProfilesView.onChangeApp = { [weak self] _ in
            self?.showAppProfileAlert(
                title: "No other supported app installed",
                message: "Klik PRO currently supports ChatGPT and Claude for App Profile generation."
            )
        }
        appProfilesView.onRefreshApps = { [weak self] in
            guard let self else { return }
            // Refresh both sides: re-scan installed apps for the generator, and reload the
            // profiles list (picking up wrappers created/removed on disk) with their health.
            self.refreshSupportedAppCandidates(showLoading: true, force: true)
            self.appProfilesView.setInstances(self.persistedConfig.instances)
            self.appProfilesView.setOriginalDockPinned(self.originalDockPinStates())
            self.appProfilesView.setOriginalMenuBarPinned(self.originalMenuBarPinStates())
            self.refreshAppProfileHealth()
        }
        // Reflect the current Dock pin state of the original-app launchers on their
        // cards at startup. Skipped in preview renders, which must not read the Dock.
        if !previewRenderingIsActive {
            appProfilesView.setOriginalDockPinned(originalDockPinStates())
        }
        // Menu-bar pin state is persisted in config (not read from the Dock), so it is
        // safe to reflect on the cards even while rendering deterministic previews.
        appProfilesView.setOriginalMenuBarPinned(originalMenuBarPinStates())
        advancedView.onUnlock = { [weak self] in
            guard let self = self, confirmUnlockAdvancedSettings() else { return }
            self.advancedView.setLocked(false)
            self.needsDisplay = true // clear the tab's lock glyph
        }
        advancedView.onChooseFolder = { [weak self] in
            self?.chooseVaultDataFolder()
        }
        advancedView.onClearFolder = { [weak self] in
            self?.clearVaultDataFolder()
        }
        advancedView.onScanAndAdopt = { [weak self] in
            self?.scanAndAdoptVaultFolder()
        }
        advancedView.onDeepScan = { [weak self] in
            self?.performDeepScanForLeftovers()
        }
        advancedView.onRepair = { [weak self] instance in
            self?.repairAppProfile(instance)
        }
        advancedView.onArchive = { [weak self] instance in
            self?.confirmArchiveAppProfile(instance)
        }
        advancedView.onRestore = { [weak self] instance in
            self?.restoreAppProfile(instance)
        }
        advancedView.onForget = { [weak self] instance in
            self?.confirmForgetAppProfile(instance)
        }
        advancedView.onDeleteData = { [weak self] instance in
            self?.confirmDeleteAppProfileData(instance)
        }
        advancedView.onDeleteOrphan = { [weak self] orphan in
            self?.confirmDeleteOrphanData(orphan)
        }
        advancedView.onRevealOrphan = { orphan in
            NSWorkspace.shared.activateFileViewerSelecting(orphan.dataPaths)
        }
        contentView.mappingProfilesView.onOpen = { [weak self] instance in
            self?.launchAppProfile(instance)
        }
        contentView.mappingProfilesView.onAssign = { [weak self] instance in
            self?.assignMouseButton(to: instance)
        }
        contentView.mappingProfilesView.onOpenOriginal = { [weak self] target in
            self?.launchOriginalApp(target)
        }
        contentView.mappingProfilesView.onAssignOriginal = { [weak self] target in
            self?.assignMouseButton(to: .original(target), label: target.title)
        }
        appProfilesView.onInstancesChange = { [weak self] instances in
            self?.contentView.mappingProfilesView.setInstances(instances)
        }
        appProfilesView.onRuntimeHealthChange = { [weak self] health in
            self?.contentView.mappingProfilesView.setRuntimeHealth(health)
        }
        appProfilesView.onStatusChange = { [weak self] message, color in
            self?.contentView.mappingProfilesView.setStatus(message, color: color)
        }

        contentView.middleButtonRow.onToggleChange = { [weak self] on in
            self?.config.middleButton.enabled = on
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }
        contentView.middleButtonRow.onComboChange = { [weak self] combo in
            self?.config.middleButton.combo = combo
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }

        contentView.gestureButtonRow.onToggleChange = { [weak self] on in
            self?.config.gestureButton.enabled = on
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }
        contentView.gestureButtonRow.onComboChange = { [weak self] combo in
            self?.config.gestureButton.combo = combo
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }

        contentView.forwardRow.onToggleChange = { [weak self] on in
            self?.config.forwardButton.enabled = on
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }
        contentView.forwardRow.onComboChange = { [weak self] combo in
            self?.config.forwardButton.combo = combo
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }

        contentView.backRow.onToggleChange = { [weak self] on in
            self?.config.backButton.enabled = on
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }
        contentView.backRow.onComboChange = { [weak self] combo in
            self?.config.backButton.combo = combo
            self?.configurationDidChange()
            self?.recomputeConflictBadges()
        }

        contentView.middleButtonRow.onOpenAppChange = { [weak self] target in
            self?.setDualAppMapping(target: target, button: .middle)
        }
        contentView.gestureButtonRow.onOpenAppChange = { [weak self] target in
            self?.setDualAppMapping(target: target, button: .gesture)
        }
        contentView.forwardRow.onOpenAppChange = { [weak self] target in
            self?.setDualAppMapping(target: target, button: .forward)
        }
        contentView.backRow.onOpenAppChange = { [weak self] target in
            self?.setDualAppMapping(target: target, button: .back)
        }

        contentView.chatGPTHotkeyRow.onComboChange = { [weak self] combo in
            self?.config.chatGPTHotkey.combo = combo
            self?.configurationDidChange()
            self?.refreshQuickLaunchAssignments()
            self?.recomputeConflictBadges()
        }
        contentView.claudeHotkeyRow.onComboChange = { [weak self] combo in
            self?.config.claudeHotkey.combo = combo
            self?.configurationDidChange()
            self?.refreshQuickLaunchAssignments()
            self?.recomputeConflictBadges()
        }

        contentView.chatGPTButtonPicker.onSelectionChange = { [weak self] button in
            self?.setQuickLaunchMouseButton(button, for: .chatGPT)
        }
        contentView.claudeButtonPicker.onSelectionChange = { [weak self] button in
            self?.setQuickLaunchMouseButton(button, for: .claude)
        }

        contentView.specialFeatureToggleRow.onToggleChange = { [weak self] on in
            guard let self = self else { return }
            guard hasInstalledQuickLaunchTarget() else {
                NSSound.beep()
                self.refreshSpecialFeatureAvailability()
                return
            }
            if on && !self.ensureLaunchAgentSetup() {
                self.refreshSpecialFeatureAvailability()
                return
            }
            if on && !previewRenderingIsActive && run(["print", inputTarget]) != 0 {
                _ = ensureInputHelperRunning(
                    launchAtLoginEnabled: self.preferencesView.launchAtLoginRow.toggle.isOn
                )
            }
            self.config.specialFeatureEnabled = on
            self.menuRunning = on
            self.refreshSpecialFeatureAvailability()
            self.configurationDidChange()
        }

        contentView.thumbWheelToggle.onChange = { [weak self] on in
            guard let self = self else { return }
            self.config.thumbWheel.enabled = on
            // Grey out / re-enable the per-browser options with the master toggle.
            self.contentView.chromeCheck.isEnabled = on
            self.contentView.braveCheck.isEnabled = on
            self.contentView.firefoxCheck.isEnabled = on
            self.contentView.safariCheck.isEnabled = on
            self.window?.invalidateCursorRects(for: self.contentView.chromeCheck)
            self.window?.invalidateCursorRects(for: self.contentView.braveCheck)
            self.window?.invalidateCursorRects(for: self.contentView.firefoxCheck)
            self.window?.invalidateCursorRects(for: self.contentView.safariCheck)
            self.configurationDidChange()
        }
        contentView.chromeCheck.onChange = { [weak self] on in
            self?.config.thumbWheel.chromeEnabled = on
            self?.configurationDidChange()
        }
        contentView.braveCheck.onChange = { [weak self] on in
            self?.config.thumbWheel.braveEnabled = on
            self?.configurationDidChange()
        }
        contentView.firefoxCheck.onChange = { [weak self] on in
            self?.config.thumbWheel.firefoxEnabled = on
            self?.configurationDidChange()
        }
        contentView.safariCheck.onChange = { [weak self] on in
            self?.config.thumbWheel.safariEnabled = on
            self?.configurationDidChange()
        }
    }

    private var hasUnsavedConfigurationChanges: Bool {
        unsavedChangesPreviewOverride
            || config != persistedConfig
            || controlState != persistedControlState
    }

    private func setDualAppMapping(
        target: LaunchAssignmentTarget?,
        button: QuickLaunchMouseButton
    ) {
        let currentOwner = launchAssignmentOwner(of: button, in: config)
        let previousButton = target.flatMap { mouseButton(assignedTo: $0, in: config) }
        let releasesDifferentOwner = currentOwner != nil && currentOwner != target
        let movesSelectedApp = previousButton != nil && previousButton != button
        if releasesDifferentOwner || movesSelectedApp {
            var names: [String] = []
            if let currentOwner {
                names.append(launchAssignmentLabel(currentOwner, in: config))
            }
            if movesSelectedApp, let target {
                let selectedName = launchAssignmentLabel(target, in: config)
                if !names.contains(selectedName) { names.append(selectedName) }
            }
            let releasedNames = names.joined(separator: " and ")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Force Release the current assignment?"
            alert.informativeText = "\(releasedNames) will lose only its mouse-button assignment. Its app, profile data, and saved keyboard shortcut remain intact."
            alert.addButton(withTitle: "Force Release & Assign")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                refreshQuickLaunchAssignments()
                return
            }
        }

        if let target {
            config = assigningMouseButton(button, to: target, in: config)
        } else if let currentOwner {
            config = clearingMouseButton(from: currentOwner, in: config)
        }
        config = normalizedQuickLaunchConfig(config)
        configurationDidChange()
        refreshButtonAssignmentViews()
    }

    private func beginAppProfileLifecycle() -> Bool {
        guard !saveInProgress,
              !appProfileLifecycleInProgress,
              !hasUnsavedConfigurationChanges else {
            return false
        }
        appProfileLifecycleInProgress = true
        window?.makeFirstResponder(nil)
        let shield = NSView(frame: bounds)
        shield.autoresizingMask = [.width, .height]
        shield.setAccessibilityLabel("App Profile change in progress")
        addSubview(shield, positioned: .above, relativeTo: nil)
        appProfileInteractionShield = shield
        saveButton.isEnabled = false
        return true
    }

    private func finishAppProfileLifecycle() {
        appProfileInteractionShield?.removeFromSuperview()
        appProfileInteractionShield = nil
        appProfileLifecycleInProgress = false
        saveButton.isEnabled = !saveInProgress
    }

    private func refreshSupportedAppCandidates(showLoading: Bool = false, force: Bool = false) {
        guard !previewRenderingIsActive else {
            appProfilesView.setSupportedCandidates([])
            // Preview app discovery is intentionally skipped, but installed-target
            // overrides still describe the original apps. Keep Mappings truthful
            // so the v1.3 original-app rows are covered by deterministic fixtures.
            refreshOriginalAssignmentViews()
            return
        }
        if let cached = supportedAppCandidateCache, !force {
            appProfilesView.setSupportedCandidates(cached)
            return
        }
        guard !supportedAppDiscoveryInProgress else { return }
        supportedAppDiscoveryInProgress = true
        if showLoading || supportedAppCandidateCache == nil {
            appProfilesView.setAppDiscoveryLoading()
        }
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let supported = self.appProfileManager.supportedCandidates()
            DispatchQueue.main.async {
                self.supportedAppDiscoveryInProgress = false
                self.supportedAppCandidateCache = supported
                self.appProfilesView.setSupportedCandidates(supported)
                self.refreshOriginalAssignmentViews()
            }
        }
    }

    /// Launch-time heal for already-generated profiles: existing instances
    /// gain any environment their compiled-in rule now requires (e.g.
    /// CLAUDE_CONFIG_DIR) plus their visible home symlink, in place, without
    /// touching profile data — so users never have to remove and regenerate a
    /// profile they are actively using. Idempotent and non-fatal; skipped
    /// entirely while rendering deterministic previews.
    private func healManagedAppProfilesIfNeeded() {
        guard !previewRenderingIsActive, !persistedConfig.instances.isEmpty else { return }
        let healed = appProfileManager.healManagedInstances(config: persistedConfig)
        guard healed != persistedConfig else { return }
        persistedConfig = healed
        config.instances = healed.instances
    }

    /// Rebuilds the App Profile manager for the current `config.dataRoot` so the
    /// generator's wired vault root stays in lockstep with the config. Called
    /// after the user picks/clears the vault folder in the Advanced tab and after
    /// an on-launch adopt. `nil`/invalid dataRoot ⇒ a no-vault generator (new
    /// profiles stay in Application Support, byte-for-byte the pre-vault app).
    private func rebuildAppProfileManager() {
        appProfileManager = makeAppProfileManager(forDataRoot: config.dataRoot)
    }

    private func reconcileAppProfileDerivedState() {
        guard !previewRenderingIsActive else { return }
        let complete = appProfileManager.reconcileDerivedState(config: persistedConfig)
        if !complete {
            advancedView.setStatus(
                "Some derived App Profile files could not be reconciled. Open Advanced to review them.",
                color: .systemOrange
            )
        }
    }

    /// On-launch durable-vault recovery (RFC §5.3–5.4; owner decision: auto-adopt
    /// only when a single valid vault is located). Runs the discovery ladder using
    /// **positive evidence of prior configuration only** — the remembered
    /// `dataRoot` pointer and surviving `~` dot-symlinks that resolve into a
    /// vault — with the default-location probe disabled, so an abandoned vault the
    /// user never configured is never silently adopted. When exactly one valid
    /// vault is found it is wired and `adoptVault` merges any of its instances
    /// missing from the config (existing rows untouched, matched by id). Zero or
    /// multiple candidates change nothing and surface a note on the Advanced tab.
    private func recoverVaultOnLaunchIfNeeded() {
        guard !previewRenderingIsActive else { return }
        let candidates = discoverVaultRootCandidates(
            rememberedPath: persistedConfig.dataRoot,
            homeSymlinkRootURL: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            defaultCandidatePaths: []
        )
        guard !candidates.isEmpty else { return }
        guard candidates.count == 1, let vaultRoot = candidates.first else {
            advancedView.setStatus(
                "Multiple Klik PRO data folders were found. Open Advanced to pick the one to recover from.",
                color: .appTextSecondary
            )
            return
        }
        let previousDataRoot = persistedConfig.dataRoot
        var working = persistedConfig
        working.dataRoot = vaultRoot.path
        config.dataRoot = vaultRoot.path
        rebuildAppProfileManager()
        do {
            let result = try appProfileManager.adoptVault(config: working)
            persistedConfig = result.config
            config.instances = result.config.instances
            config.dataRoot = result.config.dataRoot
            // adoptVault persists only when it adopted at least one instance. If
            // it adopted none but the remembered pointer changed (e.g. the vault
            // moved, or a reinstall wiped the config), persist the pointer so the
            // recovery survives the next launch without re-scanning symlinks.
            if result.adopted.isEmpty, previousDataRoot != result.config.dataRoot {
                _ = KlikProConfigStore.save(result.config)
            }
            appProfilesView.setInstances(result.config.instances)
            advancedView.setDataRoot(result.config.dataRoot)
            if !result.adopted.isEmpty {
                let noun = result.adopted.count == 1 ? "App Profile" : "App Profiles"
                advancedView.setStatus(
                    "Recovered \(result.adopted.count) \(noun) from the data folder.",
                    color: KlikProBrand.green
                )
            }
            refreshAppProfileHealth()
        } catch {
            // Discovery found a vault but adopt refused it (invalid manifest,
            // unavailable root). Leave the config as loaded and note it.
            config.dataRoot = previousDataRoot
            rebuildAppProfileManager()
            let message = (error as? AppProfileManagerError).map(appProfileErrorMessage)
                ?? "The data folder could not be recovered."
            advancedView.setStatus(message, color: .systemRed)
        }
    }

    // MARK: - Advanced tab: data folder actions

    /// Advanced tab → "Choose Folder…". Picks a directory, runs the fail-closed
    /// location gate, and stages it as `config.dataRoot`. It becomes an unsaved
    /// edit applied by the normal Save flow; the manager is rebuilt now so the
    /// wired vault root and config stay in lockstep before the next create.
    private func chooseVaultDataFolder() {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before changing the data folder."
            )
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // Let the user make a fresh folder right here (e.g. a new "Klik PRO Data"
        // on an external disk) instead of having to create it in Finder first.
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose or create a folder to store new App Profiles. "
            + "Pick a location outside the app, such as Documents or an external disk. "
            + "Use the New Folder button to make a new one."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        if let reason = vaultPathRejectionReason(path) {
            advancedView.setStatus(reason, color: .systemRed)
            return
        }
        config.dataRoot = path
        rebuildAppProfileManager()
        advancedView.setDataRoot(path)
        advancedView.setStatus(
            "Data folder set. Save to apply — new App Profiles will be stored here.",
            color: .appTextSecondary
        )
        configurationDidChange()
    }

    /// Advanced tab → "Clear". Reverts new-profile storage to the default
    /// Application Support layout. Existing profiles (vault or otherwise) are
    /// never moved — only where future profiles are created changes.
    private func clearVaultDataFolder() {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before changing the data folder."
            )
            return
        }
        guard config.dataRoot != nil else { return }
        config.dataRoot = nil
        rebuildAppProfileManager()
        advancedView.setDataRoot(nil)
        advancedView.setStatus(
            "Cleared. Save to apply — new App Profiles will use the default location. "
            + "Existing profiles are unchanged.",
            color: .appTextSecondary
        )
        configurationDidChange()
    }

    /// Advanced tab → "Scan & Adopt…". Picks an existing Klik PRO data folder and
    /// re-adopts the App Profiles its `vault.json` describes, regenerating every
    /// ephemeral artifact from the folder's CURRENT path. A folder without a valid
    /// manifest is refused by `adoptVault`. Existing rows are merged untouched.
    private func scanAndAdoptVaultFolder() {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before adopting a data folder."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before adopting a data folder."
            )
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // Show hidden items so a data folder that lives in (or under) a dot-folder
        // stays reachable; users can also toggle with Command-Shift-period.
        panel.showsHiddenFiles = true
        panel.prompt = "Scan"
        panel.message = "Choose the Klik PRO data folder that contains \"vault.json\"."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        if let reason = vaultPathRejectionReason(path) {
            advancedView.setStatus(reason, color: .systemRed)
            return
        }
        let previousDataRoot = config.dataRoot
        var working = persistedConfig
        working.dataRoot = path
        config.dataRoot = path
        rebuildAppProfileManager()
        do {
            let result = try appProfileManager.adoptVault(config: working)
            persistedConfig = result.config
            config = result.config
            advancedView.setDataRoot(result.config.dataRoot)
            appProfilesView.setInstances(result.config.instances)
            refreshAppProfileHealth()
            needsDisplay = true
            let skippedSuffix = result.skippedInstanceIDs.isEmpty
                ? ""
                : " \(result.skippedInstanceIDs.count) could not be adopted."
            if result.adopted.isEmpty {
                // adoptVault only persists when it adopts something; persist the
                // now-set data folder pointer so the choice survives relaunch.
                _ = KlikProConfigStore.save(result.config)
                advancedView.setStatus(
                    "Data folder set. No new App Profiles were found to adopt." + skippedSuffix,
                    color: .appTextSecondary
                )
            } else {
                let noun = result.adopted.count == 1 ? "App Profile" : "App Profiles"
                advancedView.setStatus(
                    "Adopted \(result.adopted.count) \(noun) from the data folder." + skippedSuffix,
                    color: KlikProBrand.green
                )
            }
        } catch {
            config.dataRoot = previousDataRoot
            rebuildAppProfileManager()
            let message = (error as? AppProfileManagerError).map(appProfileErrorMessage)
                ?? "That folder could not be adopted."
            advancedView.setStatus(message, color: .systemRed)
        }
    }

    private func repairAppProfile(_ instance: AppProfileInstance) {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before repairing an App Profile."
            )
            return
        }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        advancedView.setStatus("Repairing \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.appProfileManager.repairLauncher(
                    instanceID: instance.id, config: currentConfig
                )
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    self.advancedView.setStatus("Repaired \(instance.label).", color: KlikProBrand.green)
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func confirmArchiveAppProfile(_ instance: AppProfileInstance) {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before archiving an App Profile."
            )
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Archive \(instance.label)?"
        alert.informativeText = "Klik PRO will remove its launcher and deactivate its assignments, but preserve its login data, assignment choices, and custom icon so it can be restored later."
        alert.addButton(withTitle: "Archive")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        advancedView.setStatus("Archiving \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.archive(
                    instanceID: instance.id, config: currentConfig
                )
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    let clean = result.launcherCleanupCompleted
                    self.advancedView.setStatus(
                        applied && clean
                            ? "Archived \(instance.label). Its data is preserved."
                            : "Archived \(instance.label); launcher cleanup or helper apply is pending.",
                        color: applied && clean ? KlikProBrand.green : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func restoreAppProfile(_ instance: AppProfileInstance) {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before restoring an App Profile."
            )
            return
        }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        advancedView.setStatus("Restoring \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.appProfileManager.restore(
                    instanceID: instance.id, config: currentConfig
                )
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    self.advancedView.setStatus(
                        applied ? "Restored \(instance.label)." : "Restored; helper apply is pending.",
                        color: applied ? KlikProBrand.green : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func confirmForgetAppProfile(_ instance: AppProfileInstance) {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before forgetting an App Profile."
            )
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Forget \(instance.label)?"
        alert.informativeText = "This removes the stale record from Klik PRO. Its login data is already missing, so no data is deleted. Any data that later reappears will show as leftover data you can reclaim."
        alert.addButton(withTitle: "Forget Entry")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        advancedView.setStatus("Forgetting \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.forget(
                    instanceID: instance.id, config: currentConfig
                )
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.advancedView.setStatus(
                        "Forgot \(instance.label). No data was deleted.",
                        color: KlikProBrand.green
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func confirmDeleteAppProfileData(_ instance: AppProfileInstance) {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before deleting an App Profile's data."
            )
            return
        }
        // Two clear options. Both remove the launcher and clear all three icon
        // places (Dock, Launchpad, menu bar); they differ only in whether the
        // login/profile data is kept for recovery or erased.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(instance.label)?"
        alert.informativeText =
            "Remove Icons removes the generated launcher and clears its Dock, "
            + "Launchpad, and menu-bar icons — but keeps the login/profile data on "
            + "disk so you can recover the profile later.\n\n"
            + "Delete All Data does the same and also erases the login/profile data "
            + "(you can choose Move to Trash or Delete Permanently)."
        alert.addButton(withTitle: "Remove Icons (Keep Data)")
        alert.addButton(withTitle: "Delete All Data…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performManagedRemovalKeepingData(instance)
        case .alertSecondButtonReturn:
            let target = appProfileManager.dataRemovalTarget(for: instance)
            presentDataRemovalChoice(
                title: "Delete \(instance.label)'s profile data?",
                target: target,
                statusLabel: instance.label,
                launcherPath: instance.launcherPath
            )
        default:
            return
        }
    }

    /// Option 1 of the removal choice: remove the launcher + all three icon
    /// places, but keep the login/profile data on disk for recovery.
    private func performManagedRemovalKeepingData(_ instance: AppProfileInstance) {
        guard beginAppProfileLifecycle() else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before removing this profile."
            )
            return
        }
        let currentConfig = persistedConfig
        advancedView.setStatus("Removing \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.remove(
                    instanceID: instance.id,
                    config: currentConfig,
                    deleteProfileData: false
                )
                self.cleanupRemovedLauncherRegistration(launcherPath: instance.launcherPath)
                _ = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.advancedView.setStatus(
                        "\(instance.label) removed. Login data kept on disk for recovery.",
                        color: KlikProBrand.green
                    )
                    self.refreshAppProfileHealth()
                    self.needsDisplay = true
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func confirmDeleteOrphanData(_ orphan: OrphanFinding) {
        guard orphan.state == .orphanedData else { return }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before deleting leftover data."
            )
            return
        }
        let target = appProfileManager.dataRemovalTarget(for: orphan)
        presentDataRemovalChoice(
            title: "Delete this leftover data?",
            target: target,
            statusLabel: "leftover data"
        )
    }

    /// Shared confirmation for both direct-row and orphan deletion. Lists the
    /// exact paths + total size and offers the two owner-approved modes:
    /// Move to Trash (recoverable, default) and Delete Permanently.
    private func presentDataRemovalChoice(
        title: String,
        target: DataRemovalTarget,
        statusLabel: String,
        launcherPath: String? = nil
    ) {
        guard !target.artifacts.isEmpty else {
            advancedView.setStatus("Nothing to delete — no data found.", color: .appTextSecondary)
            return
        }
        let size = ByteCountFormatter.string(fromByteCount: target.sizeBytes, countStyle: .file)
        let paths = target.paths.map { "• \($0.path)" }.joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText =
            "Klik PRO will remove this data (\(size)):\n\n\(paths)\n\n"
            + "Move to Trash is recoverable from the macOS Trash. Delete Permanently cannot be undone."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Delete Permanently")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let mode: DataRemovalMode
        switch response {
        case .alertFirstButtonReturn: mode = .trash
        case .alertSecondButtonReturn: mode = .permanent
        default: return
        }
        // Permanent delete is irreversible and erases login/credential data, so
        // it takes a second, destructive-styled confirmation. Trash needs none.
        if mode == .permanent {
            let confirm = NSAlert()
            confirm.alertStyle = .critical
            confirm.messageText = "Permanently delete \(statusLabel) data?"
            confirm.informativeText =
                "This cannot be undone. The login and credential data will be erased, "
                + "not moved to the Trash."
            confirm.addButton(withTitle: "Cancel")
            let destroy = confirm.addButton(withTitle: "Delete Permanently")
            destroy.hasDestructiveAction = true
            guard confirm.runModal() == .alertSecondButtonReturn else { return }
        }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        advancedView.setStatus(
            mode == .trash ? "Moving \(statusLabel) data to Trash…" : "Deleting \(statusLabel) data…"
        )
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.reclaimData(
                    target: target, config: currentConfig, mode: mode
                )
                if result.allRemoved, let launcherPath {
                    self.cleanupRemovedLauncherRegistration(launcherPath: launcherPath)
                }
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.advancedView.setStatus(
                        self.dataRemovalStatusMessage(result, label: statusLabel, applied: applied),
                        color: result.allRemoved ? KlikProBrand.green : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.advancedView.setStatus(self.appProfileErrorMessage(error), color: .systemRed)
                    self.refreshAppProfileHealth()
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    // MARK: Deep scan for leftovers

    /// Returns the validated roots that are safe to include in a read-only scan.
    /// If an older config has already lost its `dataRoot` pointer and has no root
    /// history, the user can identify the previous Data Folder explicitly. This
    /// never adopts the vault and never changes where new profiles are stored.
    private func additionalVaultRootsForDeepScan() -> [URL]? {
        var normalized = normalizedQuickLaunchConfig(persistedConfig)
        var paths = normalized.knownDataRoots
        if let active = normalized.dataRoot {
            paths.removeAll { $0 == active }
        }
        let availableRoots = paths.compactMap { path -> URL? in
            let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard vaultPathRejectionReason(root.path) == nil,
                  VaultManifest.read(vaultRoot: root) != nil else { return nil }
            return root
        }
        if !availableRoots.isEmpty {
            return availableRoots
        }
        guard normalized.dataRoot == nil else { return [] }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Scan Folder"
        panel.message = "Choose a previously used Klik PRO Data Folder so Deep Scan can check its Instances folder. This is read-only and does not adopt or delete anything."
        guard panel.runModal() == .OK, let selected = panel.url else { return nil }
        let root = selected.standardizedFileURL
        if let reason = vaultPathRejectionReason(root.path) {
            advancedView.setStatus(reason, color: .systemRed)
            return nil
        }
        guard VaultManifest.read(vaultRoot: root) != nil else {
            advancedView.setStatus(
                "That folder is not a Klik PRO Data Folder (vault.json is missing or invalid).",
                color: .systemRed
            )
            return nil
        }
        normalized.knownDataRoots.append(root.path)
        normalized = normalizedQuickLaunchConfig(normalized)
        if KlikProConfigStore.save(normalized) {
            persistedConfig = normalized
            config = normalized
        }
        return [root]
    }

    private func performDeepScanForLeftovers() {
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore your current changes before scanning for leftovers."
            )
            return
        }
        guard let additionalVaultRoots = additionalVaultRootsForDeepScan() else {
            advancedView.setStatus(
                "Deep Scan cancelled — no previous Data Folder was scanned.",
                color: .appTextSecondary
            )
            return
        }
        guard beginAppProfileLifecycle() else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before scanning."
            )
            return
        }
        let currentConfig = persistedConfig
        advancedView.setStatus("Scanning for leftovers…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let leftovers = self.appProfileManager.scanLauncherLeftovers(config: currentConfig)
            let orphans = self.appProfileManager.scanOrphans(
                config: currentConfig,
                additionalVaultRoots: additionalVaultRoots
            )
            let staleDockPaths = Self.staleKlikProDockTilePaths()
            DispatchQueue.main.async {
                self.finishAppProfileLifecycle()
                self.presentDeepScanResults(
                    leftovers: leftovers, orphans: orphans,
                    staleDockPaths: staleDockPaths, config: currentConfig
                )
            }
        }
    }

    private func presentDeepScanResults(
        leftovers: [LauncherGenerator.LauncherLeftover],
        orphans: [OrphanFinding],
        staleDockPaths: [String],
        config: KlikProConfig
    ) {
        let cleanableOrphans = orphans.filter { $0.state == .orphanedData }
        let reviewOrphans = orphans.filter { $0.state == .needsManualReview }
        let cleanableTotal = leftovers.count + cleanableOrphans.count + staleDockPaths.count
        let total = cleanableTotal + reviewOrphans.count
        guard total > 0 else {
            advancedView.setStatus("No leftovers found — everything is clean.", color: KlikProBrand.green)
            return
        }
        var lines: [String] = []
        for lo in leftovers {
            let kind: String
            switch lo.kind {
            case .customIcon: kind = "custom icon"
            case .lock: kind = "lock file"
            case .launcher: kind = "launcher"
            }
            lines.append("• \(kind): \(lo.url.lastPathComponent)")
        }
        for o in cleanableOrphans {
            lines.append("• data folder: \(o.dataPaths.first?.lastPathComponent ?? o.instanceID.uuidString)")
        }
        for o in reviewOrphans {
            lines.append("• manual review data folder: \(o.dataPaths.first?.lastPathComponent ?? o.instanceID.uuidString)")
        }
        for p in staleDockPaths {
            lines.append("• Dock tile: \((p as NSString).lastPathComponent)")
        }
        let size = leftovers.reduce(Int64(0)) { $0 + $1.sizeBytes }
            + orphans.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(total) leftover item(s) found (\(sizeStr))"
        if cleanableTotal == 0 {
            alert.informativeText = lines.joined(separator: "\n")
                + "\n\nThese folders no longer have Klik PRO ownership markers, so they need manual review before deletion."
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting(
                    reviewOrphans.flatMap(\.dataPaths)
                )
            }
            advancedView.setStatus(
                "\(reviewOrphans.count) data folder(s) need manual review before deletion.",
                color: .systemOrange
            )
            refreshAppProfileHealth()
            return
        }
        let manualSuffix = reviewOrphans.isEmpty
            ? ""
            : "\n\n\(reviewOrphans.count) markerless data folder(s) need manual review and will not be auto-deleted."
        alert.informativeText = lines.joined(separator: "\n")
            + manualSuffix
            + "\n\nMove to Trash is recoverable. Delete Permanently cannot be undone."
        alert.addButton(withTitle: "Move All to Trash")
        alert.addButton(withTitle: "Delete Permanently")
        alert.addButton(withTitle: "Cancel")
        let mode: DataRemovalMode
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            mode = .trash
        case .alertSecondButtonReturn:
            let confirm = NSAlert()
            confirm.alertStyle = .critical
            confirm.messageText = "Permanently delete \(total) leftover item(s)?"
            confirm.informativeText = "This cannot be undone. Items will not be moved to the Trash."
            confirm.addButton(withTitle: "Cancel")
            let destroy = confirm.addButton(withTitle: "Delete Permanently")
            destroy.hasDestructiveAction = true
            guard confirm.runModal() == .alertSecondButtonReturn else { return }
            mode = .permanent
        default:
            return
        }
        cleanScannedLeftovers(
            leftovers: leftovers, orphans: cleanableOrphans,
            staleDockPaths: staleDockPaths, mode: mode, config: config
        )
    }

    private func cleanScannedLeftovers(
        leftovers: [LauncherGenerator.LauncherLeftover],
        orphans: [OrphanFinding],
        staleDockPaths: [String],
        mode: DataRemovalMode,
        config: KlikProConfig
    ) {
        guard beginAppProfileLifecycle() else { return }
        advancedView.setStatus(mode == .trash ? "Moving leftovers to Trash…" : "Deleting leftovers…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            var removed = 0
            var failed = 0
            var working = config
            for lo in leftovers {
                do {
                    _ = try self.appProfileManager.removeLauncherLeftover(lo, mode: mode)
                    if lo.kind == .launcher { Self.removeDockLauncherIfPresent(lo.url) }
                    removed += 1
                } catch {
                    failed += 1
                }
            }
            for orphan in orphans {
                do {
                    let target = self.appProfileManager.dataRemovalTarget(for: orphan)
                    let result = try self.appProfileManager.reclaimData(
                        target: target, config: working, mode: mode
                    )
                    working = result.config
                    if result.allRemoved { removed += 1 } else { failed += 1 }
                } catch {
                    failed += 1
                }
            }
            for path in staleDockPaths {
                if Self.removeDockLauncherIfPresent(
                    URL(fileURLWithPath: path, isDirectory: true)
                ) {
                    removed += 1
                } else {
                    failed += 1
                }
            }
            _ = applySavedConfig()
            DispatchQueue.main.async {
                self.finishAppProfileLifecycle()
                self.config = working
                self.persistedConfig = working
                self.appProfilesView.setInstances(working.instances)
                let verb = mode == .trash ? "moved to Trash" : "deleted"
                self.advancedView.setStatus(
                    failed == 0
                        ? "\(removed) leftover item(s) \(verb)."
                        : "\(removed) \(verb); \(failed) could not be removed and remain on disk. Quit the related app or restart macOS, then scan again.",
                    color: failed == 0 ? KlikProBrand.green : .systemOrange
                )
                self.refreshAppProfileHealth()
                self.needsDisplay = true
            }
        }
    }

    private func dataRemovalStatusMessage(
        _ result: DataRemovalResult,
        label: String,
        applied: Bool
    ) -> String {
        let verb = result.mode == .trash ? "moved to Trash" : "deleted"
        if result.allRemoved {
            return "Data for \(label) \(verb)."
        }
        let failed = result.perArtifact.filter {
            if case .failed = $0.outcome { return true }
            return false
        }
        return "Partly \(verb): \(failed.count) item(s) could not be removed and remain on disk. Quit the related app or restart macOS, then try again."
    }

    private func createManagedAppProfile(from candidate: AppProfileCandidate) {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before starting another one."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before adding an App Profile."
            )
            return
        }
        let proposedName = nextDualAppName(for: candidate)
        // Known vendor (ChatGPT / Claude) gets a compulsory original-app Dock icon.
        // Other eligible apps have no "original launcher" concept, so the forced row
        // is not shown and the compulsory step is skipped for them.
        let vendorTarget = QuickLaunchTarget.allCases.first {
            $0.applicationBundleIdentifier == candidate.app.bundleIdentifier
        }
        let vendorName = vendorTarget.map {
            URL(fileURLWithPath: $0.standardApplicationPath)
                .deletingPathExtension().lastPathComponent
        }
        guard let request = requestDualAppNameOptions(
            title: "Name your App Profile",
            informativeText: "This name appears under the generated icon. You can rename it later.",
            initialValue: proposedName,
            actionTitle: "Generate",
            allowDockOption: true,
            forcedOriginalDockVendorName: vendorName
        ) else { return }
        let requestedName = request.name
        guard beginAppProfileLifecycle() else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "The App Profile was not created. Finish any current Save, then save or restore your edits first."
            )
            return
        }
        appProfilesView.setStatus("Creating \(candidate.app.displayName)…")
        let currentConfig = persistedConfig
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            // Compulsory original-app Dock icon (Decision: block on failure). It runs
            // before the profile is created, because once a profile is live the native
            // vendor tile can no longer reopen the original. Running it on every
            // generation also backfills users who already have profiles but no
            // original icon yet.
            var originalDockOutcome: DockPinResult?
            if let vendor = vendorTarget {
                // Source the required Dock icon from the exact app this profile is
                // built from, so an install outside /Applications (e.g. ~/Applications)
                // no longer hard-blocks profile creation.
                let outcome = self.ensureOriginalDockIcon(
                    for: vendor,
                    preferredSourceURL: candidate.app.bundleURL
                )
                switch outcome {
                case .some(.added), .some(.alreadyPresent):
                    originalDockOutcome = outcome
                default:
                    DispatchQueue.main.async {
                        self.finishAppProfileLifecycle()
                        self.appProfilesView.setStatus(
                            "App Profile was not created.", color: .systemRed
                        )
                        self.appProfilesView.setOriginalDockPinned(self.originalDockPinStates())
                        self.showAppProfileAlert(
                            title: "Dock icon is required",
                            message: "Klik PRO could not create the required Dock icon "
                                + "for native \(vendorName ?? "app"). This can happen if an item "
                                + "already exists at \(vendor.originalDockLauncherPath) that isn't a "
                                + "Klik PRO launcher — remove it and try again. The App Profile was "
                                + "not created."
                        )
                    }
                    return
                }
            }
            do {
                let result = try self.appProfileManager.create(
                    from: candidate,
                    label: requestedName,
                    config: currentConfig
                )
                let dockResult = request.addLauncherToDock
                    ? Self.addLauncherToDock(URL(fileURLWithPath: result.instance.launcherPath, isDirectory: true))
                    : DockPinResult.notRequested
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.appProfilesView.setOriginalDockPinned(self.originalDockPinStates())
                    let dockSuffix: String
                    switch dockResult {
                    case .notRequested:
                        dockSuffix = ""
                    case .added:
                        dockSuffix = " Added to Dock."
                    case .alreadyPresent:
                        dockSuffix = " Already in Dock."
                    case .failed:
                        dockSuffix = " Dock icon was not added."
                    }
                    let originalSuffix = originalDockOutcome == .added
                        ? " Dock icon for native \(vendorName ?? "app") added."
                        : ""
                    self.appProfilesView.setStatus(
                        applied
                            ? "\(result.instance.label) was generated and opened.\(dockSuffix)\(originalSuffix)"
                            : "\(result.instance.label) was generated; helper apply is pending.\(dockSuffix)\(originalSuffix)",
                        color: applied && dockResult != .failed ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                    self.launchAppProfile(result.instance)
                    self.needsDisplay = true
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not created.", color: .systemRed)
                    self.showAppProfileAlert(
                        title: "App Profile was not created",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not created.", color: .systemRed)
                }
            }
        }
    }

    private func nextDualAppName(for candidate: AppProfileCandidate) -> String {
        let base = candidate.app.bundleIdentifier == "com.openai.codex"
            ? "ChatGPT"
            : candidate.app.displayName
        let hasNamedChatGPTProfiles = persistedConfig.instances.contains {
            $0.source.bundleIdentifier.hasPrefix("local.chatgpt.")
        }
        let matchingCount = persistedConfig.instances.filter { instance in
            if base == "ChatGPT",
               hasNamedChatGPTProfiles,
               instance.legacyQuickLaunchTarget == .chatGPT {
                return false
            }
            return instance.label.localizedCaseInsensitiveContains(base)
                || instance.source.bundleURL == candidate.app.bundleURL.path
                || (base == "ChatGPT" && instance.source.bundleIdentifier.hasPrefix("local.chatgpt."))
                || (base == "Claude" && instance.source.bundleIdentifier.hasPrefix("local.claude."))
        }.count
        return "\(base) \(matchingCount + 1)"
    }

    private struct DualAppNameRequest {
        let name: String
        let addLauncherToDock: Bool
    }

    private enum DockPinResult: Equatable {
        case notRequested
        case added
        case alreadyPresent
        case failed
    }

    private enum DockRenameResult: Equatable {
        case notPresent
        case updated
        case failed
    }

    /// True when a Klik PRO original-app launcher tile for `target` is currently
    /// pinned in the Dock. Pin state is read from the Dock itself (no persisted
    /// flag), so the App Profiles card checkbox always reflects reality.
    private func originalDockIconIsPinned(for target: QuickLaunchTarget) -> Bool {
        let launcherPath = URL(
            fileURLWithPath: target.originalDockLauncherPath,
            isDirectory: true
        ).standardizedFileURL.path
        return Self.dockPersistentAppsContain(path: launcherPath)
    }

    /// Ensures the original-app launcher exists and its tile is pinned in the Dock.
    /// Append-only: it never rewrites or removes the user's native vendor tile, and
    /// it is idempotent (a second call returns `.alreadyPresent`). Returns nil only
    /// when the launcher could not be created (e.g. a stale non-Klik-PRO item squats
    /// the launcher path) — the caller decides how to surface that.
    @discardableResult
    private func ensureOriginalDockIcon(
        for target: QuickLaunchTarget,
        preferredSourceURL: URL? = nil
    ) -> DockPinResult? {
        guard let launcherURL = Self.ensureOriginalDockLauncher(
            for: target,
            preferredSourceURL: preferredSourceURL
        ) else {
            return nil
        }
        return Self.addLauncherToDock(launcherURL)
    }

    /// Removes Klik PRO's badged original-app launcher: it unpins the tile (if the
    /// user still has it in the Dock), then deletes the generated launcher bundle and
    /// its Launch Services registration so no artifact is left behind. Works even when
    /// the tile was manually unpinned but the bundle still lingers on disk. Only ever
    /// touches a bundle that passes the strict `originalDockLauncherIsValid` check —
    /// never the native vendor app. Returns whether anything was actually removed.
    @discardableResult
    private func removeOriginalDockIcon(for target: QuickLaunchTarget) -> Bool {
        let launcherURL = URL(
            fileURLWithPath: target.originalDockLauncherPath,
            isDirectory: true
        ).standardizedFileURL
        let wasPinned = Self.dockPersistentAppsContain(path: launcherURL.path)
        Self.removeDockLauncherIfPresent(launcherURL)
        guard Self.originalDockLauncherIsValid(launcherURL, target: target) else {
            return wasPinned
        }
        Self.unregisterLaunchServicesRegistration(forOriginalDockLauncher: launcherURL)
        try? FileManager.default.removeItem(at: launcherURL)
        return true
    }

    private func originalVendorName(_ target: QuickLaunchTarget) -> String {
        URL(fileURLWithPath: target.standardApplicationPath)
            .deletingPathExtension().lastPathComponent
    }

    /// Bundle URL of the currently-discovered vendor candidate for `target`, if any.
    /// Lets the gear-menu Dock icon be sourced from the exact install App Profiles
    /// were discovered from — including one outside `/Applications`.
    private func candidateBundleURL(for target: QuickLaunchTarget) -> URL? {
        supportedAppCandidateCache?.first {
            $0.app.bundleIdentifier == target.applicationBundleIdentifier
        }?.app.bundleURL
    }

    /// Gear → "Create Dock Icon" on the App Profiles tab. Creates the badged
    /// original-app launcher and pins it. If one already exists, confirms a replace
    /// (delete + recreate) first. Never touches the native vendor Dock tile.
    private func createOriginalDockIcon(for target: QuickLaunchTarget) {
        let vendorName = originalVendorName(target)
        let preferredSourceURL = candidateBundleURL(for: target)
        // Confirm a replace on the main thread (NSAlert must run there) before the
        // slow work is dispatched off the UI thread.
        let replaceExisting: Bool
        if originalDockIconIsPinned(for: target) {
            let alert = NSAlert()
            alert.messageText = "Replace \(vendorName)'s Dock icon?"
            alert.informativeText = "A Klik PRO Dock icon for native \(vendorName) already "
                + "exists. Replace it with a fresh one? Your built-in \(vendorName) Dock icon is "
                + "not affected."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            replaceExisting = true
        } else {
            replaceExisting = false
        }
        // The badge render, ad-hoc codesign and Launch Services registration are slow
        // enough to freeze the window; run them on the App Profile queue (serialized
        // with generation so Dock mutations never overlap) and hop back to main only
        // for the status/alert/pin-state UI.
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            if replaceExisting {
                self.removeOriginalDockIcon(for: target)
            }
            let outcome = self.ensureOriginalDockIcon(
                for: target,
                preferredSourceURL: preferredSourceURL
            )
            DispatchQueue.main.async {
                switch outcome {
                case .some(.added), .some(.alreadyPresent):
                    self.saveStatusMessage = "Added a Dock icon for native \(vendorName)."
                default:
                    self.showAppProfileAlert(
                        title: "Dock icon was not created",
                        message: "Klik PRO could not create the Dock icon for native "
                            + "\(vendorName). This can happen if an item already exists at "
                            + "\(target.originalDockLauncherPath) that isn't a Klik PRO launcher — "
                            + "remove it and try again."
                    )
                }
                self.appProfilesView.setOriginalDockPinned(self.originalDockPinStates())
                self.needsDisplay = true
            }
        }
    }

    /// Gear → "Delete Dock Icon" on the App Profiles tab. Removes Klik PRO's original
    /// launcher tile and its generated bundle. The native vendor Dock tile is left
    /// untouched.
    private func deleteOriginalDockIcon(for target: QuickLaunchTarget) {
        let vendorName = originalVendorName(target)
        // Per product decision, deleting the Dock icon also clears the app's
        // menu-bar pin. When it does, this modifies persisted config, so it takes the
        // same save/apply path and unsaved-edits guards as the menu-bar toggle.
        let clearsMenuBarPin = persistedConfig.menuBarPinnedOriginals.contains(target)
        if clearsMenuBarPin {
            guard !saveInProgress, !appProfileLifecycleInProgress else {
                showAppProfileAlert(
                    title: "Please wait",
                    message: "Finish the current Save or App Profile change before removing this Dock icon."
                )
                return
            }
            guard !hasUnsavedConfigurationChanges else {
                showAppProfileAlert(
                    title: "Save current changes first",
                    message: "Save or restore the current mapping changes before removing this Dock icon."
                )
                return
            }
            appProfileLifecycleInProgress = true
            saveButton.isEnabled = false
        }
        var updated = persistedConfig
        updated.menuBarPinnedOriginals.remove(target)
        let previous = persistedConfig
        // Removing the launcher bundle and its Launch Services registration touches the
        // filesystem and runs `defaults`/`killall Dock`; keep it off the UI thread. The
        // menu-bar un-pin persists config and restarts the helper so its icon clears too.
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let removed = self.removeOriginalDockIcon(for: target)
            var configSaved = false
            if clearsMenuBarPin {
                configSaved = KlikProConfigStore.save(updated)
                if configSaved { _ = applySavedConfig() }
            }
            DispatchQueue.main.async {
                if clearsMenuBarPin {
                    self.appProfileLifecycleInProgress = false
                    self.saveButton.isEnabled = !self.saveInProgress
                    if configSaved {
                        self.config = updated
                        self.persistedConfig = updated
                    } else {
                        self.config = previous
                        self.persistedConfig = previous
                    }
                }
                self.saveStatusMessage = removed
                    ? "Removed \(vendorName)'s Dock icon."
                    : "No Klik PRO Dock icon for \(vendorName) to remove."
                self.appProfilesView.setOriginalDockPinned(self.originalDockPinStates())
                self.appProfilesView.setOriginalMenuBarPinned(self.originalMenuBarPinStates())
                self.needsDisplay = true
            }
        }
    }

    /// Removes the NATIVE vendor app's own Dock tile (ChatGPT/Claude), leaving the app
    /// installed and launchable from Launchpad, Finder, or Klik PRO's own Dock icon.
    /// Offered only once Klik PRO's own Dock icon exists (so a working Dock launcher
    /// remains) and confirmed first because it changes the user's Dock — it is
    /// reversible by dragging the app back from Launchpad/Finder.
    private func removeNativeOriginalDockTile(for target: QuickLaunchTarget) {
        let vendorName = originalVendorName(target)
        guard originalDockIconIsPinned(for: target) else {
            showAppProfileAlert(
                title: "Create Klik PRO's Dock icon first",
                message: "Add Klik PRO's Dock icon for \(vendorName) before removing the native "
                    + "app's Dock icon, so you keep a working Dock launcher."
            )
            return
        }
        let alert = NSAlert()
        alert.messageText = "Remove \(vendorName)'s own Dock icon?"
        alert.informativeText = "This removes only \(vendorName)'s native Dock tile. \(vendorName) "
            + "stays installed and can still be opened from Launchpad, Finder, or Klik PRO's Dock icon."
        alert.addButton(withTitle: "Remove from Dock")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let nativeURL = URL(fileURLWithPath: target.standardApplicationPath, isDirectory: true)
        // Touches the Dock plist and runs `killall Dock`; keep it off the UI thread.
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let absent = Self.removeDockLauncherIfPresent(nativeURL)
            DispatchQueue.main.async {
                self.saveStatusMessage = absent
                    ? "Removed \(vendorName)'s native Dock icon. It's still in Launchpad."
                    : "Could not remove \(vendorName)'s native Dock icon."
                self.needsDisplay = true
            }
        }
    }

    /// Current pin state of both original-app Dock icons, for the App Profiles cards.
    private func originalDockPinStates() -> [QuickLaunchTarget: Bool] {
        var states: [QuickLaunchTarget: Bool] = [:]
        for target in QuickLaunchTarget.allCases {
            states[target] = originalDockIconIsPinned(for: target)
        }
        return states
    }

    /// Current persisted menu-bar pin state of both original apps, for the cards.
    private func originalMenuBarPinStates() -> [QuickLaunchTarget: Bool] {
        var states: [QuickLaunchTarget: Bool] = [:]
        for target in QuickLaunchTarget.allCases {
            states[target] = persistedConfig.menuBarPinnedOriginals.contains(target)
        }
        return states
    }

    /// Card "Menu Bar Icon" toggle for an original app: flips whether ChatGPT/Claude
    /// shows its own menu-bar icon (which opens the original app) and persists it, then
    /// restarts the helper so the change takes effect. Mirrors the per-instance App
    /// Profile menu-bar toggle, including its save/apply and unsaved-edits guards.
    private func toggleOriginalMenuBarPin(for target: QuickLaunchTarget) {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before changing menu-bar visibility."
            )
            appProfilesView.setOriginalMenuBarPinned(originalMenuBarPinStates())
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before changing menu-bar visibility."
            )
            appProfilesView.setOriginalMenuBarPinned(originalMenuBarPinStates())
            return
        }

        let vendorName = originalVendorName(target)
        var updated = persistedConfig
        let willPin = !updated.menuBarPinnedOriginals.contains(target)
        if willPin {
            updated.menuBarPinnedOriginals.insert(target)
        } else {
            updated.menuBarPinnedOriginals.remove(target)
        }
        let previous = persistedConfig
        appProfileLifecycleInProgress = true
        saveButton.isEnabled = false
        appProfilesView.setStatus(
            willPin
                ? "Showing native \(vendorName) in the menu bar…"
                : "Hiding native \(vendorName) from the menu bar…",
            color: .appTextSecondary
        )
        needsDisplay = true

        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let saved = KlikProConfigStore.save(updated)
            let applied = saved && applySavedConfig()
            DispatchQueue.main.async {
                self.appProfileLifecycleInProgress = false
                self.saveButton.isEnabled = !self.saveInProgress
                if saved {
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setStatus(
                        willPin
                            ? "Native \(vendorName) will show in the menu bar."
                            : "Native \(vendorName) will not show in the menu bar.",
                        color: applied ? .systemGreen : .systemOrange
                    )
                } else {
                    self.config = previous
                    self.persistedConfig = previous
                    self.appProfilesView.setStatus(
                        "Menu bar setting was not changed.",
                        color: .systemRed
                    )
                    self.showAppProfileAlert(
                        title: "Menu bar setting was not changed",
                        message: "Klik PRO could not save the menu-bar change for native "
                            + "\(vendorName)."
                    )
                }
                self.appProfilesView.setOriginalMenuBarPinned(self.originalMenuBarPinStates())
                self.needsDisplay = true
            }
        }
    }

    private func requestDualAppName(
        title: String,
        informativeText: String,
        initialValue: String,
        actionTitle: String,
        excludingInstanceID: UUID? = nil
    ) -> String? {
        requestDualAppNameOptions(
            title: title,
            informativeText: informativeText,
            initialValue: initialValue,
            actionTitle: actionTitle,
            excludingInstanceID: excludingInstanceID,
            allowDockOption: false
        )?.name
    }

    private func requestDualAppNameOptions(
        title: String,
        informativeText: String,
        initialValue: String,
        actionTitle: String,
        excludingInstanceID: UUID? = nil,
        allowDockOption: Bool,
        forcedOriginalDockVendorName: String? = nil
    ) -> DualAppNameRequest? {
        let field = NSTextField(string: initialValue)
        let profileDockCheckbox = NSButton(
            checkboxWithTitle: "Add a Dock icon for this App Profile", target: nil, action: nil
        )
        profileDockCheckbox.state = .off

        let accessory: NSView
        if allowDockOption {
            let width: CGFloat = 340
            let rowHeight: CGFloat = 22
            let gap: CGFloat = 6
            let fieldHeight: CGFloat = 26
            // Bottom-up layout (NSView is not flipped): profile checkbox lowest, then
            // the locked original-app checkbox, then the name field on top.
            var y: CGFloat = 0
            profileDockCheckbox.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
            y += rowHeight + gap
            var originalDockCheckbox: NSButton?
            if let vendorName = forcedOriginalDockVendorName {
                // Shown checked and disabled: Klik PRO always creates this icon, and
                // the user cannot turn it off. It exists purely to make the guarantee
                // visible each time a profile is generated.
                let checkbox = NSButton(
                    checkboxWithTitle: "Add a Dock icon for native \(vendorName)  ·  always on",
                    target: nil, action: nil
                )
                checkbox.state = .on
                checkbox.isEnabled = false
                checkbox.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
                y += rowHeight + gap
                originalDockCheckbox = checkbox
            }
            field.frame = NSRect(x: 0, y: y, width: width, height: fieldHeight)
            y += fieldHeight
            let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: y))
            view.addSubview(field)
            view.addSubview(profileDockCheckbox)
            if let originalDockCheckbox { view.addSubview(originalDockCheckbox) }
            accessory = view
        } else {
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
            accessory = field
        }
        field.selectText(nil)
        let alert = NSAlert()
        alert.messageText = title
        var info = informativeText
        if let vendorName = forcedOriginalDockVendorName {
            info += "\n\nKlik PRO always keeps a dedicated Dock icon for native "
                + "\(vendorName): once an App Profile is running, \(vendorName)'s built-in "
                + "Dock icon can no longer reopen the native app."
        }
        alert.informativeText = info
        alert.accessoryView = accessory
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showAppProfileAlert(title: "Enter a name", message: "The App Profile name cannot be empty.")
            return nil
        }
        guard !persistedConfig.instances.contains(where: {
            $0.id != excludingInstanceID && $0.label.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            showAppProfileAlert(
                title: "That name is already used",
                message: "Choose a unique name so icons and button assignments stay clear."
            )
            return nil
        }
        return DualAppNameRequest(
            name: name,
            addLauncherToDock: allowDockOption && profileDockCheckbox.state == .on
        )
    }

    private static func addLauncherToDock(_ launcherURL: URL) -> DockPinResult {
        let launcherPath = launcherURL.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: launcherPath) else { return .failed }
        if dockPersistentAppsContain(path: launcherPath) { return .alreadyPresent }

        let dockEntry = """
        <dict>
          <key>tile-data</key>
          <dict>
            <key>file-data</key>
            <dict>
              <key>_CFURLString</key>
              <string>\(xmlEscaped(launcherPath))</string>
              <key>_CFURLStringType</key>
              <integer>0</integer>
            </dict>
            <key>file-label</key>
            <string>\(xmlEscaped(launcherURL.deletingPathExtension().lastPathComponent))</string>
          </dict>
          <key>tile-type</key>
          <string>file-tile</string>
        </dict>
        """

        guard runProcess("/usr/bin/defaults", [
            "write", "com.apple.dock", "persistent-apps", "-array-add", dockEntry
        ]) == 0 else {
            return .failed
        }
        _ = runProcess("/usr/bin/killall", ["Dock"])
        return dockPersistentAppsContain(path: launcherPath) ? .added : .failed
    }

    /// Resolves the installed vendor `.app` to source the original-app Dock icon
    /// from, tolerating installs outside `/Applications` (e.g. `~/Applications`).
    /// Prefers an explicit `preferred` bundle URL — the App Profile candidate's
    /// already-validated install, so the icon is sourced from the very app the
    /// profile is built from — then the standard-path probe, then a Launch Services
    /// lookup by bundle identifier. The last branch is skipped while rendering
    /// deterministic previews so a snapshot never consults live services.
    private static func originalDockIconSourceURL(
        for target: QuickLaunchTarget,
        preferred: URL?
    ) -> URL? {
        let fileManager = FileManager.default
        if let preferred,
           preferred.pathExtension.lowercased() == "app",
           fileManager.fileExists(atPath: preferred.standardizedFileURL.path) {
            return preferred
        }
        if let standard = quickLaunchTargetApplicationURL(target) {
            return standard
        }
        if !previewRenderingIsActive,
           let resolved = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.applicationBundleIdentifier
           ),
           resolved.pathExtension.lowercased() == "app",
           fileManager.fileExists(atPath: resolved.path) {
            return resolved
        }
        return nil
    }

    private static func ensureOriginalDockLauncher(
        for target: QuickLaunchTarget,
        preferredSourceURL: URL?
    ) -> URL? {
        guard let sourceURL = originalDockIconSourceURL(for: target, preferred: preferredSourceURL),
              let runnerURL = Bundle.main.url(
                forResource: "KlikProOriginalLauncher",
                withExtension: nil
              ) else {
            return nil
        }
        let fileManager = FileManager.default
        let launcherURL = URL(
            fileURLWithPath: target.originalDockLauncherPath,
            isDirectory: true
        ).standardizedFileURL
        if originalDockLauncherIsValid(launcherURL, target: target) {
            return launcherURL
        }
        if fileManager.fileExists(atPath: launcherURL.path) {
            return nil
        }

        let parentURL = launcherURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appendingPathComponent(
            "." + launcherURL.deletingPathExtension().lastPathComponent
                + ".tmp-" + UUID().uuidString + ".app",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let parentValues = try parentURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard parentValues.isDirectory == true,
                  parentValues.isSymbolicLink != true,
                  parentURL.resolvingSymlinksInPath() == parentURL else {
                return nil
            }

            let contentsURL = temporaryURL.appendingPathComponent("Contents", isDirectory: true)
            let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
            let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
            try fileManager.createDirectory(
                at: macOSURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try fileManager.createDirectory(
                at: resourcesURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )

            let copiedRunner = macOSURL.appendingPathComponent(
                "KlikProOriginalLauncher",
                isDirectory: false
            )
            try fileManager.copyItem(at: runnerURL, to: copiedRunner)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: copiedRunner.path
            )

            let iconDestination = resourcesURL.appendingPathComponent(
                "AppIcon.icns", isDirectory: false
            )
            // Badge the vendor icon (green disc + white star, top-left) so the
            // original-app Dock tile is distinguishable from the native vendor tile
            // and from profile tiles. Fall back to the plain vendor icon if the
            // badge pipeline fails, so the tile never ends up generic.
            let copiedIcon = writeBadgedOriginalIcon(from: sourceURL, to: iconDestination)
                || copyDeclaredBundleIcon(from: sourceURL, to: iconDestination)
            var info: [String: Any] = [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": sourceURL.deletingPathExtension().lastPathComponent,
                "CFBundleExecutable": "KlikProOriginalLauncher",
                "CFBundleIdentifier": target.originalDockLauncherBundleIdentifier,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": sourceURL.deletingPathExtension().lastPathComponent,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "13.0",
                "LSUIElement": true,
                "NSAppleEventsUsageDescription": LauncherGenerator.appleEventsUsageDescription,
            ]
            if copiedIcon { info["CFBundleIconFile"] = "AppIcon" }
            let infoData = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try infoData.write(
                to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false),
                options: .atomic
            )
            guard runProcess("/usr/bin/codesign", [
                "--force", "--sign", "-", "--timestamp=none", temporaryURL.path
            ]) == 0 else {
                try? fileManager.removeItem(at: temporaryURL)
                return nil
            }
            try fileManager.moveItem(at: temporaryURL, to: launcherURL)
            refreshLaunchServicesRegistration(forOriginalDockLauncher: launcherURL)
            return launcherURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return nil
        }
    }

    private static func originalDockLauncherIsValid(
        _ launcherURL: URL,
        target: QuickLaunchTarget
    ) -> Bool {
        let fileManager = FileManager.default
        guard launcherURL.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: launcherURL.path) else {
            return false
        }
        // Read Info.plist straight from disk rather than via Bundle(url:), which caches
        // one Bundle per URL for the life of the process. A validity check made before
        // the bundle was materialized would otherwise poison that cache, so a freshly
        // created — and genuinely valid — launcher reads back as invalid on the next
        // check (the false "item already exists that isn't a Klik PRO launcher" error,
        // which also wrongly blocks profile creation).
        let infoURL = launcherURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any],
              info["CFBundleIdentifier"] as? String == target.originalDockLauncherBundleIdentifier,
              info["CFBundlePackageType"] as? String == "APPL",
              info["CFBundleExecutable"] as? String == "KlikProOriginalLauncher" else {
            return false
        }
        // Symlink guard so a later removeItem only ever deletes a real bundle we own,
        // never a link pointing elsewhere. A path-value check avoids the brittle
        // URL-equality (trailing slash, /private) that resolvingSymlinksInPath invites.
        let bundleIsSymlink = (try? launcherURL.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        ))?.isSymbolicLink == true
        guard !bundleIsSymlink else { return false }
        let executableURL = launcherURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("KlikProOriginalLauncher", isDirectory: false)
        let values = try? executableURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        return values?.isRegularFile == true
            && values?.isSymbolicLink != true
            && fileManager.isExecutableFile(atPath: executableURL.path)
    }

    @discardableResult
    private static func copyDeclaredBundleIcon(from sourceURL: URL, to destinationURL: URL) -> Bool {
        let infoURL = sourceURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              var iconName = info["CFBundleIconFile"] as? String,
              !iconName.isEmpty else {
            return false
        }
        if (iconName as NSString).pathExtension.isEmpty { iconName += ".icns" }
        guard (iconName as NSString).lastPathComponent == iconName else { return false }
        let iconURL = sourceURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(iconName, isDirectory: false)
        do {
            // Clear any partial file a prior (failed) icon copy may have left, so this
            // plain-icon fallback isn't defeated by a "file already exists" error.
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: iconURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    /// Resolves the vendor app's declared `.icns`, then writes a badged `.icns` to
    /// `destinationURL`: the vendor icon with a brand-green disc + white star drawn
    /// top-left, rendered per size so it stays crisp at Dock resolution. Pure
    /// CoreGraphics/ImageIO + `iconutil` (no AppKit drawing), so it is safe to run on
    /// the background App Profile queue. Writes `destinationURL` only on full success;
    /// returns false (leaving no partial file) so the caller can fall back to the
    /// plain vendor icon.
    @discardableResult
    private static func writeBadgedOriginalIcon(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard let baseImage = largestDeclaredIconImage(in: sourceURL) else { return false }
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        // iconutil file name → pixel size (points@scale).
        let iconsetFiles: [(name: String, size: Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        let fileManager = FileManager.default
        let scratchURL = fileManager.temporaryDirectory.appendingPathComponent(
            "klik-pro-original-icon-" + UUID().uuidString, isDirectory: true
        )
        let iconsetURL = scratchURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        let outputURL = scratchURL.appendingPathComponent("AppIcon.icns", isDirectory: false)
        defer { try? fileManager.removeItem(at: scratchURL) }
        do {
            try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
            var rendered: [Int: CGImage] = [:]
            for size in sizes {
                guard let image = badgedIconImage(base: baseImage, pixelSize: size) else {
                    return false
                }
                rendered[size] = image
            }
            for entry in iconsetFiles {
                guard let image = rendered[entry.size],
                      writePNG(image, to: iconsetURL.appendingPathComponent(entry.name, isDirectory: false))
                else {
                    return false
                }
            }
            guard runProcess("/usr/bin/iconutil", [
                "-c", "icns", iconsetURL.path, "-o", outputURL.path
            ]) == 0,
            fileManager.fileExists(atPath: outputURL.path) else {
                return false
            }
            // Drop any leftover partial file first so a retry or the caller's
            // plain-icon fallback isn't blocked by a "file already exists" error.
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: outputURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    /// Largest representation of the source app's declared `.icns`, read with
    /// ImageIO (thread-safe, no AppKit). Returns nil when the app has no readable
    /// `CFBundleIconFile` icns (the badge step then declines and the caller falls
    /// back to a plain copy).
    private static func largestDeclaredIconImage(in sourceURL: URL) -> CGImage? {
        let infoURL = sourceURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any],
              var iconName = info["CFBundleIconFile"] as? String,
              !iconName.isEmpty else {
            return nil
        }
        if (iconName as NSString).pathExtension.isEmpty { iconName += ".icns" }
        guard (iconName as NSString).lastPathComponent == iconName else { return nil }
        let iconURL = sourceURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(iconName, isDirectory: false)
        guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var best: CGImage?
        var bestWidth = 0
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            if image.width > bestWidth {
                best = image
                bestWidth = image.width
            }
        }
        return best
    }

    /// Composites the base icon at `pixelSize` with the brand-green star badge in the
    /// top-left corner. All drawing is CoreGraphics into an offscreen bitmap.
    private static func badgedIconImage(base: CGImage, pixelSize: Int) -> CGImage? {
        let size = CGFloat(pixelSize)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Badge geometry: a disc in the top-left (CoreGraphics is y-up, so "top" is
        // high y). Sized ~32% of the icon so it reads at Dock scale.
        let discDiameter = size * 0.32
        let discRadius = discDiameter / 2
        let inset = size * 0.06
        let center = CGPoint(x: inset + discRadius, y: size - inset - discRadius)

        // White separator ring so the badge stays legible on any underlying icon.
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: center.x - discRadius - size * 0.012,
            y: center.y - discRadius - size * 0.012,
            width: discDiameter + size * 0.024,
            height: discDiameter + size * 0.024
        ))
        // Brand-green disc (#19BB13).
        context.setFillColor(CGColor(srgbRed: 25 / 255, green: 187 / 255, blue: 19 / 255, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: center.x - discRadius, y: center.y - discRadius,
            width: discDiameter, height: discDiameter
        ))
        // White five-pointed star centered in the disc.
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(starPath(center: center, outerRadius: discRadius * 0.62))
        context.fillPath()

        return context.makeImage()
    }

    /// A five-pointed star centered at `center`, first point up. `innerRadius`
    /// defaults to 0.40× the outer radius (the classic star proportion).
    private static func starPath(center: CGPoint, outerRadius: CGFloat) -> CGPath {
        let innerRadius = outerRadius * 0.40
        let path = CGMutablePath()
        for index in 0..<10 {
            let radius = index % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func refreshLaunchServicesRegistration(
        forOriginalDockLauncher launcherURL: URL
    ) {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        )
        process.arguments = ["-f", launcherURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private static func unregisterLaunchServicesRegistration(
        forOriginalDockLauncher launcherURL: URL
    ) {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        )
        process.arguments = ["-u", launcherURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Resolves a Dock entry's stored `_CFURLString` to a filesystem path. The
    /// Dock persists it as a percent-encoded file URL (e.g.
    /// `file:///Users/.../Klik%20PRO/Claude%20A.app/`), so it must be parsed as a
    /// URL — a raw substring/path comparison misses every launcher whose name
    /// contains a space (all of them). Falls back to treating it as a plain path.
    private static func dockEntryFilePath(_ storedString: String) -> String? {
        if let url = URL(string: storedString), url.isFileURL {
            return url.standardizedFileURL.path
        }
        return URL(fileURLWithPath: storedString).standardizedFileURL.path
    }

    private static func dockPersistentAppsContain(path launcherPath: String) -> Bool {
        // Read via the `defaults` subprocess (always current) rather than
        // CFPreferencesCopyAppValue, which can hand a long-running process a
        // stale cached snapshot of another app's domain. Match against the
        // Dock's own storage form — a percent-encoded file URL for the .app
        // directory (e.g. `file:///Users/.../Klik%20PRO/Claude%20T.app/`) — so a
        // launcher whose name has a space (all of them) is still found; a raw
        // path substring never matches.
        let encoded = URL(fileURLWithPath: launcherPath, isDirectory: true)
            .standardizedFileURL.absoluteString
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "persistent-apps"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0,
              let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
              ) else {
            return false
        }
        return output.contains(encoded)
    }

    /// Returns missing Dock tiles that point into Klik PRO's exact managed
    /// launcher directory. The bundle must already be absent: live launchers,
    /// arbitrary apps elsewhere, and malformed/non-file Dock entries are never
    /// offered for cleanup.
    private static func staleKlikProDockTilePaths() -> [String] {
        let managedRoot = URL(
            fileURLWithPath: NSHomeDirectory(), isDirectory: true
        )
        .appendingPathComponent("Applications/Klik PRO", isDirectory: true)
        .standardizedFileURL
        let appID = "com.apple.dock" as CFString
        guard let rawEntries = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            appID
        ) as? [[String: Any]] else {
            return []
        }

        var paths = Set<String>()
        for entry in rawEntries {
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let storedPath = fileData["_CFURLString"] as? String,
                  let path = dockEntryFilePath(storedPath) else {
                continue
            }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard url.pathExtension.lowercased() == "app",
                  url.deletingLastPathComponent() == managedRoot,
                  !FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            paths.insert(url.path)
        }
        return paths.sorted()
    }

    private static func renameDockLauncherIfPresent(
        from previousURL: URL,
        to updatedURL: URL
    ) -> DockRenameResult {
        let previousPath = previousURL.standardizedFileURL.path
        let updatedPath = updatedURL.standardizedFileURL.path
        guard previousPath != updatedPath else { return .notPresent }

        let appID = "com.apple.dock" as CFString
        guard let rawEntries = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            appID
        ) as? [[String: Any]] else {
            return .notPresent
        }
        var entries = rawEntries
        var found = false
        for index in entries.indices {
            guard var tileData = entries[index]["tile-data"] as? [String: Any],
                  var fileData = tileData["file-data"] as? [String: Any],
                  let storedPath = fileData["_CFURLString"] as? String,
                  dockEntryFilePath(storedPath) == previousPath else {
                continue
            }
            fileData["_CFURLString"] = updatedPath
            fileData["_CFURLStringType"] = 0
            tileData["file-data"] = fileData
            tileData["file-label"] = updatedURL.deletingPathExtension().lastPathComponent
            entries[index]["tile-data"] = tileData
            found = true
        }
        guard found else { return .notPresent }

        CFPreferencesSetAppValue(
            "persistent-apps" as CFString,
            entries as CFArray,
            appID
        )
        guard CFPreferencesAppSynchronize(appID) else { return .failed }
        _ = runProcess("/usr/bin/killall", ["Dock"])
        return dockPersistentAppsContain(path: updatedPath) ? .updated : .failed
    }

    /// Removes a removed managed launcher's pinned Dock tile, if the user pinned
    /// one, so a deleted profile does not leave a stale/broken Dock icon. Matches
    /// the same percent-encoded path logic as the rename rewrite. No-op when no
    /// tile references the path.
    @discardableResult
    private static func removeDockLauncherIfPresent(_ launcherURL: URL) -> Bool {
        let targetPath = launcherURL.standardizedFileURL.path
        let appID = "com.apple.dock" as CFString
        guard let rawEntries = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            appID
        ) as? [[String: Any]] else {
            return false
        }
        var removed = false
        let filtered = rawEntries.filter { entry in
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let storedPath = fileData["_CFURLString"] as? String,
                  dockEntryFilePath(storedPath) == targetPath else {
                return true
            }
            removed = true
            return false
        }
        guard removed else { return true }
        CFPreferencesSetAppValue("persistent-apps" as CFString, filtered as CFArray, appID)
        guard CFPreferencesAppSynchronize(appID) else { return false }
        _ = runProcess("/usr/bin/killall", ["Dock"])
        return !dockPersistentAppsContain(path: targetPath)
    }

    /// Clears the macOS launcher registration left behind after a managed profile
    /// is removed (Delete Data or Remove from Klik PRO): the pinned Dock tile and
    /// the Launch Services / Launchpad entry. Best-effort and idempotent.
    private func cleanupRemovedLauncherRegistration(launcherPath: String) {
        guard !launcherPath.isEmpty else { return }
        let url = URL(fileURLWithPath: launcherPath, isDirectory: true)
        Self.removeDockLauncherIfPresent(url)
        appProfileManager.unregisterLauncherFromLaunchServices(at: url)
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func toggleMenuBarPin(for instance: AppProfileInstance) {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before changing menu-bar visibility."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before changing menu-bar visibility."
            )
            return
        }

        var updated = persistedConfig
        guard let index = updated.instances.firstIndex(where: { $0.id == instance.id }) else { return }
        let newValue = !updated.instances[index].pinToMenuBar
        updated.instances[index].pinToMenuBar = newValue
        let previous = persistedConfig
        appProfileLifecycleInProgress = true
        saveButton.isEnabled = false
        appProfilesView.setInstances(updated.instances)
        appProfilesView.setStatus(
            newValue
                ? "Showing \(instance.label) in the menu bar…"
                : "Hiding \(instance.label) from the menu bar…",
            color: .appTextSecondary
        )
        needsDisplay = true

        appProfileQueue.async { [weak self] in
            guard let self else { return }
            let saved = KlikProConfigStore.save(updated)
            let applied = saved && applySavedConfig()
            DispatchQueue.main.async {
                self.appProfileLifecycleInProgress = false
                self.saveButton.isEnabled = !self.saveInProgress
                if saved {
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    self.appProfilesView.setStatus(
                        newValue
                            ? "\(instance.label) will show in the menu bar."
                            : "\(instance.label) will not show in the menu bar.",
                        color: applied ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                } else {
                    self.config = previous
                    self.persistedConfig = previous
                    self.appProfilesView.setInstances(previous.instances)
                    self.appProfilesView.setStatus(
                        "Menu bar setting was not changed.",
                        color: .systemRed
                    )
                    self.showAppProfileAlert(
                        title: "Menu bar setting was not changed",
                        message: "Klik PRO could not save the menu-bar setting for \(instance.label)."
                    )
                }
                self.needsDisplay = true
            }
        }
    }

    private func renameAppProfile(_ instance: AppProfileInstance) {
        guard instance.launcherKind == .managed,
              let name = requestDualAppName(
                title: "Rename \(instance.label)",
                informativeText: "Only the displayed name and generated icon change. Login and profile data stay in place.",
                initialValue: instance.label,
                actionTitle: "Rename",
                excludingInstanceID: instance.id
              ) else { return }
        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        let previousLauncherURL = URL(
            fileURLWithPath: instance.launcherPath,
            isDirectory: true
        )
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.appProfileManager.updateManagedInstance(
                    instanceID: instance.id,
                    label: name,
                    menuColor: instance.menuColor,
                    pinToMenuBar: instance.pinToMenuBar,
                    hotkey: instance.hotkey,
                    mouseButton: instance.mouseButton,
                    config: currentConfig
                )
                let updatedInstance = updated.instances.first { $0.id == instance.id }
                let dockRenameResult = updatedInstance.map {
                    Self.renameDockLauncherIfPresent(
                        from: previousLauncherURL,
                        to: URL(fileURLWithPath: $0.launcherPath, isDirectory: true)
                    )
                } ?? .notPresent
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    let dockSuffix = dockRenameResult == .failed
                        ? " The Dock icon could not be refreshed; remove the old tile and add the renamed launcher again."
                        : ""
                    self.appProfilesView.setStatus(
                        applied
                            ? "Renamed to \(name).\(dockSuffix)"
                            : "Renamed; helper apply is pending.\(dockSuffix)",
                        color: applied && dockRenameResult != .failed ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.showAppProfileAlert(
                        title: "App Profile was not renamed",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func changeAppProfileIcon(_ instance: AppProfileInstance) {
        guard instance.launcherKind == .managed else { return }
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before changing an icon."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before changing an icon."
            )
            return
        }
        let panel = ChangeIconPanelView(
            instance: instance,
            defaultBadgeCharacter: defaultBadgeCharacter(for: instance)
        )
        let alert = NSAlert()
        alert.messageText = "Change icon for \(instance.label)"
        alert.informativeText = "The native app is never modified."
        alert.accessoryView = panel
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to App Icon")
        let response = alert.runModal()
        let edit: AppProfileManager.IconEdit
        switch response {
        case .alertFirstButtonReturn:
            guard let chosen = panel.currentEdit else {
                showAppProfileAlert(
                    title: "No image chosen",
                    message: "Choose a PNG or ICO file, or pick Tint or Badge, before applying."
                )
                return
            }
            edit = chosen
        case .alertThirdButtonReturn:
            edit = .reset
        default:
            return
        }

        guard beginAppProfileLifecycle() else { return }
        let currentConfig = persistedConfig
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.appProfileManager.updateManagedIcon(
                    instanceID: instance.id,
                    edit: edit,
                    config: currentConfig
                )
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    let isReset: Bool
                    if case .reset = edit { isReset = true } else { isReset = false }
                    self.appProfilesView.setStatus(
                        applied
                            ? (isReset ? "Icon reset to the app icon." : "Icon updated.")
                            : "Icon changed; helper apply is pending.",
                        color: applied ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.showAppProfileAlert(
                        title: "Icon was not changed",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async { self.finishAppProfileLifecycle() }
            }
        }
    }

    private func assignMouseButton(to instance: AppProfileInstance) {
        assignMouseButton(to: .profile(instance.id), label: instance.label)
    }

    private func assignMouseButton(to target: LaunchAssignmentTarget, label: String) {
        // Gate on a settled configuration, exactly like the other App Profile
        // lifecycle actions. This is what keeps the two sections consistent: the
        // assign flow saves immediately from persistedConfig, so it must not run
        // while the working `config` holds unsaved Mouse Button Shortcuts edits
        // (which it would otherwise silently discard).
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before assigning a mouse button."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before assigning a mouse button."
            )
            return
        }
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 42))
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 6, width: 390, height: 30))
        picker.addItem(withTitle: "None — Clear assignment")
        for button in QuickLaunchMouseButton.allCases {
            let owner = launchAssignmentOwner(of: button, in: persistedConfig)
            let state = owner.map { "Used: \(launchAssignmentLabel($0, in: persistedConfig))" }
                ?? "Available"
            picker.addItem(withTitle: "\(button.title) Button — \(state)")
        }
        accessory.addSubview(picker)
        let alert = NSAlert()
        alert.messageText = "Assign a mouse button to \(label)"
        alert.informativeText = "The selected button will open this app, or bring its existing window forward."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if picker.indexOfSelectedItem == 0 {
            var updated = clearingMouseButton(from: target, in: persistedConfig)
            guard KlikProConfigStore.save(updated) else {
                showAppProfileAlert(
                    title: "Assignment was not cleared",
                    message: "Klik PRO could not save the change."
                )
                return
            }
            updated = normalizedQuickLaunchConfig(updated)
            let applied = applySavedConfig()
            config = updated
            persistedConfig = updated
            refreshButtonAssignmentViews()
            appProfilesView.setStatus(
                applied ? "Mouse button assignment cleared for \(label)." : "Cleared; helper apply is pending.",
                color: applied ? .systemGreen : .systemOrange
            )
            return
        }
        let button = QuickLaunchMouseButton.allCases[picker.indexOfSelectedItem - 1]
        let currentOwner = launchAssignmentOwner(of: button, in: persistedConfig)
        if let currentOwner, currentOwner != target {
            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = "Force Release \(button.title) Button?"
            confirmation.informativeText = "It is currently assigned to \(launchAssignmentLabel(currentOwner, in: persistedConfig)). Only that button assignment will be released; the app and its saved shortcut remain intact."
            confirmation.addButton(withTitle: "Force Release & Assign")
            confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }

        var updated = assigningMouseButton(button, to: target, in: persistedConfig)
        guard KlikProConfigStore.save(updated) else {
            showAppProfileAlert(title: "Button was not assigned", message: "Klik PRO could not save a valid assignment.")
            return
        }
        updated = normalizedQuickLaunchConfig(updated)
        let applied = applySavedConfig()
        config = updated
        persistedConfig = updated
        refreshButtonAssignmentViews()
        appProfilesView.setStatus(
            applied ? "\(button.title) Button opens \(label)." : "Assigned; helper apply is pending.",
            color: applied ? .systemGreen : .systemOrange
        )
        refreshAppProfileHealth()
    }

    private func configureAppProfile(_ instance: AppProfileInstance) {
        guard instance.launcherKind == .managed else { return }
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before configuring this instance."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before configuring an App Profile."
            )
            return
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 202))
        let labelTitle = NSTextField(labelWithString: "Label")
        labelTitle.frame = NSRect(x: 0, y: 176, width: 80, height: 20)
        let labelField = NSTextField(string: instance.label)
        labelField.frame = NSRect(x: 88, y: 172, width: 296, height: 26)
        let colorTitle = NSTextField(labelWithString: "Marker")
        colorTitle.frame = NSRect(x: 0, y: 142, width: 80, height: 20)
        let colorPicker = NSPopUpButton(frame: NSRect(x: 88, y: 136, width: 180, height: 30))
        colorPicker.addItem(withTitle: "None")
        AppProfileMenuColor.allCases.forEach { colorPicker.addItem(withTitle: $0.title) }
        if let color = instance.menuColor,
           let index = AppProfileMenuColor.allCases.firstIndex(of: color) {
            colorPicker.selectItem(at: index + 1)
        }
        let pinCheck = NSButton(
            checkboxWithTitle: "Pin this instance to the menu bar",
            target: nil,
            action: nil
        )
        pinCheck.frame = NSRect(x: 88, y: 104, width: 296, height: 24)
        pinCheck.state = instance.pinToMenuBar ? .on : .off
        let hotkeyCheck = NSButton(
            checkboxWithTitle: "Enable global hotkey",
            target: nil,
            action: nil
        )
        hotkeyCheck.frame = NSRect(x: 88, y: 70, width: 164, height: 24)
        hotkeyCheck.state = instance.hotkey.enabled ? .on : .off
        let recorder = ShortcutRecorderView(
            combo: instance.hotkey.combo,
            frame: NSRect(x: 258, y: 66, width: 126, height: 30)
        )
        let mouseTitle = NSTextField(labelWithString: "Mouse button")
        mouseTitle.frame = NSRect(x: 0, y: 28, width: 80, height: 20)
        let mousePicker = NSPopUpButton(frame: NSRect(x: 88, y: 22, width: 180, height: 30))
        mousePicker.addItem(withTitle: "None")
        QuickLaunchMouseButton.allCases.forEach { mousePicker.addItem(withTitle: $0.title) }
        if let button = instance.mouseButton,
           let index = QuickLaunchMouseButton.allCases.firstIndex(of: button) {
            mousePicker.selectItem(at: index + 1)
        }
        [
            labelTitle, labelField, colorTitle, colorPicker, pinCheck, hotkeyCheck, recorder,
            mouseTitle, mousePicker,
        ].forEach(accessory.addSubview)

        let alert = NSAlert()
        alert.messageText = "Configure \(instance.label)"
        alert.informativeText = "Assignments are UUID-keyed. Duplicate mouse buttons, duplicate enabled hotkeys, and Command-Tab are rejected."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard beginAppProfileLifecycle() else {
            showAppProfileAlert(
                title: "Please wait",
                message: "The App Profile configuration was not changed."
            )
            return
        }

        let selectedMouse: QuickLaunchMouseButton? = mousePicker.indexOfSelectedItem == 0
            ? nil
            : QuickLaunchMouseButton.allCases[mousePicker.indexOfSelectedItem - 1]
        let mapping = ShortcutMapping(
            enabled: hotkeyCheck.state == .on,
            combo: recorder.combo
        )
        let updatedLabel = labelField.stringValue
        let updatedMenuColor: AppProfileMenuColor? = colorPicker.indexOfSelectedItem == 0
            ? nil
            : AppProfileMenuColor.allCases[colorPicker.indexOfSelectedItem - 1]
        let updatedPin = pinCheck.state == .on
        let currentConfig = persistedConfig
        appProfilesView.setStatus("Saving \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.appProfileManager.updateManagedInstance(
                    instanceID: instance.id,
                    label: updatedLabel,
                    menuColor: updatedMenuColor,
                    pinToMenuBar: updatedPin,
                    hotkey: mapping,
                    mouseButton: selectedMouse,
                    config: currentConfig
                )
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = updated
                    self.persistedConfig = updated
                    self.appProfilesView.setInstances(updated.instances)
                    self.appProfilesView.setStatus(
                        applied ? "App Profile configuration saved." : "Saved; helper apply is pending.",
                        color: applied ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                    self.needsDisplay = true
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not changed.", color: .systemRed)
                    self.showAppProfileAlert(
                        title: "App Profile was not changed",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not changed.", color: .systemRed)
                }
            }
        }
    }

    private func confirmConvertAppProfile(_ instance: AppProfileInstance) {
        guard instance.launcherKind == .legacyExternal else { return }
        guard !saveInProgress, !appProfileLifecycleInProgress,
              !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Finish any current Save, then save or restore edits before converting."
            )
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Convert \(instance.label) to a managed App Profile?"
        alert.informativeText = "Klik PRO will create a new UUID-keyed launcher and profile, then transfer this row's assignments. The existing external launcher and all of its data remain untouched."
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard beginAppProfileLifecycle() else { return }

        let currentConfig = persistedConfig
        appProfilesView.setStatus("Converting \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.convertLegacy(
                    instanceID: instance.id,
                    config: currentConfig
                )
                let applied = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.appProfilesView.setStatus(
                        applied
                            ? "\(result.instance.label) is now managed; the external launcher was untouched."
                            : "Converted; helper apply is pending. The external launcher was untouched.",
                        color: applied ? .systemGreen : .systemOrange
                    )
                    self.refreshAppProfileHealth()
                    self.needsDisplay = true
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("Legacy conversion was not performed.", color: .systemRed)
                    self.showAppProfileAlert(
                        title: "Legacy conversion is unavailable",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("Legacy conversion was not performed.", color: .systemRed)
                }
            }
        }
    }

    private func confirmRemoveAppProfile(_ instance: AppProfileInstance) {
        guard !saveInProgress, !appProfileLifecycleInProgress else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before removing this profile."
            )
            return
        }
        guard !hasUnsavedConfigurationChanges else {
            showAppProfileAlert(
                title: "Save current changes first",
                message: "Save or restore the current mapping changes before removing an App Profile."
            )
            return
        }
        guard instance.launcherKind == .managed else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(instance.label) from Klik PRO?"
        alert.informativeText =
            "This removes the generated launcher and Klik PRO's managed entry. "
            + "The login and profile data stays on disk and is not deleted.\n\n"
            + "To remove that data too, cancel and use Delete Data in Advanced."
        alert.addButton(withTitle: "Remove from Klik PRO")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        guard beginAppProfileLifecycle() else {
            showAppProfileAlert(
                title: "Please wait",
                message: "Finish the current Save or App Profile change before removing this profile."
            )
            return
        }

        let currentConfig = persistedConfig
        appProfilesView.setStatus("Removing \(instance.label)…")
        appProfileQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.appProfileManager.remove(
                    instanceID: instance.id,
                    config: currentConfig,
                    deleteProfileData: false
                )
                self.cleanupRemovedLauncherRegistration(launcherPath: instance.launcherPath)
                _ = applySavedConfig()
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.config = result.config
                    self.persistedConfig = result.config
                    self.appProfilesView.setInstances(result.config.instances)
                    self.appProfilesView.setStatus(
                        "\(instance.label) has been removed from Klik PRO.",
                        color: .systemGreen
                    )
                    self.refreshAppProfileHealth()
                    self.needsDisplay = true
                }
            } catch let error as AppProfileManagerError {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not removed.", color: .systemRed)
                    self.showAppProfileAlert(
                        title: "App Profile was not removed",
                        message: self.appProfileErrorMessage(error)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishAppProfileLifecycle()
                    self.appProfilesView.setStatus("App Profile was not removed.", color: .systemRed)
                }
            }
        }
    }

    /// Reopening Badge mode keeps this profile's saved choice. A profile without
    /// one receives the first unused single-digit badge among profiles for the
    /// same source app: 1, 2, … 9, then 0.
    private func defaultBadgeCharacter(for instance: AppProfileInstance) -> String {
        if let saved = instance.badgeCharacter?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            return String(saved.prefix(1))
        }
        let used = Set(persistedConfig.instances.compactMap { candidate -> String? in
            guard candidate.id != instance.id,
                  candidate.source.bundleIdentifier == instance.source.bundleIdentifier,
                  let character = candidate.badgeCharacter?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !character.isEmpty else { return nil }
            return String(character.uppercased().prefix(1))
        })
        return ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            .first(where: { !used.contains($0) }) ?? "1"
    }

    private func launchAppProfile(_ instance: AppProfileInstance) {
        if instance.launcherKind == .managed {
            do {
                let launcherURL = try appProfileManager.generatedLauncherURL(for: instance)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(
                    at: launcherURL,
                    configuration: configuration
                ) { [weak self] _, error in
                    guard error != nil else { return }
                    DispatchQueue.main.async {
                        self?.showAppProfileAlert(
                            title: "App Profile could not be opened",
                            message: "macOS could not open the validated launcher for \(instance.label)."
                        )
                    }
                }
            } catch {
                showAppProfileAlert(
                    title: "App Profile could not be opened",
                    message: "The generated launcher for \(instance.label) is missing or no longer passes validation."
                )
            }
            return
        }
        appProfileRuntime.launchOrFocus(instance) { [weak self] result in
            guard case .failure(let error) = result else { return }
            DispatchQueue.main.async {
                self?.showAppProfileAlert(
                    title: "App Profile action was blocked",
                    message: self?.appProfileRuntimeErrorMessage(error)
                        ?? "Klik PRO could not safely launch or focus this instance."
                )
            }
        }
    }

    private func launchOriginalApp(_ target: QuickLaunchTarget) {
        appProfileRuntime.launchOriginal(target) { [weak self] result in
            guard case .failure = result else { return }
            DispatchQueue.main.async {
                self?.showAppProfileAlert(
                    title: "Native app could not be opened",
                    message: "Klik PRO could not safely open the native \(target.title) app."
                )
            }
        }
    }

    private func refreshAppProfileHealth() {
        let instances = persistedConfig.instances
        if previewRenderingIsActive {
            appProfilesView.setRuntimeHealth(
                Dictionary(uniqueKeysWithValues: instances.map { ($0.id, .ready) })
            )
            advancedView.setMaintenanceInstances(
                instances,
                health: Dictionary(uniqueKeysWithValues: instances.map { ($0.id, .healthy) })
            )
            return
        }
        let currentConfig = persistedConfig
        let additionalVaultRoots = currentConfig.knownDataRoots.compactMap { path -> URL? in
            guard path != currentConfig.dataRoot else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        appProfileHealthQueue.async { [weak self] in
            guard let self else { return }
            let runtimeHealth = Dictionary(uniqueKeysWithValues: instances.map {
                ($0.id, self.appProfileRuntime.health(for: $0))
            })
            let maintenanceHealth = Dictionary(uniqueKeysWithValues: instances.map {
                ($0.id, self.appProfileManager.maintenanceHealth(for: $0))
            })
            let orphans = self.appProfileManager.scanOrphans(
                config: currentConfig,
                additionalVaultRoots: additionalVaultRoots
            )
            DispatchQueue.main.async {
                self.appProfilesView.setRuntimeHealth(runtimeHealth)
                self.advancedView.setMaintenanceInstances(
                    instances, health: maintenanceHealth, orphans: orphans
                )
            }
        }
    }

    private func appProfileRuntimeErrorMessage(_ error: AppProfileRuntimeError) -> String {
        switch error {
        case .unavailable(let health):
            switch health {
            case .ready:
                return "The instance changed while it was being opened."
            case .sourceUnavailable:
                return "The exact source application is missing or changed."
            case .verificationRequired(let reason):
                return reason
            case .launcherUnavailable:
                return "The UUID-keyed launcher or profile path no longer passes validation."
            case .externalUnavailable:
                return "The external legacy launcher is missing."
            }
        case .processScanIncomplete:
            return "Process identity could not be inspected completely, so Klik PRO failed closed."
        case .ambiguousProcesses:
            return "More than one verified root process references this profile. Klik PRO did not guess."
        case .launchFailed:
            return "macOS did not return a launched application for this instance."
        case .processVerificationFailed:
            return "The returned process did not match the exact executable and profile argument."
        case .activationFailed:
            return "The verified process did not become the frontmost application."
        }
    }

    private func appProfileErrorMessage(_ error: AppProfileManagerError) -> String {
        switch error {
        case .sourceChanged:
            return "The selected app changed after it was scanned. Scan it again before creating a profile."
        case .creationDisabled(let reason):
            return reason
        case .duplicateInstanceID:
            return "The generated instance UUID already exists. Nothing was created."
        case .duplicateLabel:
            return "That App Profile name is already used. Choose a unique name."
        case .materializationFailed:
            return "Klik PRO could not create and sign its managed launcher."
        case .persistenceFailed:
            return "Klik PRO could not save the updated configuration."
        case .externalInstance:
            return "Legacy external wrappers cannot be removed or claimed by Klik PRO."
        case .launcherUnavailable:
            return "The launcher is missing or no longer passes managed-path validation."
        case .launcherCleanupFailed:
            return "Klik PRO could not safely stage its managed launcher for removal. Nothing was removed."
        case .invalidAssignments:
            return "Assignments must use a unique mouse button and unique enabled hotkey. Command-Tab is never allowed."
        case .processScanIncomplete:
            return "Process inspection was incomplete, so profile deletion was blocked."
        case .profileInUse:
            return "A verified process still references this profile. Quit that instance before deleting its data."
        case .profileCleanupFailed:
            return "The profile path, UUID ownership marker, or removal staging check failed. Data was not deleted."
        case .conversionUnavailable:
            return "Only one of the two known legacy external rows can be explicitly converted."
        case .iconImageInvalid:
            return "That image could not be used. Choose a square PNG or ICO at least 256×256 pixels."
        case .vaultUnavailable:
            return "No data folder is configured or mounted, so nothing could be scanned."
        case .vaultManifestInvalid:
            return "That folder is not a Klik PRO data folder (no valid vault.json), so it was not adopted."
        case .invalidLifecycleState:
            return "That App Profile is not in the required active or archived state for this action."
        case .repairUnavailable:
            return "Klik PRO could not find verified profile data to rebuild this launcher safely."
        case .forgetUnavailable:
            return "Forget Entry only applies to a record whose profile data is already missing."
        case .dataRemovalUnavailable:
            return "Klik PRO could not verify this data as safely owned, so nothing was removed."
        }
    }

    private func showAppProfileAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func recheckControlState() {
        controlState = AppControlState(
            launchAtLogin: preferencesView.launchAtLoginRow.toggle.isOn,
            automaticUpdateChecks: preferencesView.autoUpdateRow.toggle.isOn,
            specialFeatureEnabled: contentView.specialFeatureToggleRow.toggle.isOn
        )
    }

    private func configurationDidChange() {
        recheckControlState()
        // A new edit supersedes any stale Saved/check-for-updates footer message.
        if !saveInProgress {
            saveStatusMessage = nil
        }
        needsDisplay = true
    }

    private func refreshSpecialFeatureAvailability() {
        let available = hasInstalledQuickLaunchTarget()
        menuRunning = config.specialFeatureEnabled && available
        contentView.setSpecialFeatureAvailability(available, isOn: menuRunning)
        refreshQuickLaunchAssignments()
        recomputeConflictBadges()
        needsDisplay = true
    }

    private func refreshAccessibilityStatus() {
        preferencesView.setAccessibilityGranted(helperAccessibilityGranted())
    }

    /// Requests a fresh, no-prompt TCC check from the helper and reloads the status
    /// pill after the helper has had a moment to append its response to the event log.
    private func recheckAccessibilityStatus() {
        guard !previewRenderingIsActive else {
            refreshAccessibilityStatus()
            return
        }
        preferencesView.recheckAccessibilityLink.title = "Checking…"
        DistributedNotificationCenter.default().post(
            name: accessibilityStatusCheckRequestedNotification,
            object: nil
        )
        refreshAccessibilityStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshAccessibilityStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.refreshAccessibilityStatus()
            self?.preferencesView.recheckAccessibilityLink.title = "Recheck"
        }
    }

    func showFirstLaunchOnboardingIfNeeded() {
        presentOnboarding(force: false)
    }

    /// Reopening Klik PRO after a menu-bar "Quit" left the background helper
    /// stopped (Quit disables + boots it out), so the menu-bar icon and mouse
    /// shortcuts stayed gone until the user toggled Launch at login. Bringing
    /// the app to the foreground is a clear intent to use it, so restart the
    /// helper for this session — honoring the resolved Launch-at-login value so
    /// a prior "off" choice still means no auto-start at the next login.
    /// `ensureInputHelperRunning` no-ops when the helper is already running, so
    /// a normal launch never restarts or churns it. Onboarding starts the
    /// helper through its own accessibility flow, so skip while it is pending.
    func ensureBackgroundHelperRunningAtLaunch() {
        guard !previewRenderingIsActive, config.onboardingCompleted else { return }
        let launchAtLoginEnabled = controlState.launchAtLogin
        saveApplyQueue.async {
            _ = ensureInputHelperRunning(launchAtLoginEnabled: launchAtLoginEnabled)
        }
    }

    private func presentOnboarding(force: Bool) {
        guard !previewRenderingIsActive,
              force || !config.onboardingCompleted,
              let window = window,
              window.attachedSheet == nil else { return }

        // One checklist instance carries the toggle choices across Back/Continue.
        presentOnboardingStep(.welcome, selections: OnboardingChecklistView())
    }

    /// One sheet per step. Welcome has a single Continue; later steps offer Back;
    /// no step offers Cancel. Choices apply only from the last page, so backing
    /// up and changing a toggle never leaves a half-applied state.
    private func presentOnboardingStep(
        _ step: OnboardingStep,
        selections: OnboardingChecklistView
    ) {
        guard let window = window, window.attachedSheet == nil else { return }

        let granted = helperAccessibilityGranted()
        let alert = makeOnboardingAlert(
            step: step,
            accessibilityGranted: granted,
            checklist: selections
        )

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            let advance: (OnboardingStep) -> Void = { next in
                DispatchQueue.main.async {
                    self.presentOnboardingStep(next, selections: selections)
                }
            }
            switch step {
            case .welcome:
                advance(.preferences)
            case .preferences:
                response == .alertFirstButtonReturn
                    ? advance(.accessibility)
                    : advance(.welcome)
            case .accessibility:
                // Finishing always completes onboarding and applies the toggles. When
                // opening Accessibility setup, that flow starts the helper, so the apply
                // pass skips its own start to avoid a second, churning launchd pass.
                let finish: (_ openAccessibilitySetup: Bool) -> Void = { openSetup in
                    self.applyOnboardingSelections(
                        launchAtLogin: selections.launchAtLoginOn,
                        autoUpdate: selections.autoUpdateOn,
                        showMenuBarIcon: selections.showMenuBarIconOn,
                        caffeinate: selections.caffeinateOn,
                        startHelper: !openSetup
                    )
                    if openSetup {
                        self.selectTab(1)
                        self.beginAccessibilitySetup()
                    } else {
                        self.selectTab(0)
                    }
                }
                if granted {
                    // Buttons: [Start Using Klik PRO, Back]
                    response == .alertFirstButtonReturn ? finish(false) : advance(.preferences)
                } else {
                    // Buttons: [Set Up Accessibility…, Skip for Now, Back]
                    switch response {
                    case .alertFirstButtonReturn: finish(true)   // opt in now
                    case .alertSecondButtonReturn: finish(false) // Skip for Now — grant later
                    default: advance(.preferences)               // Back
                    }
                }
            }
        }
    }

    /// Persist and apply the first-run toggle choices. UserDefaults-backed switches
    /// (launch at login, auto-update) are written with concrete values so a later launch
    /// never re-resolves them from the pre-onboarding defaults; config-backed switches
    /// (menu-bar icon, Caffeinate) are saved to config.json. `startHelper` runs a single
    /// launchd apply pass so the menu-bar icon appears/disappears immediately; callers
    /// that will start the helper themselves (Accessibility setup) pass false to avoid a
    /// second, churning pass.
    private func applyOnboardingSelections(
        launchAtLogin: Bool,
        autoUpdate: Bool,
        showMenuBarIcon: Bool,
        caffeinate: Bool,
        startHelper: Bool
    ) {
        let effectiveCaffeinate = showMenuBarIcon && caffeinate

        UserDefaults.standard.set(autoUpdate, forKey: ToggleView.autoCheckKey)
        UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginPreferenceKey)

        preferencesView.launchAtLoginRow.toggle.isOn = launchAtLogin
        preferencesView.autoUpdateRow.toggle.isOn = autoUpdate
        preferencesView.showMenuBarIconRow.toggle.isOn = showMenuBarIcon
        preferencesView.caffeinateRow.toggle.isOn = effectiveCaffeinate

        config.showMenuBarIcon = showMenuBarIcon
        config.caffeinateMenuEnabled = effectiveCaffeinate
        config.onboardingCompleted = true
        recheckControlState()

        if KlikProConfigStore.save(config) {
            persistedConfig = config
            persistedControlState = controlState
        }

        guard startHelper, !previewRenderingIsActive else { return }
        saveApplyQueue.async {
            _ = installLaunchAgentPlist(appBundleURL: Bundle.main.bundleURL)
            _ = applySavedConfig(launchAtLoginEnabled: launchAtLogin)
        }
    }

    private func resetAccessibilityApproval(bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func ensureLaunchAgentSetup() -> Bool {
        guard installLaunchAgentPlist(appBundleURL: Bundle.main.bundleURL) else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Background services could not be installed"
            alert.informativeText = "Klik PRO could not create its per-user LaunchAgent files. Make sure the app is in Applications, then reopen it and try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
        return true
    }

    private func confirmAccessibilityReset() {
        guard !previewRenderingIsActive else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset Accessibility?"
        alert.informativeText = "Mouse mappings will pause until Accessibility is granted to Klik PRO Helper again. Klik PRO will restart the guided setup immediately."
        alert.addButton(withTitle: "Reset and Set Up Again")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard resetAccessibilityApproval(bundleIdentifier: "local.klik-pro.helper") else {
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .critical
            errorAlert.messageText = "Accessibility could not be reset"
            errorAlert.informativeText = "Klik PRO could not clear the helper's macOS permission. Remove Klik PRO Helper from Accessibility in System Settings, then try again."
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
            return
        }

        // Remove any stale entry for the settings app as well. The nested helper is
        // the process that actually requires Accessibility, so this is best-effort.
        _ = resetAccessibilityApproval(bundleIdentifier: "local.klik-pro")
        preferencesView.setAccessibilityGranted(false)
        _ = run(["kickstart", "-k", inputTarget])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.presentOnboarding(force: true)
        }
    }

    /// Accessibility remains a user-controlled macOS permission. This guided action
    /// starts the real nested helper when necessary, asks that helper to register its
    /// own trust request, then opens the exact pane containing the generated entry.
    private func beginAccessibilitySetup() {
        guard !previewRenderingIsActive else { return }
        guard ensureLaunchAgentSetup() else { return }

        if run(["print", inputTarget]) != 0 {
            _ = ensureInputHelperRunning(
                launchAtLoginEnabled: preferencesView.launchAtLoginRow.toggle.isOn
            )
        }

        func notifyHelper() {
            DistributedNotificationCenter.default().post(
                name: accessibilitySetupRequestedNotification,
                object: nil
            )
        }
        notifyHelper()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            notifyHelper()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Accessibility re-grant guidance (after an app update)

    // Klik PRO is ad-hoc signed, so each update changes the helper's code
    // signature and macOS drops its Accessibility grant — even though the old
    // "Klik PRO Helper" entry still shows enabled. The bare system prompt that
    // then appears is confusing, so we proactively explain the remove-and-
    // re-grant steps. Shown at most once per launch.
    private var didGuideAccessibilityRegrantThisSession = false
    private static let lastRunBundleVersionKey = "klikpro.lastRunBundleVersion"

    /// Records the running build and reports an update. Existing installations
    /// upgrading to the first build that carries this key have no previous value,
    /// so their already-completed onboarding distinguishes them from a true fresh
    /// install. This must run before first-launch onboarding is presented.
    private func consumeBundleVersionChanged() -> Bool {
        let current = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let previous = UserDefaults.standard.string(forKey: Self.lastRunBundleVersionKey)
        UserDefaults.standard.set(current, forKey: Self.lastRunBundleVersionKey)
        return previous.map { $0 != current } ?? config.onboardingCompleted
    }

    /// Launch hook: after an update, if the user relies on the helper (menu-bar
    /// icon on) but it is no longer trusted, walk them through the re-grant
    /// instead of leaving the raw system prompt unexplained.
    func guideAccessibilityRegrantAfterUpdateIfNeeded() {
        guard !previewRenderingIsActive else { return }
        let updated = consumeBundleVersionChanged()
        guard updated, config.onboardingCompleted, config.showMenuBarIcon else { return }
        guideAccessibilityRegrantIfStillMissing()
    }

    /// Menu-bar toggle turned ON (or launch-after-update): give the helper a
    /// moment to report its trust status, then guide the user if it is still not
    /// trusted. No-op when already granted, already shown this launch, or a sheet
    /// is up. Only reads the helper's status log and asks for a recheck — it
    /// never restarts or otherwise churns the helper.
    func guideAccessibilityRegrantIfStillMissing() {
        guard !previewRenderingIsActive,
              config.onboardingCompleted,
              !didGuideAccessibilityRegrantThisSession,
              let window = window,
              window.attachedSheet == nil else { return }
        DistributedNotificationCenter.default().post(
            name: accessibilityStatusCheckRequestedNotification,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self,
                  !self.didGuideAccessibilityRegrantThisSession,
                  !helperAccessibilityGranted(),
                  let window = self.window,
                  window.attachedSheet == nil else { return }
            self.didGuideAccessibilityRegrantThisSession = true
            self.presentAccessibilityRegrantGuidance(in: window)
        }
    }

    private func presentAccessibilityRegrantGuidance(in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Klik PRO Helper needs Accessibility permission"
        alert.informativeText = """
        Klik PRO Helper isn’t currently trusted for Accessibility, so mouse \
        buttons and hotkeys won’t work until it’s granted.

        If you just updated Klik PRO, macOS may still show an old “Klik PRO \
        Helper” as enabled even though the updated helper needs granting again.

        Click “Register Helper” and Klik PRO makes the current helper’s toggle \
        appear in Privacy & Security → Accessibility — you do not need the “+” \
        button (the helper lives inside the app bundle and can’t be added by hand). \
        Then:

        1. If an old “Klik PRO Helper” is already listed, select it and click \
        “–” to remove the stale entry.
        2. Turn on the “Klik PRO Helper” that just appeared.
        """
        alert.addButton(withTitle: "Register Helper")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            // Force the current helper to register its trust request so its
            // Accessibility toggle appears immediately, instead of leaving the
            // user to hunt for a nested helper that “+” cannot reach.
            self?.beginAccessibilitySetup()
        }
    }

    private func setQuickLaunchMouseButton(
        _ button: QuickLaunchMouseButton?,
        for target: QuickLaunchTarget
    ) {
        if !quickLaunchMouseSelectionIsAllowed(
            button,
            readiness: quickLaunchTargetReadiness(target)
        ) {
            NSSound.beep()
            refreshQuickLaunchAssignments()
            return
        }
        let other = target == .chatGPT ? config.claudeMouseButton : config.chatGPTMouseButton
        guard button == nil || button != other else {
            NSSound.beep()
            refreshQuickLaunchAssignments()
            return
        }
        let current = target == .chatGPT ? config.chatGPTMouseButton : config.claudeMouseButton
        guard button != current else {
            refreshQuickLaunchAssignments()
            return
        }
        switch target {
        case .chatGPT: config.chatGPTMouseButton = button
        case .claude: config.claudeMouseButton = button
        }
        configurationDidChange()
        refreshButtonAssignmentViews()
    }

    private func refreshQuickLaunchAssignments() {
        contentView.updateQuickLaunchAssignments(
            config: config,
            featureActive: menuRunning
        )
    }

    /// Single refresh for every button-assignment mutation. Rebuilds the App
    /// Profiles list (which fans out to the compact Mappings list via
    /// onInstancesChange), the Mouse Button Shortcuts rows, and the conflict
    /// badges from the same `config.instances[].mouseButton` state, so the two
    /// sections can never drift out of sync. Callers must set `config` first.
    private func refreshButtonAssignmentViews() {
        appProfilesView.setInstances(config.instances)
        refreshOriginalAssignmentViews()
        refreshQuickLaunchAssignments()
        recomputeConflictBadges()
    }

    private func launchAssignmentLabel(
        _ target: LaunchAssignmentTarget,
        in config: KlikProConfig
    ) -> String {
        switch target {
        case .original(let original): return original.title
        case .profile(let id):
            return config.instances.first { $0.id == id }?.label ?? "App Profile"
        }
    }

    private func refreshOriginalAssignmentViews() {
        appProfilesView.setOriginalAssignments(
            chatGPT: config.chatGPTMouseButton,
            claude: config.claudeMouseButton
        )
        let originals: [(QuickLaunchTarget, String, String, QuickLaunchMouseButton?)] =
            QuickLaunchTarget.allCases.compactMap { target in
                guard let url = quickLaunchTargetApplicationURL(target) else { return nil }
                return (target, target.title, url.path, quickLaunchMouseButton(for: target, in: config))
            }
        contentView.mappingProfilesView.setOriginals(originals)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let updateButtonTrackingArea = updateButtonTrackingArea {
            removeTrackingArea(updateButtonTrackingArea)
        }
        if let closeButtonTrackingArea = closeButtonTrackingArea {
            removeTrackingArea(closeButtonTrackingArea)
        }
        let updateArea = NSTrackingArea(
            rect: updateButtonRect,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        let closeArea = NSTrackingArea(
            rect: closeButtonRect,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(updateArea)
        addTrackingArea(closeArea)
        updateButtonTrackingArea = updateArea
        closeButtonTrackingArea = closeArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(updateButtonRect, cursor: .pointingHand)
        addCursorRect(closeButtonRect, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === updateButtonTrackingArea {
            setUpdateButtonHovered(true)
        } else if event.trackingArea === closeButtonTrackingArea {
            setCloseButtonHovered(true)
        } else {
            super.mouseEntered(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === updateButtonTrackingArea {
            setUpdateButtonHovered(false)
        } else if event.trackingArea === closeButtonTrackingArea {
            setCloseButtonHovered(false)
        } else {
            super.mouseExited(with: event)
        }
    }

    private func setUpdateButtonHovered(_ hovered: Bool) {
        guard updateButtonHovered != hovered else { return }
        updateButtonHovered = hovered
        needsDisplay = true
    }

    private func setCloseButtonHovered(_ hovered: Bool) {
        guard closeButtonHovered != hovered else { return }
        closeButtonHovered = hovered
        needsDisplay = true
    }

    private func recomputeConflictBadges() {
        let launchableInstanceIDs = launchableAppProfileInstanceIDs(
            in: config,
            instanceIsLaunchable: { [appProfileRuntime] instance in
                !previewRenderingIsActive && appProfileRuntime.health(for: instance) == .ready
            }
        )
        let statuses = evaluateShortcutConflicts(
            candidate: config,
            persisted: persistedConfig,
            browserExtensionShortcuts: browserExtensionShortcuts,
            specialFeatureActive: menuRunning,
            chatGPTAvailable: quickLaunchTargetIsAvailable(.chatGPT),
            claudeAvailable: quickLaunchTargetIsAvailable(.claude),
            activeInstanceIDs: launchableInstanceIDs
        )
        contentView.middleButtonRow.badge.status = statuses[.middleButton] ?? .ok
        contentView.gestureButtonRow.badge.status = statuses[.gestureButton] ?? .ok
        contentView.forwardRow.badge.status = statuses[.forwardButton] ?? .ok
        contentView.backRow.badge.status = statuses[.backButton] ?? .ok
        contentView.chatGPTHotkeyRow.setConflictStatus(statuses[.chatGPTHotkey] ?? .ok)
        contentView.claudeHotkeyRow.setConflictStatus(statuses[.claudeHotkey] ?? .ok)
    }

    private func saveConfiguration() {
        guard !appProfileLifecycleInProgress else {
            saveStatusMessage = "Wait for the App Profile change to finish."
            needsDisplay = true
            return
        }
        guard !saveInProgress else { return }
        if !quickLaunchMouseAssignmentsAreValid(config),
           let button = config.chatGPTMouseButton {
            saveStatusMessage = "\(button.title) is already assigned to both launchers."
            needsDisplay = true
            return
        }
        if configuredSlotUsingGestureSentinel(in: config) != nil {
            saveStatusMessage = "⌘F20 is reserved for the Gesture Button."
            needsDisplay = true
            return
        }
        if configuredGlobalHotKeyUsingReservedCommandTab(in: config) != nil {
            saveStatusMessage = "⌘Tab is reserved for keyboard app switching and cannot be a global hotkey."
            needsDisplay = true
            return
        }
        let previousConfig = persistedConfig
        let chatGPTAvailable = quickLaunchTargetIsAvailable(.chatGPT)
        let claudeAvailable = quickLaunchTargetIsAvailable(.claude)
        let previousFeatureActive = previousConfig.specialFeatureEnabled
            && (chatGPTAvailable || claudeAvailable)
        let currentFeatureActive = config.specialFeatureEnabled
            && (chatGPTAvailable || claudeAvailable)
        let configToSave = config
        let controlStateToSave = controlState
        let disablingGesture = mapping(
            for: .gestureButton,
            in: previousConfig,
            specialFeatureActive: previousFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        ).enabled && !mapping(
            for: .gestureButton,
            in: config,
            specialFeatureActive: currentFeatureActive,
            chatGPTAvailable: chatGPTAvailable,
            claudeAvailable: claudeAvailable
        ).enabled
        // Save writes config.json, then auto-applies by restarting the running
        // helper(s) so the new mappings take effect immediately — no manual step
        // and no launchctl jargon shown to the user. The restart re-reads config
        // but keeps the same binary, so the Accessibility grant is preserved.
        setSaveInProgress(true)
        saveApplyQueue.async { [weak self] in
            let saved = KlikProConfigStore.save(configToSave)
            let gestureCleanupOK = saved
                && (!disablingGesture || clearGestureSentinelMappingIfOwned())
            let applied = saved && applySavedConfig()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if saved {
                    self.persistedConfig = configToSave
                    self.persistedControlState = controlStateToSave
                    self.recomputeConflictBadges()
                    let newerEditsRemain = self.config != configToSave
                        || self.controlState != controlStateToSave
                    if !gestureCleanupOK {
                        self.saveStatusMessage = applied
                            ? "Saved — Gesture cleanup will retry."
                            : "Saved — Gesture cleanup is pending."
                    } else if newerEditsRemain {
                        self.saveStatusMessage = applied
                            ? "Saved — newer edits remain unsaved."
                            : "Saved — newer edits remain unsaved; apply is pending."
                    } else {
                        self.saveStatusMessage = applied
                            ? "Saved — changes applied."
                            : "Saved — helper apply timed out."
                    }
                } else {
                    self.saveStatusMessage = "Save failed — check permissions."
                }
                self.setSaveInProgress(false)
                self.needsDisplay = true
            }
        }
    }

    private func setSaveInProgress(_ inProgress: Bool) {
        saveInProgress = inProgress
        saveButton.isEnabled = !inProgress
        saveButton.title = inProgress ? "Applying…" : "Save"
        saveButton.setAccessibilityLabel(
            inProgress ? "Applying saved settings" : "Save settings"
        )
        saveButton.needsDisplay = true
        window?.invalidateCursorRects(for: saveButton)
        if inProgress {
            saveStatusMessage = "Applying changes…"
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if updateButtonRect.contains(point) {
            if let url = updateAvailableURL { NSWorkspace.shared.open(url) } else { checkForUpdates() }
            return
        }
        if mappingsTabRect.contains(point) { selectTab(0); return }
        if settingsTabRect.contains(point) { selectTab(1); return }
        if appProfilesTabRect.contains(point) { selectTab(2); return }
        if advancedTabRect.contains(point) { selectTab(3); return }

        if closeButtonRect.contains(point) {
            if saveInProgress {
                NSSound.beep()
                saveStatusMessage = "Please wait while settings are applied…"
                needsDisplay = true
                return
            }
            onClose?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeader()
        drawFooter()
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        // Marketing version only — the build number ("(2)") is internal and reads as
        // a confusing pseudo-patch to users, so it's not shown in the header.
        return "v\(short)"
    }

    private func drawHeader() {
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.appTextSecondary
        ]
        // Mappings and Settings share the same centralized Klik PRO wordmark view.
        versionString.draw(
            at: NSPoint(x: headerWordmark.frame.maxX + 12, y: 43),
            withAttributes: bodyAttributes
        )

        // Check-for-updates button — lights up green when an update is available.
        let hasUpdate = updateAvailableURL != nil
        let updateFill: NSColor
        if hasUpdate {
            updateFill = updateButtonHovered
                ? (NSColor.systemGreen.blended(withFraction: 0.12, of: .white) ?? .systemGreen)
                : .systemGreen
        } else {
            updateFill = NSColor.controlAccentColor.withAlphaComponent(
                updateButtonHovered ? 0.20 : 0.12
            )
        }
        let updateButtonPath = NSBezierPath(
            roundedRect: updateButtonRect,
            xRadius: updateButtonRect.height / 2,
            yRadius: updateButtonRect.height / 2
        )
        updateFill.setFill()
        updateButtonPath.fill()
        if updateButtonHovered {
            (hasUpdate
                ? NSColor.white.withAlphaComponent(0.55)
                : NSColor.controlAccentColor.withAlphaComponent(0.68)
            ).setStroke()
            updateButtonPath.lineWidth = 1.5
            updateButtonPath.stroke()
        }
        let cfuAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: hasUpdate ? NSColor.white : NSColor.controlAccentColor
        ]
        let cfu = (hasUpdate ? "Update available" : "Check for Updates") as NSString
        let cfuSize = cfu.size(withAttributes: cfuAttrs)
        cfu.draw(at: NSPoint(x: updateButtonRect.midX - cfuSize.width / 2, y: updateButtonRect.midY - cfuSize.height / 2), withAttributes: cfuAttrs)

        // Pill tab bar: a rounded track holds the four tabs (visual order Mappings,
        // App Profiles, Settings, Advanced) with even padding; the active tab is a
        // filled accent pill with white text. Segment frames are measured here and
        // stored back into the named rects so mouseDown/selectTab stay in sync.
        let tabFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let tabHPad: CGFloat = 18
        let tabTrackPad: CGFloat = 4
        let tabTrackY: CGFloat = 42
        let tabTrackHeight: CGFloat = 32
        let tabLockGap: CGFloat = 5
        let tabLockWidth: CGFloat = 13
        let tabOrder: [(label: String, idx: Int)] = [
            ("Mappings", 0), ("App Profiles", 2), ("Settings", 1), ("Advanced", 3),
        ]
        let tabWidths: [CGFloat] = tabOrder.map { tab in
            let labelWidth = (tab.label as NSString).size(withAttributes: [.font: tabFont]).width
            let glyphWidth: CGFloat = (tab.idx == 3 && advancedView.locked) ? tabLockGap + tabLockWidth : 0
            return ceil(labelWidth) + glyphWidth + tabHPad * 2
        }
        let tabTrackWidth = tabWidths.reduce(0, +) + tabTrackPad * 2
        let tabTrackX = ((bounds.width - tabTrackWidth) / 2).rounded()
        NSColor.appTextPrimary.withAlphaComponent(0.06).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: tabTrackX, y: tabTrackY, width: tabTrackWidth, height: tabTrackHeight),
            xRadius: tabTrackHeight / 2, yRadius: tabTrackHeight / 2
        ).fill()
        var tabX = tabTrackX + tabTrackPad
        let tabPillY = tabTrackY + tabTrackPad
        let tabPillHeight = tabTrackHeight - tabTrackPad * 2
        for (i, tab) in tabOrder.enumerated() {
            let segWidth = tabWidths[i]
            let segRect = NSRect(x: tabX, y: tabTrackY, width: segWidth, height: tabTrackHeight)
            switch tab.idx {
            case 0: mappingsTabRect = segRect
            case 1: settingsTabRect = segRect
            case 2: appProfilesTabRect = segRect
            default: advancedTabRect = segRect
            }
            let active = activeTab == tab.idx
            if active {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: tabX, y: tabPillY, width: segWidth, height: tabPillHeight),
                    xRadius: tabPillHeight / 2, yRadius: tabPillHeight / 2
                ).fill()
            }
            let tAttrs: [NSAttributedString.Key: Any] = [
                .font: tabFont,
                .foregroundColor: active ? NSColor.white : NSColor.appTextSecondary,
            ]
            let labelWidth = (tab.label as NSString).size(withAttributes: tAttrs).width
            let glyphWidth: CGFloat = (tab.idx == 3 && advancedView.locked) ? tabLockGap + tabLockWidth : 0
            let labelX = tabX + (segWidth - labelWidth - glyphWidth) / 2
            (tab.label as NSString).draw(at: NSPoint(x: labelX, y: tabTrackY + 8), withAttributes: tAttrs)
            // A small lock glyph marks the Advanced tab while its options are locked.
            if tab.idx == 3, advancedView.locked,
               let lockGlyph = NSImage(
                   systemSymbolName: "lock.fill",
                   accessibilityDescription: "Locked"
               )?.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                       .applying(.init(paletteColors: [active ? .white : .appTextSecondary]))
               ) {
                let gh = lockGlyph.size.height
                lockGlyph.draw(in: NSRect(
                    x: labelX + labelWidth + tabLockGap,
                    y: tabTrackY + 8 + (13 - gh) / 2 + 1,
                    width: lockGlyph.size.width,
                    height: gh
                ))
            }
            tabX += segWidth
        }
    }

    // silent = auto-check on launch: never shows the "up to date"/"couldn't check" alerts,
    // only lights up the header button if a newer release exists.
    private func checkForUpdates(silent: Bool = false) {
        if !silent { saveStatusMessage = "Checking for updates…"; needsDisplay = true }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/AminudinMurad/klik-pro/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Klik-PRO", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !silent { self.saveStatusMessage = nil; self.needsDisplay = true }
                guard error == nil, let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = obj["tag_name"] as? String else {
                    if !silent {
                        self.showUpdateAlert("Couldn't check for updates",
                                             "Please check your connection and try again, or visit the Releases page.",
                                             URL(string: "https://github.com/AminudinMurad/klik-pro/releases"))
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let releaseURL = (obj["html_url"] as? String).flatMap { URL(string: $0) }
                if self.isNewer(latest, than: current) {
                    self.updateAvailableURL = releaseURL
                    self.needsDisplay = true
                    if !silent {
                        self.showUpdateAlert("Update available — \(tag)",
                                             "You have v\(current). Open the release page to download the latest version.",
                                             releaseURL)
                    }
                } else if !silent {
                    self.showUpdateAlert("You're up to date", "Klik PRO v\(current) is the latest version.", nil)
                }
            }
        }.resume()
    }

    func checkForUpdatesFromMenuBar() {
        NSApp.activate(ignoringOtherApps: true)
        checkForUpdates()
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func showUpdateAlert(_ title: String, _ info: String, _ releaseURL: URL?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        if let url = releaseURL {
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func drawFooter() {
        NSColor.controlColor.setFill()
        let closeButtonPath = NSBezierPath(
            roundedRect: closeButtonRect,
            xRadius: closeButtonRect.height / 2,
            yRadius: closeButtonRect.height / 2
        )
        closeButtonPath.fill()
        if closeButtonHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.68).setStroke()
            closeButtonPath.lineWidth = 1.5
            closeButtonPath.stroke()
        }

        drawCentered("Close", in: closeButtonRect, font: .systemFont(ofSize: 14), color: .appTextPrimary)

        if hasUnsavedConfigurationChanges {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.systemRed
            ]
            "Unsaved changes".draw(at: NSPoint(x: 184, y: 866), withAttributes: attrs)
        }

        if let message = saveStatusMessage {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.appTextSecondary
            ]
            message.draw(at: NSPoint(x: 356, y: 866), withAttributes: attrs)
        }
    }

    private func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let nsText = text as NSString
        let size = nsText.size(withAttributes: attrs)
        nsText.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ToggleWindowController?
    private var updateCheckObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller = ToggleWindowController()
        controller?.showWindow(nil)
        // A menu-bar Quit stops the background helper; reopening the app should
        // bring the mouse icon and shortcuts back rather than requiring a
        // Launch-at-login toggle. No-ops when the helper is already running.
        controller?.ensureBackgroundHelperRunningAtLaunch()
        updateCheckObserver = DistributedNotificationCenter.default().addObserver(
            forName: updateCheckRequestedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controller?.checkForUpdatesFromMenuBar()
        }
        DispatchQueue.main.async { [weak self] in
            self?.controller?.guideAccessibilityRegrantAfterUpdateIfNeeded()
            self?.controller?.showFirstLaunchOnboardingIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    deinit {
        if let updateCheckObserver = updateCheckObserver {
            DistributedNotificationCenter.default().removeObserver(updateCheckObserver)
        }
    }
}

// NOTE: With KlikProConfig.swift compiled alongside this file, Swift no
// longer treats this file as an implicit script entry point (that special case only
// applies when a single file is passed to swiftc), so app startup is wrapped in an
// `@main` type rather than living as bare top-level statements.
@main
private struct KlikProAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
