import AppKit

// NoSleep Pro — app icon generator.
//
// Concept (informed by design references on Mobbin — Atoms/Peanut's bold bolt mark and
// Moonly/(Not Boring)'s premium glossy-gradient squircle): a warm amber thunderbolt with
// an electric bloom, sitting on a deep indigo→violet gradient squircle. Energy, at night.
//
// Usage:  swift generate_icon.swift [output.iconset]

// MARK: - Palette

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let bgTop    = rgb(0.13, 0.12, 0.34)   // deep indigo
let bgMid    = rgb(0.30, 0.13, 0.60)   // royal violet
let bgBottom = rgb(0.52, 0.26, 0.95)   // electric violet

let boltTop    = rgb(1.00, 0.90, 0.32)  // bright yellow
let boltMid    = rgb(1.00, 0.74, 0.16)  // amber
let boltBottom = rgb(1.00, 0.53, 0.08)  // deep amber

// MARK: - Bolt geometry (normalised 0…1, y up)

let bolt: [(CGFloat, CGFloat)] = [
    (0.615, 0.930),   // apex
    (0.300, 0.520),   // left shoulder
    (0.500, 0.520),
    (0.400, 0.070),   // bottom tip
    (0.705, 0.485),   // right shoulder
    (0.505, 0.485),
]

func boltPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    for (i, p) in bolt.enumerated() {
        let pt = CGPoint(x: rect.minX + p.0 * rect.width,
                         y: rect.minY + p.1 * rect.height)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    return path
}

// MARK: - Draw

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let cs = CGColorSpaceCreateDeviceRGB()
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded-rect "squircle" body (Apple icon grid: ~18.75% inset, ~22% radius).
    let inset = size * 0.085
    let body = full.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.235
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow beneath the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.045,
                  color: rgb(0, 0, 0, 0.40))
    ctx.setFillColor(bgMid)
    ctx.addPath(bodyPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    if let g = CGGradient(colorsSpace: cs, colors: [bgTop, bgMid, bgBottom] as CFArray,
                          locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: body.minX, y: body.maxY),
                               end: CGPoint(x: body.maxX, y: body.minY),
                               options: [])
    }

    // Soft glossy sheen across the top third.
    if let sheen = CGGradient(colorsSpace: cs,
                              colors: [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0.0)] as CFArray,
                              locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.midY + body.height * 0.05),
                               options: [])
    }

    // Electric bloom behind the bolt.
    let center = CGPoint(x: body.midX, y: body.midY + body.height * 0.02)
    if let glow = CGGradient(colorsSpace: cs,
                             colors: [rgb(1.0, 0.86, 0.35, 0.55),
                                      rgb(1.0, 0.70, 0.20, 0.20),
                                      rgb(1.0, 0.70, 0.20, 0.0)] as CFArray,
                             locations: [0.0, 0.45, 1.0]) {
        ctx.drawRadialGradient(glow,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: body.width * 0.48,
                               options: [])
    }
    ctx.restoreGState()

    // The thunderbolt itself, inside the body rect (a touch narrower for margin).
    let boltRect = body.insetBy(dx: body.width * 0.055, dy: body.height * 0.055)
    let path = boltPath(in: boltRect)

    // Bolt glow / outer stroke for that "charged" edge.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.03, color: rgb(1.0, 0.80, 0.25, 0.85))
    ctx.setFillColor(boltMid)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    // Bolt gradient fill.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let bg = CGGradient(colorsSpace: cs, colors: [boltTop, boltMid, boltBottom] as CFArray,
                           locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(bg,
                               start: CGPoint(x: boltRect.midX, y: boltRect.maxY),
                               end: CGPoint(x: boltRect.midX, y: boltRect.minY),
                               options: [])
    }
    // Bright specular highlight along the upper-left facet.
    if let hi = CGGradient(colorsSpace: cs,
                           colors: [rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0.0)] as CFArray,
                           locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hi,
                               start: CGPoint(x: boltRect.minX, y: boltRect.maxY),
                               end: CGPoint(x: boltRect.midX, y: boltRect.midY),
                               options: [])
    }
    ctx.restoreGState()

    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data {
    // Render crisply at exact pixel dimensions.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Emit .iconset

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for spec in specs {
    let pixels = spec.base * spec.scale
    let suffix = spec.scale == 2 ? "@2x" : ""
    let name = "\(outDir)/icon_\(spec.base)x\(spec.base)\(suffix).png"
    try! png(drawIcon(size: CGFloat(pixels)), pixels).write(to: URL(fileURLWithPath: name))
}

// Also emit a standalone 1024 master for stores/README.
try! png(drawIcon(size: 1024), 1024).write(to: URL(fileURLWithPath: "\(outDir)/../icon-1024.png"))

print("Generated iconset at \(outDir)")
