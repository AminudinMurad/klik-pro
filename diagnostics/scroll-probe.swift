import AppKit
import Carbon

// Tests whether the thumb wheel surfaces as CGEventType.scrollWheel deltas
// via a standard CGEventTap, and whether it's reported as continuous
// (trackpad-like) or discrete (notched). Also watches keyDown/keyUp and
// otherMouse events, so a button that turns out to emit a plain keystroke
// (rather than a raw HID button number) still shows up here.
//
// Build:  swiftc scroll-probe.swift -o scroll-probe
// Run:    ./scroll-probe
// Needs Accessibility permission for whichever binary/terminal runs it
// (System Settings -> Privacy & Security -> Accessibility).

private let startDate = Date()
private var lastHorizontalTimestamp: Date?

private func elapsed() -> String {
    String(format: "%8.3f", Date().timeIntervalSince(startDate))
}

private func describeButton(_ n: Int64) -> String {
    switch n {
    case 0: return "left"
    case 1: return "right"
    case 2: return "middle"
    default: return "other(\(n))"
    }
}

private func describeModifiers(_ flags: CGEventFlags) -> String {
    var parts: [String] = []
    if flags.contains(.maskControl) { parts.append("Control") }
    if flags.contains(.maskAlternate) { parts.append("Option") }
    if flags.contains(.maskShift) { parts.append("Shift") }
    if flags.contains(.maskCommand) { parts.append("Command") }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
}

private func describeSource(_ event: CGEvent) -> String {
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let userID = event.getIntegerValueField(.eventSourceUserID)
    let groupID = event.getIntegerValueField(.eventSourceGroupID)
    let stateID = event.getIntegerValueField(.eventSourceStateID)
    let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
    return "source(pid=\(pid) uid=\(userID) gid=\(groupID) state=\(stateID) keyboardType=\(keyboardType))"
}

print("Thumb Wheel / Scroll Probe (path 1: CGEventTap scroll deltas)")
print("==============================================================")
print("Move the vertical wheel, tilt/scroll the thumb wheel, click side")
print("buttons, and press any other control one at a time. Watch for")
print("HSCROLL lines (thumb wheel), BUTTON lines (raw mouse buttons),")
print("or KEY DOWN/UP lines (a control that emits a plain keystroke).")
print("Press Ctrl+C to stop.\n")

let trusted = AXIsProcessTrustedWithOptions([
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
] as CFDictionary)

if !trusted {
    print("Accessibility permission not yet granted. Grant it in System")
    print("Settings -> Privacy & Security -> Accessibility for this binary")
    print("(or your terminal app), then re-run.\n")
}

let eventMask =
    (1 << CGEventType.scrollWheel.rawValue)
    | (1 << CGEventType.otherMouseDown.rawValue)
    | (1 << CGEventType.otherMouseUp.rawValue)
    | (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.keyUp.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(eventMask),
    callback: { _, type, event, _ in
        switch type {
        case .scrollWheel:
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)

            if axis2 != 0 || pointAxis2 != 0 {
                let now = Date()
                let gap: String
                if let last = lastHorizontalTimestamp {
                    gap = String(format: "+%.3fs", now.timeIntervalSince(last))
                } else {
                    gap = "first"
                }
                lastHorizontalTimestamp = now
                print("[\(elapsed())] HSCROLL axis2=\(axis2) pointAxis2=\(pointAxis2) continuous=\(isContinuous) phase=\(phase) gap=\(gap)")
            } else if axis1 != 0 || pointAxis1 != 0 {
                print("[\(elapsed())] vscroll axis1=\(axis1) pointAxis1=\(pointAxis1) continuous=\(isContinuous)")
            }
        case .otherMouseDown:
            let n = event.getIntegerValueField(.mouseEventButtonNumber)
            print("[\(elapsed())] BUTTON DOWN \(describeButton(n))")
        case .otherMouseUp:
            let n = event.getIntegerValueField(.mouseEventButtonNumber)
            print("[\(elapsed())] BUTTON UP \(describeButton(n))")
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            print("[\(elapsed())] KEY DOWN keyCode=\(keyCode) modifiers=\(describeModifiers(event.flags)) \(describeSource(event))")
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            print("[\(elapsed())] KEY UP keyCode=\(keyCode) modifiers=\(describeModifiers(event.flags)) \(describeSource(event))")
        default:
            break
        }
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("Failed to create event tap. Check Accessibility permission and try again.")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Tap installed. Listening...\n")
CFRunLoopRun()
