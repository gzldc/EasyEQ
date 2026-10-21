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
    private static let railWidth: CGFloat = 6

    @Environment(\.theme) private var theme

    /// 18 pt normally; 31 bands leave only ~16 pt per column, so the thumb shrinks to avoid overlapping.
    private var thumbSize: CGFloat { compact ? 14 : 18 }

    /// Fixed row height so text scaling never changes the track geometry (all columns stay level).
    private var textRowHeight: CGFloat { compact ? 11 : 15 }

    var body: some View {
        VStack(spacing: 4) {
            textRow(Self.valueText(value),
                    font: .system(size: compact ? 8 : 11, weight: .semibold).monospacedDigit(),
                    color: theme.accentText)

            track
                .frame(minHeight: 150)

            if let label {
                textRow(label, font: .system(size: 11), color: theme.textSecondary)
            }
            textRow(Self.frequencyText(frequency),
                    font: .system(size: compact ? 8 : 11),
                    color: theme.textSecondary)
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

    /// One line of text in a fixed-height row; long text shrinks inside the row instead of resizing it.
    private func textRow(_ text: String, font: Font, color: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .frame(height: textRowHeight)
    }

    private var track: some View {
        GeometryReader { geo in
            let r = thumbSize / 2
            let usable = max(geo.size.height - thumbSize, 1)
            let thumbY = r + usable * (1 - (value + Self.range) / (2 * Self.range))
            let midY = r + usable / 2
            ZStack(alignment: .topLeading) {
                // Track rail
                Capsule()
                    .fill(theme.track)
                    .frame(width: Self.railWidth, height: geo.size.height - 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // 0 dB center line
                Rectangle()
                    .fill(theme.textSecondary.opacity(0.6))
                    .frame(width: min(geo.size.width, 14), height: 1)
                    .position(x: geo.size.width / 2, y: midY)
                // Filled portion between 0 dB and the thumb
                Capsule()
                    .fill(theme.accentGradientVertical)
                    .frame(width: Self.railWidth, height: max(abs(thumbY - midY), 0.5))
                    .position(x: geo.size.width / 2, y: (thumbY + midY) / 2)
                Circle()
                    .fill(theme.thumbFill)
                    .overlay(Circle().strokeBorder(theme.accentStart, lineWidth: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: theme.thumbShadow, radius: 2, y: 1)
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
