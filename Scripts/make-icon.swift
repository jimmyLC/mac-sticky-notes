// Turns a rounded-square icon picture on a white background into a macOS app icon:
// the white surround becomes transparent, the tile is centred in a 1024px canvas with the
// usual margin, and a soft shadow is added.
// Usage: swift Scripts/make-icon.swift <source image> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3,
      let source = NSImage(contentsOf: URL(fileURLWithPath: args[1])),
      let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source> <output.png>\n".utf8))
    exit(1)
}

let width = cgSource.width
let height = cgSource.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue

pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space, bitmapInfo: info
    )!
    context.draw(cgSource, in: CGRect(x: 0, y: 0, width: width, height: height))
}

func isWhite(_ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    return pixels[i] > 232 && pixels[i + 1] > 232 && pixels[i + 2] > 232
}

// Flood fill the white surround from every border pixel.
var outside = [Bool](repeating: false, count: width * height)
var stack: [(Int, Int)] = []
func seed(_ x: Int, _ y: Int) {
    if isWhite(x, y), !outside[y * width + x] { outside[y * width + x] = true; stack.append((x, y)) }
}
for x in 0..<width { seed(x, 0); seed(x, height - 1) }
for y in 0..<height { seed(0, y); seed(width - 1, y) }
while let (x, y) = stack.popLast() {
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        if nx >= 0, ny >= 0, nx < width, ny < height { seed(nx, ny) }
    }
}

// Transparent outside; a soft edge on pixels touching the outside.
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        if outside[y * width + x] {
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            continue
        }
        var touches = false
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < width, ny < height, outside[ny * width + nx] { touches = true }
        }
        if touches {
            let lowest = Double(min(pixels[i], pixels[i + 1], pixels[i + 2]))
            let whiteness = min(max((lowest - 120) / 120, 0), 1)
            let alpha = 1 - whiteness
            pixels[i] = UInt8(Double(pixels[i]) * alpha)
            pixels[i + 1] = UInt8(Double(pixels[i + 1]) * alpha)
            pixels[i + 2] = UInt8(Double(pixels[i + 2]) * alpha)
            pixels[i + 3] = UInt8(alpha * 255)
        }
        if pixels[i + 3] > 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}

let cutout: CGImage = pixels.withUnsafeMutableBytes { buffer in
    CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space, bitmapInfo: info
    )!.makeImage()!
}
let tile = cutout.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

// Compose onto the 1024 canvas: 824px tile, soft shadow.
let canvas = 1024
let out = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: info
)!
out.interpolationQuality = .high
out.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
// Keep the picture's proportions: fit it inside the 824px box.
let fit = 824.0 / Double(max(tile.width, tile.height))
let drawWidth = Double(tile.width) * fit
let drawHeight = Double(tile.height) * fit
out.draw(tile, in: CGRect(
    x: (Double(canvas) - drawWidth) / 2, y: (Double(canvas) - drawHeight) / 2,
    width: drawWidth, height: drawHeight
))

let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]): picture \(maxX - minX + 1)x\(maxY - minY + 1) fitted into 824px")
