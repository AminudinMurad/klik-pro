#!/usr/bin/env swift

// Builds assets/onboarding-flow.gif from the rendered onboarding fixtures — one
// frame per first-run page, in flow order. The GIF used to be a hand-made screen
// recording, so it went stale the moment a step was added; building it from the
// same fixtures `tools/render-previews.sh` already renders keeps it honest.
//
// Usage: xcrun swift tools/render-onboarding-flow.swift <fixtures-directory>

import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputURL = root.appendingPathComponent("assets/onboarding-flow.gif")

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-onboarding-flow.swift <fixtures-directory>\n", stderr)
    exit(64)
}
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

// The four first-run pages, in the order the sheet presents them. Each page has
// its own height, so the canvas below is sized to the tallest one.
let frameNames = [
    "onboarding.png",           // Step 1 — Welcome
    "onboarding-data-folder.png", // Step 2 — Where your profile logins live
    "onboarding-toggles.png",   // Step 3 — Preferences
    "onboarding-access.png",    // Step 4 — Accessibility
]

let frames: [CGImage] = frameNames.map { name in
    let url = fixtures.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs(
            "Missing onboarding fixture \(name). Run tools/render-previews.sh first.\n",
            stderr
        )
        exit(1)
    }
    return image
}

// Each fixture is the sheet itself, hairline border included, so the pages are
// centred on a light backdrop rather than stretched — they read as one dialog
// changing pages instead of four differently-cropped screenshots. The margin keeps
// the widest page's own border clear of the canvas edge, so no page looks cropped.
let margin = 24
let canvasWidth = frames.map(\.width).max()! + margin * 2
let canvasHeight = frames.map(\.height).max()! + margin * 2
let backdrop = CGColor(srgbRed: 0.941, green: 0.941, blue: 0.949, alpha: 1)

func composite(_ image: CGImage) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fputs("Unable to create onboarding flow frame context\n", stderr)
        exit(1)
    }
    context.setFillColor(backdrop)
    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    context.draw(image, in: CGRect(
        x: (canvasWidth - image.width) / 2,
        y: (canvasHeight - image.height) / 2,
        width: image.width,
        height: image.height
    ))
    guard let composited = context.makeImage() else {
        fputs("Unable to composite onboarding flow frame\n", stderr)
        exit(1)
    }
    return composited
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    frames.count,
    nil
) else {
    fputs("Unable to create onboarding flow GIF destination\n", stderr)
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0,
    ],
] as CFDictionary)

// A step needs long enough to read before the next one replaces it; 2.2s matches
// the cadence the App Profiles showcase GIF already uses.
let frameDelay = 2.2
for frame in frames {
    CGImageDestinationAddImage(destination, composite(frame), [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
        ],
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to finalize onboarding flow GIF\n", stderr)
    exit(1)
}

print("Wrote \(outputURL.path) (\(frames.count) frames, \(canvasWidth)x\(canvasHeight))")
