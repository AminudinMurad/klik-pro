import AppKit

extension NSColor {
    /// A small global legibility boost (owner request): slightly darker/crisper
    /// than the system label colors, still adapting to light and dark mode. These
    /// replace labelColor / secondaryLabelColor for the app's text.
    static let appTextPrimary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.96, alpha: 1)
            : NSColor(calibratedWhite: 0.11, alpha: 1)
    }
    static let appTextSecondary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.72, alpha: 1)
            : NSColor(calibratedWhite: 0.40, alpha: 1)
    }
}

/// Shared styling for the small cards that sit on the white panel surfaces. The fill is
/// a label-color tint so it reads as a soft gray in light mode and inverts in dark mode;
/// a plain white fill on the white panels left the cards visually indistinguishable.
let innerCardFillColor = NSColor.appTextPrimary.withAlphaComponent(0.045)
let innerCardCornerRadius: CGFloat = 10
let innerCardSpacing: CGFloat = 10

private final class FlippedProfileStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class AppProfileButton: NSButton {
    var onPress: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressedDown = false
    private var baseTitle: String = ""
    /// When set, the button shows `baseTitle` at rest and this string on hover.
    /// Used by the assign control to show the current assignment normally and
    /// "Change ⋯" on hover.
    var hoverTitle: String?
    /// When true, the control renders in the "in use" state — a green pill
    /// background (the icon and label keep their normal color) — so an
    /// already-assigned mouse button is clearly distinguishable from an unassigned
    /// one. Hover and press behaviour are unchanged.
    private var isAssigned = false

    override var isEnabled: Bool {
        didSet {
            updateBackground()
            window?.invalidateCursorRects(for: self)
        }
    }

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        self.title = title
        // The pill is drawn on the button's own layer so its corner radius can match
        // innerCardCornerRadius exactly; the system .rounded bezel is not adjustable.
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        font = .systemFont(ofSize: 12, weight: .semibold)
        target = self
        action = #selector(pressed)
        setAccessibilityLabel(title)
        updateBackground()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if let hoverTitle { title = hoverTitle }
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if hoverTitle != nil { title = baseTitle }
        updateBackground()
    }

    /// Configures the button as an assignment control: a leading SF Symbol
    /// indicator (chain = linked, link-plus = not yet linked), a rest label (the
    /// assignment itself, e.g. "Forward Button", in normal text color), and an
    /// optional hover label ("Change ⋯"). Falls back to no symbol if the system
    /// symbol is unavailable.
    func configureAssignment(
        restTitle: String,
        symbolName: String,
        hoverTitle: String?,
        assigned: Bool = false
    ) {
        self.baseTitle = restTitle
        self.hoverTitle = hoverTitle
        self.isAssigned = assigned
        // Assigned state uses a green pill background only; the chain-link icon and
        // the label keep the normal (original) color.
        self.contentTintColor = nil
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true
            self.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            )
            self.imagePosition = .imageLeading
            self.imageHugsTitle = true
        } else {
            self.image = nil
            self.imagePosition = .noImage
        }
        self.title = isHovered ? (hoverTitle ?? restTitle) : restTitle
        updateBackground()
    }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressedDown = flag
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    /// One place decides the pill fill so hover, press, and disabled states compose:
    /// pressed is darkest, hover sits between rest and press, disabled is faint.
    private func updateBackground() {
        let hoverActive = isEnabled && (isHovered || isPressedDown)
        let alpha: CGFloat
        if !isEnabled {
            alpha = 0.05
        } else if isPressedDown {
            alpha = 0.36
        } else if isHovered {
            alpha = 0.18
        } else {
            alpha = 0.08
        }
        // Hover and press turn every pill green so all buttons share the same
        // "actionable" cue as the primary Save button's green-on-hover. At rest
        // the pill is green only for an in-use assignment, otherwise neutral.
        let fillBase = (hoverActive || isAssigned) ? KlikProBrand.green : NSColor.appTextPrimary
        layer?.backgroundColor = fillBase.withAlphaComponent(alpha).cgColor
    }

    required init?(coder: NSCoder) { nil }
    @objc private func pressed() { onPress?() }
}

