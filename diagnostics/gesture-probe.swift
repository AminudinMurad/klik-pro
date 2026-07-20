import AppKit
import Carbon
import Foundation
import IOKit.hid

// Confirms that the MX Master 3 Mac's physical Gesture button can be separated
// from keyboard Command-Tab by correlating its raw HID report with the later
// CGEvent. This probe is listen-only: it never suppresses or remaps input.
//
// Build: swiftc gesture-probe.swift -o gesture-probe
// Run:   ./gesture-probe
// Needs Accessibility and Input Monitoring permission for the host terminal.

private let targetVendorID = 0x046D
private let targetProductID = 0xB023
private let correlationWindow: CFAbsoluteTime = 0.100
private var lastRawGestureTime: CFAbsoluteTime?

private func elapsed(_ start: CFAbsoluteTime) -> String {
    String(format: "%8.3f", CFAbsoluteTimeGetCurrent() - start)
}

private func isMouseCommandTabReport(reportID: UInt32, bytes: [UInt8]) -> Bool {
    guard reportID == 1, bytes.count >= 8 else { return false }
    let commandMask: UInt8 = 0x88 // left or right GUI/Command
    let hasCommand = bytes[1] & commandMask != 0
    let keys = bytes[2..<8]
    return hasCommand && keys.contains(0x2B) // USB HID Keyboard Tab
}

let start = CFAbsoluteTimeGetCurrent()
print("MX Master 3 Gesture / Command-Tab Isolation Probe")
print("================================================")
print("Press the mouse Gesture button once, then keyboard Command-Tab once.")
print("The expected classifications are MOUSE GESTURE, then KEYBOARD/OTHER.")
print("This probe is listen-only. Press Ctrl+C to stop.\n")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey: targetVendorID,
    kIOHIDProductIDKey: targetProductID,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

let matchCallback: IOHIDDeviceCallback = { _, _, _, device in
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
    print("Matched device: \(product)")
}
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)

let reportCallback: IOHIDReportCallback = { _, _, _, _, reportID, report, reportLength in
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    guard isMouseCommandTabReport(reportID: reportID, bytes: bytes) else { return }
    let now = CFAbsoluteTimeGetCurrent()
    lastRawGestureTime = now
    print("[\(elapsed(start))] RAW mouse Command-Tab report")
}
IOHIDManagerRegisterInputReportCallback(manager, reportCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openStatus == kIOReturnSuccess else {
    fputs("Unable to open MX Master 3 HID device (status \(openStatus)). Check Input Monitoring.\n", stderr)
    exit(1)
}

let trusted = AXIsProcessTrustedWithOptions([
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
] as CFDictionary)
if !trusted {
    print("Accessibility is not granted; grant it and re-run.")
}

let eventMask =
    (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.keyUp.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(eventMask),
    callback: { _, type, event, _ in
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == CGKeyCode(kVK_Tab), event.flags.contains(.maskCommand) else {
            return Unmanaged.passRetained(event)
        }

        let now = CFAbsoluteTimeGetCurrent()
        let delta = lastRawGestureTime.map { now - $0 }
        let isMouseGesture = delta.map { $0 >= 0 && $0 <= correlationWindow } ?? false
        let phase = type == .keyDown ? "DOWN" : "UP"
        let source = isMouseGesture ? "MOUSE GESTURE" : "KEYBOARD/OTHER"
        let timing = delta.map { String(format: "rawDelta=%.4fs", $0) } ?? "rawDelta=none"
        print("[\(elapsed(start))] CG Command-Tab \(phase): \(source) (\(timing))")
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    fputs("Unable to create listen-only event tap. Check Accessibility.\n", stderr)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("Listening...\n")
CFRunLoopRun()
