// Renders the drag-to-install DMG window background (640x420 pt) at 1x and 2x.
//
// Usage:
//   swift scripts/make-dmg-background.swift <out-dir>
//   tiffutil -cathidpicheck <out-dir>/background.png <out-dir>/background@2x.png -out Resources/DMG/background.tiff
//
// The PNGs are tagged 72 dpi / 144 dpi so tiffutil accepts them as a 1x/2x pair; Finder picks the right one.
// Layout (window points): EasyEQ.app icon centre (160, 200), Applications (480, 200), icon size 128 --
// keep in sync with scripts/dmg-settings.py.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 640
let height: CGFloat = 420
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: rgb,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}

func render(scale: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(width) * scale, height: Int(height) * scale, bitsPerComponent: 8, bytesPerRow: 0,
        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Top-left origin, y down, in window points.
    ctx.translateBy(x: 0, y: height * CGFloat(scale))
    ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

    // Background: diagonal #F6F8FF -> #F9F6FF -> #F4FBF9.
    let bg = CGGradient(
        colorsSpace: rgb, colors: [color(0xF6F8FF), color(0xF9F6FF), color(0xF4FBF9)] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: width, y: height), options: [])

    // Soft arrow between the two icons (icon centres at y = 200).
    let arrowColor = color(0x6E7CFF, alpha: 0.55)
    ctx.setStrokeColor(arrowColor)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 258, y: 200))
    ctx.addLine(to: CGPoint(x: 382, y: 200))
    // Same path as the shaft, so the translucent stroke doesn't double up where they meet.
    ctx.move(to: CGPoint(x: 362, y: 180))
    ctx.addLine(to: CGPoint(x: 384, y: 200))
    ctx.addLine(to: CGPoint(x: 362, y: 220))
    ctx.strokePath()

    // Two-line caption, centred, #6B7192. AppKit text drawing wants a flipped=false context, so
    // draw through a flipped NSGraphicsContext that matches our y-down space.
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    func caption(_ text: String, font: NSFont, centerY: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(cgColor: color(0x6B7192))!,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: (width - size.width) / 2, y: centerY - size.height / 2))
    }
    caption(
        "把 EasyEQ 拖到“应用程序”即可安装", font: NSFont(name: "PingFangSC-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium),
        centerY: 348)
    caption(
        "Drag EasyEQ to Applications to install", font: .systemFont(ofSize: 13, weight: .regular), centerY: 374)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, dpi: Double, to path: String) {
    guard
        let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot create \(path)") }
    let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <out-dir>\n".utf8))
    exit(64)
}
let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
writePNG(render(scale: 1), dpi: 72, to: "\(out)/background.png")
writePNG(render(scale: 2), dpi: 144, to: "\(out)/background@2x.png")
