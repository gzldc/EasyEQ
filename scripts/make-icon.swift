// Renders the EasyEQ app icon (macOS squircle on a 1024x1024 canvas). Pure CoreGraphics, no external tools.
//
// Usage:
//   swift scripts/make-icon.swift <out.iconset> [--design A|B|C|D|E|F]   write an .iconset (16...1024, incl. @2x)
//   swift scripts/make-icon.swift --png <out.png> [--size 256] [--design A|B|C|D|E|F]   write one preview PNG
//
// Then build the .icns with:  iconutil -c icns <out.iconset> -o Resources/AppBundle/AppIcon.icns
// Design A (default) is the shipped icon; B-F are alternatives kept for comparison
// (see docs/images/icon-options/). Geometry matches the 1024x1024 SVG mock-ups.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colors and gradients

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: rgb,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}

func gradient(_ stops: [(CGFloat, UInt32, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: rgb, colors: stops.map { color($0.1, alpha: $0.2) } as CFArray,
        locations: stops.map { $0.0 })!
}

let gBT = gradient([(0, 0x6E7CFF, 1), (1, 0x45C9BA, 1)])
let gPink = gradient([(0, 0x7B6CFF, 1), (0.55, 0x9B7CFF, 1), (1, 0xFF8FB1, 1)])
let gNight = gradient([(0, 0x1D2140, 1), (1, 0x2A2552, 1)])
let gLight = gradient([(0, 0xFFFFFF, 1), (1, 0xEEF1FF, 1)])
let gGlow = gradient([(0, 0x8090FF, 1), (1, 0x52D6C7, 1)])
let gShine = gradient([(0, 0xFFFFFF, 0.28), (0.5, 0xFFFFFF, 0)])

/// Fills `path` with `g`, SVG objectBoundingBox style: (0,0) -> (1,1) maps to the path's bounds.
func fillGradient(
    _ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint, alpha: CGFloat = 1
) {
    let b = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(path)
    ctx.clip()
    let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    ctx.drawLinearGradient(
        g, start: CGPoint(x: b.minX + from.x * b.width, y: b.minY + from.y * b.height),
        end: CGPoint(x: b.minX + to.x * b.width, y: b.minY + to.y * b.height), options: opts)
    ctx.restoreGState()
}

/// Strokes `path` with a gradient (used for the gradient EQ curves).
func strokeGradient(
    _ ctx: CGContext, _ path: CGPath, width: CGFloat, _ g: CGGradient, from: CGPoint, to: CGPoint,
    alpha: CGFloat = 1
) {
    let b = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        g, start: CGPoint(x: b.minX + from.x * b.width, y: b.minY + from.y * b.height),
        end: CGPoint(x: b.minX + to.x * b.width, y: b.minY + to.y * b.height),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - Shapes (coordinates are SVG-style: origin top-left, y down)

/// Rounded rect with continuous (squircle) corners, as used by the macOS icon grid.
func continuousRoundedRect(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    // Top-right corner template: offsets in units of r from the corner point (dx inward, dy downward).
    let cs: [[(CGFloat, CGFloat)]] = [
        // (c1, c2, end) per cubic, starting at (1.52866483, 0)
        [(1.08849296, 0), (0.86840694, 0), (0.63149379, 0.07491461)],
        [(0.37282383, 0.16906013), (0.16906013, 0.37282383), (0.07491461, 0.63149379)],
        [(0, 0.86840694), (0, 1.08849296), (0, 1.52866483)],
    ]
    // Each other corner is the top-right template rotated 90 degrees * k about the (square) rect center.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    func rot(_ pt: CGPoint, _ k: Int) -> CGPoint {
        var x = pt.x - center.x
        var y = pt.y - center.y
        for _ in 0..<k { (x, y) = (-y, x) }  // 90 degrees clockwise on a y-down canvas
        return CGPoint(x: x + center.x, y: y + center.y)
    }
    func tr(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: rect.maxX - dx * r, y: rect.minY + dy * r)
    }
    p.move(to: rot(tr(1.52866483, 0), 0))
    for k in 0..<4 {
        if k > 0 { p.addLine(to: rot(tr(1.52866483, 0), k)) }
        for c in cs {
            p.addCurve(
                to: rot(tr(c[2].0, c[2].1), k), control1: rot(tr(c[0].0, c[0].1), k),
                control2: rot(tr(c[1].0, c[1].1), k))
        }
    }
    p.closeSubpath()
    return p
}

let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircleRadius: CGFloat = 185

func squircle() -> CGPath { continuousRoundedRect(squircleRect, radius: squircleRadius) }

