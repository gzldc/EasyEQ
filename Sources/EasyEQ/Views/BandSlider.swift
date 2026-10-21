import SwiftUI

/// One vertical band slider. Dragging anywhere in the column maps the pointer's y straight to gain;
/// double-click resets to 0 dB.
struct BandSlider: View {
    let value: Double
    let frequency: Double
    /// Zone name shown under the track (10-band layout); nil shows only the frequency.
    let label: String?
    /// Zone name shown as a tooltip when there is no visible label.
    var tooltip: String?
    var compact = false
    let onChange: (Double) -> Void
    let onReset: () -> Void

    private static let range = 12.0
    private static let thumbSize: CGFloat = 14

    var body: some View {
        VStack(spacing: 4) {
            Text(Self.valueText(value))
                .font(.system(size: compact ? 8 : 11, weight: .medium).monospacedDigit())
                .foregroundStyle(value == 0 ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            track
                .frame(minHeight: 200)

            if let label {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(Self.frequencyText(frequency))
                .font(.system(size: compact ? 8 : 11))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.frequencyText(frequency))
        .accessibilityValue(Self.valueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(value + 1)
            case .decrement: onChange(value - 1)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let r = Self.thumbSize / 2
            let usable = max(geo.size.height - Self.thumbSize, 1)
            let thumbY = r + usable * (1 - (value + Self.range) / (2 * Self.range))
            let midY = r + usable / 2
            ZStack(alignment: .topLeading) {
                // Track rail
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 4, height: geo.size.height - 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // 0 dB center line
                Rectangle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: min(geo.size.width, 14), height: 1)
                    .position(x: geo.size.width / 2, y: midY)
                // Filled portion between 0 dB and the thumb
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 4, height: max(abs(thumbY - midY), 0.5))
                    .position(x: geo.size.width / 2, y: (thumbY + midY) / 2)
                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .shadow(radius: 1, y: 1)
                    .position(x: geo.size.width / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = (drag.location.y - r) / usable
                        onChange(Self.range - fraction * 2 * Self.range)
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
        }
    }

    /// `+2.5`, `0`, `-6`.
    static func valueText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == 0 ? "0" : String(format: "%+g", rounded)
    }

    /// `32`, `31.5`, `1K`, `1.6K`, `16K`.
    static func frequencyText(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%gK", hz / 1000) : String(format: "%g", hz)
    }
}
