import AppKit
import QuartzCore
import UniformTypeIdentifiers

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

/// Geometry shared by every two-row app card — the App Profiles generator, the
/// App Profiles list, and both Mappings lists. Row 1 carries the name, the
/// optional compatibility badge and the gear; row 2 carries the action buttons,
/// right-flushed; the icon spans both rows on the left. All four lists pin to
/// these numbers so the cards line up across the two tabs, which is the whole
/// point of the shared layout — keep them here rather than per class.
enum AppCardMetrics {
    static let height: CGFloat = 86
    static let iconSize: CGFloat = 56
    static let iconX: CGFloat = 14
    static let iconNameGap: CGFloat = 12
    /// Right padding, which also keeps the actions clear of a list scroller.
    static let rightInset: CGFloat = 14
    static let gearSize: CGFloat = 26
    static let gearY: CGFloat = 12
    /// The list-order pin, right-most on row 1. Same box as the gear so the two read
    /// as one control cluster rather than two unrelated affordances.
    static let pinSize: CGFloat = gearSize
    /// Deliberately tighter than `buttonGap`: the pin and gear are a pair.
    static let gearPinGap: CGFloat = 2
    static let nameY: CGFloat = 14
    static let nameHeight: CGFloat = 22
    static let actionY: CGFloat = 46
    static let actionHeight: CGFloat = 28
    static let buttonGap: CGFloat = 8
    static let openWidth: CGFloat = 52
    static let generateWidth: CGFloat = 96
    static let badgeWidth: CGFloat = 66
    static let badgeGap: CGFloat = 8
    /// Minimum width the assignment pill may shrink to before its label truncates.
    static let minAssignWidth: CGFloat = 84

    static var nameX: CGFloat { iconX + iconSize + iconNameGap }

    static func iconFrame() -> NSRect {
        NSRect(x: iconX, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
    }

    /// Right-most control on row 1, so it lands on the same vertical line as the
    /// action row's trailing edge below it.
    static func pinFrame(cardWidth: CGFloat) -> NSRect {
        NSRect(x: cardWidth - rightInset - pinSize, y: gearY, width: pinSize, height: pinSize)
    }

    /// Sits immediately left of the pin. Every card that uses this also carries a pin,
    /// so the shift is unconditional and the three lists stay aligned with each other.
    static func gearFrame(cardWidth: CGFloat) -> NSRect {
        NSRect(
            x: pinFrame(cardWidth: cardWidth).minX - gearPinGap - gearSize,
            y: gearY, width: gearSize, height: gearSize
        )
    }
}

/// The Verified / Unverified compatibility pill. Only the two lists that show
/// catalogue apps use it (the generator column and Mappings' Native Apps); the
/// App Profiles lists stay badge-free in both tabs.
func makeCompatibilityBadgeField() -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = .systemFont(ofSize: 10, weight: .semibold)
    field.alignment = .center
    field.wantsLayer = true
    field.layer?.cornerRadius = 4
    field.isHidden = true
    return field
}

/// Applies the badge treatment: green reads as proven, amber as known-but-unproven.
/// Passing nil hides the pill, which is what a card with no candidate does.
func applyCompatibilityBadge(_ field: NSTextField, verified: Bool?) {
    guard let verified else {
        field.isHidden = true
        return
    }
    field.isHidden = false
    field.stringValue = verified ? "Verified" : "Unverified"
    field.textColor = verified
        ? NSColor.systemGreen.blended(withFraction: 0.35, of: .black) ?? .systemGreen
        : NSColor.systemOrange.blended(withFraction: 0.4, of: .black) ?? .systemOrange
    field.layer?.backgroundColor = (verified ? NSColor.systemGreen : NSColor.systemOrange)
        .withAlphaComponent(0.16).cgColor
}

/// Sizes a card's name field to its own text so the badge can sit immediately
/// after it, with both kept clear of the gear. A hidden badge gives the name the
/// whole row. Shared so the generator and Mappings' Native Apps agree exactly.
func layoutNameAndBadge(
    nameField: NSTextField,
    badgeField: NSTextField,
    gearMinX: CGFloat
) {
    let nameX = AppCardMetrics.nameX
    // Measure through the cell, not the raw string: NSTextField adds its own inset
    // around the glyphs, so sizing to NSString.size alone leaves a field a couple of
    // points too narrow and the label truncates ("Claude" → "Clau…") with empty space
    // still beside it.
    let textW: CGFloat
    if let cell = nameField.cell {
        textW = ceil(cell.cellSize.width) + 2
    } else {
        let font = nameField.font ?? .systemFont(ofSize: 15, weight: .semibold)
        textW = ceil((nameField.stringValue as NSString)
            .size(withAttributes: [.font: font]).width) + 6
    }
    let badgeW: CGFloat = badgeField.isHidden ? 0 : AppCardMetrics.badgeWidth
    let available = gearMinX - 10 - nameX
    let nameW = max(
        40,
        min(textW, available - (badgeW > 0 ? badgeW + AppCardMetrics.badgeGap : 0))
    )
    nameField.frame = NSRect(
        x: nameX, y: AppCardMetrics.nameY, width: nameW, height: AppCardMetrics.nameHeight
    )
    if !badgeField.isHidden {
        badgeField.frame = NSRect(
            x: nameX + nameW + AppCardMetrics.badgeGap,
            y: AppCardMetrics.nameY + 3,
            width: badgeW,
            height: 16
        )
    }
}

/// Lays out the two-button action row (Open + Assign) right-flushed on row 2, so
/// the three lists that lack "+ New Profile" still end on the same vertical line
/// as the generator's three buttons and the gear above them. The assignment pill
/// sizes to its own label instead of stretching.
func layoutOpenAndAssign(
    openButton: AppProfileButton,
    assignButton: AppProfileButton,
    cardWidth: CGFloat
) {
    let gap = AppCardMetrics.buttonGap
    let openW = AppCardMetrics.openWidth
    let maxAssign = max(
        AppCardMetrics.minAssignWidth,
        cardWidth - openW - gap - AppCardMetrics.nameX - AppCardMetrics.rightInset
    )
    let assignW = min(assignButton.preferredAssignmentWidth(), maxAssign)
    let rightEdge = cardWidth - AppCardMetrics.rightInset
    let assignX = rightEdge - assignW
    let openX = assignX - gap - openW
    let y = AppCardMetrics.actionY
    let h = AppCardMetrics.actionHeight
    openButton.frame = NSRect(x: openX, y: y, width: openW, height: h)
    assignButton.frame = NSRect(x: assignX, y: y, width: assignW, height: h)
}

/// A menu row carrying a live toggle switch, used as the last item of every card's
/// gear menu. It is a real switch rather than a checkmark item, so an NSMenuItem
/// custom view hosts the same ToggleSwitchView the cards used to show inline.
/// The controller owns the real state and rebuilds the row on success, so the
/// switch is reverted to the known value immediately and only the request is
/// forwarded — a blocked change never leaves the switch lying.
func makeMenuBarToggleItem(
    isOn: Bool,
    isEnabled: Bool,
    onChange: @escaping () -> Void,
    cancelTracking: @escaping () -> Void
) -> NSMenuItem {
    let item = NSMenuItem()
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
    let label = NSTextField(labelWithString: "Menu Bar Icon")
    label.font = .systemFont(ofSize: 13)
    label.frame = NSRect(x: 14, y: 7, width: 140, height: 17)
    let toggle = ToggleSwitchView(
        isOn: isOn, frame: NSRect(x: 186, y: 4, width: 40, height: 22)
    )
    toggle.isEnabled = isEnabled
    toggle.setAccessibilityLabel(isOn ? "Hide from menu bar" : "Show in menu bar")
    toggle.onChange = { _ in
        toggle.isOn = isOn
        onChange()
        cancelTracking()
    }
    container.addSubview(label)
    container.addSubview(toggle)
    item.view = container
    return item
}

/// The icon-only rescan control that sits inline at the right of each list's
/// section header. Four exist (two per tab) and every one calls the same
/// `onRefreshApps` — a duplicated affordance, not duplicated behaviour, so
/// whichever column the user is reading has the control to hand. Sitting inline
/// with the section title it also costs no vertical space.
func makeRefreshIconButton() -> RefreshIconButton {
    let button = RefreshIconButton(frame: .zero)
    button.toolTip = "Refresh App List"
    button.setAccessibilityLabel("Refresh App List")
    return button
}

/// Keeps a refresh icon's animation and state in step with the others.
func applyRefreshIconState(_ button: RefreshIconButton, refreshing: Bool) {
    button.setRefreshing(refreshing)
}

/// Stable-partitions a list so pinned entries lead, in the order the user pinned them,
/// with everything else keeping its incoming order behind them.
///
/// Driven by the ordered pin array and never by a `Set`: `Set` iteration order varies
/// between processes, which would make two otherwise identical fixture renders differ
/// and fail the byte-comparison in `tools/check.sh`. `enumerated()` supplies the
/// tie-break so the comparator is a strict weak ordering and unpinned items keep their
/// relative order.
func topPinnedFirst<Element, Key: Hashable>(
    _ items: [Element],
    pins: [Key],
    key: (Element) -> Key
) -> [Element] {
    guard !pins.isEmpty else { return items }
    // First occurrence wins, and duplicates are tolerated rather than trapped: a
    // hand-edited config can repeat an entry, and this is a render path.
    var rank: [Key: Int] = [:]
    for (index, pin) in pins.enumerated() where rank[pin] == nil {
        rank[pin] = index
    }
    return items.enumerated().sorted { lhs, rhs in
        switch (rank[key(lhs.element)], rank[key(rhs.element)]) {
        case let (left?, right?):
            return left == right ? lhs.offset < rhs.offset : left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.offset < rhs.offset
        }
    }.map(\.element)
}

/// The icon-only list-order pin that sits right of each card's gear. Both tabs carry
/// it, because the pin the user sets on either one decides which cards lead the list
/// everywhere — one preference, two places to set it.
final class AppProfilePinButton: NSButton {
    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        // The pin is intentionally a bare glyph, not a pill. Rotate the whole
        // square control so every card uses the same 20° clockwise treatment.
        layer?.transform = CATransform3DMakeRotation(
            -20 * .pi / 180, 0, 0, 1
        )
        target = self
        action = #selector(pressed)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    @objc private func pressed() { onPress?() }
}

func makePinIconButton() -> AppProfilePinButton {
    AppProfilePinButton(frame: .zero)
}

/// Applies a pin's three states. `atLimit` is the case worth being careful with: the
/// cap never silently evicts an existing pin, so an unpinned card in a full list shows
/// a disabled pin that says why, rather than a live control that quietly swaps
/// something else out.
func applyPinIconState(_ button: AppProfilePinButton, pinned: Bool, atLimit: Bool) {
    let symbol = pinned ? "pin.fill" : "pin"
    if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
       let sized = base.withSymbolConfiguration(
           NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
       ) {
        sized.isTemplate = true
        button.image = sized
    }
    // A pinned card stays actionable so it can always be unpinned — that is the only
    // way to free a slot once the list is full.
    button.isEnabled = pinned || !atLimit
    // The glyph carries the state, not just the pill: AppProfileButton's disabled pill is
    // only 0.03 alpha lighter than its resting one, which on a 26pt control is far too
    // subtle to read as "no slots left" without hovering for the tooltip.
    if pinned {
        button.contentTintColor = .black
    } else {
        button.contentTintColor = button.isEnabled ? .appTextSecondary : .tertiaryLabelColor
    }
    if pinned {
        button.toolTip = "Keep at the top of the list. Click to unpin."
        button.setAccessibilityLabel("Unpin from the top of the list")
    } else if atLimit {
        button.toolTip =
            "One card is already pinned. Unpin it before pinning another."
        button.setAccessibilityLabel("Cannot pin: this list already has a pinned card")
    } else {
        button.toolTip = "Keep this card at the top of the list."
        button.setAccessibilityLabel("Pin to the top of the list")
    }
}

/// A frame-laid-out document view keeps the list height equal to its actual cards.
/// There are deliberately no top/bottom insets and no viewport-sized filler.
private final class AppCardDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A deterministic scrollbar for the four app lists. AppKit's overlay scroller can
/// disappear based on a system preference and its knob length is proportional to the
/// document; the product requirement is the opposite: always visible, with a handle
/// exactly one app card high.
private final class FixedAppCardScrollbarView: NSView {
    static let width: CGFloat = 10
    static let gap: CGFloat = 8

    private weak var scrollView: NSScrollView?
    private let thumbHeight: CGFloat
    private var boundsObserver: NSObjectProtocol?
    private var dragOffset: CGFloat?
    private var interactionEnabled = true

    override var isFlipped: Bool { true }

    init(
        scrollView: NSScrollView,
        thumbHeight: CGFloat = AppCardMetrics.height,
        accessibilityLabel: String = "App list scroll bar"
    ) {
        self.scrollView = scrollView
        self.thumbHeight = thumbHeight
        super.init(frame: .zero)
        wantsLayer = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.synchronize()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.scrollBar)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityOrientation(.vertical)
        synchronize()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func setInteractionEnabled(_ enabled: Bool) {
        interactionEnabled = enabled
        setAccessibilityEnabled(enabled && maximumOffset > 0)
        needsDisplay = true
    }

    func synchronize() {
        let value = maximumOffset > 0
            ? min(1, max(0, currentOffset / maximumOffset))
            : 0
        setAccessibilityMinValue(0.0)
        setAccessibilityMaxValue(1.0)
        setAccessibilityValue(Double(value))
        setAccessibilityEnabled(interactionEnabled && maximumOffset > 0)
        needsDisplay = true
    }

    private var currentOffset: CGFloat {
        scrollView?.contentView.bounds.origin.y ?? 0
    }