func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(w, h) / 2, cornerHeight: min(w, h) / 2, transform: nil)
}

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x1, y: y1))
    p.addLine(to: CGPoint(x: x2, y: y2))
    return p
}

/// SVG path-data subset: absolute M, L, C, S, Z.
func svgPath(_ d: String) -> CGPath {
    let tokens = d.replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: "M", with: " M ").replacingOccurrences(of: "L", with: " L ")
        .replacingOccurrences(of: "C", with: " C ").replacingOccurrences(of: "S", with: " S ")
        .replacingOccurrences(of: "Z", with: " Z ").split(separator: " ").map(String.init)
    let p = CGMutablePath()
    var i = 0
    var cmd = ""
    var lastC2: CGPoint?
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    func pt() -> CGPoint { let x = num(); let y = num(); return CGPoint(x: x, y: y) }
    while i < tokens.count {
        if let t = tokens[i].first, t.isLetter { cmd = tokens[i]; i += 1 }
        switch cmd {
        case "M": p.move(to: pt()); lastC2 = nil
        case "L": p.addLine(to: pt()); lastC2 = nil
        case "C":
            let c1 = pt(), c2 = pt(), e = pt()
            p.addCurve(to: e, control1: c1, control2: c2)
            lastC2 = c2
        case "S":
            let cur = p.currentPoint
            let c1 = lastC2.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
            let c2 = pt(), e = pt()
            p.addCurve(to: e, control1: c1, control2: c2)
            lastC2 = c2
        case "Z": p.closeSubpath(); lastC2 = nil
        default: fatalError("unsupported path command \(cmd)")
        }
    }
    return p
}

/// Circular arc (SVG coordinates, angles in degrees, increasing = clockwise on screen) as cubics.
func arc(center c: CGPoint, radius r: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let segs = max(1, Int(ceil(abs(a1 - a0) / 45)))
    let step = (a1 - a0) / CGFloat(segs) * .pi / 180
    let k = 4.0 / 3.0 * tan(step / 4)
    var a = a0 * .pi / 180
    p.move(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
    for _ in 0..<segs {
        let b = a + step
        p.addCurve(
            to: CGPoint(x: c.x + r * cos(b), y: c.y + r * sin(b)),
            control1: CGPoint(x: c.x + r * (cos(a) - k * sin(a)), y: c.y + r * (sin(a) + k * cos(a))),
            control2: CGPoint(x: c.x + r * (cos(b) + k * sin(b)), y: c.y + r * (sin(b) - k * cos(b))))
        a = b
    }
    return p
}

// MARK: - Painting helpers

func fill(_ ctx: CGContext, _ path: CGPath, _ c: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(c)
    ctx.fillPath()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ c: CGColor, width: CGFloat, dash: [CGFloat]? = nil, cap: CGLineCap = .round) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(c)
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    if let dash { ctx.setLineDash(phase: 0, lengths: dash) }
    ctx.strokePath()
    ctx.restoreGState()
}

let white = color(0xFFFFFF)
func white(_ a: CGFloat) -> CGColor { color(0xFFFFFF, alpha: a) }

func shine(_ ctx: CGContext, alpha: CGFloat = 1) {
    fillGradient(ctx, squircle(), gShine, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 1), alpha: alpha)
}

func background(_ ctx: CGContext, _ g: CGGradient) {
    fillGradient(ctx, squircle(), g, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 1))
}

// MARK: - Designs

func drawA(_ ctx: CGContext) {
    background(ctx, gBT)
    shine(ctx)
    stroke(ctx, svgPath("M210 590 C300 640 360 650 430 600 S560 420 640 430 S760 520 814 470"), white, width: 44)
    for (x, y) in [(330, 622), (560, 452), (740, 488)] as [(CGFloat, CGFloat)] { fill(ctx, circle(x, y, 46), white) }
}

func drawB(_ ctx: CGContext) {
    background(ctx, gBT)
    shine(ctx)
    for x: CGFloat in [332, 512, 692] { stroke(ctx, line(x, 270, x, 754), white(0.45), width: 34) }
    fill(ctx, pill(272, 560, 120, 74), white)
    fill(ctx, pill(452, 360, 120, 74), white)
    fill(ctx, pill(632, 470, 120, 74), white)
}

func drawC(_ ctx: CGContext) {
    background(ctx, gBT)
    shine(ctx)
    let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (236, 560, 200, 0.9), (326, 500, 260, 0.9), (416, 430, 330, 0.9), (506, 340, 420, 0.9),
        (596, 400, 360, 0.9), (686, 470, 290, 0.9), (776, 520, 240, 0.75),
    ]
    for (x, y, h, a) in bars { fill(ctx, pill(x, y, 56, h), white(a)) }
    stroke(ctx, svgPath("M220 520 C330 470 420 380 534 300 S720 400 840 470"), white(0.7), width: 22)
}

