import Foundation

public enum BandLayout: Int, Codable, CaseIterable, Sendable {
    case ten = 10
    case fifteen = 15
    case thirtyOne = 31

    public static let gainRange: ClosedRange<Double> = -12...12

    public var bandCount: Int { rawValue }

    public var frequencies: [Double] {
        switch self {
        case .ten:
            return [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        case .fifteen:
            return [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000]
        case .thirtyOne:
            return [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
                    1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
        }
    }

    public var q: Double {
        switch self {
        case .ten: return 1.41
        case .fifteen: return 2.1
        case .thirtyOne: return 4.3
        }
    }

    /// Whether the band at `index` gets a frequency label under its slider. The 31-band layout labels every
    /// other band (the odd positions: 25, 40, 63 … 1K … 16K), the others are reachable through the hover readout.
    public func showsFrequencyLabel(at index: Int) -> Bool {
        self != .thirtyOne || index % 2 == 1
    }

    /// Localization key naming the frequency zone a band falls into.
    public static func zoneKey(forFrequency hz: Double) -> String {
        switch hz {
        case ..<45: return "zone.subbass"
        case ..<90: return "zone.bass"
        case ..<180: return "zone.warmth"
        case ..<350: return "zone.mud"
        case ..<700: return "zone.body"
        case ..<1400: return "zone.voice"
        case ..<2800: return "zone.presence"
        case ..<5600: return "zone.clarity"
        case ..<11000: return "zone.sibilance"
        default: return "zone.air"
        }
    }
}
