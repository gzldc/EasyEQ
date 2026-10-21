import Foundation

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: EQSettings
    public var formatVersion: Int = 1

    public init(id: UUID, name: String, settings: EQSettings, formatVersion: Int = 1) {
        self.id = id
        self.name = name
        self.settings = settings
        self.formatVersion = formatVersion
    }

    /// Returns a copy that is safe to feed to the EQ: finite gains clamped to ±12 dB and rounded to 0.1 dB,
    /// with exactly `layout.bandCount` gains (padded with 0 or truncated).
    public func sanitized() -> Preset {
        var copy = self
        let count = settings.layout.bandCount
        var gains = settings.gains.prefix(count).map { value -> Double in
            guard value.isFinite else { return 0 }
            let rounded = (min(max(value, BandLayout.gainRange.lowerBound), BandLayout.gainRange.upperBound) * 10).rounded() / 10
            return rounded == 0 ? 0 : rounded   // normalize -0.0
        }
        if gains.count < count {
            gains += Array(repeating: 0, count: count - gains.count)
        }
        copy.settings.gains = gains
        return copy
    }
}

public enum BuiltInPreset: String, CaseIterable, Codable, Sendable {
    case voice, voicePlus, podcast, movie, music, night, lessBass, bassBoost, trebleBoost, flat

    public var nameKey: String { "preset.\(rawValue)" }
    public var descriptionKey: String { "preset.\(rawValue).desc" }

    private var tenBandGains: [Double] {
        switch self {
        case .voice: return [-6, -5, -4, -3, -1, 0, 2, 2.5, 0, 0]
        case .voicePlus: return [-10, -9, -7, -5, -2, 0, 3, 3, 0, -1]
        case .podcast: return [-6, -4, -2, -1, 0, 1, 3, 2, -1, -2]
        case .movie: return [2, 2, 0, -1, 0, 1, 2, 2, 1, 0]
        case .music: return [3, 2, 1, 0, -1, -1, 0, 1, 2, 2]
        case .night: return [-8, -6, -4, -2, 0, 1, 2, 2, 0, -1]
        case .lessBass: return [-8, -7, -5, -3, -1, 0, 0, 0, 0, 0]
        case .bassBoost: return [5, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .trebleBoost: return [0, 0, 0, 0, 0, 1, 2, 3, 4, 4]
        case .flat: return Array(repeating: 0, count: 10)
        }
    }

    public func settings(for layout: BandLayout) -> EQSettings {
        EQSettings(layout: .ten, gains: tenBandGains).converted(to: layout)
    }
}