func drawD(_ ctx: CGContext) {
    background(ctx, gLight)
    // Thin border (inset half a stroke so it sits inside the edge).
    stroke(
        ctx, continuousRoundedRect(CGRect(x: 100.5, y: 100.5, width: 823, height: 823), radius: squircleRadius),
        color(0x1D2340, alpha: 0.08), width: 3)
    stroke(ctx, line(220, 512, 804, 512), color(0x6B7192, alpha: 0.25), width: 10, dash: [18, 20], cap: .butt)
    let curve = "M210 610 C300 660 360 660 430 610 S560 400 640 410 S760 520 814 480"
    fillGradient(
        ctx, svgPath(curve + " L814 760 L210 760 Z"), gradient([(0, 0x6E7CFF, 1), (1, 0x45C9BA, 1)]),
        from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 1), alpha: 0.14)
    strokeGradient(
        ctx, svgPath(curve), width: 46, gradient([(0, 0x6E7CFF, 1), (1, 0x45C9BA, 1)]),
        from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 0))
    fill(ctx, circle(560, 432, 52 + 9), color(0x5A68F0))  // stroke 18 centred on r=52 -> ring 43...61
    fill(ctx, circle(560, 432, 52 - 9), white)
}

func drawE(_ ctx: CGContext) {
    background(ctx, gNight)
    shine(ctx, alpha: 0.5)
    let curve = svgPath("M210 600 C300 650 360 650 430 600 S560 410 640 420 S760 520 814 475")
    strokeGradient(ctx, curve, width: 70, gGlow, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 0), alpha: 0.28)
    strokeGradient(ctx, curve, width: 38, gGlow, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 0))
    for (x, y) in [(330, 632), (560, 442), (740, 490)] as [(CGFloat, CGFloat)] { fill(ctx, circle(x, y, 34), white) }
}

func drawF(_ ctx: CGContext) {
    background(ctx, gPink)
    shine(ctx)
    func asin2(_ half: CGFloat, _ r: CGFloat) -> CGFloat { asin(half / r) * 180 / .pi }
    // A220 220 0 0 1 : (600,340) -> (600,684); centre sits left of the chord.
    let r1: CGFloat = 220
    let c1 = CGPoint(x: 600 - sqrt(r1 * r1 - 172 * 172), y: 512)
    let t1 = asin2(172, r1)
    stroke(ctx, arc(center: c1, radius: r1, from: -t1, to: t1), white(0.55), width: 40)
    // A330 330 0 0 1 : (680,260) -> (680,764)
    let r2: CGFloat = 330
    let c2 = CGPoint(x: 680 - sqrt(r2 * r2 - 252 * 252), y: 512)
    let t2 = asin2(252, r2)
    stroke(ctx, arc(center: c2, radius: r2, from: -t2, to: t2), white(0.32), width: 40)
    stroke(ctx, line(300, 320, 300, 704), white(0.55), width: 30)
    stroke(ctx, line(450, 320, 450, 704), white(0.55), width: 30)
    fill(ctx, pill(246, 540, 108, 66), white)
    fill(ctx, pill(396, 400, 108, 66), white)
}

let designs: [String: (CGContext) -> Void] = ["A": drawA, "B": drawB, "C": drawC, "D": drawD, "E": drawE, "F": drawF]

// MARK: - Output

func render(design: String, pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // SVG-style canvas: 1024 units, origin top-left, y down.
    let s = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: s, y: -s)
    designs[design]!(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(path)") }
}

var args = Array(CommandLine.arguments.dropFirst())
var design = "A"
var pngOut: String?
var size = 256
var iconset: String?
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--design": design = (args.isEmpty ? "" : args.removeFirst()).uppercased()
    case "--png": pngOut = args.isEmpty ? nil : args.removeFirst()
    case "--size": size = Int(args.isEmpty ? "" : args.removeFirst()) ?? 256
    default: iconset = a
    }
}
guard designs[design] != nil else {
    FileHandle.standardError.write(Data("unknown design '\(design)' (use A-F)\n".utf8))
    exit(64)
}

if let pngOut {
    writePNG(render(design: design, pixels: size), to: pngOut)
} else if let iconset {
    try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    let entries: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, px) in entries { writePNG(render(design: design, pixels: px), to: "\(iconset)/\(name).png") }
} else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset> [--design A-F] | --png <out.png> [--size N] [--design A-F]\n".utf8))
    exit(64)
}
