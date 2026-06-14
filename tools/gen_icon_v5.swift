// Icon v5 (SHIPPING) = v4 composition (purple squircle + window/arrow + colorful
// panels behind the window) but the dock holds GENERIC colorful tiles instead of
// real Apple app icons — same "window minimizing into a dock" story, zero trademark
// risk. Pure Core Graphics. Renders an .iconset directory.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [r, g, b, a])!
}

// Colorful panels fanned behind the window (color, angleDegrees).
let panels: [([CGFloat], CGFloat)] = [
    ([0.28, 0.82, 0.48], -34), ([0.18, 0.78, 0.78], -20), ([0.30, 0.62, 1.00], -7),
    ([0.98, 0.45, 0.80],   7), ([1.00, 0.62, 0.30],  20), ([1.00, 0.85, 0.36], 34),
]

// Generic dock tiles (distinct vibrant hues — reads as a dock of apps).
let tiles: [[CGFloat]] = [
    [1.00, 0.38, 0.38], // red
    [1.00, 0.64, 0.26], // orange
    [0.32, 0.80, 0.46], // green
    [0.26, 0.56, 1.00], // blue
    [0.64, 0.42, 0.96], // purple
]

func drawIcon(_ ctx: CGContext, _ size: CGFloat) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let inset = size * 0.09
    let sq = size - inset * 2
    let frame = CGRect(x: inset, y: inset, width: sq, height: sq)
    let radius = sq * 0.2237
    let squircle = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: col(0, 0, 0, 0.28))
    ctx.addPath(squircle); ctx.setFillColor(col(0, 0, 0, 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: rgb, colors: [col(0.31, 0.56, 1.00), col(0.49, 0.23, 0.93)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: frame.minX, y: frame.maxY), end: CGPoint(x: frame.maxX, y: frame.minY), options: [])
    let gloss = CGGradient(colorsSpace: rgb, colors: [col(1, 1, 1, 0.22), col(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: frame.midX, y: frame.maxY), startRadius: 0,
                           endCenter: CGPoint(x: frame.midX, y: frame.maxY), endRadius: sq * 0.72, options: [])

    // Window geometry.
    let cx = frame.midX
    let wW = sq * 0.42, wH = sq * 0.285
    let wTop = frame.maxY - sq * 0.15
    let windowRect = CGRect(x: cx - wW / 2, y: wTop - wH, width: wW, height: wH)
    let windowCorner = sq * 0.05

    // Colorful panels behind the window.
    let pivot = CGPoint(x: cx, y: windowRect.minY - sq * 0.015)
    for (base, deg) in panels {
        let angle = deg * .pi / 180
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y); ctx.rotate(by: angle); ctx.translateBy(x: -pivot.x, y: -pivot.y)
        let panel = CGPath(roundedRect: windowRect, cornerWidth: windowCorner, cornerHeight: windowCorner, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.004), blur: size * 0.015, color: col(0, 0, 0, 0.18))
        ctx.addPath(panel); ctx.clip()
        let g = CGGradient(colorsSpace: rgb,
                           colors: [col(base[0] + (1 - base[0]) * 0.35, base[1] + (1 - base[1]) * 0.35, base[2] + (1 - base[2]) * 0.35, 0.95),
                                    col(base[0], base[1], base[2], 0.92)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: windowRect.minX, y: windowRect.maxY), end: CGPoint(x: windowRect.minX, y: windowRect.minY), options: [])
        ctx.restoreGState()
    }

    // White window in front.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.018, color: col(0, 0, 0, 0.22))
    ctx.addPath(CGPath(roundedRect: windowRect, cornerWidth: windowCorner, cornerHeight: windowCorner, transform: nil))
    ctx.setFillColor(col(1, 1, 1, 1)); ctx.fillPath()
    ctx.restoreGState()
    let barH = wH * 0.16
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: windowRect, cornerWidth: windowCorner, cornerHeight: windowCorner, transform: nil)); ctx.clip()
    ctx.setFillColor(col(0.31, 0.50, 0.98, 0.28))
    ctx.fill(CGRect(x: windowRect.minX, y: windowRect.maxY - barH, width: wW, height: barH))
    ctx.restoreGState()

    let white = col(1, 1, 1, 1)
    // Down arrow.
    let shaftW = sq * 0.072
    let shaftTopY = windowRect.minY - sq * 0.04
    let shaftBotY = shaftTopY - sq * 0.12
    ctx.setFillColor(white)
    ctx.addPath(CGPath(roundedRect: CGRect(x: cx - shaftW / 2, y: shaftBotY, width: shaftW, height: shaftTopY - shaftBotY),
                       cornerWidth: shaftW * 0.4, cornerHeight: shaftW * 0.4, transform: nil)); ctx.fillPath()
    let headW = sq * 0.185
    let headTopY = shaftBotY + sq * 0.018
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx - headW / 2, y: headTopY)); ctx.addLine(to: CGPoint(x: cx + headW / 2, y: headTopY))
    ctx.addLine(to: CGPoint(x: cx, y: headTopY - sq * 0.115)); ctx.closePath()
    ctx.setFillColor(white); ctx.fillPath()

    // --- Frosted macOS-style dock with GENERIC colorful tiles ---
    let dockW = sq * 0.66, dockH = sq * 0.135
    let dockRect = CGRect(x: cx - dockW / 2, y: frame.minY + sq * 0.07, width: dockW, height: dockH)
    let dockCorner = dockH * 0.30
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: dockRect, cornerWidth: dockCorner, cornerHeight: dockCorner, transform: nil))
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.004), blur: size * 0.01, color: col(0, 0, 0, 0.20))
    ctx.setFillColor(col(1, 1, 1, 0.24)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: dockRect.insetBy(dx: max(0.5, sq * 0.003), dy: max(0.5, sq * 0.003)), cornerWidth: dockCorner, cornerHeight: dockCorner, transform: nil))
    ctx.setStrokeColor(col(1, 1, 1, 0.30)); ctx.setLineWidth(max(1, sq * 0.004)); ctx.strokePath()
    ctx.restoreGState()

    let n = tiles.count
    let pad = dockH * 0.16
    let tileSize = dockH - 2 * pad
    let totalW = CGFloat(n) * tileSize
    let gap = (dockW - 2 * pad - totalW) / CGFloat(max(1, n - 1))
    let startX = dockRect.minX + pad
    let tileY = dockRect.midY - tileSize / 2
    let tileCorner = tileSize * 0.28

    for (i, base) in tiles.enumerated() {
        let x = startX + CGFloat(i) * (tileSize + gap)
        let rect = CGRect(x: x, y: tileY, width: tileSize, height: tileSize)
        let path = CGPath(roundedRect: rect, cornerWidth: tileCorner, cornerHeight: tileCorner, transform: nil)

        // Soft shadow + base fill.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.002), blur: size * 0.006, color: col(0, 0, 0, 0.3))
        ctx.addPath(path); ctx.setFillColor(col(base[0], base[1], base[2], 1)); ctx.fillPath()
        ctx.restoreGState()

        // Gradient body + top gloss.
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: rgb,
                           colors: [col(base[0] + (1 - base[0]) * 0.35, base[1] + (1 - base[1]) * 0.35, base[2] + (1 - base[2]) * 0.35, 1),
                                    col(base[0] * 0.88, base[1] * 0.88, base[2] * 0.88, 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.minY), options: [])
        let tg = CGGradient(colorsSpace: rgb, colors: [col(1, 1, 1, 0.38), col(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(tg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.midY), options: [])
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(ctx, CGFloat(px)); return ctx.makeImage()!
}
func write(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Minimizer.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var cache: [Int: CGImage] = [:]
for (name, px) in entries {
    let img = cache[px] ?? render(px); cache[px] = img
    write(img, to: "\(outDir)/\(name).png")
}
print("Wrote \(entries.count) images (v5: generic dock tiles) to \(outDir)")
