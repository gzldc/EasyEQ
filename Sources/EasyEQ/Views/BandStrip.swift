import AppKit
import EasyEQCore
import SwiftUI

/// The row of band sliders with shared pointer handling: one drag gesture over the whole strip "paints" gains
/// (every band between two samples is filled in), a double-click resets the band under the pointer, hovering
/// highlights a column and shows its readout, and the scroll wheel nudges the hovered band by 0.5 dB per step.
struct BandStrip: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    static let space = "bandStrip"
    private static let scrollStepDB = 0.5

    @State private var hovered: Int?
    @State private var painting = false
    @State private var track: BandTrackMetrics?
    @State private var bubbleWidth: CGFloat = 80
    @State private var stepper = ScrollStepper(pointsPerStep: 6)

    var body: some View {
        let layout = model.session.current.layout
        // The strip's own size drives the painter and the bubble, so measure it synchronously.
        GeometryReader { geo in
            strip(size: geo.size)
        }
        .frame(minHeight: BandSlider.minHeight(compact: layout == .thirtyOne, hasZoneLabel: layout == .ten))
    }

    @ViewBuilder
    private func strip(size: CGSize) -> some View {
        let layout = model.session.current.layout
        let gains = model.session.current.gains
        let frequencies = layout.frequencies
        let compact = layout == .thirtyOne
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(frequencies.enumerated()), id: \.offset) { index, hz in
                let zone = localizer.t(BandLayout.zoneKey(forFrequency: hz))
                BandSlider(
                    value: index < gains.count ? gains[index] : 0,
                    frequency: hz,
                    label: layout == .ten ? zone : nil,
                    tooltip: layout == .ten ? nil : zone,
                    compact: compact,
                    showsFrequency: layout.showsFrequencyLabel(at: index),
                    onChange: { model.setGain($0, at: index) }
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .coordinateSpace(name: Self.space)
        .background { highlight(count: frequencies.count) }
        .onPreferenceChange(BandTrackKey.self) { track = $0 }
        .overlay { ScrollCatcher { x, dy, precise in scroll(size: size, x: x, deltaY: dy, precise: precise) } }
        .contentShape(Rectangle())
        .paintGesture(
            painter: painter(size: size, bandCount: frequencies.count, compact: compact),
            originY: trackTop(compact: compact),
            acceptsStart: { acceptsStart($0) },
            onPaint: { model.setGains($0) },
            onDoubleClick: { model.resetBand(at: $0) },
            onActive: { painting = $0 }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                setHovered(columnPainter(size: size, bandCount: frequencies.count)?.band(atX: point.x))
            case .ended:
                setHovered(nil)
            }
        }
        .overlay(alignment: .topLeading) {
            bubble(size: size, layout: layout, gains: gains)
        }
    }

    // MARK: - Geometry

    private func columnPainter(size: CGSize, bandCount: Int) -> BandPainter? {
        guard size.width > 0, bandCount > 0 else { return nil }
        return BandPainter(bandCount: bandCount, width: size.width, height: 1)
    }

    /// Top of the thumb's travel (track top plus the thumb radius), in strip coordinates.
    private func trackTop(compact: Bool) -> CGFloat {
        (track?.minY ?? 0) + BandSlider.thumbSize(compact: compact) / 2
    }

    /// Maps x to a column and y to a gain over the thumb's travel, so the thumb stays under the pointer.
    private func painter(size: CGSize, bandCount: Int, compact: Bool) -> BandPainter? {
        guard let track, size.width > 0, bandCount > 0 else { return nil }
        let usable = max(track.height - BandSlider.thumbSize(compact: compact), 1)
        return BandPainter(bandCount: bandCount, width: size.width, height: usable, range: BandSlider.range)
    }

    /// A press only starts painting on the track itself, not on the value / frequency text rows.
    private func acceptsStart(_ point: CGPoint) -> Bool {
        guard let track else { return false }
        return point.y >= track.minY && point.y <= track.minY + track.height
    }

    // MARK: - Hover and scroll

    private func setHovered(_ index: Int?) {
        guard index != hovered else { return }
        hovered = index
        stepper.reset()
    }

    private func scroll(size: CGSize, x: CGFloat, deltaY: CGFloat, precise: Bool) {
        let count = model.session.current.gains.count
        guard let index = columnPainter(size: size, bandCount: count)?.band(atX: x) else { return }
        setHovered(index)
        let steps = stepper.steps(forDelta: Double(deltaY), precise: precise)
        guard steps != 0 else { return }
        let gain = model.session.current.gains[index] + Self.scrollStepDB * Double(steps)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.setGain(gain, at: index) }
    }

    // MARK: - Decoration

    private func highlight(count: Int) -> some View {
        GeometryReader { geo in
            if let hovered, count > 0 {
                let width = geo.size.width / CGFloat(count)
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(theme.hoverRowFill)
                    .frame(width: width, height: geo.size.height)
                    .offset(x: width * CGFloat(hovered))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func bubble(size: CGSize, layout: BandLayout, gains: [Double]) -> some View {
        if let hovered, !painting, size.width > 0, hovered < gains.count,
           hovered < layout.frequencies.count {
            let text = "\(BandSlider.frequencyText(layout.frequencies[hovered])) · \(BandSlider.valueText(gains[hovered])) dB"
            let columnWidth = size.width / CGFloat(layout.bandCount)
            let half = bubbleWidth / 2
            let centre = min(max((CGFloat(hovered) + 0.5) * columnWidth, half), max(size.width - half, half))
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(theme.segmentSelectedFill)
                        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                        .shadow(color: theme.thumbShadow.opacity(0.5), radius: 3, y: 1)
                )
                .background {
                    GeometryReader { geo in Color.clear.preference(key: BubbleWidthKey.self, value: geo.size.width) }
                }
                .onPreferenceChange(BubbleWidthKey.self) { bubbleWidth = $0 }
                .position(x: centre, y: -10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct BubbleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Paint gesture

/// Press-and-drag "painting": each drag sample is turned into per-band gains by `BandPainter.stroke` between the
/// previous and the current point, so fast drags never skip bands. A drag stays locked to its starting column until
/// it has moved sideways by more than half a column. Never animates. A double-click calls
/// `onDoubleClick` with the band under the pointer.
private struct PaintGesture: ViewModifier {
    let painter: BandPainter?
    /// Subtracted from the pointer's y before it is mapped to a gain.
    let originY: CGFloat
    let acceptsStart: (CGPoint) -> Bool
    let onPaint: ([(index: Int, gain: Double)]) -> Void
    let onDoubleClick: ((Int) -> Void)?
    let onActive: (Bool) -> Void

    @State private var last: CGPoint?
    @State private var rejected = false
    /// Where the current drag began, and whether it has left its starting column (see `isHorizontalIntent`).
    @State private var start: CGPoint?
    @State private var unlocked = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !rejected, let painter else { return }
                        if last == nil {
                            guard acceptsStart(drag.startLocation) else {
                                rejected = true
                                return
                            }
                            onActive(true)
                            start = drag.startLocation
                            unlocked = false
                        }
                        let origin = start ?? drag.startLocation
                        if !unlocked, painter.isHorizontalIntent(start: (x: origin.x, y: origin.y),
                                                                 current: (x: drag.location.x, y: drag.location.y)) {
                            unlocked = true
                        }
                        let from = last ?? drag.startLocation
                        // Column lock: until the pointer has travelled sideways past half a column, only the
                        // starting column is painted (vertical strokes). Afterwards strokes run from there.
                        let target = unlocked ? drag.location : CGPoint(x: origin.x, y: drag.location.y)
                        last = target
                        let updates = painter.stroke(from: (x: from.x, y: from.y - originY),
                                                     to: (x: target.x, y: target.y - originY))
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onPaint(updates) }
                    }
                    .onEnded { _ in
                        if last != nil { onActive(false) }
                        last = nil
                        start = nil
                        unlocked = false
                        rejected = false
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    guard let painter, let onDoubleClick, acceptsStart(tap.location) else { return }
                    onDoubleClick(painter.band(atX: tap.location.x))
                }
            )
    }
}

extension View {
    fileprivate func paintGesture(painter: BandPainter?,
                                  originY: CGFloat,
                                  acceptsStart: @escaping (CGPoint) -> Bool = { _ in true },
                                  onPaint: @escaping ([(index: Int, gain: Double)]) -> Void,
                                  onDoubleClick: ((Int) -> Void)? = nil,
                                  onActive: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(PaintGesture(painter: painter, originY: originY, acceptsStart: acceptsStart,
                              onPaint: onPaint, onDoubleClick: onDoubleClick, onActive: onActive))
    }
}

// MARK: - Scroll wheel

/// Transparent overlay that receives scroll-wheel events over the strip only. It ignores hit testing for every
/// other event, so clicks, drags and hover reach the views beneath, and scrolling anywhere else is untouched.
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            // Trackpad inertia would keep nudging the gain after the fingers lift: swallow it.
            guard event.momentumPhase.isEmpty else { return }
            let point = convert(event.locationInWindow, from: nil)
            onScroll?(point.x, event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
        }
    }
}

// MARK: - Curve painting

extension View {
    /// Lets the response curve card be painted on too: x picks the band (equal columns over the width), y the gain.
    func paintOnCurve(bandCount: Int, size: CGSize, inset: CGFloat,
                      onPaint: @escaping ([(index: Int, gain: Double)]) -> Void) -> some View {
        let painter = BandPainter(bandCount: bandCount, width: size.width,
                                  height: max(size.height - 2 * inset, 1), range: BandSlider.range)
        return contentShape(Rectangle())
            .paintGesture(painter: painter, originY: inset, onPaint: onPaint)
    }
}
