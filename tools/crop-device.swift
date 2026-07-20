import AppKit
import Foundation

// Produces the fixed 1000x742 device-reference.png canvas used by the settings card.
// The mouse is cropped to its opaque bounding box, scaled into a 30px safe area, and
// centered without changing its aspect ratio. The source render is a single clean
// mouse (one connected alpha component), so no speckle cleanup is applied — an earlier
// connected-component cleanup pass split the downscaled mouse on its anti-aliased necks
// and deleted part of it, which shifted the mouse into the top-left and left a large
// empty margin. Cropping+centering the whole opaque region keeps the mouse framed.

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: crop-device <source.png> <device-reference.png>\n", stderr)
    exit(64)
}

let sourcePath = CommandLine.arguments[1]
let destinationPath = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: sourcePath),
      let tiff = image.tiffRepresentation,
      let source = NSBitmapImageRep(data: tiff) else {
    fputs("Unable to load \(sourcePath)\n", stderr)
    exit(1)
}

let width = source.pixelsWide
let height = source.pixelsHigh
var minX = width
var minY = height
var maxX = -1
var maxY = -1

for y in 0..<height {
    for x in 0..<width {
        guard let color = source.colorAt(x: x, y: y), color.alphaComponent > 0.04 else {
            continue
        }
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

guard maxX >= minX, maxY >= minY else {
    fputs("Source image is fully transparent\n", stderr)
    exit(1)
}

let outputWidth = 1000
let outputHeight = 742
let outputPadding = 30
let cropWidth = maxX - minX + 1
let cropHeight = maxY - minY + 1
let scale = min(
    Double(outputWidth - outputPadding * 2) / Double(cropWidth),
    Double(outputHeight - outputPadding * 2) / Double(cropHeight)
)
let drawWidth = Double(cropWidth) * scale
let drawHeight = Double(cropHeight) * scale
let drawRect = NSRect(
    x: (Double(outputWidth) - drawWidth) / 2,
    y: (Double(outputHeight) - drawHeight) / 2,
    width: drawWidth,
    height: drawHeight
)

// Crop and scale via CGImage — reliable pixel-exact cropping. CGImage uses a
// top-left origin, matching the NSBitmapImageRep.colorAt scan above.
guard let sourceCG = source.cgImage else {
    fputs("Unable to obtain source CGImage\n", stderr)
    exit(1)
}
let cropRect = CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)
guard let croppedCG = sourceCG.cropping(to: cropRect) else {
    fputs("Unable to crop source CGImage\n", stderr)
    exit(1)
}

guard let context = CGContext(
    data: nil,
    width: outputWidth,
    height: outputHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create output graphics context\n", stderr)
    exit(1)
}
context.interpolationQuality = .high
// CGContext origin is bottom-left; drawRect is vertically symmetric so it maps
// directly. The cropped image draws right-side-up.
context.draw(croppedCG, in: drawRect)

guard let outputCG = context.makeImage() else {
    fputs("Unable to render output image\n", stderr)
    exit(1)
}
let output = NSBitmapImageRep(cgImage: outputCG)
guard let png = output.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode output PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    print("Wrote \(destinationPath) (\(outputWidth)x\(outputHeight))")
} catch {
    fputs("Unable to write \(destinationPath): \(error)\n", stderr)
    exit(1)
}
