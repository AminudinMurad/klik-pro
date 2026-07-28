import AppKit

/// Click-reachability harness for the Mappings mouse slide.
///
/// `MouseProfileHeaderView` is a transparent overlay across the whole mouse card,
/// so it needs a custom `hitTest(_:)`: clicks must reach the mapping rows beneath
/// it, while its own gear and arrows stay clickable. Both halves of that contract
/// are invisible to the rendered screenshot fixtures — a dead gear looks exactly
/// like a live one — and a coordinate-space slip in that override once shipped the
/// gear and both arrows completely unclickable.
///
/// This harness drives the real view through the real hosting chain and asserts on
/// which view a click actually lands on. Control geometry is discovered from the
/// live subviews rather than hardcoded, so moving the gear or arrows cannot make
/// the harness quietly stop testing them.
@main
private struct MouseSlideHitTestMain {
    /// Flipped stand-in for `SettingsContentView`, which is also flipped. Only the
    /// coordinate conventions of the chain matter here, not its content.
    private final class HostView: NSView {
        override var isFlipped: Bool { true }
    }

    /// A real control living under the overlay, standing in for the mapping rows
    /// and thumb-wheel controls that must keep receiving their own clicks.
    private final class UnderlayControl: NSButton {
        override var isFlipped: Bool { true }
    }

    private static var failures: [String] = []

    private static func check(_ condition: Bool, _ description: String) {
        if condition {
            print("  ok   \(description)")
        } else {
            print("  FAIL \(description)")
            failures.append(description)
        }
    }

    private static func describe(_ view: NSView?) -> String {
        guard let view else { return "nil (click falls through)" }
        return String(describing: type(of: view))
    }

    private static func profiles(count: Int) -> [MouseProfile] {
        (0..<count).map { index in
            MouseProfile.quietDefault(name: "Mapping \(index + 1)")
        }
    }