private final class DualAppGeneratorCard: NSView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let generateButton = AppProfileButton(title: "Generate", frame: .zero)
    private let changeButton = AppProfileButton(title: "Change App", frame: .zero)
    private(set) var candidate: AppProfileCandidate?
    let bundleIdentifier: String
    let fallbackName: String
    var onGenerate: ((AppProfileCandidate) -> Void)?
    var onChange: (() -> Void)?

    override var isFlipped: Bool { true }

    init(bundleIdentifier: String, fallbackName: String, width: CGFloat) {
        self.bundleIdentifier = bundleIdentifier
        self.fallbackName = fallbackName
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 112))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        iconView.frame = NSRect(x: 14, y: 14, width: 48, height: 48)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.frame = NSRect(x: 76, y: 14, width: width - 90, height: 24)
        nameField.font = .systemFont(ofSize: 15, weight: .semibold)
        statusField.frame = NSRect(x: 76, y: 40, width: width - 90, height: 20)
        statusField.font = .systemFont(ofSize: 11, weight: .medium)
        generateButton.frame = NSRect(x: 14, y: 70, width: width - 28, height: 28)
        changeButton.frame = NSRect(x: width / 2 + 4, y: 70, width: width / 2 - 18, height: 28)
        generateButton.onPress = { [weak self] in
            guard let self, let candidate = self.candidate else { return }
            self.onGenerate?(candidate)
        }
        changeButton.onPress = { [weak self] in self?.onChange?() }
        [iconView, nameField, statusField, generateButton, changeButton].forEach(addSubview)
        showLoading()
    }

    required init?(coder: NSCoder) { nil }

    func showLoading() {
        candidate = nil
        nameField.stringValue = fallbackName
        iconView.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Loading")
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        statusField.stringValue = "Loading apps…"
        statusField.textColor = .appTextSecondary
        generateButton.isEnabled = false
        changeButton.isEnabled = false
        changeButton.isHidden = true
        generateButton.frame = NSRect(x: 14, y: 70, width: bounds.width - 28, height: 28)
    }

    func update(candidate: AppProfileCandidate?, alternativesAvailable: Bool) {
        self.candidate = candidate
        nameField.stringValue = candidate?.app.displayName ?? fallbackName
        if let candidate {
            iconView.image = NSWorkspace.shared.icon(forFile: candidate.app.bundleURL.path)
            statusField.stringValue = "Installed"
            statusField.textColor = .systemGreen
            generateButton.isEnabled = true
        } else {
            iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            statusField.stringValue = "Not installed"
            statusField.textColor = .appTextSecondary
            generateButton.isEnabled = false
        }
        changeButton.isEnabled = alternativesAvailable
        changeButton.isHidden = !alternativesAvailable
        if alternativesAvailable {
            generateButton.frame = NSRect(x: 14, y: 70, width: bounds.width / 2 - 18, height: 28)
            changeButton.frame = NSRect(
                x: bounds.width / 2 + 4,
                y: 70,
                width: bounds.width / 2 - 18,
                height: 28
            )
        } else {
            generateButton.frame = NSRect(x: 14, y: 70, width: bounds.width - 28, height: 28)
        }
    }
}

final class AppProfileInstanceRowView: NSView {
    /// The card height. The list pins each row to this, so keep them in sync.
    static let rowHeight: CGFloat = 92
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let menuBarLabel = NSTextField(labelWithString: "Menu bar")
    private let menuBarToggle: ToggleSwitchView
    private let renameButton = AppProfileButton(title: "Rename", frame: .zero)
    private let removeButton = AppProfileButton(title: "Remove", frame: .zero)
    private(set) var instance: AppProfileInstance
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onRename: ((AppProfileInstance) -> Void)?
    var onRemove: ((AppProfileInstance) -> Void)?

    override var isFlipped: Bool { true }

