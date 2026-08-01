import CoreGraphics
import Foundation
import ImageIO

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func decodedRGBA(at path: String) -> (width: Int, height: Int, bytes: [UInt8]) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("Could not decode preview image: \(path)")
    }
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    let drewImage = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let baseAddress = storage.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drewImage else { fail("Could not rasterize preview image: \(path)") }
    return (width, height, bytes)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: ComparePreviewPixels FIRST.png SECOND.png")
}

let first = decodedRGBA(at: CommandLine.arguments[1])
let second = decodedRGBA(at: CommandLine.arguments[2])
guard first.width == second.width, first.height == second.height else {
    fail("Preview dimensions differ")
}

var differentPixels = 0
var maximumChannelDelta = 0
for pixelOffset in stride(from: 0, to: first.bytes.count, by: 4) {
    var pixelDiffers = false
    for channel in 0..<4 {
        let delta = abs(
            Int(first.bytes[pixelOffset + channel])
                - Int(second.bytes[pixelOffset + channel])
        )
        maximumChannelDelta = max(maximumChannelDelta, delta)
        pixelDiffers = pixelDiffers || delta != 0
    }
    if pixelDiffers { differentPixels += 1 }
}

let totalPixels = first.width * first.height
let allowedDifferentPixels = max(64, totalPixels / 500)
guard maximumChannelDelta <= 8,
      differentPixels <= allowedDifferentPixels else {
    fail(
        "Preview pixels differ materially: \(differentPixels)/\(totalPixels) pixels, "
            + "maximum channel delta \(maximumChannelDelta)"
    )
}

if differentPixels > 0 {
    print(
        "Preview pixels equivalent within antialias tolerance: "
            + "\(differentPixels)/\(totalPixels), maximum delta \(maximumChannelDelta)"
    )
}