    private var maximumOffset: CGFloat {
        guard let scrollView, let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.frame.height - scrollView.contentView.bounds.height)
    }

    private var thumbRect: NSRect {
        let track = bounds.insetBy(dx: 2, dy: 0)
        let thumbHeight = min(self.thumbHeight, track.height)
        let travel = max(0, track.height - thumbHeight)
        let fraction = maximumOffset > 0
            ? min(1, max(0, currentOffset / maximumOffset))
            : 0
        return NSRect(
            x: track.minX,
            y: track.minY + fraction * travel,
            width: track.width,
            height: thumbHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 3, dy: 0)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        NSColor.appTextPrimary.withAlphaComponent(0.08).setFill()
        trackPath.fill()

        let thumb = thumbRect
        let thumbPath = NSBezierPath(roundedRect: thumb, xRadius: thumb.width / 2, yRadius: 4)
        let active = interactionEnabled && maximumOffset > 0
        NSColor.appTextPrimary.withAlphaComponent(active ? 0.42 : 0.20).setFill()
        thumbPath.fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard interactionEnabled, maximumOffset > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let thumb = thumbRect
        if thumb.contains(point) {
            dragOffset = point.y - thumb.minY
        } else {
            dragOffset = thumb.height / 2
            scrollThumb(to: point.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragOffset != nil else { return }
        scrollThumb(to: convert(event.locationInWindow, from: nil).y)
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = nil
    }

    private func scrollThumb(to pointerY: CGFloat) {
        guard let scrollView else { return }
        let thumb = thumbRect
        let travel = max(0, bounds.height - thumb.height)
        guard travel > 0 else { return }
        let proposedY = pointerY - (dragOffset ?? thumb.height / 2)
        let fraction = min(1, max(0, proposedY / travel))
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: fraction * maximumOffset))
        scrollView.reflectScrolledClipView(clipView)
        synchronize()
    }

    override func accessibilityPerformIncrement() -> Bool {
        scrollByOneCard(direction: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        scrollByOneCard(direction: -1)
    }

    private func scrollByOneCard(direction: CGFloat) -> Bool {
        guard interactionEnabled, maximumOffset > 0, let scrollView else { return false }
        let clipView = scrollView.contentView
        let next = min(
            maximumOffset,
            max(0, currentOffset + direction * (AppCardMetrics.height + innerCardSpacing))
        )
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: next))
        scrollView.reflectScrolledClipView(clipView)
        synchronize()
        return true
    }
}

/// The busy veil for one list. It intentionally leaves the cards visible beneath
/// it, while blocking edits and adding a spinner/caption over the dimmed rows.
private final class AppCardRefreshOverlayView: NSView {
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "Refreshing…")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .appTextPrimary
        label.alignment = .center
        [spinner, label].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Refreshing app list")
        isHidden = true
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let centerY = bounds.midY
        spinner.frame = NSRect(x: bounds.midX - 10, y: centerY - 24, width: 20, height: 20)
        label.frame = NSRect(x: 8, y: centerY + 4, width: max(0, bounds.width - 16), height: 18)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.28).cgColor
    }

    func setActive(_ active: Bool, message: String) {
        label.stringValue = message
        setAccessibilityLabel(message)
        isHidden = !active
        if active {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }
}

/// Shared by all four user-facing app lists. It owns the exact 86-point row
/// geometry, 10-point spacing, deterministic scrollbar, and per-list busy state.
private final class AppCardListView: NSView {
    static func contentWidth(for outerWidth: CGFloat) -> CGFloat {
        max(1, outerWidth - FixedAppCardScrollbarView.gap - FixedAppCardScrollbarView.width)
    }

    private let scrollView = NSScrollView()
    private let documentView = AppCardDocumentView()
    private let scrollbar: FixedAppCardScrollbarView
    private let refreshOverlay = AppCardRefreshOverlayView(frame: .zero)
    private var rows: [NSView] = []
    /// The leading run of pinned rows. They live on this view rather than inside the
    /// scroller's document, so scrolling moves everything except them.
    private var stickyRows: [NSView] = []
    private var emptyField: NSTextField?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        scrollbar = FixedAppCardScrollbarView(scrollView: scrollView)
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        [scrollView, scrollbar, refreshOverlay].forEach(addSubview)
        layoutList()
    }

    required init?(coder: NSCoder) { nil }

    var rowContentWidth: CGFloat {
        Self.contentWidth(for: bounds.width)
    }

    override func layout() {
        super.layout()
        layoutList()
    }

    private func layoutList() {
        let contentWidth = rowContentWidth
        // Sticky rows keep the list's own pitch, so the seam between them and the
        // scroller is invisible: it reads as one column in which the pinned card simply
        // never moves.
        let pitch = AppCardMetrics.height + innerCardSpacing
        for (index, row) in stickyRows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y: CGFloat(index) * pitch,
                width: contentWidth,
                height: AppCardMetrics.height
            )
        }
        let stickyHeight = stickyRows.isEmpty ? 0 : CGFloat(stickyRows.count) * pitch
        let scrollHeight = max(0, bounds.height - stickyHeight)
        scrollView.frame = NSRect(
            x: 0, y: stickyHeight, width: contentWidth, height: scrollHeight
        )
        scrollbar.frame = NSRect(
            x: bounds.width - FixedAppCardScrollbarView.width,
            y: stickyHeight,
            width: FixedAppCardScrollbarView.width,
            height: scrollHeight
        )
        refreshOverlay.frame = scrollView.frame
        layoutRows()
    }

    /// `stickyCount` is how many of `newRows` lead the list as pinned. They are lifted
    /// out of the scroller and parked at the top; the remainder scrolls beneath them.
    func setRows(_ newRows: [NSView], stickyCount: Int = 0, emptyMessage: String) {
        (stickyRows + rows).forEach { $0.removeFromSuperview() }
        emptyField?.removeFromSuperview()
        emptyField = nil

        let pinned = max(0, min(stickyCount, newRows.count))
        stickyRows = Array(newRows.prefix(pinned))
        rows = Array(newRows.dropFirst(pinned))

        stickyRows.forEach {
            $0.isHidden = false
            addSubview($0)
        }

        // The empty state keys off the whole list rather than the scrolling part, so a
        // single pinned card with nothing behind it never sits above "No App Profiles yet".
        if newRows.isEmpty {
            let empty = NSTextField(labelWithString: emptyMessage)
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .appTextSecondary
            empty.alignment = .center
            documentView.addSubview(empty)
            emptyField = empty
        } else {
            rows.forEach {
                $0.isHidden = false
                documentView.addSubview($0)
            }
        }
        layoutList()
    }

    private func layoutRows() {
        let width = rowContentWidth
        if rows.isEmpty {
            documentView.frame = NSRect(x: 0, y: 0, width: width, height: AppCardMetrics.height)
            emptyField?.frame = NSRect(x: 0, y: 0, width: width, height: AppCardMetrics.height)
        } else {
            let pitch = AppCardMetrics.height + innerCardSpacing
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(
                    x: 0,
                    y: CGFloat(index) * pitch,
                    width: width,
                    height: AppCardMetrics.height
                )
            }
            let exactHeight = CGFloat(rows.count) * AppCardMetrics.height
                + CGFloat(max(0, rows.count - 1)) * innerCardSpacing
            documentView.frame = NSRect(x: 0, y: 0, width: width, height: exactHeight)
        }
        scrollView.contentView.scroll(to: NSPoint(
            x: 0,
            y: min(
                scrollView.contentView.bounds.origin.y,
                max(0, documentView.frame.height - scrollView.contentView.bounds.height)
            )
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollbar.synchronize()
    }

    func setRefreshing(_ refreshing: Bool, message: String = "Refreshing…") {
        scrollView.alphaValue = refreshing ? 0.44 : 1
        scrollbar.alphaValue = refreshing ? 0.64 : 1
        scrollbar.setInteractionEnabled(!refreshing)
        // Pinned rows dim with the rest so the list reads as one surface, but they keep
        // their place: a refresh — the launch scan or a force refresh — never makes the
        // pinned card move or disappear.
        stickyRows.forEach { $0.alphaValue = refreshing ? 0.44 : 1 }
        refreshOverlay.setActive(refreshing, message: message)
    }
}

/// Returns the icon that represents one App Profile everywhere in Klik PRO.
/// Managed profiles own a launcher-specific icon, which may be custom, tinted,
/// or badged. Read that icns directly so every tab bypasses NSWorkspace's stale
/// per-path cache and immediately agrees after Change Icon. External launchers
/// and missing managed icons retain the existing safe fallbacks.
private func appProfileDisplayIcon(for instance: AppProfileInstance) -> NSImage {
    let launcherIconURL = URL(fileURLWithPath: instance.launcherPath, isDirectory: true)
        .appendingPathComponent("Contents/Resources/AppIcon.icns")
    if instance.launcherKind == .managed,
       let launcherIcon = NSImage(contentsOf: launcherIconURL) {
        return launcherIcon
    }
    if instance.launcherKind == .managed,
       FileManager.default.fileExists(atPath: instance.launcherPath) {
        return VendorAppIconCache.icon(forFile: instance.launcherPath)
    }
    return VendorAppIconCache.icon(forFile: instance.source.bundleURL)
}

/// `NSWorkspace.shared.icon(forFile:)` reaches Icon Services and the disk. Every row in
/// all four lists asked for its icon on every rebuild, and a single refresh rebuilds the
/// lists several times over — `setInstances`, `setRuntimeHealth`, `setOriginals` and
/// `setTopPinnedProfiles` each rebuild independently — so the same handful of icons were
/// re-fetched dozens of times per refresh, on the main thread.
///
/// Only vendor app icons live here. A managed launcher's own `AppIcon.icns` is still read
/// straight from disk on every rebuild by `appProfileDisplayIcon(for:)`, because Change
/// Icon has to show up immediately — bypassing a per-path icon cache is the entire reason
/// that path exists, and caching it here would reintroduce the staleness it was written
/// to avoid.
///
/// Main-thread only: every caller is view code building rows.
enum VendorAppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forFile path: String) -> NSImage {
        // Deterministic preview fixtures bypass the cache. Icon Services can hand back a
        // placeholder that resolves a moment later; re-fetching per row gave a render
        // several chances to catch the real icon, while caching freezes whatever the
        // first call returned for the whole render. That turns a latent race into a
        // visible diff between two runs of the same fixture, and check.sh requires those
        // two renders to be byte-identical.
        guard !previewRenderingIsActive else {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let cached = icons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    /// Dropped on an explicit refresh, so an app replaced on disk since launch still
    /// picks up its new icon. Rebuilds that are not refreshes keep the cache.
    static func invalidate() { icons.removeAll() }
}

class AppProfileButton: NSButton {
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
    /// The rest label an assignment control was configured with. Width is measured
    /// from this rather than `title`, which would be the hover label ("Change ⋯")
    /// while the pointer is over the button and would size the pill wrongly.
    private var assignmentRestTitle: String = ""

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
        self.assignmentRestTitle = restTitle
        self.title = isHovered ? (hoverTitle ?? restTitle) : restTitle
        updateBackground()
    }

