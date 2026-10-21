import Combine
import Foundation

/// Runtime-switchable string lookup backed by the `.strings` tables in the
/// package resource bundle. Each language's table is loaded once and cached.
public final class Localizer: ObservableObject {
    @Published public private(set) var language: AppLanguage

    private static let cacheLock = NSLock()
    private static var tableCache: [AppLanguage: [String: String]] = [:]

    public init(language: AppLanguage) {
        self.language = language
    }

    public func setLanguage(_ l: AppLanguage) {
        language = l
    }

    /// Current language's value, falling back to English, then to the key itself.
    public func t(_ key: String) -> String {
        if let value = Self.table(for: language)[key] { return value }
        if let value = Self.table(for: .en)[key] { return value }
        return key
    }

    /// All keys defined in the given language's `.strings` file.
    public static func keys(for language: AppLanguage) -> Set<String> {
        Set(table(for: language).keys)
    }

    /// The bundle holding the `.lproj` folders: the packaged app's resource
    /// bundle if present, otherwise the SwiftPM-generated `Bundle.module`.
    public static func resourceBundle() -> Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("EasyEQ_EasyEQCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    private static func table(for language: AppLanguage) -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = tableCache[language] { return cached }
        var loaded: [String: String] = [:]
        if let url = resourceBundle().url(
            forResource: "Localizable", withExtension: "strings",
            subdirectory: nil, localization: language.rawValue),
           let dict = NSDictionary(contentsOf: url) as? [String: String] {
            loaded = dict
        }
        tableCache[language] = loaded
        return loaded
    }
}
