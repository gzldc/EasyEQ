import Foundation

public enum LanguageChoice: String, Codable, CaseIterable, Sendable {
    case system, chinese, english
}

public enum AppLanguage: String, Sendable {
    case zhHans = "zh-Hans"
    case en
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selection: PresetRef
    public var effectEnabled: Bool
    public var lastLayout: BandLayout
    public var language: LanguageChoice

    public init(selection: PresetRef = .builtIn(.voice),
                effectEnabled: Bool = true,
                lastLayout: BandLayout = .ten,
                language: LanguageChoice = .system) {
        self.selection = selection
        self.effectEnabled = effectEnabled
        self.lastLayout = lastLayout
        self.language = language
    }

    /// `.system` follows the first preferred language: any Chinese variant maps to Simplified Chinese, everything else to English.
    public static func resolve(_ choice: LanguageChoice, preferredLanguages: [String]) -> AppLanguage {
        switch choice {
        case .chinese: return .zhHans
        case .english: return .en
        case .system:
            return preferredLanguages.first?.hasPrefix("zh") == true ? .zhHans : .en
        }
    }
}

public final class SettingsStore {
    private static let key = "EasyEQ.settings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ s: AppSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
