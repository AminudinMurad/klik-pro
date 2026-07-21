#!/usr/bin/env swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let profilesURL = root.appendingPathComponent("assets/screenshot-app-profiles.png")
let mappingsURL = root.appendingPathComponent("assets/screenshot-mappings.png")
let outputURL = root.appendingPathComponent("assets/app-profiles-icon-showcase.gif")
let frameDirectory = root.appendingPathComponent("build/app-profiles-showcase", isDirectory: true)

guard let profiles = NSImage(contentsOf: profilesURL),
      let mappings = NSImage(contentsOf: mappingsURL) else {
    fputs("Run tools/render-previews.sh before building the App Profiles showcase.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)

let canvasSize = NSSize(width: 1200, height: 1200)
let brandBlue = NSColor(calibratedRed: 0.03, green: 0.47, blue: 0.98, alpha: 1)
let primary = NSColor(calibratedWhite: 0.10, alpha: 1)
let secondary = NSColor(calibratedWhite: 0.39, alpha: 1)

struct Scene {
    let image: NSImage
    let title: String
    let subtitle: String
    /// Crop expressed in source-image pixels from the top-left.
    let crop: NSRect
}

let scenes = [
    Scene(
        image: profiles,
        title: "Make every profile unmistakable",
        subtitle: "Use a colour tint or an initial badge — without modifying the original app.",
        crop: NSRect(x: 700, y: 190, width: 1080, height: 1450)
    ),
    Scene(
        image: profiles,
        title: "Manage identity from one place",
        subtitle: "Open the gear menu to rename, change the icon, reset it, or remove the profile.",
        crop: NSRect(x: 700, y: 430, width: 1080, height: 980)
    ),
    Scene(
        image: mappings,
        title: "The same icon follows every mapping",
        subtitle: "App Profiles and Mappings refresh together, so assignments stay easy to recognise.",
        crop: NSRect(x: 900, y: 650, width: 850, height: 920)
    ),
]

func sourceRect(for scene: Scene) -> NSRect {
    NSRect(
        x: scene.crop.minX,
        y: scene.image.size.height - scene.crop.maxY,
        width: scene.crop.width,
        height: scene.crop.height
    )
}

func render(_ scene: Scene) -> CGImage {
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    NSColor.white.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    let eyebrow = "KLIK PRO 1.2.1 · APP PROFILES"
    eyebrow.draw(
        at: NSPoint(x: 72, y: 1090),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: brandBlue,
            .kern: 0.7,
        ]
    )

    scene.title.draw(
        at: NSPoint(x: 72, y: 1015),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: primary,
        ]
    )

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    (scene.subtitle as NSString).draw(
        in: NSRect(x: 72, y: 910, width: 1056, height: 74),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 25, weight: .regular),
            .foregroundColor: secondary,
            .paragraphStyle: paragraph,
        ]
    )

    let card = NSRect(x: 62, y: 72, width: 1076, height: 800)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -7)
    shadow.set()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28).fill()
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28).addClip()

    let crop = sourceRect(for: scene)
    let scale = max(card.width / crop.width, card.height / crop.height)
    let target = NSRect(
        x: card.midX - crop.width * scale / 2,
        y: card.midY - crop.height * scale / 2,
        width: crop.width * scale,
        height: crop.height * scale
    )
    scene.image.draw(in: target, from: crop, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()

    image.unlockFocus()
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Unable to render showcase frame")
    }
    return cgImage
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    scenes.count,
    nil
) else {
    fatalError("Unable to create GIF destination")
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0,
    ],
] as CFDictionary)

for (index, scene) in scenes.enumerated() {
    let frame = render(scene)
    let frameURL = frameDirectory.appendingPathComponent(String(format: "frame-%02d.png", index + 1))
    if let png = CGImageDestinationCreateWithURL(
        frameURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) {
        CGImageDestinationAddImage(png, frame, nil)
        _ = CGImageDestinationFinalize(png)
    }
    CGImageDestinationAddImage(destination, frame, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 2.2,
            kCGImagePropertyGIFUnclampedDelayTime: 2.2,
        ],
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to finalize App Profiles showcase GIF")
}

print("Rendered \(outputURL.path)")
print("Preview frames: \(frameDirectory.path)")
