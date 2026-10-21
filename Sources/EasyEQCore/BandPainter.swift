import Foundation

/// Maps pointer positions on a band-editor canvas to band indices and gains, so a drag can "paint" gains.
/// Columns are equal-width over `width`; y = 0 is +range, y = height is −range.
public struct BandPainter: Sendable {
    public let bandCount: Int
    public let width: Double
    public let height: Double
    public let range: Double

    public init(bandCount: Int, width: Double, height: Double, range: Double = 12) {
        self.bandCount = bandCount
        self.width = width
        self.height = height
        self.range = range
    }

    /// Column under `x`, clamped to `0..<bandCount`.
    public func band(atX x: Double) -> Int {
        guard bandCount > 0, width > 0, !x.isNaN else { return 0 }
        let raw = (x / width * Double(bandCount)).rounded(.down)
        return min(max(Int(max(min(raw, Double(bandCount)), -1)), 0), bandCount - 1)
    }

    /// Gain at `y`, rounded to 0.1 dB and clamped to ±range.
    public func gain(atY y: Double) -> Double {
        guard height > 0, !y.isNaN else { return 0 }
        let raw = (1 - 2 * y / height) * range
        let value = min(max((raw * 10).rounded() / 10, -range), range)
        return value == 0 ? 0 : value   // normalise -0.0
    }

    /// Whether a drag that began at `start` has travelled sideways far enough (more than half a column) to mean
    /// "move on to the neighbouring bands". Until then a drag is a vertical stroke in its starting column, so a
    /// slight sideways drift while dragging up or down never repaints the neighbour.
    public func isHorizontalIntent(start: (x: Double, y: Double), current: (x: Double, y: Double)) -> Bool {
        guard bandCount > 0, width > 0, !start.x.isNaN, !current.x.isNaN else { return false }
        return abs(current.x - start.x) > width / Double(bandCount) / 2
    }

    /// Every band whose column lies between the two points (inclusive, in travel order), so a fast drag
    /// never skips bands. Gains are interpolated along the segment at each column's centre; the end band
    /// uses `to`'s y. A move that stays in one column returns just that band at `to`'s y.
    public func stroke(from: (x: Double, y: Double), to: (x: Double, y: Double)) -> [(index: Int, gain: Double)] {
        guard bandCount > 0 else { return [] }
        let start = band(atX: from.x)
        let end = band(atX: to.x)
        if start == end { return [(end, gain(atY: to.y))] }
        let step = end > start ? 1 : -1
        let columnWidth = width / Double(bandCount)
        var result: [(index: Int, gain: Double)] = []
        for index in stride(from: start, through: end, by: step) {
            if index == end {
                result.append((index, gain(atY: to.y)))
                continue
            }
            let centre = (Double(index) + 0.5) * columnWidth
            let t = min(max((centre - from.x) / (to.x - from.x), 0), 1)
            result.append((index, gain(atY: from.y + t * (to.y - from.y))))
        }
        return result
    }
}