    init(instance: AppProfileInstance, health: AppProfileRuntimeHealth?, width: CGFloat) {
        self.instance = instance
        self.menuBarToggle = ToggleSwitchView(isOn: instance.pinToMenuBar, frame: .zero)
        // Two-row card: a large app icon fills the left edge across both rows. Row 1
        // (top) carries the app name (left) and the Menu bar toggle (right); row 2
        // (bottom) carries all the action buttons, right-flushed.
        let rowHeight = Self.rowHeight
        let vpad: CGFloat = 16           // even top & bottom padding for both rows
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        let iconSize: CGFloat = 54
        iconView.frame = NSRect(x: 14, y: (rowHeight - iconSize) / 2, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSWorkspace.shared.icon(forFile: instance.source.bundleURL)
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .appTextPrimary
        titleField.stringValue = instance.label
        titleField.lineBreakMode = .byTruncatingTail

        let managed = instance.launcherKind == .managed

        let gap: CGFloat = 8
        let buttonH: CGFloat = 28
        let openW: CGFloat = 52
        // Wider than the other controls so the assignment label ("Gesture Button")
        // fits alongside the chain-link indicator without truncating.
        let assignW: CGFloat = 132
        let menuCaptionW: CGFloat = 56
        let toggleW: CGFloat = 40
        let renameW: CGFloat = 62
        let removeW: CGFloat = 66
        let rightEdge = width - 18   // right padding so controls clear the card border

        // Row 1 (top): Menu bar label + toggle, flushed to the right edge.
        let toggleY: CGFloat = vpad
        let toggleX = rightEdge - toggleW
        menuBarLabel.frame = NSRect(
            x: toggleX - 4 - menuCaptionW, y: toggleY + 3, width: menuCaptionW, height: 16
        )
        menuBarLabel.font = .systemFont(ofSize: 11, weight: .medium)
        menuBarLabel.textColor = .appTextSecondary
        menuBarLabel.alignment = .right
        menuBarToggle.frame = NSRect(x: toggleX, y: toggleY, width: toggleW, height: 22)
        menuBarToggle.setAccessibilityLabel(
            instance.pinToMenuBar ? "Hide from menu bar" : "Show in menu bar"
        )

        // Row 2 (bottom): action buttons, flushed to the right edge. Left→right for
        // managed rows: Rename, Remove, Open, Assign — with Assign on the right edge.
        let buttonY = rowHeight - vpad - buttonH
        let assignX = rightEdge - assignW
        let openX = assignX - gap - openW
        openButton.frame = NSRect(x: openX, y: buttonY, width: openW, height: buttonH)
        assignButton.frame = NSRect(x: assignX, y: buttonY, width: assignW, height: buttonH)
        renameButton.isHidden = !managed
        removeButton.isHidden = !managed
        if managed {
            let removeX = openX - gap - removeW
            let renameX = removeX - gap - renameW
            renameButton.frame = NSRect(x: renameX, y: buttonY, width: renameW, height: buttonH)
            removeButton.frame = NSRect(x: removeX, y: buttonY, width: removeW, height: buttonH)
        }

        // The assign control shows the assignment IN its own label (normal color,
        // no separate green caption) with a chain-link indicator: linked when a
        // button is assigned, link-plus when not. Hovering swaps the label to
        // "Change ⋯". The name is shortened so it never runs under the controls.
        assignButton.font = .systemFont(ofSize: 11, weight: .semibold)
        if let mouseButton = instance.mouseButton {
            let assignmentTitle = "\(mouseButton.title) Button"
            assignButton.configureAssignment(
                restTitle: assignmentTitle, symbolName: "link", hoverTitle: "Change ⋯", assigned: true
            )
            assignButton.toolTip = assignmentTitle
            assignButton.setAccessibilityLabel("Change button assignment, currently \(assignmentTitle)")
        } else {
            assignButton.configureAssignment(
                restTitle: "Assign Button", symbolName: "link.badge.plus", hoverTitle: nil
            )
            assignButton.setAccessibilityLabel("Assign a mouse button")
        }
        // The name sits on the first row beside the icon, aligned with the Menu bar
        // toggle, and is capped to end before the Menu bar label (truncates if long).
        let nameX = iconView.frame.maxX + 14
        titleField.frame = NSRect(
            x: nameX, y: toggleY,
            width: max(80, menuBarLabel.frame.minX - nameX - gap), height: 22
        )
        openButton.onPress = { [weak self] in
            guard let self else { return }; self.onOpen?(self.instance)
        }
        assignButton.onPress = { [weak self] in
            guard let self else { return }; self.onAssign?(self.instance)
        }
        menuBarToggle.onChange = { [weak self] _ in
            guard let self else { return }
            // The controller owns the real menu-bar state and rebuilds this row on a
            // successful change; revert the optimistic flip so a blocked change (e.g.
            // unsaved edits) never leaves the toggle showing the wrong state.
            self.menuBarToggle.isOn = self.instance.pinToMenuBar
            self.onToggleMenuBar?(self.instance)
        }
        renameButton.onPress = { [weak self] in
            guard let self else { return }; self.onRename?(self.instance)
        }
        removeButton.onPress = { [weak self] in
            guard let self else { return }; self.onRemove?(self.instance)
        }
        [
            iconView, titleField, openButton, assignButton,
            menuBarLabel, menuBarToggle, renameButton, removeButton,
        ]
            .forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }
}

/// Compact profile row used beside Mappings. It offers quick Open plus Assign
/// Button (assigning a mouse button to launch the profile is natural on the
/// mouse-mapping tab); full management stays on the App Profiles tab.
private final class MappingAppProfileOpenRowView: NSView {
    /// Same card height as the App Profiles tab rows; the list pins each row to it.
    static let rowHeight: CGFloat = 92
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let instance: AppProfileInstance
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?

