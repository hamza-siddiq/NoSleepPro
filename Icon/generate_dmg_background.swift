import AppKit

// Renders the DMG window background: a soft brand-tinted canvas with a title, a hint, and an
// amber arrow pointing from the app toward the Applications folder.
//
// The DMG window is 600×400 points; we render at 2× (1200×800) so it's crisp on Retina.
// Usage:  swift generate_dmg_background.swift <output.png>

let W: CGFloat = 1200, H: CGFloat = 800
let s: CGFloat = 2   // points → pixels

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

// Soft lavender gradient background.
if let g = CGGradient(colorsSpace: cs,
                      colors: [rgb(0.97, 0.96, 1.0), rgb(0.91, 0.89, 0.99)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
}

// Centered text (context is y-up / non-flipped, so text draws upright at its lower-left).
func drawCentered(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, topInset: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * s, weight: weight),
        .foregroundColor: color,
    ]
    let a = NSAttributedString(string: string, attributes: attrs)
    let sz = a.size()
    a.draw(at: CGPoint(x: (W - sz.width) / 2, y: H - topInset * s - sz.height))
}

drawCentered("NoSleep Pro", size: 30, weight: .bold,
             color: NSColor(red: 0.30, green: 0.13, blue: 0.60, alpha: 1), topInset: 34)
drawCentered("Drag the app onto the Applications folder to install", size: 14, weight: .regular,
             color: NSColor(red: 0.42, green: 0.44, blue: 0.52, alpha: 1), topInset: 74)

// Amber arrow between the two icons (icons sit at x≈150 and x≈450 points, y≈200 from top).
// In this y-up canvas that vertical center is H - 200*s = 400.
let midY: CGFloat = H - 200 * s
let x0: CGFloat = 246 * s   // just right of the app icon
let x1: CGFloat = 354 * s   // just left of the Applications folder
let shaftH: CGFloat = 10 * s
let headW: CGFloat = 26 * s
let headH: CGFloat = 30 * s
let amber = rgb(1.0, 0.62, 0.11)

ctx.setFillColor(amber)
// shaft
ctx.fill(CGRect(x: x0, y: midY - shaftH / 2, width: (x1 - headW) - x0, height: shaftH))
// head
ctx.beginPath()
ctx.move(to: CGPoint(x: x1, y: midY))
ctx.addLine(to: CGPoint(x: x1 - headW, y: midY + headH / 2))
ctx.addLine(to: CGPoint(x: x1 - headW, y: midY - headH / 2))
ctx.closePath()
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Generated DMG background at \(out)")
