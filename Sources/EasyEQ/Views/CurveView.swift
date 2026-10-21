import EasyEQCore
import SwiftUI

/// Overall frequency response of the current settings: log-frequency x axis (20 Hz-20 kHz), y axis +/-12 dB.
struct CurveView: View {
    let settings: EQSettings

    var body: some View {
        CurveCanvas(samples: ResponseSamples(settings: settings))
            .accessibilityHidden(true)
    }
}

/// Fixed-length dB samples of the response; interpolates component-wise so SwiftUI can animate the curve
/// between presets (and between band counts, whose curves have the same sample count).
struct ResponseSamples: VectorArithmetic {
    static let count = 120
    static let minHz = 20.0
    static let maxHz = 20_000.0

    var values: [Double]

    static var zero: ResponseSamples { ResponseSamples(values: Array(repeating: 0, count: count)) }

    init(values: [Double]) { self.values = values }

    init(settings: EQSettings) {
        let lo = log(Self.minHz), hi = log(Self.maxHz)
        values = (0..<Self.count).map { i in
            let t = Double(i) / Double(Self.count - 1)
            return settings.responseDB(at: exp(lo + (hi - lo) * t))
        }
    }

    static func + (l: Self, r: Self) -> Self { ResponseSamples(values: zip(l.values, r.values).map(+)) }
    static func - (l: Self, r: Self) -> Self { ResponseSamples(values: zip(l.values, r.values).map(-)) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// Draws the curve; being `Animatable`, it re-renders with interpolated samples inside an animation
/// transaction and renders instantly otherwise (e.g. while dragging a slider).
private struct CurveCanvas: View, Animatable {
    var samples: ResponseSamples
    @Environment(\.theme) private var theme

    var animatableData: ResponseSamples {
        get { samples }
        set { samples = newValue }
    }

    private static let rangeDB = 12.0

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // Inset so the 2.5 pt stroke at +/-12 dB (and its round caps) isn't cut off at the edges.
            let inset: CGFloat = 2
            func y(_ db: Double) -> CGFloat {
                let clamped = min(max(db, -Self.rangeDB), Self.rangeDB)
                return inset + (h - 2 * inset) * (1 - (clamped + Self.rangeDB) / (2 * Self.rangeDB))
            }

            // Grid: +/-6 dB faint, 0 dB dashed.
            for db in [-6.0, 6.0] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(db)))
                line.addLine(to: CGPoint(x: w, y: y(db)))
                context.stroke(line, with: .color(theme.textSecondary.opacity(0.15)), lineWidth: 1)
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: w, y: y(0)))
            context.stroke(zero, with: .color(theme.textSecondary.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Response curve.
            let values = samples.values
            guard values.count > 1 else { return }
            var curve = Path()
            var minY = y(0), maxY = y(0)
            for (i, db) in values.enumerated() {
                let point = CGPoint(x: inset + (w - 2 * inset) * Double(i) / Double(values.count - 1), y: y(db))
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            var fill = curve
            fill.addLine(to: CGPoint(x: w - inset, y: y(0)))
            fill.addLine(to: CGPoint(x: inset, y: y(0)))
            fill.closeSubpath()
            // Start color 18% -> 0%, top to bottom of the filled area.
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [theme.accentStart.opacity(0.18), theme.accentStart.opacity(0)]),
                startPoint: CGPoint(x: 0, y: minY),
                endPoint: CGPoint(x: 0, y: max(maxY, minY + 1))))
            context.stroke(curve, with: .linearGradient(
                Gradient(colors: [theme.accentStart, theme.accentEnd]),
                startPoint: CGPoint(x: inset, y: 0), endPoint: CGPoint(x: w - inset, y: 0)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}