    override var isFlipped: Bool { true }

    init(instance: AppProfileInstance, health: AppProfileRuntimeHealth?, width: CGFloat) {
        self.instance = instance
        // Two-row card matching the App Profiles tab (without the toggle/manage
        // controls): a large icon on the left, the app name on row 1, and the
        // Assign + Open buttons right-flushed on row 2. Because the name owns row 1
        // on its own, even long names fit before truncating.
        let rowHeight = Self.rowHeight
        let vpad: CGFloat = 16
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        let iconSize: CGFloat = 54
        iconView.frame = NSRect(x: 14, y: (rowHeight - iconSize) / 2, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSWorkspace.shared.icon(forFile: instance.source.bundleURL)

        let gap: CGFloat = 8
        let buttonH: CGFloat = 28
        let rightEdge = width - 18
        let openW: CGFloat = 52
        let assignW: CGFloat = 132

        // Row 2 (bottom): Open + Assign, right-flushed (Assign on the right edge).
        let buttonY = rowHeight - vpad - buttonH
        let assignX = rightEdge - assignW
        let openX = assignX - gap - openW
        openButton.frame = NSRect(x: openX, y: buttonY, width: openW, height: buttonH)
        assignButton.frame = NSRect(x: assignX, y: buttonY, width: assignW, height: buttonH)

        // Row 1 (top): the app name beside the icon, using the full width.
        let nameX = iconView.frame.maxX + 14
        titleField.frame = NSRect(
            x: nameX, y: vpad, width: max(80, rightEdge - nameX), height: 24
        )
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .appTextPrimary
        titleField.stringValue = instance.label
        titleField.lineBreakMode = .byTruncatingTail

        // Mirror the App Profiles tab: the assignment is the button's own label
        // (normal color) with a chain-link indicator; hovering swaps it to
        // "Change ⋯". Link-plus indicates a not-yet-assigned profile.
        assignButton.font = .systemFont(ofSize: 11, weight: .semibold)
        if let mouseButton = instance.mouseButton {
            let assignmentTitle = "\(mouseButton.title) Button"
            assignButton.configureAssignment(
                restTitle: assignmentTitle, symbolName: "link", hoverTitle: "Change ⋯", assigned: true
            )
            assignButton.toolTip = assignmentTitle
            assignButton.setAccessibilityLabel(
                "Change button assignment, currently \(assignmentTitle)"
            )
        } else {
            assignButton.configureAssignment(
                restTitle: "Assign Button", symbolName: "link.badge.plus", hoverTitle: nil
            )
            assignButton.setAccessibilityLabel("Assign a mouse button")
        }
        assignButton.onPress = { [weak self] in
            guard let self else { return }
            self.onAssign?(self.instance)
        }
        openButton.onPress = { [weak self] in
            guard let self else { return }
            self.onOpen?(self.instance)
        }
        [iconView, titleField, assignButton, openButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }
}

/// The approved Mappings right column: a fixed header and independently scrolling
/// profile list. It offers quick Open and Assign Button; other management stays
/// on the App Profiles tab.
final class MappingAppProfilesView: NSView {
    private let titleField = NSTextField(labelWithString: "YOUR APP PROFILES")
    private let statusField = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let stackView = FlippedProfileStackView()
    private var instances: [AppProfileInstance]
    private var runtimeHealth: [UUID: AppProfileRuntimeHealth] = [:]
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?

    override var isFlipped: Bool { true }

    init(instances: [AppProfileInstance], frame: NSRect) {
        self.instances = instances
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        titleField.frame = NSRect(x: 18, y: 20, width: frame.width - 36, height: 19)
        titleField.font = .boldSystemFont(ofSize: 12)
        titleField.textColor = .appTextSecondary
        // The status line ("… is ready.") is hidden here too; the list is the
        // content. Hiding it lets the list start higher and show more profiles.
        statusField.frame = NSRect(x: 18, y: 43, width: frame.width - 36, height: 16)
        statusField.font = .systemFont(ofSize: 11, weight: .semibold)
        statusField.textColor = .systemGreen
        statusField.isHidden = true

        scrollView.frame = NSRect(x: 14, y: 44, width: frame.width - 28, height: frame.height - 58)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        // Tighter gap than the management tab so the read-only list packs in more
        // profiles before it needs to scroll.
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 1, left: 0, bottom: 2, right: 0)
        scrollView.documentView = stackView

        [titleField, statusField, scrollView].forEach(addSubview)
        rebuildRows()
    }

    required init?(coder: NSCoder) { nil }

    func setInstances(_ instances: [AppProfileInstance]) {
        self.instances = instances
        runtimeHealth = runtimeHealth.filter { id, _ in instances.contains { $0.id == id } }
        rebuildRows()
    }

    func setRuntimeHealth(_ health: [UUID: AppProfileRuntimeHealth]) {
        runtimeHealth = health
        rebuildRows()
    }

    func setStatus(_ message: String, color: NSColor = .appTextSecondary) {
        statusField.stringValue = message
        statusField.textColor = color
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let rowWidth = max(320, scrollView.contentSize.width - 4)
        let visible = instances.filter { instance in
            instance.launcherKind == .managed
                || previewRenderingIsActive
                || FileManager.default.fileExists(atPath: instance.launcherPath)
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        if visible.isEmpty {
            let empty = NSTextField(labelWithString: "No App Profiles yet")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .appTextSecondary
            empty.alignment = .center
            stackView.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 56).isActive = true
        } else {
            visible.forEach { instance in
                let row = MappingAppProfileOpenRowView(
                    instance: instance,
                    health: runtimeHealth[instance.id],
                    width: rowWidth
                )
                row.onOpen = { [weak self] in self?.onOpen?($0) }
                row.onAssign = { [weak self] in self?.onAssign?($0) }
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
                row.heightAnchor.constraint(
                    equalToConstant: MappingAppProfileOpenRowView.rowHeight
                ).isActive = true
            }
        }
        stackView.frame = NSRect(
            x: 0,
            y: 0,
            width: rowWidth,
            height: max(scrollView.contentSize.height, CGFloat(max(1, visible.count)) * 100 + 3)
        )
    }
}

final class AppProfilesContentView: NSView {
    private let explanationField = NSTextField(wrappingLabelWithString:
        "Generate another icon for the same app, with a separate login and settings. The original app is never copied, cloned or modified."
    )
    private let statusField = NSTextField(labelWithString: "")
    private let chatGPTCard: DualAppGeneratorCard
    private let claudeCard: DualAppGeneratorCard
    private let loadingView = NSView()
    private let loadingSpinner = NSProgressIndicator()
    private let loadingField = NSTextField(labelWithString: "Scanning installed apps…")
    private let refreshButton = AppProfileButton(title: "Refresh App List", frame: .zero)
    private let scrollView = NSScrollView()
    private let stackView = FlippedProfileStackView()
    var onGenerate: ((AppProfileCandidate) -> Void)?
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onRename: ((AppProfileInstance) -> Void)?
    var onRemove: ((AppProfileInstance) -> Void)?
    var onChangeApp: ((String) -> Void)?
    var onRefreshApps: (() -> Void)?
    var onInstancesChange: (([AppProfileInstance]) -> Void)?
    var onRuntimeHealthChange: (([UUID: AppProfileRuntimeHealth]) -> Void)?
    var onStatusChange: ((String, NSColor) -> Void)?
    private var instances: [AppProfileInstance] = []
    private var supportedCandidates: [AppProfileCandidate] = []
    private var runtimeHealth: [UUID: AppProfileRuntimeHealth] = [:]