    /// Builds window -> scroll view -> flipped document -> slide container -> header,
    /// mirroring how `SettingsContentView` hosts the overlay in the running app.
    private static func makeHierarchy(
        headerOrigin: NSPoint,
        profileCount: Int
    ) -> (NSWindow, MouseProfileHeaderView, MouseSlideContainerView, [UnderlayControl]) {
        let card = SettingsContentView.deviceCard
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: card.width, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scroll = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: card.width, height: 640)
        )
        let document = HostView(
            frame: NSRect(x: 0, y: 0, width: card.width, height: 566)
        )
        let container = MouseSlideContainerView(frame: card)

        // Two controls beneath the overlay, placed in gaps the overlay's own
        // buttons do not occupy, matching the real toggle/pull-down positions.
        let underlays = [
            NSRect(x: 332, y: 40, width: 40, height: 22),
            NSRect(x: 380, y: 68, width: 150, height: 26),
        ].map { frame -> UnderlayControl in
            let control = UnderlayControl(frame: frame)
            control.isBordered = false
            container.addSubview(control)
            return control
        }

        let header = MouseProfileHeaderView(
            frame: NSRect(
                x: headerOrigin.x,
                y: headerOrigin.y,
                width: card.width,
                height: card.height
            )
        )
        // Added last, so the overlay sits above the underlying controls exactly as
        // it does in `SettingsContentView`.
        container.addSubview(header)

        document.addSubview(container)
        scroll.documentView = document
        window.contentView = scroll

        let all = profiles(count: profileCount)
        header.configure(
            profiles: all,
            viewedID: all[min(1, all.count - 1)].id,
            activeID: all[0].id,
            connectedDevices: []
        )
        return (window, header, container, underlays)
    }

    /// Clicks the visible centre of `target` and reports the view AppKit would
    /// deliver that click to, driving the lookup from window base coordinates just
    /// as event dispatch does.
    private static func viewClicked(
        at target: NSView,
        in window: NSWindow
    ) -> NSView? {
        let centre = NSPoint(x: target.bounds.midX, y: target.bounds.midY)
        let windowPoint = target.convert(centre, to: nil)
        return window.contentView?.hitTest(windowPoint)
    }

    private static func overlayButtons(
        _ header: MouseProfileHeaderView
    ) -> (gear: NSView?, arrows: [NSView]) {
        var gear: NSView?
        var arrows: [NSView] = []
        for subview in header.subviews {
            if subview is AppProfileGearButton {
                gear = subview
            } else if subview is MouseSlideNavigationButton {
                arrows.append(subview)
            }
        }
        // Left-to-right, so the pair reads as previous then next.
        arrows.sort { $0.frame.minX < $1.frame.minX }
        return (gear, arrows)
    }

    private static func runCase(name: String, headerOrigin: NSPoint) {
        print("\(name):")
        let (window, header, _, underlays) = makeHierarchy(
            headerOrigin: headerOrigin,
            profileCount: 3
        )
        let (gear, arrows) = overlayButtons(header)

        guard let gear else {
            check(false, "the slide overlay still carries a gear button")
            return
        }
        check(
            arrows.count == 2,
            "the slide overlay still carries two navigation arrows"
        )

        let gearHit = viewClicked(at: gear, in: window)
        check(
            gearHit === gear,
            "a click on the gear reaches the gear (got \(describe(gearHit)))"
        )

        for (index, arrow) in arrows.enumerated() {
            let label = index == 0 ? "previous" : "next"
            let hit = viewClicked(at: arrow, in: window)
            check(
                hit === arrow,
                "a click on the \(label) arrow reaches that arrow (got \(describe(hit)))"
            )
        }

        for (index, underlay) in underlays.enumerated() {
            let hit = viewClicked(at: underlay, in: window)
            check(
                hit === underlay,
                "the overlay does not steal the click on underlying control "
                    + "\(index + 1) (got \(describe(hit)))"
            )
        }

        // A point inside the overlay but outside every one of its buttons must fall
        // through, otherwise the overlay swallows clicks meant for the artwork and
        // mapping rows behind it.
        let emptyPoint = NSPoint(x: header.bounds.midX, y: header.bounds.midY)
        let windowPoint = header.convert(emptyPoint, to: nil)
        let emptyHit = window.contentView?.hitTest(windowPoint)
        check(
            !(emptyHit is AppProfileGearButton)
                && !(emptyHit is MouseSlideNavigationButton)
                && emptyHit !== header,
            "empty overlay space does not capture the click (got \(describe(emptyHit)))"
        )
        print("")
    }

    /// The gear must not open its menu while it is disabled. It presents on
    /// mouse-down, which bypasses NSControl's own disabled guard.
    private static func runDisabledGearCase() {
        print("disabled gear ignores mouse-down:")
        let gear = AppProfileGearButton(frame: NSRect(x: 0, y: 0, width: 30, height: 28))
        var presentations = 0
        gear.onMouseDown = { _ in presentations += 1 }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = HostView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        host.addSubview(gear)
        window.contentView = host

        func click() {
            let point = gear.convert(
                NSPoint(x: gear.bounds.midX, y: gear.bounds.midY),
                to: nil
            )
            guard let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) else { return }
            gear.mouseDown(with: event)
        }

        gear.isEnabled = false
        click()
        check(presentations == 0, "a disabled gear does not present its menu")

        gear.isEnabled = true
        click()
        check(presentations == 1, "an enabled gear presents its menu once per click")
        print("")
    }

    /// End-to-end: dispatch a real left-mouse-down at the gear's on-screen position
    /// and confirm an NSMenu actually begins tracking with the expected items.
    ///
    /// This needs a visible window and a window server, so it is opt-in (`menu`
    /// argument) and kept out of the default run: a menu-tracking run loop must
    /// never be able to stall an unattended check.
    private static func runMenuPresentationCase() {
        print("clicking the gear opens its menu:")
        let (window, header, _, _) = makeHierarchy(headerOrigin: .zero, profileCount: 3)
        window.orderFrontRegardless()

        guard let gear = overlayButtons(header).gear else {
            check(false, "the slide overlay still carries a gear button")
            return
        }

        var trackedTitles: [String] = []
        var trackingMenu: NSMenu?
        let observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let menu = note.object as? NSMenu, trackingMenu == nil else { return }
            trackingMenu = menu
            trackedTitles = menu.items.map(\.title)
            // Cancelling from inside didBeginTracking is too early to take effect,
            // so hand it back to the tracking loop first.
            RunLoop.main.perform(inModes: [.eventTracking, .default]) {
                menu.cancelTracking()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Menu tracking runs its own nested run loop and blocks until it is
        // dismissed, so queue an Escape ahead of the click: the tracking session
        // consumes it as soon as it starts and returns control here. A timer added
        // to the tracking run-loop mode is the backstop, since the main dispatch
        // queue is not serviced reliably while a menu is up.
        if let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) {
            NSApp.postEvent(escape, atStart: true)
        }
        let watchdog = Timer(timeInterval: 4, repeats: false) { _ in
            trackingMenu?.cancelTracking()
        }
        for mode in [RunLoop.Mode.eventTracking, .modalPanel, .default] {
            RunLoop.main.add(watchdog, forMode: mode)
        }
        defer { watchdog.invalidate() }

        // Full dispatch path: ask the hierarchy which view AppKit would deliver the
        // click to, then deliver it there.
        let centre = NSPoint(x: gear.bounds.midX, y: gear.bounds.midY)
        let windowPoint = gear.convert(centre, to: nil)
        let target = window.contentView?.hitTest(windowPoint)
        check(target === gear, "the click at the gear is routed to the gear")

        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            check(false, "a synthetic mouse-down event could be constructed")
            return
        }
        target?.mouseDown(with: event)

        check(!trackedTitles.isEmpty, "a menu began tracking from the gear's mouse-down")
        for expected in [
            "Activate “Mapping 2”",
            "Add Mapping",
            "Rename Mapping…",
            "Duplicate Mapping",
            "Reset Mapping…",
            "Delete Mapping…",
        ] {
            check(
                trackedTitles.contains(expected),
                "the menu offers \(expected)"
            )
        }
        check(
            !trackedTitles.contains("Assign Mouse…")
                && !trackedTitles.contains("Change Mouse…")
                && !trackedTitles.contains("Unassign Mouse"),
            "mapping presets do not imply unsupported physical-mouse routing"
        )
        if !trackedTitles.isEmpty {
            print("  menu items: \(trackedTitles.filter { !$0.isEmpty }.joined(separator: " | "))")
        }
        print("")
    }

    /// `RefreshIconButton` overrides `hitTest(_:)` so its glyph and spinner cannot
    /// take the click. That override carried the same coordinate-space slip as the
    /// mouse overlay — comparing a superview-space point with `bounds` — which left
    /// all three refresh buttons unclickable wherever they are drawn. These are their
    /// real frames from `AppProfilesUI.swift`.
    private static func runRefreshButtonCase() {
        print("refresh buttons are clickable where they are drawn:")
        let cases: [(String, NSRect, NSSize)] = [
            (
                "list header refresh",
                NSRect(x: 436 - 14 - 26, y: 9, width: 26, height: 26),
                NSSize(width: 436, height: 380)
            ),
            (
                "generator column refresh",
                NSRect(x: 420 - 18 - 26, y: 45, width: 26, height: 26),
                NSSize(width: 872, height: 560)
            ),
            (
                "profiles column refresh",
                NSRect(x: 872 - 18 - 26, y: 45, width: 26, height: 26),
                NSSize(width: 872, height: 560)
            ),
        ]
        for (label, buttonFrame, hostSize) in cases {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hostSize),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let host = HostView(frame: NSRect(origin: .zero, size: hostSize))
            let button = makeRefreshIconButton()
            button.frame = buttonFrame
            host.addSubview(button)
            window.contentView = host

            let hit = viewClicked(at: button, in: window)
            check(
                hit === button,
                "a click on the \(label) reaches it (got \(describe(hit)))"
            )
        }
        print("")
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Production places the overlay at the card origin. The offset case guards
        // the frame-versus-bounds half of the conversion, which a zero origin hides.
        runCase(name: "overlay at the card origin", headerOrigin: .zero)
        runCase(name: "overlay at an offset origin", headerOrigin: NSPoint(x: 24, y: 17))
        runDisabledGearCase()
        runRefreshButtonCase()
        if CommandLine.arguments.contains("menu") {
            runMenuPresentationCase()
        }

        if failures.isEmpty {
            print("Mouse slide hit-test harness: all checks passed")
            exit(0)
        }
        fputs("Mouse slide hit-test harness failed:\n", stderr)
        for failure in failures {
            fputs("  - \(failure)\n", stderr)
        }
        exit(1)
    }
}