    /// The width this assignment pill wants: its rest label plus the chain-link
    /// glyph and padding, floored so a short assignment still reads as a control.
    /// Callers clamp it to whatever the card can spare.
    func preferredAssignmentWidth() -> CGFloat {
        let font = self.font ?? .systemFont(ofSize: 11, weight: .semibold)
        let label = assignmentRestTitle.isEmpty ? title : assignmentRestTitle
        let titleWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let iconAllowance: CGFloat = image != nil ? 22 : 0
        return max(ceil(titleWidth) + iconAllowance + 24, AppCardMetrics.minAssignWidth)
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

/// Refresh-specific button that swaps its static arrow for the native macOS
/// spinner during discovery. Rotating the asymmetric arrow glyph looked like a
/// wobble; the centered progress indicator stays visually stable.
final class RefreshIconButton: AppProfileButton {
    private let glyphView = NSImageView()
    private let spinner = NSProgressIndicator()
    private(set) var isRefreshing = false

    override init(title: String, frame: NSRect) {
        super.init(title: title, frame: frame)
        configureGlyph()
    }

    init(frame: NSRect) {
        super.init(title: "", frame: frame)
        configureGlyph()
    }

    private func configureGlyph() {
        image = nil
        imagePosition = .noImage
        glyphView.imageScaling = .scaleProportionallyUpOrDown
        glyphView.wantsLayer = true
        if let base = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        ), let sized = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ) {
            sized.isTemplate = true
            glyphView.image = sized
        }
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        [glyphView, spinner].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let side = min(16, min(bounds.width, bounds.height))
        glyphView.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        spinner.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    /// Keeps the button visibly busy until the controller ends the refresh.
    func setRefreshing(_ refreshing: Bool) {
        guard refreshing != isRefreshing else { return }
        isRefreshing = refreshing
        isEnabled = !refreshing
        toolTip = refreshing ? "Refreshing…" : "Refresh App List"
        setAccessibilityLabel(refreshing ? "Refreshing app list" : "Refresh App List")
        glyphView.isHidden = refreshing
        spinner.isHidden = !refreshing
        if refreshing {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    /// The decorative glyph and spinner must never steal the button's hit target.
    ///
    /// `point` arrives in this button's *superview* space, so it has to be compared
    /// with `frame`. Comparing it with `bounds` anchored the hit region at the
    /// superview's origin instead, which left every refresh button unclickable
    /// wherever it is actually drawn. A disabled button still claims its own area,
    /// matching AppKit, so a click during a refresh cannot fall through to the list.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }
}

/// The small gear at a managed profile card's top-right corner. It holds the
/// infrequent management actions (Rename, Change Icon, Remove) so row 2 stays
/// uncrowded. Shares the hover/press pill cue with `AppProfileButton`.
final class AppProfileGearButton: NSButton {
    var onPress: (() -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressedDown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        imagePosition = .imageOnly
        let symbol = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Manage")
        symbol?.isTemplate = true
        image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        contentTintColor = .appTextSecondary
        target = self
        action = #selector(pressed)
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateBackground() }
    /// A gear that opens a menu behaves like a pull-down control: tracking starts
    /// on mouse-down. Bypassing `super` also bypasses NSControl's own disabled
    /// guard, so `isEnabled` has to be honored explicitly here — otherwise a
    /// greyed-out gear would still open its menu.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let onMouseDown else {
            super.mouseDown(with: event)
            return
        }
        // Keep the gear visibly engaged for the life of the tracking session;
        // `highlight(_:)` never runs on this path because the button's own mouse
        // tracking is skipped.
        isPressedDown = true
        updateBackground()
        onMouseDown(event)
        isPressedDown = false
        updateBackground()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func highlight(_ flag: Bool) {
        super.highlight(flag); isPressedDown = flag; updateBackground()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateBackground()
    }

    private func updateBackground() {
        let active = isHovered || isPressedDown
        let alpha: CGFloat = isPressedDown ? 0.36 : (isHovered ? 0.18 : 0)
        let base = active ? KlikProBrand.green : NSColor.appTextPrimary
        layer?.backgroundColor = base.withAlphaComponent(alpha).cgColor
        contentTintColor = active ? KlikProBrand.green : .appTextSecondary
    }

    @objc private func pressed() { onPress?() }
}

private final class DualAppGeneratorCard: NSView {
    /// Two rows: name + badge, then the action buttons. The icon spans both.
    /// Shared with the other three lists via AppCardMetrics so all four line up.
    static let cardHeight: CGFloat = AppCardMetrics.height
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let badgeField = makeCompatibilityBadgeField()
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let generateButton = AppProfileButton(title: "+ New Profile", frame: .zero)
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let dockGearButton = AppProfileGearButton(frame: .zero)
    private let pinButton = makePinIconButton()
    private(set) var candidate: AppProfileCandidate?
    private var dockPinned = false
    private var menuBarPinned = false
    /// List-order pin state. Named `topPinned` rather than `pinned` because this class
    /// already tracks two unrelated kinds of pinning (Dock tile and menu bar).
    private var topPinned = false
    private var topPinAtLimit = false
    /// False for a target with no persisted mouse-button slot (Canva, Zoom, Spotify).
    /// Its Assign control has nowhere to store an assignment, so it is disabled with
    /// the reason rather than looking live and silently doing nothing.
    private var assignable = true
    // Persisted custom name/icon for the native Dock launcher (set via the gear's
    // Rename / Change Icon). When present, the card tile reflects them so it matches
    // the Dock; nil falls back to the vendor app's own name/icon.
    private var customDockName: String?
    private var customDockIcon: NSImage?
    let bundleIdentifier: String
    let fallbackName: String
    var onGenerate: ((AppProfileCandidate) -> Void)?
    var onOpen: ((AppProfileCandidate) -> Void)?
    var onAssign: (() -> Void)?
    var onCreateDock: (() -> Void)?
    var onRenameDock: (() -> Void)?
    var onChangeIconDock: (() -> Void)?
    var onResetIconDock: (() -> Void)?
    var onDeleteDock: (() -> Void)?
    var onAddNativeDock: (() -> Void)?
    var onRemoveNativeDock: (() -> Void)?
    var onToggleMenuBar: (() -> Void)?
    var onTogglePin: (() -> Void)?

    override var isFlipped: Bool { true }

    init(bundleIdentifier: String, fallbackName: String, width: CGFloat) {
        self.bundleIdentifier = bundleIdentifier
        self.fallbackName = fallbackName
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.cardHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // The icon spans both rows and is vertically centred, so the name row and
        // the action row read as one block beside it.
        iconView.frame = AppCardMetrics.iconFrame()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        // A gear at the card's top-right manages the original app's Klik PRO Dock
        // icon (create / delete) and now also carries the menu-bar toggle. It never
        // touches the native vendor Dock tile.
        dockGearButton.frame = AppCardMetrics.gearFrame(cardWidth: width)
        dockGearButton.toolTip = "Manage this app's Klik PRO Dock icon and menu-bar icon"
        // The pin sits right of the gear and keeps this app at the top of the app lists
        // on both tabs. It is a view preference only — no Dock or menu-bar effect.
        pinButton.frame = AppCardMetrics.pinFrame(cardWidth: width)
        pinButton.onPress = { [weak self] in self?.onTogglePin?() }
        // Row 1: name, then the compatibility badge, ending before the gear.
        nameField.frame = NSRect(
            x: AppCardMetrics.nameX, y: AppCardMetrics.nameY,
            width: 140, height: AppCardMetrics.nameHeight
        )
        nameField.font = .systemFont(ofSize: 15, weight: .semibold)
        assignButton.font = .systemFont(ofSize: 11, weight: .semibold)
        // The three actions (Open, + New Profile, Assign) are laid out right-flushed
        // in relayoutActionButtons(); the assignment pill sizes to its own label
        // rather than stretching across the card.
        openButton.onPress = { [weak self] in
            guard let self, let candidate = self.candidate else { return }
            self.onOpen?(candidate)
        }
        generateButton.onPress = { [weak self] in
            guard let self, let candidate = self.candidate else { return }
            self.onGenerate?(candidate)
        }
        assignButton.onPress = { [weak self] in self?.onAssign?() }
        dockGearButton.onPress = { [weak self] in self?.presentDockMenu() }
        [
            iconView, nameField, badgeField, openButton, generateButton,
            assignButton, dockGearButton, pinButton,
        ]
            .forEach(addSubview)
        applyPinIconState(pinButton, pinned: topPinned, atLimit: topPinAtLimit)
        showLoading()
    }

    required init?(coder: NSCoder) { nil }

    func showLoading() {
        candidate = nil
        nameField.stringValue = fallbackName
        iconView.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Loading")
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        badgeField.isHidden = true
        generateButton.isEnabled = false
        openButton.isEnabled = false
        assignButton.isEnabled = false
        updateAssignment(nil)
        updateDockGear()
    }

    /// Reflects whether the original app's Klik PRO Dock icon is currently pinned.
    /// Driven by the controller (live Dock state); affects the gear menu label —
    /// Create becomes Replace when an icon is already pinned. Delete stays available
    /// regardless, so a leftover launcher can always be cleaned up.
    func setDockPinned(_ pinned: Bool) {
        dockPinned = pinned
        updateDockGear()
    }

    /// Reflects whether the original app is currently pinned to the menu bar. Driven by
    /// the controller (persisted config state), so the toggle always mirrors reality.
    func setMenuBarPinned(_ pinned: Bool) {
        menuBarPinned = pinned
    }

    /// Reflects list-order pin state. `atLimit` is separate from `pinned` because a
    /// full list must still let its own pinned cards be unpinned — that is how the
    /// user frees a slot.
    func setTopPinned(_ pinned: Bool, atLimit: Bool) {
        topPinned = pinned
        topPinAtLimit = atLimit
        applyPinIconState(pinButton, pinned: pinned, atLimit: atLimit)
    }

    /// Whether this target can take a mouse-button assignment at all. Static per
    /// target (it follows `QuickLaunchTarget.shortcutSlot`), so the controller sets it
    /// once at construction.
    func setAssignable(_ value: Bool) {
        assignable = value
        updateAssignEnabled()
    }

    /// One place decides the Assign control's enabled state: it needs both an
    /// installed app and somewhere to persist the assignment.
    private func updateAssignEnabled() {
        assignButton.isEnabled = candidate != nil && assignable
        if candidate != nil && !assignable {
            assignButton.toolTip =
                "\(nameField.stringValue) cannot take a mouse-button assignment yet."
        } else {
            assignButton.toolTip = nil
        }
    }

    /// The compatibility badge shown beside the app name. `verified` picks the
    /// green treatment; anything else reads as amber. Passing nil hides it, which
    /// is what a card with no candidate does.
    func setCompatibility(verified: Bool?) {
        applyCompatibilityBadge(badgeField, verified: verified)
        layoutNameRow()
    }

    /// Sizes the name to its text so the badge can sit immediately after it, with
    /// both kept clear of the gear.
    private func layoutNameRow() {
        layoutNameAndBadge(
            nameField: nameField,
            badgeField: badgeField,
            gearMinX: dockGearButton.frame.minX
        )
    }

    private func updateDockGear() {
        // The original launcher can only be created (and the app only pinned to the
        // menu bar) when the vendor app is installed, so both controls are disabled
        // until the card has a candidate.
        dockGearButton.isEnabled = candidate != nil
        dockGearButton.setAccessibilityLabel("Manage the Dock icon")
    }

    /// Gear menu: create (or replace) the original app's Klik PRO Dock icon, delete it,
    /// or remove the NATIVE app's own Dock tile. The first two manage only Klik PRO's
    /// own launcher tile; the third unpins the vendor app's tile (the app itself stays
    /// installed) and is offered only once Klik PRO's own Dock icon exists. The
    /// controller confirms a replace.
    private func presentDockMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Star-themed icons make it unmistakable that this gear manages Klik PRO's
        // generated launcher Dock icon — not the native (original) vendor Dock tile
        // and not any App Profile's icon.
        let create = NSMenuItem(
            title: dockPinned ? "Replace Dock Icon…" : "Create Dock Icon",
            action: #selector(menuCreateDock), keyEquivalent: ""
        )
        create.target = self
        create.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        menu.addItem(create)
        // Rename and Change Icon act on an existing Klik PRO Dock icon, so they are
        // grouped with Create/Delete and enabled only once that icon is pinned.
        let rename = NSMenuItem(
            title: "Rename Dock Icon…", action: #selector(menuRenameDock), keyEquivalent: ""
        )
        rename.target = self
        rename.isEnabled = candidate != nil && dockPinned
        rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(rename)
        let changeIcon = NSMenuItem(
            title: "Change Icon…", action: #selector(menuChangeIconDock), keyEquivalent: ""
        )
        changeIcon.target = self
        changeIcon.isEnabled = candidate != nil && dockPinned
        changeIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        menu.addItem(changeIcon)
        // Resets the badged/tinted/custom icon straight to the default native icon,
        // without opening the Change Icon dialog. Same gate as Rename/Change Icon.
        let resetIcon = NSMenuItem(
            title: "Reset to Native Icon", action: #selector(menuResetIconDock), keyEquivalent: ""
        )
        resetIcon.target = self
        resetIcon.isEnabled = candidate != nil && dockPinned
        resetIcon.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        menu.addItem(resetIcon)
        let delete = NSMenuItem(
            title: "Delete Dock Icon", action: #selector(menuDeleteDock), keyEquivalent: ""
        )
        delete.target = self
        // Available whenever the app is present (same gate as the gear), not only when
        // the tile is currently pinned — so a manually-unpinned but still-on-disk
        // Klik PRO launcher can always be removed. Removes only the badged Klik PRO
        // launcher, never the native vendor Dock tile.
        delete.isEnabled = candidate != nil
        delete.image = NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil)
        menu.addItem(delete)
        menu.addItem(.separator())
        // Adds the NATIVE app's own Dock tile back. Since forced creation on profile
        // generation is now skipped when a Dock entry already exists, this is the
        // manual way to restore the native tile. Enabled whenever the app is present;
        // a no-op with feedback if the tile is already in the Dock.
        let addNative = NSMenuItem(
            title: "Add Native App Dock Icon",
            action: #selector(menuAddNativeDock), keyEquivalent: ""
        )
        addNative.target = self
        addNative.isEnabled = candidate != nil
        addNative.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
        addNative.toolTip = "Adds the native app's own Dock tile back."
        menu.addItem(addNative)
        // Removes the NATIVE app's own Dock tile — not the app, which stays installed
        // and launchable from Launchpad/Finder. Enabled only once Klik PRO's own Dock
        // icon exists (dockPinned), so a working Dock launcher remains afterward.
        let removeNative = NSMenuItem(
            title: "Remove Native App Dock Icon",
            action: #selector(menuRemoveNativeDock), keyEquivalent: ""
        )
        removeNative.target = self
        removeNative.isEnabled = candidate != nil && dockPinned
        removeNative.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
        removeNative.toolTip = dockPinned
            ? "Removes the app's own Dock tile; the app stays in Launchpad."
            : "Create Klik PRO's Dock icon first, then this can remove the native tile."
        menu.addItem(removeNative)
        // The menu-bar control is last, after a divider. It is a real switch rather
        // than a checkmark item, so an NSMenuItem custom view hosts the same
        // ToggleSwitchView the cards used to show inline.
        menu.addItem(.separator())
        menu.addItem(makeMenuBarToggleItem(
            isOn: menuBarPinned,
            isEnabled: candidate != nil,
            onChange: { [weak self] in self?.onToggleMenuBar?() },
            cancelTracking: { [weak self] in self?.dockGearButton.menu?.cancelTracking() }
        ))
        let origin = NSPoint(x: dockGearButton.frame.minX, y: dockGearButton.frame.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    @objc private func menuCreateDock() { onCreateDock?() }
    @objc private func menuRenameDock() { onRenameDock?() }
    @objc private func menuChangeIconDock() { onChangeIconDock?() }
    @objc private func menuResetIconDock() { onResetIconDock?() }
    @objc private func menuDeleteDock() { onDeleteDock?() }
    @objc private func menuAddNativeDock() { onAddNativeDock?() }
    @objc private func menuRemoveNativeDock() { onRemoveNativeDock?() }

    func update(candidate: AppProfileCandidate?, alternativesAvailable: Bool) {
        self.candidate = candidate
        nameField.stringValue = candidate?.app.displayName ?? fallbackName
        layoutNameRow()
        if let candidate {
            iconView.image = VendorAppIconCache.icon(forFile: candidate.app.bundleURL.path)
            generateButton.isEnabled = true
            openButton.isEnabled = true
        } else {
            iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            badgeField.isHidden = true
            generateButton.isEnabled = false
            openButton.isEnabled = false
        }
        updateAssignEnabled()
        applyDockCustomizationOverlay()
        updateDockGear()
        _ = alternativesAvailable
    }

    /// Reflects the native Dock launcher's persisted custom name/icon on the card tile,
    /// or falls back to the vendor app's own name/icon when none is set. Only meaningful
    /// once the app is installed.
    private func applyDockCustomizationOverlay() {
        guard let candidate else { return }
        if let customDockName, !customDockName.isEmpty {
            nameField.stringValue = customDockName
        } else {
            nameField.stringValue = candidate.app.displayName
        }
        iconView.image = customDockIcon
            ?? VendorAppIconCache.icon(forFile: candidate.app.bundleURL.path)
    }

    /// Pushed from the controller whenever the native launcher's persisted custom
    /// name/icon may have changed (rename, change icon, reset, refresh, startup).
    func setDockCustomization(name: String?, icon: NSImage?) {
        customDockName = name
        customDockIcon = icon
        applyDockCustomizationOverlay()
    }

    func updateAssignment(_ button: QuickLaunchMouseButton?) {
        if let button {
            let title = "\(button.title) Button"
            assignButton.configureAssignment(
                restTitle: title, symbolName: "link", hoverTitle: "Change ⋯", assigned: true
            )
            assignButton.setAccessibilityLabel("Change button assignment, currently \(title)")
        } else {
            assignButton.configureAssignment(
                restTitle: "Assign Button", symbolName: "link.badge.plus", hoverTitle: nil
            )
            assignButton.setAccessibilityLabel("Assign a mouse button to the native app")
        }
        relayoutActionButtons()
    }

    /// Lays out Open, + New Profile, and Assign right-flushed. The assignment pill is
    /// sized to its current label (clamped) instead of a fixed width, so a short
    /// assignment like "Back Button" doesn't leave a stretched control. A right inset
    /// keeps the actions clear of a list scroll bar.
    private func relayoutActionButtons() {
        let gap = AppCardMetrics.buttonGap
        let openW = AppCardMetrics.openWidth
        let generateW = AppCardMetrics.generateWidth
        // Cap so Open and + New Profile still fit with a left margin (rightEdge keeps
        // a matching right margin for scroll-bar clearance).
        let maxAssign = max(
            AppCardMetrics.minAssignWidth,
            bounds.width - openW - generateW - 2 * gap - 28
        )
        let assignW = min(assignButton.preferredAssignmentWidth(), maxAssign)
        let rightEdge = bounds.width - AppCardMetrics.rightInset
        let assignX = rightEdge - assignW
        let generateX = assignX - gap - generateW
        let openX = generateX - gap - openW
        let y = AppCardMetrics.actionY
        let h = AppCardMetrics.actionHeight
        openButton.frame = NSRect(x: openX, y: y, width: openW, height: h)
        generateButton.frame = NSRect(x: generateX, y: y, width: generateW, height: h)
        assignButton.frame = NSRect(x: assignX, y: y, width: assignW, height: h)
    }
}

final class AppProfileInstanceRowView: NSView {
    /// The card height. The list pins each row to this, so keep them in sync.
    static let rowHeight: CGFloat = AppCardMetrics.height
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let gearButton = AppProfileGearButton(frame: .zero)
    private let pinButton = makePinIconButton()
    private(set) var instance: AppProfileInstance
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onRename: ((AppProfileInstance) -> Void)?
    var onRemove: ((AppProfileInstance) -> Void)?
    var onChangeIcon: ((AppProfileInstance) -> Void)?
    var onAddToDock: ((AppProfileInstance) -> Void)?
    var onTogglePin: ((AppProfileInstance) -> Void)?

    override var isFlipped: Bool { true }

    init(
        instance: AppProfileInstance,
        health: AppProfileRuntimeHealth?,
        width: CGFloat,
        topPinned: Bool,
        topPinAtLimit: Bool
    ) {
        self.instance = instance
        // Two-row card: a large app icon fills the left edge across both rows. Row 1
        // (top) carries the app name (left) and the gear (right); row 2 (bottom)
        // carries the action buttons, right-flushed. The menu-bar control lives inside
        // the gear menu, not inline, so the name owns the whole of row 1.
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        iconView.frame = AppCardMetrics.iconFrame()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = appProfileDisplayIcon(for: instance)
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .appTextPrimary
        titleField.stringValue = instance.label
        titleField.lineBreakMode = .byTruncatingTail

        let managed = instance.launcherKind == .managed

        // Row 1 (top): pin and gear use the same geometry as the other three cards.
        pinButton.frame = AppCardMetrics.pinFrame(cardWidth: width)
        applyPinIconState(pinButton, pinned: topPinned, atLimit: topPinAtLimit)
        gearButton.isHidden = !managed
        gearButton.frame = AppCardMetrics.gearFrame(cardWidth: width)

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
        layoutOpenAndAssign(
            openButton: openButton,
            assignButton: assignButton,
            cardWidth: width
        )
        // The name owns row 1 beside the icon, ending before the gear (or before the
        // pin on external rows, which have no gear but are still pinnable), so long
        // labels get far more room than when they shared the row with the toggle.
        let nameX = AppCardMetrics.nameX
        let nameRightLimit = managed ? gearButton.frame.minX : pinButton.frame.minX
        titleField.frame = NSRect(
            x: nameX, y: AppCardMetrics.nameY,
            width: max(80, nameRightLimit - nameX - AppCardMetrics.buttonGap),
            height: AppCardMetrics.nameHeight
        )
        openButton.onPress = { [weak self] in
            guard let self else { return }; self.onOpen?(self.instance)
        }
        assignButton.onPress = { [weak self] in
            guard let self else { return }; self.onAssign?(self.instance)
        }
        gearButton.setAccessibilityLabel("Manage \(instance.label)")
        gearButton.toolTip = "Rename, change icon, menu-bar icon, or remove from Klik PRO"
        gearButton.onPress = { [weak self] in self?.presentManageMenu() }
        pinButton.onPress = { [weak self] in
            guard let self else { return }; self.onTogglePin?(self.instance)
        }
        [iconView, titleField, openButton, assignButton, gearButton, pinButton]
            .forEach(addSubview)
    }

    /// The gear menu: the infrequent management actions live here so row 2 keeps
    /// only the everyday controls. Remove is destructive and sits below a
    /// separator; the caller still runs its own confirmation.
    private func presentManageMenu() {
        let menu = NSMenu()
        let rename = NSMenuItem(
            title: "Rename…", action: #selector(menuRename), keyEquivalent: ""
        )
        rename.target = self
        rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(rename)
        let changeIcon = NSMenuItem(
            title: "Change Icon…", action: #selector(menuChangeIcon), keyEquivalent: ""
        )
        changeIcon.target = self
        changeIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        menu.addItem(changeIcon)
        // Adds this profile's own launcher to the Dock (e.g. if it wasn't added at
        // generation). Reuses the shared add path; a no-op with feedback if present.
        let addToDock = NSMenuItem(
            title: "Add to Dock", action: #selector(menuAddToDock), keyEquivalent: ""
        )
        addToDock.target = self
        addToDock.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
        menu.addItem(addToDock)
        menu.addItem(.separator())
        let remove = NSMenuItem(
            title: "Remove from Klik PRO…", action: #selector(menuRemove), keyEquivalent: ""
        )
        remove.target = self
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(remove)
        // The menu-bar control is last, after a divider — the same position it holds
        // in the generator card's gear, so both card types agree.
        menu.addItem(.separator())
        menu.addItem(makeMenuBarToggleItem(
            isOn: instance.pinToMenuBar,
            isEnabled: true,
            onChange: { [weak self] in
                guard let self else { return }
                self.onToggleMenuBar?(self.instance)
            },
            cancelTracking: { [weak self] in self?.gearButton.menu?.cancelTracking() }
        ))
        let origin = NSPoint(x: gearButton.frame.minX, y: gearButton.frame.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    @objc private func menuRename() { onRename?(instance) }
    @objc private func menuChangeIcon() { onChangeIcon?(instance) }
    @objc private func menuAddToDock() { onAddToDock?(instance) }
    @objc private func menuRemove() { onRemove?(instance) }

    required init?(coder: NSCoder) { nil }
}

/// Compact profile row used beside Mappings. It offers quick Open plus Assign
/// Button (assigning a mouse button to launch the profile is natural on the
/// mouse-mapping tab); full management stays on the App Profiles tab.
private final class MappingAppProfileOpenRowView: NSView {
    /// The shared two-row card, so this list lines up with the other three.
    static let rowHeight: CGFloat = AppCardMetrics.height
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let gearButton = AppProfileGearButton(frame: .zero)
    private let pinButton = makePinIconButton()
    private let instance: AppProfileInstance
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onTogglePin: ((AppProfileInstance) -> Void)?

    override var isFlipped: Bool { true }

    init(
        instance: AppProfileInstance,
        health: AppProfileRuntimeHealth?,
        width: CGFloat,
        topPinned: Bool,
        topPinAtLimit: Bool
    ) {
        self.instance = instance
        // The icon spans both rows; row 1 carries the name and the gear, row 2 the
        // right-flushed actions. No badge — the App Profiles lists stay badge-free in
        // both tabs — and no "+ New Profile" on this tab.
        let rowHeight = Self.rowHeight
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        iconView.frame = AppCardMetrics.iconFrame()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = appProfileDisplayIcon(for: instance)

        let managed = instance.launcherKind == .managed
        gearButton.isHidden = !managed
        gearButton.frame = AppCardMetrics.gearFrame(cardWidth: width)
        gearButton.toolTip = "Manage this profile's menu-bar icon"
        gearButton.setAccessibilityLabel("Manage \(instance.label)")
        gearButton.onPress = { [weak self] in self?.presentManageMenu() }

        // Every profile can be pinned, including an external launcher, so unlike the
        // gear this control is never hidden.
        pinButton.frame = AppCardMetrics.pinFrame(cardWidth: width)
        applyPinIconState(pinButton, pinned: topPinned, atLimit: topPinAtLimit)
        pinButton.onPress = { [weak self] in
            guard let self else { return }
            self.onTogglePin?(self.instance)
        }

        // An external launcher shows no gear, so the name runs on to the pin instead —
        // not to the card edge, which would slide the title under the pin.
        let nameRightLimit = managed ? gearButton.frame.minX : pinButton.frame.minX
        titleField.frame = NSRect(
            x: AppCardMetrics.nameX,
            y: AppCardMetrics.nameY,
            width: max(80, nameRightLimit - AppCardMetrics.nameX - AppCardMetrics.buttonGap),
            height: AppCardMetrics.nameHeight
        )
        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .appTextPrimary
        titleField.stringValue = instance.label
        titleField.lineBreakMode = .byTruncatingTail
        titleField.toolTip = instance.label

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
        [iconView, titleField, assignButton, openButton, gearButton, pinButton]
            .forEach(addSubview)
        layoutOpenAndAssign(
            openButton: openButton, assignButton: assignButton, cardWidth: width
        )
    }

    /// The gear exists to host the menu-bar toggle; renaming, icons and removal stay
    /// on the App Profiles tab.
    private func presentManageMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(makeMenuBarToggleItem(
            isOn: instance.pinToMenuBar,
            isEnabled: true,
            onChange: { [weak self] in
                guard let self else { return }
                self.onToggleMenuBar?(self.instance)
            },
            cancelTracking: { [weak self] in self?.gearButton.menu?.cancelTracking() }
        ))
        let origin = NSPoint(x: gearButton.frame.minX, y: gearButton.frame.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    required init?(coder: NSCoder) { nil }
}

/// One installed native app as the Mappings Native Apps list shows it. Bundled
/// into a struct rather than a long tuple because the row needs the badge, the
/// menu-bar state and whether the target can take an assignment at all.
struct MappingNativeApp {
    let target: QuickLaunchTarget
    let name: String
    let path: String
    let mouseButton: QuickLaunchMouseButton?
    /// nil hides the pill; true reads "Verified", false "Unverified".
    let verified: Bool?
    let menuBarPinned: Bool
    /// False for a target with no persisted mouse-button slot, whose Assign
    /// control would otherwise look live and silently do nothing.
    let assignable: Bool
    /// Whether this app is pinned to the top of the app lists. Distinct from
    /// `menuBarPinned`, which is menu-bar visibility.
    let topPinned: Bool
    /// True when the list already holds `KlikProConfig.topPinLimit` pins and this app
    /// is not one of them, so its pin renders disabled with the reason.
    let topPinAtLimit: Bool
}

/// An installed vendor app shown as an assignment target, using the same two-row
/// card as the other three lists. It offers only Open and Assign — originals never
/// receive managed-profile lifecycle actions — plus a gear holding the menu-bar
/// toggle. No "+ New Profile": this tab assigns buttons, it does not create
/// profiles.
private final class MappingOriginalAppRowView: NSView {
    static let rowHeight: CGFloat = AppCardMetrics.height
    private let target: QuickLaunchTarget
    private let nameField = NSTextField(labelWithString: "")
    private let badgeField = makeCompatibilityBadgeField()
    private let openButton = AppProfileButton(title: "Open", frame: .zero)
    private let assignButton = AppProfileButton(title: "Assign Button", frame: .zero)
    private let gearButton = AppProfileGearButton(frame: .zero)
    private let pinButton = makePinIconButton()
    private let menuBarPinned: Bool
    var onOpen: ((QuickLaunchTarget) -> Void)?
    var onAssign: ((QuickLaunchTarget) -> Void)?
    var onToggleMenuBar: ((QuickLaunchTarget) -> Void)?
    var onTogglePin: ((QuickLaunchTarget) -> Void)?

    override var isFlipped: Bool { true }

    init(app: MappingNativeApp, width: CGFloat) {
        self.target = app.target
        self.menuBarPinned = app.menuBarPinned
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        wantsLayer = true
        layer?.cornerRadius = innerCardCornerRadius
        layer?.backgroundColor = innerCardFillColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // The icon spans both rows on the left; row 1 is name + badge + gear and
        // row 2 the right-flushed actions, matching the generator card exactly.
        let icon = NSImageView(frame: AppCardMetrics.iconFrame())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = VendorAppIconCache.icon(forFile: app.path)

        gearButton.frame = AppCardMetrics.gearFrame(cardWidth: width)
        gearButton.toolTip = "Manage this app's menu-bar icon"
        gearButton.setAccessibilityLabel("Manage \(app.name)")
        gearButton.onPress = { [weak self] in self?.presentManageMenu() }

        pinButton.frame = AppCardMetrics.pinFrame(cardWidth: width)
        applyPinIconState(pinButton, pinned: app.topPinned, atLimit: app.topPinAtLimit)
        pinButton.onPress = { [weak self] in
            guard let self else { return }; self.onTogglePin?(self.target)
        }

        nameField.font = .systemFont(ofSize: 15, weight: .semibold)
        nameField.textColor = .appTextPrimary
        nameField.stringValue = app.name
        nameField.lineBreakMode = .byTruncatingTail
        nameField.toolTip = app.name
        applyCompatibilityBadge(badgeField, verified: app.verified)

        assignButton.font = .systemFont(ofSize: 11, weight: .semibold)
        if let mouseButton = app.mouseButton {
            let assignmentTitle = "\(mouseButton.title) Button"
            assignButton.configureAssignment(
                restTitle: assignmentTitle,
                symbolName: "link",
                hoverTitle: "Change ⋯",
                assigned: true
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
        // A target with no mouse-button slot cannot store an assignment, so the
        // control is disabled with the reason rather than failing silently.
        if !app.assignable {
            assignButton.isEnabled = false
            assignButton.toolTip = "\(app.name) cannot take a mouse-button assignment yet."
        }

        assignButton.onPress = { [weak self] in
            guard let self else { return }; self.onAssign?(self.target)
        }
        openButton.onPress = { [weak self] in
            guard let self else { return }; self.onOpen?(self.target)
        }
        [icon, nameField, badgeField, openButton, assignButton, gearButton, pinButton]
            .forEach(addSubview)
        layoutNameAndBadge(
            nameField: nameField, badgeField: badgeField, gearMinX: gearButton.frame.minX
        )
        layoutActionRow()
    }

    /// Open + Assign, right-flushed to the card's trailing edge — the same line the
    /// pin ends on above them, so this list and the generator's three-button row end
    /// on one vertical edge.
    private func layoutActionRow() {
        layoutOpenAndAssign(
            openButton: openButton, assignButton: assignButton, cardWidth: bounds.width
        )
    }

    /// The gear exists to host the menu-bar toggle; full management of a native app
    /// stays on the App Profiles tab.
    private func presentManageMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(makeMenuBarToggleItem(
            isOn: menuBarPinned,
            isEnabled: true,
            onChange: { [weak self] in
                guard let self else { return }
                self.onToggleMenuBar?(self.target)
            },
            cancelTracking: { [weak self] in self?.gearButton.menu?.cancelTracking() }
        ))
        let origin = NSPoint(x: gearButton.frame.minX, y: gearButton.frame.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    required init?(coder: NSCoder) { nil }
}

/// One titled, independently-scrolling card in the Mappings right column. The
/// column stacks two of these — the installed native apps on top and the generated
/// App Profiles below — so each group is its own card with its own caption and its
/// own vertical scroller.
private final class MappingSectionCardView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let listView = AppCardListView(frame: .zero)
    /// The rescan control, inline at the right of this card's section header.
    let refreshButton = makeRefreshIconButton()
    var onRefresh: (() -> Void)?

    override var isFlipped: Bool { true }

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // The refresh icon shares the header line with the title, so it costs no
        // vertical space; the title stops short of it.
        let refreshSide: CGFloat = 26
        refreshButton.frame = NSRect(
            x: frame.width - 14 - refreshSide, y: 9, width: refreshSide, height: refreshSide
        )
        refreshButton.onPress = { [weak self] in self?.onRefresh?() }

        titleField.frame = NSRect(
            x: 18, y: 14, width: max(60, refreshButton.frame.minX - 26), height: 16
        )
        titleField.font = .boldSystemFont(ofSize: 11)
        titleField.textColor = .appTextSecondary
        titleField.stringValue = title

        // Pin capacity and viewport size are separate product choices: only one card
        // may be sticky, while three cards remain visible without scrolling.
        let visibleRows: CGFloat = 3
        let threeRowsHeight = visibleRows * AppCardMetrics.height
            + (visibleRows - 1) * innerCardSpacing
        // Keep the first card close to its section title. Extra column height belongs
        // below the visible rows, not as a large dead band above them.
        let listY: CGFloat = 50
        // On a 13-inch display the dashboard is intentionally shorter. Keep the
        // card inside that fixed viewport and let only its app list scroll.
        let listHeight = min(threeRowsHeight, max(0, frame.height - listY - 12))
        listView.frame = NSRect(x: 12, y: listY, width: frame.width - 24, height: listHeight)
        listView.setAccessibilityLabel("\(title) list")

        [titleField, refreshButton, listView].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    /// Row content width inside this card, mirroring the sizing the single Mappings
    /// list used before the column split into two cards.
    var rowContentWidth: CGFloat { max(320, listView.rowContentWidth) }

    /// Replaces the card's rows. Rows are prebuilt by the owner (so their Open/Assign
    /// callbacks are already wired) at `rowContentWidth`; an empty group shows a
    /// centered caption instead.
    func setRows(
        _ rows: [NSView],
        rowHeight: CGFloat,
        stickyCount: Int = 0,
        emptyMessage: String
    ) {
        precondition(
            rowHeight == AppCardMetrics.height,
            "Every app list row must use the shared 86-point card height"
        )
        listView.setRows(rows, stickyCount: stickyCount, emptyMessage: emptyMessage)
    }

    /// Initial discovery and manual refresh share the same non-destructive busy veil:
    /// existing cards stay visible and dim instead of disappearing.
    func showLoading(_ message: String = "Loading apps…") {
        setRefreshing(true, message: message)
    }

    func setRefreshing(_ refreshing: Bool, message: String = "Refreshing…") {
        applyRefreshIconState(refreshButton, refreshing: refreshing)
        listView.setRefreshing(refreshing, message: message)
    }
}

/// The Mappings app lists: two side-by-side, independently-scrolling cards — the
/// installed native apps on the LEFT and the generated App Profiles on the RIGHT.
/// Each card offers quick Open and Assign Button; other management stays on the
/// App Profiles tab.
final class MappingAppProfilesView: NSView {
    private let nativeCard: MappingSectionCardView
    private let profilesCard: MappingSectionCardView
    private var instances: [AppProfileInstance]
    private var runtimeHealth: [UUID: AppProfileRuntimeHealth] = [:]
    private var originals: [MappingNativeApp] = []
    // False until the first setOriginals call (the app scan reporting in). Until then
    // the Native Apps card shows a loading spinner rather than "No native apps".
    private var originalsLoaded = false
    /// True between setRefreshing(true) and setRefreshing(false). While it is set, the
    /// shared busy state owns both cards and setOriginals must not clear either.
    private var sharedRefreshActive = false
    /// Profiles pinned to the top, in the user's pin order. Natives arrive already
    /// ordered from the controller (it builds `MappingNativeApp`), but this list sorts
    /// its own rows by label, so it needs the pin order to apply afterwards.
    private var topPinnedProfileIDs: [UUID] = []
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onOpenOriginal: ((QuickLaunchTarget) -> Void)?
    var onAssignOriginal: ((QuickLaunchTarget) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onToggleOriginalMenuBar: ((QuickLaunchTarget) -> Void)?
    var onTogglePinOriginal: ((QuickLaunchTarget) -> Void)?
    var onTogglePinProfile: ((AppProfileInstance) -> Void)?
    // Re-scans installed native apps and reloads the profiles list for both columns.
    // Each column header carries its own icon; both call this.
    var onRefreshApps: (() -> Void)?

    override var isFlipped: Bool { true }

    init(instances: [AppProfileInstance], frame: NSRect) {
        self.instances = instances
        // Two cards side by side, filling the whole view: the old Refresh App List
        // header row is gone (its icon now sits inline in each card's header), so all
        // of that vertical space goes to the lists — which the taller two-row cards
        // need. The outer view is itself a transparent container (no card chrome, no
        // title). Native apps take the LEFT column, the generated App Profiles the
        // RIGHT. Each column is its own card with its own caption, its own refresh
        // icon, and an independent vertical scroller.
        let gap: CGFloat = 16
        let columnWidth = (frame.width - gap) / 2
        nativeCard = MappingSectionCardView(
            title: "NATIVE APPS",
            frame: NSRect(x: 0, y: 0, width: columnWidth, height: frame.height)
        )
        profilesCard = MappingSectionCardView(
            title: "APP PROFILES",
            frame: NSRect(
                x: columnWidth + gap, y: 0,
                width: columnWidth, height: frame.height
            )
        )
        super.init(frame: frame)
        nativeCard.onRefresh = { [weak self] in self?.onRefreshApps?() }
        profilesCard.onRefresh = { [weak self] in self?.onRefreshApps?() }
        [nativeCard, profilesCard].forEach(addSubview)
        rebuildRows()
    }

    /// Keeps both header icons and both list overlays in step during a rescan.
    func setRefreshing(_ refreshing: Bool, message: String = "Refreshing…") {
        sharedRefreshActive = refreshing
        nativeCard.setRefreshing(refreshing, message: message)
        profilesCard.setRefreshing(refreshing, message: message)
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

    func setOriginals(_ originals: [MappingNativeApp]) {
        self.originals = originals
        originalsLoaded = true
        // First arrival owns its own overlay: nobody called setRefreshing(true) for the
        // launch scan, so this is what ends the initial loading state.
        //
        // A user-initiated rescan is the opposite case and must not be cleared here. The
        // four refresh icons are driven together by setRefreshControlsBusy(_:) and must
        // never disagree, but the Mappings handler calls refreshOriginalAssignmentViews()
        // synchronously right after starting the async scan — which lands here and used
        // to switch the native card off microseconds after it was switched on, leaving
        // the App Profiles column spinning alone. The native list was being rescanned the
        // whole time; it just showed no sign of it, which read as "only App Profiles
        // refreshed". While a shared refresh is in flight, that call owns the state.
        if !sharedRefreshActive {
            nativeCard.setRefreshing(false)
        }
        rebuildRows()
    }

    /// The pinned profile ids, in pin order. Separate from `setInstances` because the
    /// pins change independently of the profile list itself.
    func setTopPinnedProfiles(_ ids: [UUID]) {
        topPinnedProfileIDs = ids
        rebuildRows()
    }

    /// Retained for the owner's status calls; the compact Mappings cards intentionally
    /// show no status line (the two lists are the content), so this is a no-op.
    func setStatus(_ message: String, color: NSColor = .appTextSecondary) {
        _ = message
        _ = color
    }

    private func rebuildRows() {
        // Top card: the installed native apps. Until the first setOriginals call (the
        // scan hasn't reported yet on first launch), show a loading state instead of a
        // premature "No native apps installed" over empty space.
        if originalsLoaded {
            let nativeWidth = nativeCard.rowContentWidth
            // Already ordered pinned-first by the controller, which owns the pin list.
            let nativeRows: [NSView] = originals.map { original in
                let row = MappingOriginalAppRowView(app: original, width: nativeWidth)
                row.onOpen = { [weak self] in self?.onOpenOriginal?($0) }
                row.onAssign = { [weak self] in self?.onAssignOriginal?($0) }
                row.onToggleMenuBar = { [weak self] in self?.onToggleOriginalMenuBar?($0) }
                row.onTogglePin = { [weak self] in self?.onTogglePinOriginal?($0) }
                return row
            }
            nativeCard.setRows(
                nativeRows,
                rowHeight: MappingOriginalAppRowView.rowHeight,
                stickyCount: originals.prefix { $0.topPinned }.count,
                emptyMessage: "No native apps installed"
            )
        } else {
            nativeCard.showLoading()
        }

        // Bottom card: the generated App Profiles.
        let profilesWidth = profilesCard.rowContentWidth
        let visible = instances.filter { instance in
            instance.state == .active
                && (instance.launcherKind == .managed
                || previewRenderingIsActive
                || FileManager.default.fileExists(atPath: instance.launcherPath))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        // Pinned profiles lead; the rest stay alphabetical behind them.
        let ordered = topPinnedFirst(visible, pins: topPinnedProfileIDs) { $0.id }
        // Only pins for profiles actually in this list consume a slot: a pin left behind by
        // a deleted profile has no card to unpin from, so counting it would lock the user
        // out. Set membership is fine here — nothing iterates it.
        let liveIDs = Set(visible.map(\.id))
        let atLimit = topPinnedProfileIDs.filter(liveIDs.contains).count
            >= KlikProConfig.topPinLimit
        let profileRows: [NSView] = ordered.map { instance in
            let row = MappingAppProfileOpenRowView(
                instance: instance,
                health: runtimeHealth[instance.id],
                width: profilesWidth,
                topPinned: topPinnedProfileIDs.contains(instance.id),
                topPinAtLimit: atLimit
            )
            row.onOpen = { [weak self] in self?.onOpen?($0) }
            row.onAssign = { [weak self] in self?.onAssign?($0) }
            row.onToggleMenuBar = { [weak self] in self?.onToggleMenuBar?($0) }
            row.onTogglePin = { [weak self] in self?.onTogglePinProfile?($0) }
            return row
        }
        profilesCard.setRows(
            profileRows,
            rowHeight: MappingAppProfileOpenRowView.rowHeight,
            stickyCount: ordered.prefix { topPinnedProfileIDs.contains($0.id) }.count,
            emptyMessage: "No App Profiles yet"
        )
    }
}

final class AppProfilesContentView: NSView {
    /// Even split between the generator column and the management list.
    private static let generatorColumnRatio: CGFloat = 0.50
    /// Top of both column headers. The titles are drawn in `draw(_:)` while the
    /// refresh icons are real subviews, so both read this rather than repeating a
    /// literal — that split is what let the refresh control drift out of the header
    /// in the first place. Kept tight to the panel edge: there is nothing above the
    /// headers, so a large inset was only dead space.
    private static let headerTopY: CGFloat = 24
    /// First row of column content, below the header and its one-line caption.
    private static let columnContentY: CGFloat = 126

    private let explanationField = NSTextField(wrappingLabelWithString:
        "Generate another icon for the same app, with a separate login and settings. The native app is never copied, cloned or modified."
    )
    private let statusField = NSTextField(labelWithString: "")
    /// One generator card per launch target, built from QuickLaunchTarget.allCases so
    /// a new target needs no wiring here. Kept in allCases order for stable layout.
    private let generatorCards: [(target: QuickLaunchTarget, card: DualAppGeneratorCard)]
    private let generatorList = AppCardListView(frame: .zero)
    private let profilesList = AppCardListView(frame: .zero)
    /// One rescan icon per column, inline at the right of each section header, so
    /// whichever column the user is reading has the control to hand. Both call the
    /// same onRefreshApps and are kept in the same enabled state.
    private let generatorRefreshButton = makeRefreshIconButton()
    private let profilesRefreshButton = makeRefreshIconButton()
    var onGenerate: ((AppProfileCandidate) -> Void)?
    var onOpenOriginal: ((QuickLaunchTarget) -> Void)?
    var onAssignOriginal: ((QuickLaunchTarget) -> Void)?
    var onCreateOriginalDock: ((QuickLaunchTarget) -> Void)?
    var onRenameOriginalDock: ((QuickLaunchTarget) -> Void)?
    var onChangeOriginalDockIcon: ((QuickLaunchTarget) -> Void)?
    var onResetOriginalDockIcon: ((QuickLaunchTarget) -> Void)?
    var onDeleteOriginalDock: ((QuickLaunchTarget) -> Void)?
    var onAddNativeOriginalDock: ((QuickLaunchTarget) -> Void)?
    var onRemoveNativeOriginalDock: ((QuickLaunchTarget) -> Void)?
    var onToggleOriginalMenuBar: ((QuickLaunchTarget) -> Void)?
    var onOpen: ((AppProfileInstance) -> Void)?
    var onAssign: ((AppProfileInstance) -> Void)?
    var onToggleMenuBar: ((AppProfileInstance) -> Void)?
    var onRename: ((AppProfileInstance) -> Void)?
    var onRemove: ((AppProfileInstance) -> Void)?
    var onChangeIcon: ((AppProfileInstance) -> Void)?
    var onAddToDock: ((AppProfileInstance) -> Void)?
    var onChangeApp: ((String) -> Void)?
    var onRefreshApps: (() -> Void)?
    var onTogglePinOriginal: ((QuickLaunchTarget) -> Void)?
    var onTogglePinProfile: ((AppProfileInstance) -> Void)?
    var onInstancesChange: (([AppProfileInstance]) -> Void)?
    var onRuntimeHealthChange: (([UUID: AppProfileRuntimeHealth]) -> Void)?
    var onStatusChange: ((String, NSColor) -> Void)?
    private var instances: [AppProfileInstance] = []
    private var supportedCandidates: [AppProfileCandidate] = []
    private var runtimeHealth: [UUID: AppProfileRuntimeHealth] = [:]
    /// List-order pins, in the user's pin order. Both columns read these: the generator
    /// column reorders its cards, the profiles column reorders its rows.
    private var topPinnedOriginals: [QuickLaunchTarget] = []
    private var topPinnedProfileIDs: [UUID] = []

    override var isFlipped: Bool { true }

    init(instances: [AppProfileInstance], width: CGFloat, height: CGFloat = 566) {
        let generatorColumnWidth = floor(width * Self.generatorColumnRatio)
        let generatorListWidth = generatorColumnWidth - 36
        let generatorWidth = AppCardListView.contentWidth(for: generatorListWidth)
        let profilesX = generatorColumnWidth + 16
        generatorCards = QuickLaunchTarget.allCases.map { target in
            (target, DualAppGeneratorCard(
                bundleIdentifier: target.applicationBundleIdentifier,
                fallbackName: target.title,
                width: generatorWidth
            ))
        }
        // Match the outer scroll viewport so the profiles column fills the window rather
        // than leaving empty space below a fixed-height card.
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        explanationField.frame = NSRect(
            x: 18, y: Self.headerTopY + 26, width: generatorListWidth, height: 64
        )
        explanationField.font = .systemFont(ofSize: 12)
        explanationField.textColor = .appTextSecondary
        // The transient status line ("… is ready.", "… was generated") is
        // intentionally hidden: the list itself shows the profiles, and failures
        // already surface as an alert. The field is kept (off-screen text sink)
        // so the many setStatus call sites stay valid.
        statusField.frame = NSRect(x: profilesX, y: 108, width: width - profilesX - 18, height: 20)
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .appTextSecondary
        statusField.isHidden = true
        // Refresh re-scans installed apps for both columns. One icon per column,
        // right-aligned inline with that column's section header (drawn at y 52 in
        // draw(_:)), so it costs no vertical space and the reading column always has
        // the control to hand.
        let refreshSide: CGFloat = 26
        // Centred on the header text's line (headerTopY is the text's top, ~14pt tall).
        let headerRefreshY = Self.headerTopY + 7 - refreshSide / 2
        generatorRefreshButton.frame = NSRect(
            x: generatorColumnWidth - 18 - refreshSide, y: headerRefreshY,
            width: refreshSide, height: refreshSide
        )
        profilesRefreshButton.frame = NSRect(
            x: width - 18 - refreshSide, y: headerRefreshY,
            width: refreshSide, height: refreshSide
        )
        generatorRefreshButton.onPress = { [weak self] in self?.onRefreshApps?() }
        profilesRefreshButton.onPress = { [weak self] in self?.onRefreshApps?() }

        // Both columns use the same scroll primitive, top line, card height, spacing,
        // fixed-size handle, and refresh veil.
        let listHeight = bounds.height - Self.columnContentY - 14
        generatorList.frame = NSRect(
            x: 18,
            y: Self.columnContentY,
            width: generatorListWidth,
            height: listHeight
        )
        profilesList.frame = NSRect(
            x: generatorColumnWidth + 12,
            y: Self.columnContentY,
            width: width - generatorColumnWidth - 28,
            height: listHeight
        )
        generatorList.setAccessibilityLabel("App Profile Generator list")
        profilesList.setAccessibilityLabel("Your App Profiles list")

        for (target, card) in generatorCards {
            // Mouse Profile launch assignments are target-based, so every declared
            // native app can own a button even when it has no global hotkey slot.
            card.setAssignable(true)
            card.onGenerate = { [weak self] in self?.onGenerate?($0) }
            card.onOpen = { [weak self] _ in self?.onOpenOriginal?(target) }
            card.onAssign = { [weak self] in self?.onAssignOriginal?(target) }
            card.onCreateDock = { [weak self] in self?.onCreateOriginalDock?(target) }
            card.onRenameDock = { [weak self] in self?.onRenameOriginalDock?(target) }
            card.onChangeIconDock = { [weak self] in self?.onChangeOriginalDockIcon?(target) }
            card.onResetIconDock = { [weak self] in self?.onResetOriginalDockIcon?(target) }
            card.onDeleteDock = { [weak self] in self?.onDeleteOriginalDock?(target) }
            card.onAddNativeDock = { [weak self] in self?.onAddNativeOriginalDock?(target) }
            card.onRemoveNativeDock = { [weak self] in self?.onRemoveNativeOriginalDock?(target) }
            card.onToggleMenuBar = { [weak self] in self?.onToggleOriginalMenuBar?(target) }
            card.onTogglePin = { [weak self] in self?.onTogglePinOriginal?(target) }
        }
        ([
            explanationField, statusField,
            generatorRefreshButton, profilesRefreshButton, generatorList, profilesList,
        ] as [NSView]).forEach(addSubview)
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

    /// Sends the installed cards to the shared scroll list, pinned first. Filtering
    /// before `setRows` means an absent app leaves neither a row nor spacing behind.
    private func relayoutGeneratorCards() {
        let ordered = topPinnedFirst(generatorCards, pins: topPinnedOriginals) { $0.target }
        // Counted after filtering, not before: a pin whose app is not installed leaves no
        // card, so counting it would make an unpinned card sticky.
        let visible = ordered.filter { $0.card.candidate != nil }
        generatorList.setRows(
            visible.map { $0.card },
            stickyCount: visible.prefix { topPinnedOriginals.contains($0.target) }.count,
            emptyMessage: "No supported apps installed"
        )
    }

    /// Reflects which native apps are pinned to the top of the app lists, and pushes the
    /// cap state so an unpinned card in a full list shows a disabled pin with the reason.
    /// `atLimit` is supplied by the controller rather than derived from `targets.count`:
    /// only pins with an installed app behind them consume a slot, and this view cannot
    /// tell which those are.
    func setTopPinnedOriginals(_ targets: [QuickLaunchTarget], atLimit: Bool) {
        topPinnedOriginals = targets
        for (target, card) in generatorCards {
            card.setTopPinned(targets.contains(target), atLimit: atLimit)
        }
        relayoutGeneratorCards()
    }

    /// Pinned profile ids in pin order, for the right-hand column's own ordering.
    func setTopPinnedProfiles(_ ids: [UUID]) {
        topPinnedProfileIDs = ids
        rebuildRows()
    }

    /// Reflects the live Dock pin state of each original-app launcher on its card.
    func setOriginalDockPinned(_ states: [QuickLaunchTarget: Bool]) {
        for (target, card) in generatorCards { card.setDockPinned(states[target] ?? false) }
    }

    /// A native Dock launcher's persisted custom name/icon, for the generator card tile.
    struct DockCustomization {
        let name: String?
        let icon: NSImage?
    }

    /// Reflects each native launcher's persisted custom name/icon on its card.
    func setOriginalDockCustomization(_ states: [QuickLaunchTarget: DockCustomization]) {
        for (target, card) in generatorCards {
            card.setDockCustomization(name: states[target]?.name, icon: states[target]?.icon)
        }
    }

    /// Reflects the persisted menu-bar pin state of each original app on its card.
    func setOriginalMenuBarPinned(_ states: [QuickLaunchTarget: Bool]) {
        for (target, card) in generatorCards { card.setMenuBarPinned(states[target] ?? false) }
    }

    func setSupportedCandidates(_ candidates: [AppProfileCandidate]) {
        supportedCandidates = candidates.filter { $0.canCreate }
        let cardBundleIDs = Set(generatorCards.map(\.card.bundleIdentifier))
        let alternatives = supportedCandidates.filter {
            !cardBundleIDs.contains($0.app.bundleIdentifier)
        }
        setRefreshing(false)
        // A card only appears when its app is actually installed; a listed-but-absent
        // app would otherwise show a card whose every action is dead.
        for (_, card) in generatorCards {
            let candidate = supportedCandidates.first {
                $0.app.bundleIdentifier == card.bundleIdentifier
            }
            card.isHidden = candidate == nil
            card.update(candidate: candidate, alternativesAvailable: !alternatives.isEmpty)
            // Exact catalogue rules are owner-declared Verified; generic engine-only
            // detections never reach this list.
            card.setCompatibility(verified: candidate.map { $0.eligibility.kind == .verified })
        }
        relayoutGeneratorCards()
        if statusField.stringValue == "Scanning installed apps…" {
            setStatus("")
        }
    }

    func setOriginalAssignments(
        _ assignments: [QuickLaunchTarget: QuickLaunchMouseButton]
    ) {
        for (target, card) in generatorCards {
            card.updateAssignment(assignments[target])
        }
    }

    /// Keeps both column icons and both per-list overlays in step during a rescan.
    func setRefreshing(_ refreshing: Bool, message: String = "Refreshing…") {
        applyRefreshIconState(generatorRefreshButton, refreshing: refreshing)
        applyRefreshIconState(profilesRefreshButton, refreshing: refreshing)
        generatorList.setRefreshing(refreshing, message: message)
        profilesList.setRefreshing(refreshing, message: message)
    }

    func setAppDiscoveryLoading() {
        setRefreshing(true, message: "Scanning installed apps…")
        setStatus("Scanning installed apps…")
    }

    func setRuntimeHealth(_ health: [UUID: AppProfileRuntimeHealth]) {
        runtimeHealth = health
        rebuildRows()
        onRuntimeHealthChange?(health)
    }

    private func rebuildRows() {
        let rowWidth = max(320, profilesList.rowContentWidth)
        let visible = instances.filter { instance in
            instance.state == .active
                && (instance.launcherKind == .managed
                || previewRenderingIsActive
                || FileManager.default.fileExists(atPath: instance.launcherPath))
        }
        // Pinned profiles lead, then the rest alphabetically — the same ordering the
        // Mappings profiles list uses, so both tabs agree.
        let sorted = visible.sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        let liveIDs = Set(visible.map(\.id))
        let atLimit = topPinnedProfileIDs.filter(liveIDs.contains).count
            >= KlikProConfig.topPinLimit
        let orderedInstances = topPinnedFirst(
            sorted,
            pins: topPinnedProfileIDs,
            key: { $0.id }
        )
        let profileRows: [NSView] = orderedInstances.map { instance in
            let row = AppProfileInstanceRowView(
                instance: instance,
                health: runtimeHealth[instance.id],
                width: rowWidth,
                topPinned: topPinnedProfileIDs.contains(instance.id),
                topPinAtLimit: atLimit
            )
            row.onOpen = { [weak self] in self?.onOpen?($0) }
            row.onAssign = { [weak self] in self?.onAssign?($0) }
            row.onToggleMenuBar = { [weak self] in self?.onToggleMenuBar?($0) }
            row.onRename = { [weak self] in self?.onRename?($0) }
            row.onRemove = { [weak self] in self?.onRemove?($0) }
            row.onChangeIcon = { [weak self] in self?.onChangeIcon?($0) }
            row.onAddToDock = { [weak self] in self?.onAddToDock?($0) }
            row.onTogglePin = { [weak self] in self?.onTogglePinProfile?($0) }
            return row
        }
        profilesList.setRows(
            profileRows,
            stickyCount: orderedInstances.prefix { topPinnedProfileIDs.contains($0.id) }.count,
            emptyMessage: "No App Profiles yet"
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
        "APP PROFILE GENERATOR".draw(at: NSPoint(x: 18, y: Self.headerTopY), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.appTextSecondary,
        ])
        let generatorColumnWidth = floor(bounds.width * Self.generatorColumnRatio)
        let profilesX = generatorColumnWidth + 16
        "YOUR APP PROFILES".draw(at: NSPoint(x: profilesX, y: Self.headerTopY), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.appTextSecondary,
        ])
        ("Open, assign, or manage each separate profile." as NSString).draw(
            at: NSPoint(x: profilesX, y: Self.headerTopY + 27),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.appTextPrimary,
            ]
        )
        NSColor.separatorColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: generatorColumnWidth - 0.5,
                y: 0,
                width: 1,
                height: bounds.height
            )
        ).fill()
    }
}

/// The locked "Advanced" tab (Durable Data Vault, Phase 2). A dumb view in the
/// same mould as `AppProfilesContentView`: chrome in `draw(_:)`, everything else
/// a subview, and all real work driven by the owner through closures + setters.
/// Locked behind a padlock by default so the data-location controls can't be
/// changed by accident; unlocking reveals three sections — the data folder new
/// profiles are stored in (choose, clear, or Scan & Import an existing one), the
/// per-profile maintenance rows, and profile cleanup for leftovers.
private final class FlippedMaintenanceView: NSView {
    override var isFlipped: Bool { true }
}

final class AdvancedSettingsContentView: NSView {
    // Locked-state views. The lock icon itself is the control — pressing it asks
    // for an explicit risk confirmation before the data-location options appear.
    private let lockButton = NSButton()
    private let lockTitle = NSTextField(labelWithString: "Advanced settings are locked")
    private let lockBody = NSTextField(wrappingLabelWithString:
        "Advanced options change where App Profile data is stored on disk. Pointing "
        + "at the wrong folder can leave profiles unfindable or split across locations, "
        + "and existing profiles are never moved. Only continue if you understand the "
        + "consequences."
    )
    private let lockHint = NSTextField(labelWithString: "Click the lock to unlock")

    // Unlocked-state views — "Data folder for new profiles". Scan & Import lives
    // here too: it points Klik PRO at an existing data folder, which is the same
    // decision as choosing one.
    private let dataRootLabel = NSTextField(labelWithString: "DATA FOLDER FOR NEW PROFILES")
    private let dataRootBody = NSTextField(wrappingLabelWithString:
        "New App Profiles are stored here so their logins survive uninstalling Klik PRO. "
        + "Existing profiles are never moved. Already have a Klik PRO data folder from a "
        + "reinstall or another Mac? Scan & Import brings back the App Profiles it holds — "
        + "pick the folder containing \"vault.json\", not the \".claude\" or \".codex\" "
        + "links in your Home folder."
    )
    private let dataRootValueField = NSTextField(labelWithString: "")
    private let chooseButton = AppProfileButton(title: "Choose Folder…", frame: .zero)
    private let clearButton = AppProfileButton(title: "Clear", frame: .zero)
    private let scanButton = AppProfileButton(title: "Scan & Import…", frame: .zero)

    // Unlocked-state views — "Profile cleanup". Leftovers outlive the profiles
    // that made them, so this sits after the maintenance rows.
    private let cleanupLabel = NSTextField(labelWithString: "PROFILE CLEANUP")
    private let cleanupBody = NSTextField(wrappingLabelWithString:
        "Find and remove leftovers from App Profiles you have already removed — Dock, "
        + "Launchpad, and menu-bar icons, custom-icon copies, lock files, and profile "
        + "data with no Klik PRO entry. Only Klik PRO-owned locations are scanned."
    )
    private let deepScanButton = AppProfileButton(title: "Deep Scan for Leftovers…", frame: .zero)

    // Unlocked-state views — lifecycle and repair. Rows are rebuilt from the
    // persisted configuration so this surface never acts on unsaved mappings.
    private let maintenanceLabel = NSTextField(labelWithString: "APP PROFILE MAINTENANCE")
    private let maintenanceBody = NSTextField(wrappingLabelWithString:
        "Repair a missing launcher, or archive a profile without deleting its login data. "
        + "Archived profiles can be restored later. Delete Data removes the launcher, "
        + "Klik PRO entry, and login/profile data after confirmation."
    )
    private let maintenanceScroll = NSScrollView()
    private let maintenanceDocument = FlippedMaintenanceView()
    private let maintenanceScrollbar: FixedAppCardScrollbarView

    private let statusField = NSTextField(wrappingLabelWithString: "")

    var onUnlock: (() -> Void)?
    var onChooseFolder: (() -> Void)?
    var onClearFolder: (() -> Void)?
    /// Scan & Import — point Klik PRO at an existing data folder and bring back
    /// the App Profiles its `vault.json` describes.
    var onScanAndImport: (() -> Void)?
    /// Deep scan for orphaned launcher/metadata leftovers, with one-click clean.
    var onDeepScan: (() -> Void)?
    var onRepair: ((AppProfileInstance) -> Void)?
    var onArchive: ((AppProfileInstance) -> Void)?
    var onRestore: ((AppProfileInstance) -> Void)?
    /// Forget Entry — drop a stale record whose data is already gone.
    var onForget: ((AppProfileInstance) -> Void)?
    /// Delete an existing profile's login data (Trash or Permanent, chosen at
    /// action time).
    var onDeleteData: ((AppProfileInstance) -> Void)?
    /// Reclaim record-less orphaned data on disk.
    var onDeleteOrphan: ((OrphanFinding) -> Void)?
    var onRevealOrphan: ((OrphanFinding) -> Void)?

    private var isLocked = true
    /// Whether the tab is currently locked — read by the tab bar to show a lock glyph.
    var locked: Bool { isLocked }
    private var lockedViews: [NSView] { [lockButton, lockTitle, lockBody, lockHint] }
    private var unlockedViews: [NSView] {
        [dataRootLabel, dataRootBody, dataRootValueField, chooseButton, clearButton,
         scanButton, maintenanceLabel, maintenanceBody, maintenanceScroll,
         maintenanceScrollbar, cleanupLabel, cleanupBody, deepScanButton, statusField]
    }

    override var isFlipped: Bool { true }

    init(dataRoot: String?, width: CGFloat, height: CGFloat = 566) {
        maintenanceScrollbar = FixedAppCardScrollbarView(
            scrollView: maintenanceScroll,
            thumbHeight: AppCardMetrics.height * 0.4,
            accessibilityLabel: "App profile maintenance scroll bar"
        )
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Locked state, centred. The lock icon is a pressable button.
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        lockButton.isBordered = false
        lockButton.imagePosition = .imageOnly
        lockButton.title = ""
        lockButton.setButtonType(.momentaryChange)
        lockButton.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")?
            .withSymbolConfiguration(iconConfig)
        lockButton.contentTintColor = .appTextSecondary
        lockButton.frame = NSRect(x: width / 2 - 28, y: 150, width: 56, height: 56)
        lockButton.target = self
        lockButton.action = #selector(lockPressed)
        lockTitle.frame = NSRect(x: 0, y: 220, width: width, height: 24)
        lockTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        lockTitle.textColor = .appTextPrimary
        lockTitle.alignment = .center
        lockBody.frame = NSRect(x: width / 2 - 270, y: 252, width: 540, height: 72)
        lockBody.font = .systemFont(ofSize: 12)
        lockBody.textColor = .appTextSecondary
        lockBody.alignment = .center
        lockHint.frame = NSRect(x: 0, y: 338, width: width, height: 18)
        lockHint.font = .systemFont(ofSize: 12, weight: .medium)
        lockHint.textColor = .controlAccentColor
        lockHint.alignment = .center

        // Sections 1 and 3 share the top row. Keeping these compact side by side
        // gives the maintenance list the vertical space it needs below.
        let columnGap: CGFloat = 24
        let columnWidth = floor((width - 56 - columnGap) / 2)
        let rightColumnX = 28 + columnWidth + columnGap
        styleSectionLabel(dataRootLabel, frame: NSRect(x: 28, y: 24, width: columnWidth, height: 16))
        styleBody(dataRootBody, frame: NSRect(x: 28, y: 48, width: columnWidth, height: 64))
        dataRootValueField.frame = NSRect(x: 28, y: 116, width: columnWidth, height: 20)
        dataRootValueField.font = .systemFont(ofSize: 12, weight: .medium)
        dataRootValueField.textColor = .appTextPrimary
        dataRootValueField.lineBreakMode = .byTruncatingMiddle
        chooseButton.frame = NSRect(x: 28, y: 140, width: 132, height: 28)
        chooseButton.onPress = { [weak self] in self?.onChooseFolder?() }
        clearButton.frame = NSRect(x: 168, y: 140, width: 78, height: 28)
        clearButton.onPress = { [weak self] in self?.onClearFolder?() }
        scanButton.frame = NSRect(x: 252, y: 140, width: min(170, columnWidth - 224), height: 28)
        scanButton.toolTip =
            "Point Klik PRO at an existing data folder and bring back the App Profiles "
            + "its \"vault.json\" describes. Existing profiles are left untouched."
        scanButton.onPress = { [weak self] in self?.onScanAndImport?() }

        // Section 2 — Maintenance rows for the profiles Klik PRO still tracks.
        styleSectionLabel(maintenanceLabel, frame: NSRect(x: 28, y: 204, width: width - 56, height: 16))
        styleBody(maintenanceBody, frame: NSRect(x: 28, y: 228, width: width - 56, height: 36))
        maintenanceScroll.frame = NSRect(x: 28, y: 270, width: width - 56, height: 242)
        maintenanceScroll.drawsBackground = false
        maintenanceScroll.hasVerticalScroller = false
        maintenanceScroll.autohidesScrollers = false
        maintenanceScroll.documentView = maintenanceDocument
        maintenanceScrollbar.frame = NSRect(x: width - 42, y: 270, width: FixedAppCardScrollbarView.width + 4, height: 242)

        // Section 3 — Profile cleanup for what removed profiles left behind.
        styleSectionLabel(cleanupLabel, frame: NSRect(x: rightColumnX, y: 24, width: columnWidth, height: 16))
        styleBody(cleanupBody, frame: NSRect(x: rightColumnX, y: 48, width: columnWidth, height: 64))
        deepScanButton.frame = NSRect(x: rightColumnX, y: 132, width: min(226, columnWidth), height: 28)
        deepScanButton.toolTip =
            "Find and remove leftover Dock, Launchpad, and menu-bar icons, custom-icon "
            + "copies, lock files, and data folders from profiles you've removed."
        deepScanButton.onPress = { [weak self] in self?.onDeepScan?() }

        // Keep transient feedback inside the maintenance card. The card reaches
        // almost to the bottom of this tab, avoiding a detached blank band above
        // the window's fixed Save / Close footer.
        statusField.frame = NSRect(x: 28, y: 520, width: width - 56, height: 30)
        statusField.font = .systemFont(ofSize: 12)
        statusField.textColor = .appTextSecondary

        (lockedViews + unlockedViews).forEach(addSubview)
        setDataRoot(dataRoot)
        setLocked(true)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func lockPressed() { onUnlock?() }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isLocked { addCursorRect(lockButton.frame, cursor: .pointingHand) }
    }

    private func styleSectionLabel(_ field: NSTextField, frame: NSRect) {
        field.frame = frame
        field.font = .boldSystemFont(ofSize: 12)
        field.textColor = .appTextSecondary
    }

    private func styleBody(_ field: NSTextField, frame: NSRect) {
        field.frame = frame
        field.font = .systemFont(ofSize: 12)
        field.textColor = .appTextSecondary
    }

    /// Locks or unlocks the tab. Locking also clears any transient status so a
    /// stale message never greets the next unlock.
    func setLocked(_ locked: Bool) {
        isLocked = locked
        lockedViews.forEach { $0.isHidden = !locked }
        unlockedViews.forEach { $0.isHidden = locked }
        if locked { statusField.stringValue = "" }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// Reflects the persisted `config.dataRoot`: the absolute path when a vault is
    /// configured, or the default Application Support wording when it is nil.
    func setDataRoot(_ path: String?) {
        if let path, !path.isEmpty {
            dataRootValueField.stringValue = path
            dataRootValueField.textColor = .appTextPrimary
            clearButton.isEnabled = true
        } else {
            dataRootValueField.stringValue = "Default (Application Support)"
            dataRootValueField.textColor = .appTextSecondary
            clearButton.isEnabled = false
        }
    }

    func setStatus(_ message: String, color: NSColor = .appTextSecondary) {
        statusField.stringValue = message
        statusField.textColor = color
    }

    func setMaintenanceInstances(
        _ instances: [AppProfileInstance],
        health: [UUID: AppProfileMaintenanceHealth],
        orphans: [OrphanFinding] = []
    ) {
        maintenanceDocument.subviews.forEach { $0.removeFromSuperview() }
        let ordered = instances
            .filter { $0.launcherKind == .managed }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        let width = maintenanceScroll.contentSize.width
        let rowHeight: CGFloat = 54
        let headerHeight: CGFloat = 24
        // config rows + (orphan header + orphan rows) when any orphans exist.
        let orphanBlock = orphans.isEmpty ? 0 : Int(headerHeight) + orphans.count * Int(rowHeight)
        let contentHeight = CGFloat(ordered.count) * rowHeight + CGFloat(orphanBlock)
        // Exact document height, never stretched up to the viewport: the scroller draws
        // its handle as viewport/document, so padding the document toward the viewport
        // height forced a nearly full-length handle that barely moved. With the true
        // height the handle is proportional to how much is off-screen, and
        // autohidesScrollers hides it entirely when the list fits.
        maintenanceDocument.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

        if ordered.isEmpty && orphans.isEmpty {
            let empty = NSTextField(labelWithString: "No managed App Profiles yet.")
            empty.frame = NSRect(x: 12, y: 16, width: 300, height: 18)
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .appTextSecondary
            maintenanceDocument.addSubview(empty)
            return
        }

        var y: CGFloat = 0
        for (index, instance) in ordered.enumerated() {
            let state = health[instance.id] ?? .missingData
            addMaintenanceRow(
                at: y, width: width, title: instance.label,
                detail: state.displayName, detailColor: state.displayColor,
                primary: primaryAction(for: state, instance: instance),
                delete: deleteAction(for: state, instance: instance)
            )
            if index + 1 < ordered.count || !orphans.isEmpty {
                addMaintenanceDivider(at: y + rowHeight - 1, width: width)
            }
            y += rowHeight
        }

        guard !orphans.isEmpty else { return }
        let header = NSTextField(labelWithString: "LEFTOVER DATA — NO PROFILE")
        header.frame = NSRect(x: 12, y: y + 6, width: width - 24, height: 14)
        header.font = .boldSystemFont(ofSize: 10)
        header.textColor = .appTextSecondary
        maintenanceDocument.addSubview(header)
        y += headerHeight
        for (index, orphan) in orphans.enumerated() {
            let path = orphan.dataPaths.first?.path ?? orphan.instanceID.uuidString
            let size = ByteCountFormatter.string(fromByteCount: orphan.sizeBytes, countStyle: .file)
            let detail = "\(orphan.state.displayName) · \(size) · \(path)"
            let primary: (title: String, action: () -> Void)? = orphan.state == .needsManualReview
                ? ("Reveal in Finder", { [weak self] in self?.onRevealOrphan?(orphan) })
                : nil
            let delete: (title: String, action: () -> Void)? = orphan.state == .orphanedData
                ? ("Delete Data…", { [weak self] in self?.onDeleteOrphan?(orphan) })
                : nil
            addMaintenanceRow(
                at: y, width: width, title: "Unknown profile",
                detail: detail, detailColor: orphan.state.displayColor,
                primary: primary, delete: delete
            )
            if index + 1 < orphans.count {
                addMaintenanceDivider(at: y + rowHeight - 1, width: width)
            }
            y += rowHeight
        }
    }

    private func primaryAction(
        for state: AppProfileMaintenanceHealth,
        instance: AppProfileInstance
    ) -> (title: String, action: () -> Void)? {
        switch state {
        case .missingLauncher:
            return ("Repair", { [weak self] in self?.onRepair?(instance) })
        case .recoverableArchived:
            return ("Restore", { [weak self] in self?.onRestore?(instance) })
        case .healthy:
            return ("Archive", { [weak self] in self?.onArchive?(instance) })
        case .missingData:
            return ("Forget…", { [weak self] in self?.onForget?(instance) })
        case .orphanedData, .needsManualReview:
            return nil
        }
    }

    private func deleteAction(
        for state: AppProfileMaintenanceHealth,
        instance: AppProfileInstance
    ) -> (title: String, action: () -> Void)? {
        // Missing-data rows have no data to delete (Forget is the only action).
        switch state {
        case .healthy, .recoverableArchived, .missingLauncher:
            return ("Delete Data…", { [weak self] in self?.onDeleteData?(instance) })
        case .missingData, .orphanedData, .needsManualReview:
            return nil
        }
    }

    private func addMaintenanceRow(
        at y: CGFloat,
        width: CGFloat,
        title: String,
        detail: String,
        detailColor: NSColor,
        primary: (title: String, action: () -> Void)?,
        delete: (title: String, action: () -> Void)?
    ) {
        let name = NSTextField(labelWithString: title)
        name.frame = NSRect(x: 12, y: y + 8, width: 250, height: 18)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = .appTextPrimary
        maintenanceDocument.addSubview(name)

        // Leave room on the right for whichever buttons this row shows so the
        // (truncated) detail text never runs under them.
        let buttonCount = (primary == nil ? 0 : 1) + (delete == nil ? 0 : 1)
        let reserved: CGFloat = buttonCount == 2 ? 218 : (buttonCount == 1 ? 118 : 12)
        let detailField = NSTextField(labelWithString: detail)
        detailField.frame = NSRect(x: 12, y: y + 28, width: max(80, width - 12 - reserved), height: 16)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = detailColor
        detailField.lineBreakMode = .byTruncatingMiddle
        maintenanceDocument.addSubview(detailField)

        var buttonX = width - 118
        if let primary {
            let button = AppProfileButton(
                title: primary.title,
                frame: NSRect(x: buttonX, y: y + 13, width: 104, height: 28)
            )
            button.onPress = primary.action
            button.toolTip = Self.maintenanceButtonTooltip(for: primary.title)
            maintenanceDocument.addSubview(button)
            buttonX -= 100
        }
        if let delete {
            let button = AppProfileButton(
                title: delete.title,
                frame: NSRect(x: buttonX, y: y + 13, width: 92, height: 28)
            )
            button.onPress = delete.action
            button.toolTip = Self.maintenanceButtonTooltip(for: delete.title)
            maintenanceDocument.addSubview(button)
        }
    }

    /// Hover help for each App Profile Maintenance action. Keyed on the button
    /// title so both the standard rows and the orphan-data row stay in sync.
    private static func maintenanceButtonTooltip(for title: String) -> String? {
        switch title {
        case "Repair":
            return "Rebuild this profile's launcher — its login data is not touched."
        case "Restore":
            return "Bring this archived profile back with its original identity and icon."
        case "Archive":
            return "Deactivate this profile but keep its login data, settings, and icon to restore later."
        case "Forget…":
            return "Remove this profile's entry after its data went missing — nothing on disk is deleted."
        case "Delete Data…":
            return "Remove the launcher, Klik PRO entry, and login/profile data after confirmation."
        case "Reveal in Finder":
            return "Show this manual-review folder in Finder. Klik PRO will not delete it."
        default:
            return nil
        }
    }

    private func addMaintenanceDivider(at y: CGFloat, width: CGFloat) {
        let divider = NSBox(frame: NSRect(x: 8, y: y, width: width - 16, height: 1))
        divider.boxType = .separator
        maintenanceDocument.addSubview(divider)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Three distinct cards while unlocked: two compact top cards and the
        // full-width maintenance card below. Their geometry mirrors the content
        // columns and leaves a consistent 12-point gap between cards.
        if !isLocked {
            NSColor.separatorColor.setFill()
            let cardStroke = NSColor.separatorColor
            let cardFill = NSColor.controlBackgroundColor
            let topY: CGFloat = 8
            let topHeight: CGFloat = 168
            let bottomCardHeight = bounds.height - 196
            let leftWidth = floor((bounds.width - 56 - 24) / 2) + 16
            let rightX = 16 + leftWidth + 12
            let rightWidth = bounds.width - rightX - 16
            let cards = [
                NSRect(x: 16, y: topY, width: leftWidth, height: topHeight),
                NSRect(x: rightX, y: topY, width: rightWidth, height: topHeight),
                NSRect(
                    x: 16, y: 188, width: bounds.width - 32,
                    height: bottomCardHeight
                )
            ]
            for rect in cards {
                cardFill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
                cardStroke.setStroke()
                let border = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
                border.lineWidth = 1
                border.stroke()
            }
        }
    }
}

private extension AppProfileMaintenanceHealth {
    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .recoverableArchived: return "Archived — data preserved"
        case .missingLauncher: return "Missing launcher — repair available"
        case .missingData: return "Profile data is missing"
        case .orphanedData: return "Orphaned data"
        case .needsManualReview: return "Needs manual review"
        }
    }

    var displayColor: NSColor {
        switch self {
        case .healthy: return KlikProBrand.green
        case .recoverableArchived: return .appTextSecondary
        case .missingLauncher: return .systemOrange
        case .missingData: return .systemRed
        case .orphanedData: return .systemOrange
        case .needsManualReview: return .appTextSecondary
        }
    }
}

extension LauncherGenerator.IconColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

/// One colour dot in the Change Icon dialog. Draws a filled circle in a palette
/// colour with a selection ring, and reports clicks.
private final class IconColorSwatch: NSView {
    let color: AppProfileMenuColor
    var isSelected = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?

    init(color: AppProfileMenuColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        setAccessibilityLabel(color.title)
        toolTip = color.title
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isSelected ? 4 : 1
        let circle = bounds.insetBy(dx: inset, dy: inset)
        color.iconColor.nsColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        if color == .white {
            NSColor.separatorColor.setStroke()
            let outline = NSBezierPath(ovalIn: circle)
            outline.lineWidth = 1
            outline.stroke()
        }
        if isSelected {
            KlikProBrand.green.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// The Change Icon dialog body (used as an NSAlert accessory). Offers three
/// modes — replace with a PNG/ICO, tint the source icon, or badge it with the
/// user-selected character — over the shared nine-colour palette, with a live preview.
final class ChangeIconPanelView: NSView, NSTextFieldDelegate {
    enum Mode: Int { case image, tint, badge }

    private let sourceBundleURL: URL
    private let sourceImage: CGImage?
    private let fallbackImage: NSImage

    private let segmented: NSSegmentedControl
    private let preview = NSImageView()
    private let hint = NSTextField(wrappingLabelWithString:
        "Tint or badge the app's own icon, or choose your own PNG or ICO. "
        + "The native app is never modified."
    )
    private let chooseButton = AppProfileButton(title: "Choose PNG or ICO…", frame: .zero)
    private let chosenLabel = NSTextField(labelWithString: "No image chosen")
    private let imageRequirementLabel = NSTextField(labelWithString: "")
    private let colorLabel = NSTextField(labelWithString: "Colour")
    private let badgeCharacterLabel = NSTextField(labelWithString: "Character")
    private let badgeCharacterField = NSTextField(string: "")
    private var swatches: [IconColorSwatch] = []

    private var mode: Mode = .tint
    private var chosenImageURL: URL?
    private var selectedColor: AppProfileMenuColor = .blue

    override var isFlipped: Bool { true }

    /// `sourceBundleURL` is the vendor app the tint/badge modes derive from;
    /// `fallbackImage` is shown when the source icon can't be read or Image mode
    /// has no file yet. Managed profiles pass instance-derived values; the original
    /// app's Dock launcher passes the vendor bundle and its current launcher icon.
    init(sourceBundleURL: URL, fallbackImage: NSImage, defaultBadgeCharacter: String) {
        self.sourceBundleURL = sourceBundleURL
        badgeCharacterField.stringValue = String(defaultBadgeCharacter.uppercased().prefix(1))
        sourceImage = LauncherGenerator().sourceIconImage(sourceBundleURL: sourceBundleURL)
        self.fallbackImage = fallbackImage
        segmented = NSSegmentedControl(
            labels: ["Image", "Tint", "Badge"],
            trackingMode: .selectOne, target: nil, action: nil
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 226))

        segmented.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        segmented.selectedSegment = Mode.tint.rawValue
        segmented.target = self
        segmented.action = #selector(modeChanged)
        // Tint/Badge derive from the source app icon; if it can't be read, only
        // the Image mode is offered.
        if sourceImage == nil {
            segmented.setEnabled(false, forSegment: Mode.tint.rawValue)
            segmented.setEnabled(false, forSegment: Mode.badge.rawValue)
            mode = .image
            segmented.selectedSegment = Mode.image.rawValue
        }

        preview.frame = NSRect(x: 0, y: 40, width: 96, height: 96)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true

        hint.frame = NSRect(x: 112, y: 44, width: 308, height: 88)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .appTextSecondary

        chooseButton.frame = NSRect(x: 0, y: 150, width: 180, height: 28)
        chooseButton.onPress = { [weak self] in self?.chooseImageFile() }
        chosenLabel.frame = NSRect(x: 190, y: 155, width: 230, height: 18)
        chosenLabel.font = .systemFont(ofSize: 11)
        chosenLabel.textColor = .appTextSecondary
        chosenLabel.lineBreakMode = .byTruncatingMiddle
        let minimum = LauncherGenerator.customIconMinimumPixelSize
        imageRequirementLabel.stringValue =
            "Minimum: \(minimum) × \(minimum) px (shortest side at least \(minimum) px)"
        imageRequirementLabel.frame = NSRect(x: 0, y: 188, width: 420, height: 18)
        imageRequirementLabel.font = .systemFont(ofSize: 11, weight: .medium)
        imageRequirementLabel.textColor = .appTextSecondary

        colorLabel.frame = NSRect(x: 0, y: 150, width: 420, height: 16)
        colorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        colorLabel.textColor = .appTextSecondary

        badgeCharacterLabel.frame = NSRect(x: 280, y: 150, width: 64, height: 18)
        badgeCharacterLabel.font = .systemFont(ofSize: 11, weight: .medium)
        badgeCharacterLabel.textColor = .appTextSecondary
        badgeCharacterField.frame = NSRect(x: 350, y: 146, width: 44, height: 24)
        badgeCharacterField.alignment = .center
        badgeCharacterField.font = .systemFont(ofSize: 14, weight: .semibold)
        badgeCharacterField.delegate = self
        badgeCharacterField.setAccessibilityLabel("Badge character")

        var x: CGFloat = 0
        for color in AppProfileMenuColor.allCases {
            let swatch = IconColorSwatch(color: color)
            swatch.frame = NSRect(x: x, y: 174, width: 30, height: 30)
            swatch.isSelected = color == selectedColor
            swatch.onSelect = { [weak self] in self?.selectColor(color) }
            swatches.append(swatch)
            addSubview(swatch)
            x += 42
        }

        [
            segmented, preview, hint, chooseButton, chosenLabel, imageRequirementLabel, colorLabel,
            badgeCharacterLabel, badgeCharacterField,
        ].forEach(addSubview)
        updateModeControls()
        updatePreview()
    }

    required init?(coder: NSCoder) { nil }

    /// The edit the user configured, or nil when Image mode has no file chosen.
    var currentEdit: AppProfileManager.IconEdit? {
        switch mode {
        case .image:
            guard let chosenImageURL else { return nil }
            return .image(chosenImageURL)
        case .tint:
            return .tint(selectedColor)
        case .badge:
            guard let character = normalizedBadgeCharacter else { return nil }
            return .badge(selectedColor, character)
        }
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmented.selectedSegment) ?? .tint
        updateModeControls()
        updatePreview()
    }

    private func selectColor(_ color: AppProfileMenuColor) {
        selectedColor = color
        swatches.forEach { $0.isSelected = $0.color == color }
        updatePreview()
    }

    func controlTextDidChange(_ notification: Notification) {
        let normalized = String(badgeCharacterField.stringValue.uppercased().prefix(1))
        if badgeCharacterField.stringValue != normalized {
            badgeCharacterField.stringValue = normalized
        }
        updatePreview()
    }

    private var normalizedBadgeCharacter: String? {
        let trimmed = badgeCharacterField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.uppercased().prefix(1))
    }

    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .ico]
        panel.prompt = "Choose"
        let minimum = LauncherGenerator.customIconMinimumPixelSize
        panel.message = "Minimum: \(minimum) × \(minimum) pixels. "
            + "The shortest side must be at least \(minimum) pixels."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chosenImageURL = url
        chosenLabel.stringValue = url.lastPathComponent
        updatePreview()
    }

    private func updateModeControls() {
        let imageMode = mode == .image
        chooseButton.isHidden = !imageMode
        chosenLabel.isHidden = !imageMode
        imageRequirementLabel.isHidden = !imageMode
        colorLabel.isHidden = imageMode
        swatches.forEach { $0.isHidden = imageMode }
        badgeCharacterLabel.isHidden = mode != .badge
        badgeCharacterField.isHidden = mode != .badge
    }

    private func updatePreview() {
        let size = NSSize(width: 96, height: 96)
        switch mode {
        case .image:
            if let chosenImageURL,
               let shaped = LauncherGenerator.macOSShapedImage(fromImageAt: chosenImageURL) {
                preview.image = NSImage(cgImage: shaped, size: size)
            } else {
                preview.image = fallbackImage
            }
        case .tint:
            if let sourceImage,
               let tinted = LauncherGenerator.tintedIcon(
                sourceImage, color: selectedColor.iconColor
               ) {
                preview.image = NSImage(cgImage: tinted, size: size)
            } else {
                preview.image = fallbackImage
            }
        case .badge:
            if let sourceImage, let character = normalizedBadgeCharacter,
               let badged = LauncherGenerator.badgedIcon(
                sourceImage, color: selectedColor.iconColor, letter: character
               ) {
                preview.image = NSImage(cgImage: badged, size: size)
            } else {
                preview.image = fallbackImage
            }
        }
    }
}