    override var isFlipped: Bool { true }

    init(instances: [AppProfileInstance], width: CGFloat) {
        let generatorWidth: CGFloat = 292
        chatGPTCard = DualAppGeneratorCard(
            bundleIdentifier: "com.openai.codex", fallbackName: "ChatGPT", width: generatorWidth
        )
        claudeCard = DualAppGeneratorCard(
            bundleIdentifier: "com.anthropic.claudefordesktop", fallbackName: "Claude", width: generatorWidth
        )
        // Match the outer scroll viewport so the profiles column fills the window rather
        // than leaving empty space below a fixed-height card.
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 702))

        explanationField.frame = NSRect(x: 18, y: 78, width: generatorWidth, height: 64)
        explanationField.font = .systemFont(ofSize: 12)
        explanationField.textColor = .appTextSecondary
        chatGPTCard.frame.origin = NSPoint(x: 18, y: 154)
        claudeCard.frame.origin = NSPoint(x: 18, y: 154 + 112 + innerCardSpacing)
        loadingView.frame = NSRect(x: 18, y: 154, width: generatorWidth, height: 224 + innerCardSpacing)
        loadingView.wantsLayer = true
        loadingView.layer?.cornerRadius = innerCardCornerRadius
        loadingView.layer?.backgroundColor = innerCardFillColor.cgColor
        loadingView.layer?.borderColor = NSColor.separatorColor.cgColor
        loadingView.layer?.borderWidth = 1
        loadingSpinner.frame = NSRect(x: generatorWidth / 2 - 12, y: 88, width: 24, height: 24)
        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .regular
        loadingSpinner.isIndeterminate = true
        loadingField.frame = NSRect(x: 0, y: 122, width: generatorWidth, height: 20)
        loadingField.font = .systemFont(ofSize: 12, weight: .medium)
        loadingField.textColor = .appTextSecondary
        loadingField.alignment = .center
        loadingView.setAccessibilityLabel("Scanning installed apps")
        loadingView.addSubview(loadingSpinner)
        loadingView.addSubview(loadingField)
        // The transient status line ("… is ready.", "… was generated") is
        // intentionally hidden: the list itself shows the profiles, and failures
        // already surface as an alert. The field is kept (off-screen text sink)
        // so the many setStatus call sites stay valid.
        statusField.frame = NSRect(x: 344, y: 108, width: width - 362, height: 20)
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .appTextSecondary
        statusField.isHidden = true
        // Refresh re-scans installed apps for both columns; it sits in the panel's
        // top-right corner, out of the way of the column divider and headers.
        refreshButton.frame = NSRect(x: width - 174, y: 12, width: 160, height: 28)
        refreshButton.onPress = { [weak self] in self?.onRefreshApps?() }

