import Foundation

/// Turns scroll-wheel deltas into discrete ±1 steps. Mouse wheels send whole "lines" (one notch = one step);
/// trackpads send many small point deltas, which are accumulated so that every `pointsPerStep` points is one step.
public struct ScrollStepper: Sendable {
    public var pointsPerStep: Double
    private var remainder = 0.0

    public init(pointsPerStep: Double = 6) {
        self.pointsPerStep = pointsPerStep
    }

    /// Steps (positive = up) produced by this event; leftover delta carries into the next call.
    public mutating func steps(forDelta delta: Double, precise: Bool) -> Int {
        guard delta.isFinite, delta != 0 else { return 0 }
        if !precise {
            remainder = 0
            let whole = Int(delta.rounded(.towardZero))
            return whole != 0 ? whole : (delta > 0 ? 1 : -1)
        }
        remainder += delta
        let whole = Int((remainder / pointsPerStep).rounded(.towardZero))
        remainder -= Double(whole) * pointsPerStep
        return whole
    }

    /// Drops any partial accumulation (pointer moved to another column, gesture ended).
    public mutating func reset() { remainder = 0 }
}
