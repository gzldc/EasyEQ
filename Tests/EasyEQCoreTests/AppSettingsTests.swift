import Foundation
import Testing
@testable import EasyEQCore

@Test func languageResolution() {
    #expect(AppSettings.resolve(.system, preferredLanguages: ["zh-Hans-CN"]) == .zhHans)
    #expect(AppSettings.resolve(.system, preferredLanguages: ["zh-Hant-TW"]) == .zhHans)
    #expect(AppSettings.resolve(.system, preferredLanguages: ["ja-JP", "zh-Hans"]) == .en)
    #expect(AppSettings.resolve(.system, preferredLanguages: ["en-US"]) == .en)
    #expect(AppSettings.resolve(.chinese, preferredLanguages: ["en-US"]) == .zhHans)
    #expect(AppSettings.resolve(.english, preferredLanguages: ["zh-Hans"]) == .en)
    #expect(AppSettings.resolve(.system, preferredLanguages: []) == .en)
}

@Test func defaultSettings() {
    let d = AppSettings()
    #expect(d.selection == .builtIn(.voice))
    #expect(d.effectEnabled)
    #expect(d.lastLayout == .ten)
    #expect(d.language == .system)
}

@Test func settingsPersist() {
    let name = UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = SettingsStore(defaults: defaults)
    #expect(store.load() == AppSettings())

    let custom = AppSettings(selection: .user(UUID()), effectEnabled: false, lastLayout: .thirtyOne, language: .english)
    store.save(custom)
    #expect(SettingsStore(defaults: defaults).load() == custom)
}

@Test func corruptSettingsFallBackToDefaults() {
    let name = UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(Data("not json".utf8), forKey: "EasyEQ.settings")
    #expect(SettingsStore(defaults: defaults).load() == AppSettings())
}

@Test func settingsFromPreviousVersionKeepFieldsAndDefaultAppearance() throws {
    let id = UUID()
    let encoded = try JSONEncoder().encode(
        AppSettings(selection: .user(id), effectEnabled: false, lastLayout: .thirtyOne, language: .chinese))
    // Drop the `appearance` key to reproduce the shape written before the setting existed.
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "appearance")
    let old = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AppSettings.self, from: old)
    #expect(decoded.selection == .user(id))
    #expect(decoded.effectEnabled == false)
    #expect(decoded.lastLayout == .thirtyOne)
    #expect(decoded.language == .chinese)
    #expect(decoded.appearance == .system)
}

@Test func appearancePersists() {
    let name = UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = SettingsStore(defaults: defaults)
    store.save(AppSettings(appearance: .dark))
    #expect(store.load().appearance == .dark)
}