        scrollView.frame = NSRect(x: 340, y: 142, width: width - 356, height: 546)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = innerCardSpacing
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        scrollView.documentView = stackView

        chatGPTCard.onGenerate = { [weak self] in self?.onGenerate?($0) }
        claudeCard.onGenerate = { [weak self] in self?.onGenerate?($0) }
        chatGPTCard.onChange = { [weak self] in self?.onChangeApp?("com.openai.codex") }
        claudeCard.onChange = { [weak self] in self?.onChangeApp?("com.anthropic.claudefordesktop") }
        [explanationField, chatGPTCard, claudeCard, loadingView, statusField, refreshButton, scrollView].forEach(addSubview)
        setAppDiscoveryLoading()
        setInstances(instances)
    }

    required init?(coder: NSCoder) { nil }

    func setInstances(_ instances: [AppProfileInstance]) {
        self.instances = instances
        runtimeHealth = runtimeHealth.filter { id, _ in instances.contains { $0.id == id } }
        rebuildRows()
        onInstancesChange?(instances)
    }

    func setSupportedCandidates(_ candidates: [AppProfileCandidate]) {
        supportedCandidates = candidates.filter { $0.canCreate }
        let chatGPT = supportedCandidates.first { $0.app.bundleIdentifier == chatGPTCard.bundleIdentifier }
        let claude = supportedCandidates.first { $0.app.bundleIdentifier == claudeCard.bundleIdentifier }
        let alternatives = supportedCandidates.filter {
            $0.app.bundleIdentifier != chatGPTCard.bundleIdentifier
                && $0.app.bundleIdentifier != claudeCard.bundleIdentifier
        }
        loadingSpinner.stopAnimation(nil)
        loadingView.isHidden = true
        refreshButton.isEnabled = true
        refreshButton.title = "Refresh App List"
        refreshButton.setAccessibilityLabel("Refresh App List")
        chatGPTCard.isHidden = false
        claudeCard.isHidden = false
        chatGPTCard.update(candidate: chatGPT, alternativesAvailable: !alternatives.isEmpty)
        claudeCard.update(candidate: claude, alternativesAvailable: !alternatives.isEmpty)
        if statusField.stringValue == "Scanning installed apps…" {
            setStatus("")
        }
    }

