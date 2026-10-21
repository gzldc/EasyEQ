import Foundation

/// Normalized biquad coefficients (a0 == 1).
public struct BiquadCoefficients: Equatable, Sendable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    /// RBJ Audio EQ Cookbook peaking filter.
    /// The center frequency is clamped to `0.49 * sampleRate` to stay stable near Nyquist.
    public static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        if gainDB == 0 {
            return BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
        }
        let f = min(frequency, 0.49 * sampleRate)
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * f / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha / a
        return BiquadCoefficients(
            b0: (1 + alpha * a) / a0,
            b1: (-2 * cosW0) / a0,
            b2: (1 - alpha * a) / a0,
            a1: (-2 * cosW0) / a0,
            a2: (1 - alpha / a) / a0
        )
    }

    /// Magnitude response in dB, evaluating H(e^{jw}) at `hz`.
    public func magnitudeDB(at hz: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * hz / sampleRate
        let c1 = cos(w), s1 = sin(w)
        let c2 = cos(2 * w), s2 = sin(2 * w)
        let numRe = b0 + b1 * c1 + b2 * c2
        let numIm = -(b1 * s1 + b2 * s2)
        let denRe = 1 + a1 * c1 + a2 * c2
        let denIm = -(a1 * s1 + a2 * s2)
        let num = numRe * numRe + numIm * numIm
        let den = denRe * denRe + denIm * denIm
        return 10 * log10(num / den)
    }
}
