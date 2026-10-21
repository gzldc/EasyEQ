import EasyEQCore
import SwiftUI

/// Overall frequency response of the current settings: log-frequency x axis (20 Hz-20 kHz), y axis +/-12 dB.
struct CurveView: View {
    let settings: EQSettings

    private static let sampleCount = 120
    private static let minHz = 20.0
    private static let maxHz = 20_000.0
    private static let rangeDB = 12.0

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func y(_ db: Double) -> CGFloat {
                let clamped = min(max(db, -Self.rangeDB), Self.rangeDB)
                return h * (1 - (clamped + Self.rangeDB) / (2 * Self.rangeDB))
            }

            // Grid: +/-6 dB faint, 0 dB stronger.
            for db in [-6.0, 6.0] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(db)))
                line.addLine(to: CGPoint(x: w, y: y(db)))
                context.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: w, y: y(0)))
            context.stroke(zero, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

            // Response curve.
            let lo = log(Self.minHz), hi = log(Self.maxHz)
            var curve = Path()
            for i in 0..<Self.sampleCount {
                let t = Double(i) / Double(Self.sampleCount - 1)
                let hz = exp(lo + (hi - lo) * t)
                let point = CGPoint(x: w * t, y: y(settings.responseDB(at: hz)))
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            var fill = curve
            fill.addLine(to: CGPoint(x: w, y: y(0)))
            fill.addLine(to: CGPoint(x: 0, y: y(0)))
            fill.closeSubpath()
            context.fill(fill, with: .color(.accentColor.opacity(0.15)))
            context.stroke(curve, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