    func setAppDiscoveryLoading() {
        chatGPTCard.isHidden = true
        claudeCard.isHidden = true
        loadingView.isHidden = false
        loadingSpinner.startAnimation(nil)
        refreshButton.isEnabled = false
        refreshButton.title = "Refreshing…"
        refreshButton.setAccessibilityLabel("Refreshing app list")
        setStatus("Scanning installed apps…")
    }

    func setRuntimeHealth(_ health: [UUID: AppProfileRuntimeHealth]) {
        runtimeHealth = health
        rebuildRows()
        onRuntimeHealthChange?(health)
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0); $0.removeFromSuperview()
        }
        // Leave a right margin so the cards clear the vertical scroller instead of
        // sitting right against it.
        let rowWidth = max(430, scrollView.contentSize.width - 20)
        let visible = instances.filter { instance in
            instance.launcherKind == .managed
                || previewRenderingIsActive
                || FileManager.default.fileExists(atPath: instance.launcherPath)
        }
        if visible.isEmpty {
            let empty = NSTextField(labelWithString: "No App Profiles yet")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .appTextSecondary
            empty.alignment = .center
            stackView.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 70).isActive = true
        } else {
            for instance in visible.sorted(by: { $0.label.localizedStandardCompare($1.label) == .orderedAscending }) {
                let row = AppProfileInstanceRowView(
                    instance: instance, health: runtimeHealth[instance.id], width: rowWidth
                )
                row.onOpen = { [weak self] in self?.onOpen?($0) }
                row.onAssign = { [weak self] in self?.onAssign?($0) }
                row.onToggleMenuBar = { [weak self] in self?.onToggleMenuBar?($0) }
                row.onRename = { [weak self] in self?.onRename?($0) }
                row.onRemove = { [weak self] in self?.onRemove?($0) }
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
                // Must match AppProfileInstanceRowView's rowHeight, or the card is
                // clipped and the bottom row loses its padding.
                row.heightAnchor.constraint(
                    equalToConstant: AppProfileInstanceRowView.rowHeight
                ).isActive = true
            }
        }
        stackView.frame = NSRect(
            x: 0, y: 0, width: rowWidth,
            height: max(scrollView.contentSize.height, CGFloat(max(1, visible.count)) * 102 + 4)
        )
    }

    func setStatus(_ message: String, color: NSColor = .appTextSecondary) {
        statusField.stringValue = message
        statusField.textColor = color
        onStatusChange?(message, color)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        border.lineWidth = 1; border.stroke()
        "APP PROFILE GENERATOR".draw(at: NSPoint(x: 18, y: 52), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.appTextSecondary,
        ])
        "YOUR APP PROFILES".draw(at: NSPoint(x: 344, y: 52), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.appTextSecondary,
        ])
        ("Open, assign, or manage each separate profile." as NSString).draw(
            at: NSPoint(x: 344, y: 79),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.appTextPrimary,
            ]
        )
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 327.5, y: 0, width: 1, height: bounds.height)).fill()
    }
}
