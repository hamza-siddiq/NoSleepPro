import AppKit

// NoSleep Pro — app icon generator.
//
// A smooth, rounded electric-blue thunderbolt with a cyan bloom, on a deep indigo-navy
// glossy squircle. Energy, at night.
//
// Usage:  swift generate_icon.swift [output.iconset]

// MARK: - Palette

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let bgTop    = rgb(0.055, 0.086, 0.200)   // deep indigo-navy
let bgMid    = rgb(0.090, 0.140, 0.290)   // navy blue
let bgBottom = rgb(0.150, 0.230, 0.470)   // brighter blue

let boltTop    = rgb(0.72, 0.94, 1.00)    // pale cyan
let boltMid    = rgb(0.24, 0.72, 0.98)    // sky blue
let boltBottom = rgb(0.15, 0.45, 0.96)    // electric blue
let glowColor  = rgb(0.30, 0.76, 1.00, 1) // cyan bloom

// MARK: - Bolt geometry (normalised 0…1, y up)

let bolt: [(CGFloat, CGFloat)] = [
    (0.615, 0.930),   // apex
    (0.315, 0.520),   // left shoulder
    (0.495, 0.520),
    (0.405, 0.075),   // bottom tip
    (0.690, 0.485),   // right shoulder
    (0.505, 0.485),
]

/// A rounded polygon: each vertex is filleted with `radius` using tangent arcs, giving the
/// bolt smooth corners instead of hard points. CoreGraphics clamps the radius on short edges.
func boltPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    let pts = bolt.map { CGPoint(x: rect.minX + $0.0 * rect.width,
                                 y: rect.minY + $0.1 * rect.height) }
    let n = pts.count
    let path = CGMutablePath()
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(pts[0], pts[1]))
    for i in 1...n {
        path.addArc(tangent1End: pts[i % n], tangent2End: pts[(i + 1) % n], radius: radius)
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

    // Rounded-rect "squircle" body (Apple icon grid).
    let inset = size * 0.085
    let body = full.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.235
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow beneath the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.045, color: rgb(0, 0, 0, 0.40))
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
    // Soft glossy sheen across the top.
    if let sheen = CGGradient(colorsSpace: cs,
                              colors: [rgb(1, 1, 1, 0.14), rgb(1, 1, 1, 0.0)] as CFArray,
                              locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.midY + body.height * 0.05),
                               options: [])
    }
    // Electric cyan bloom behind the bolt.
    let center = CGPoint(x: body.midX, y: body.midY + body.height * 0.02)
    if let glow = CGGradient(colorsSpace: cs,
                             colors: [rgb(0.30, 0.76, 1.0, 0.55),
                                      rgb(0.20, 0.55, 1.0, 0.18),
                                      rgb(0.20, 0.55, 1.0, 0.0)] as CFArray,
                             locations: [0.0, 0.45, 1.0]) {
        ctx.drawRadialGradient(glow,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: body.width * 0.46,
                               options: [])
    }
    ctx.restoreGState()

    // The thunderbolt — smaller (more breathing room) and with rounded corners.
    let boltRect = body.insetBy(dx: body.width * 0.135, dy: body.height * 0.135)
    let path = boltPath(in: boltRect, radius: boltRect.width * 0.022)

    // Bolt glow / soft charged edge.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.028, color: rgb(0.30, 0.78, 1.0, 0.85))
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
    // Specular highlight along the upper-left facet.
    if let hi = CGGradient(colorsSpace: cs,
                           colors: [rgb(1, 1, 1, 0.50), rgb(1, 1, 1, 0.0)] as CFArray,
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
try! png(drawIcon(size: 1024), 1024).write(to: URL(fileURLWithPath: "\(outDir)/../icon-1024.png"))

print("Generated iconset at \(outDir)")
