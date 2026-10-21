import Foundation

public struct EQSettings: Codable, Equatable, Sendable {
    public var layout: BandLayout
    public var gains: [Double]

    public init(layout: BandLayout, gains: [Double]) {
        self.layout = layout
        self.gains = gains
    }

    public static func flat(_ layout: BandLayout) -> EQSettings {
        EQSettings(layout: layout, gains: Array(repeating: 0, count: layout.bandCount))
    }

    /// Combined magnitude response (dB) of all bands at `hz`.
    public func responseDB(at hz: Double, sampleRate: Double = 48_000) -> Double {
        var total = 0.0
        for (freq, gain) in zip(layout.frequencies, gains) where gain != 0 {
            let c = BiquadCoefficients.peaking(frequency: freq, gainDB: gain, q: layout.q, sampleRate: sampleRate)
            total += c.magnitudeDB(at: hz, sampleRate: sampleRate)
        }
        return total
    }

    /// Re-samples the curve onto another layout, interpolating linearly over log2(frequency).
    public func converted(to target: BandLayout) -> EQSettings {
        let srcLog = layout.frequencies.map { log2($0) }
        let newGains = target.frequencies.map { freq -> Double in
            let x = log2(freq)
            var value: Double
            if x <= srcLog[0] {
                value = gains[0]
            } else if x >= srcLog[srcLog.count - 1] {
                value = gains[gains.count - 1]
            } else {
                let upper = srcLog.firstIndex { $0 >= x }!
                let lower = upper - 1
                let t = (x - srcLog[lower]) / (srcLog[upper] - srcLog[lower])
                value = gains[lower] + t * (gains[upper] - gains[lower])
            }
            value = (value * 10).rounded() / 10
            return min(max(value, BandLayout.gainRange.lowerBound), BandLayout.gainRange.upperBound)
        }
        return EQSettings(layout: target, gains: newGains)
    }

    /// 3-tap smoothing (0.25 / 0.5 / 0.25; ends use 0.75 self + 0.25 neighbour), rounded to 0.1 dB and clamped.
    public func smoothed() -> EQSettings {
        let n = gains.count
        guard n > 1 else { return self }
        let lo = BandLayout.gainRange.lowerBound, hi = BandLayout.gainRange.upperBound
        let out = (0..<n).map { i -> Double in
            let v: Double
            if i == 0 {
                v = 0.75 * gains[0] + 0.25 * gains[1]
            } else if i == n - 1 {
                v = 0.75 * gains[n - 1] + 0.25 * gains[n - 2]
            } else {
                v = 0.25 * gains[i - 1] + 0.5 * gains[i] + 0.25 * gains[i + 1]
            }
            let r = min(max((v * 10).rounded() / 10, lo), hi)
            return r == 0 ? 0 : r
        }
        return EQSettings(layout: layout, gains: out)
    }

    /// All bands set to 0 dB, same layout.
    public func zeroed() -> EQSettings { .flat(layout) }

    /// Negative preamp (dB) that offsets the curve's peak boost across 20 Hz–20 kHz; 0 if there is no boost.
    public func autoPreampDB(sampleRate: Double = 48_000) -> Double {
        let points = 200
        let lo = log2(20.0), hi = log2(20_000.0)
        var peak = 0.0
        for i in 0..<points {
            let hz = pow(2, lo + (hi - lo) * Double(i) / Double(points - 1))
            peak = max(peak, responseDB(at: hz, sampleRate: sampleRate))
        }
        return peak > 0 ? -peak : 0
    }
}
