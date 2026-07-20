import AppKit
import Foundation

// Renders the Klik PRO app icon: two overlapping App Profile tiles (dark + brand
// green) joined by a toggle, on a light squircle tile, with the PRO badge. The icon
// is deliberately DECOUPLED from the device artwork — it expresses the app's job
// (map a button to switch between app profiles), not the mouse hardware.

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-app-icon <icon-master.png>\n", stderr)
    exit(64)
}
let destinationPath = CommandLine.arguments[1]

let S = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let ns = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Unable to allocate bitmap\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns
let cg = ns.cgContext   // bottom-left origin

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}
// top-left rect helper (y measured from the top)
func TL(_ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(S) - yTop - h, width: w, height: h)
}
let green = NSColor(srgbRed: 25 / 255, green: 187 / 255, blue: 19 / 255, alpha: 1).cgColor
let dark = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1).cgColor

// Squircle tile with a subtle vertical shade.
cg.saveGState()
cg.addPath(rr(CGRect(x: 100, y: 100, width: 824, height: 824), 188))
cg.clip()
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [NSColor(white: 0.985, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
cg.restoreGState()

// Two overlapping App Profile tiles (dark left, green right), centered seam.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(white: 0, alpha: 0.20).cgColor)
cg.addPath(rr(TL(178, 320, 384, 384), 92)); cg.setFillColor(dark); cg.fillPath()
cg.addPath(rr(TL(462, 320, 384, 384), 92)); cg.setFillColor(green); cg.fillPath()
cg.restoreGState()

// Toggle pill on the seam.
let pill = TL(410, 463, 204, 99)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor(white: 0, alpha: 0.30).cgColor)
cg.addPath(rr(pill, 49)); cg.setFillColor(NSColor(srgbRed: 0.58, green: 0.60, blue: 0.63, alpha: 1).cgColor); cg.fillPath()
cg.restoreGState()
cg.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
cg.fillEllipse(in: CGRect(x: pill.minX + 14, y: pill.minY + 14, width: pill.height - 28, height: pill.height - 28))

// PRO badge (top-left).
let badge = TL(245, 286, 162, 68)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 9, color: NSColor(white: 0, alpha: 0.18).cgColor)
cg.addPath(rr(badge, 20)); cg.setFillColor(green); cg.fillPath()
cg.restoreGState()
let pro = "PRO" as NSString
let attr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 42, weight: .heavy),
    .foregroundColor: NSColor.white,
]
let ts = pro.size(withAttributes: attr)
pro.draw(at: CGPoint(x: badge.midX - ts.width / 2, y: badge.midY - ts.height / 2), withAttributes: attr)

NSGraphicsContext.restoreGraphicsState()
guard let out = rep.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode PNG\n", stderr)
    exit(1)
}
try! out.write(to: URL(fileURLWithPath: destinationPath))
