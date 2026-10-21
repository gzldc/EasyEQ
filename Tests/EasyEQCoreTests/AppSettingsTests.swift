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
