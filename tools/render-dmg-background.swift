import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-dmg-background.swift /path/to/background.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 760, height: 420)
let image = NSImage(size: size)

image.lockFocus()
NSColor(calibratedRed: 0.985, green: 0.988, blue: 0.992, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

// A quiet angled footer echoes Klik PRO's card language without competing with
// Finder's app and Applications icons.
let footer = NSBezierPath()
footer.move(to: NSPoint(x: 0, y: 0))
footer.line(to: NSPoint(x: size.width, y: 0))
footer.line(to: NSPoint(x: size.width, y: 58))
footer.line(to: NSPoint(x: 0, y: 44))
footer.close()
NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
footer.fill()

NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size.width, height: 8)).fill()

let title = "Drag Klik PRO to Applications"
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.14, alpha: 1),
]
let titleSize = (title as NSString).size(withAttributes: titleAttributes)
(title as NSString).draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 348),
    withAttributes: titleAttributes
)

let subtitle = "Install in one step"
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.44, alpha: 1),
]
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
(subtitle as NSString).draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 320),
    withAttributes: subtitleAttributes
)

// Finder positions Applications on the left and Klik PRO.app on the right.
// The arrow therefore points left, matching the drag direction.
let arrow = NSBezierPath()
arrow.lineWidth = 9
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 505, y: 210))
arrow.line(to: NSPoint(x: 255, y: 210))
arrow.move(to: NSPoint(x: 255, y: 210))
arrow.line(to: NSPoint(x: 290, y: 181))
arrow.move(to: NSPoint(x: 255, y: 210))
arrow.line(to: NSPoint(x: 290, y: 239))
NSColor(calibratedRed: 0.04, green: 0.48, blue: 0.95, alpha: 1).setStroke()
arrow.stroke()

let note = "Manual installation tools are available in Extras"
let noteAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.47, alpha: 1),
]
let noteSize = (note as NSString).size(withAttributes: noteAttributes)
(note as NSString).draw(
    at: NSPoint(x: (size.width - noteSize.width) / 2, y: 20),
    withAttributes: noteAttributes
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render DMG background\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
