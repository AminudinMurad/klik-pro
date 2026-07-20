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
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let title = "Drag Klik PRO.app to Applications"
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor.systemRed,
]
let titleSize = (title as NSString).size(withAttributes: titleAttributes)
(title as NSString).draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 42),
    withAttributes: titleAttributes
)

let subtitle = "Then open Klik PRO from Applications"
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor.secondaryLabelColor,
]
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
(subtitle as NSString).draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 80),
    withAttributes: subtitleAttributes
)

let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 565, y: 175))
arrow.line(to: NSPoint(x: 215, y: 175))
arrow.move(to: NSPoint(x: 215, y: 175))
arrow.line(to: NSPoint(x: 242, y: 153))
arrow.move(to: NSPoint(x: 215, y: 175))
arrow.line(to: NSPoint(x: 242, y: 197))
NSColor.systemRed.setStroke()
arrow.stroke()

let note = "Need manual repair files? Open Extras."
let noteAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor.tertiaryLabelColor,
]
let noteSize = (note as NSString).size(withAttributes: noteAttributes)
(note as NSString).draw(
    at: NSPoint(x: (size.width - noteSize.width) / 2, y: 350),
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
