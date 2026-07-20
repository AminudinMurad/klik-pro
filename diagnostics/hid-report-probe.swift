import Foundation
import IOKit.hid

// Tests the raw-HID implementation path for the thumb wheel: does it produce
// a distinct raw HID input report (independent of whatever CGEventTap
// surfaces)? This does not parse any vendor-specific report semantics — it
// just prints raw report bytes so we can compare a normal vertical-scroll
// report against a thumb-wheel-tilt report and see if they're
// distinguishable at the HID layer.
//
// Build:  swiftc hid-report-probe.swift -o hid-report-probe
// Run:    ./hid-report-probe
// Needs Input Monitoring permission for whichever binary/terminal runs it
// (System Settings -> Privacy & Security -> Input Monitoring), in addition
// to Accessibility.
//
// Set targetVendorID below to your mouse's USB vendor ID (check
// System Information -> USB, or `ioreg -p IOUSB -l` for the vendor ID).

let targetVendorID = 0x046D

print("Raw HID Report Probe (raw device reports)")
print("===========================================================")
print("Matching vendor ID 0x\(String(targetVendorID, radix: 16)). Move/tilt the wheel,")
print("click buttons, and compare the raw bytes between gestures.")
print("Press Ctrl+C to stop.\n")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matchingDict: [String: Any] = [kIOHIDVendorIDKey: targetVendorID]
IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

let matchCallback: IOHIDDeviceCallback = { _, _, _, device in
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
    let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? -1
    let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? -1
    print("Matched device: \(product) (vendorID=0x\(String(vendorID, radix: 16)) productID=0x\(String(productID, radix: 16)))")
}
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, nil)

let startDate = Date()

let reportCallback: IOHIDReportCallback = { _, _, sender, _, reportID, report, reportLength in
    let product: String
    if let sender {
        let device = unsafeBitCast(sender, to: IOHIDDevice.self)
        product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
    } else {
        product = "unknown"
    }
    let bytes = UnsafeBufferPointer(start: report, count: reportLength)
    let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    let t = String(format: "%8.3f", Date().timeIntervalSince(startDate))
    print("[\(t)] device=\(product) reportID=\(reportID) len=\(reportLength) bytes: \(hex)")
}

IOHIDManagerRegisterInputReportCallback(manager, reportCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openStatus != kIOReturnSuccess {
    print("Failed to open IOHIDManager (status \(openStatus)).")
    print("Grant Input Monitoring permission in System Settings -> Privacy &")
    print("Security -> Input Monitoring for this binary/terminal, then re-run.")
}

print("Listening for raw HID reports...\n")
CFRunLoopRun()
