import Testing
@testable import EasyEQCore

struct LocalizerTests {
    static let requiredKeys: [String] = [
        "app.name", "sidebar.builtIn", "sidebar.mine", "sidebar.new",
        "preset.voice", "preset.voicePlus", "preset.flat",
        "editor.effect", "editor.bands", "editor.revert", "editor.smooth", "editor.zero", "editor.save", "editor.saveAs",
        "editor.builtInReadOnly", "menu.rename", "menu.delete",
        "sheet.name", "sheet.cancel", "sheet.ok",
        "zone.subbass", "zone.bass", "zone.warmth", "zone.mud", "zone.body",
        "zone.voice", "zone.presence", "zone.clarity", "zone.sibilance", "zone.air",
        "device.output", "permission.title", "permission.open",
        "settings.language", "settings.system", "settings.appearance", "appearance.light", "appearance.dark",
        "preset.voice.desc", "preset.voicePlus.desc", "preset.flat.desc",
        "preset.podcast", "preset.movie", "preset.music", "preset.night",
        "preset.lessBass", "preset.bassBoost", "preset.trebleBoost",
        "preset.podcast.desc", "preset.movie.desc", "preset.music.desc", "preset.night.desc",
        "preset.lessBass.desc", "preset.bassBoost.desc", "preset.trebleBoost.desc",
        "engine.starting", "engine.failed", "engine.retry", "error.saveFailed", "error.deleteFailed",
        "sidebar.newGroup", "sidebar.import", "menu.moveToGroup", "menu.ungrouped", "menu.export",
        "menu.newPresetHere", "menu.deleteGroup", "menu.renameGroup", "sheet.groupName",
        "confirm.deletePreset.title", "confirm.deletePreset.message", "confirm.delete",
        "error.importFailed", "error.exportFailed", "error.groupSaveFailed",
        "a11y.expanded", "a11y.collapsed", "a11y.presetCount",
        "menu.newPreset", "menu.save", "menu.saveAs", "menu.toggleEffect",
        "settings.launchAtLogin", "settings.launchAtLogin.moveHint", "error.loginItemFailed",
        "engine.repair", "engine.unresponsive", "error.repairFailed",
    ]

    @Test func everyKeyExistsInBothLanguages() {
        let en = Localizer.keys(for: .en), zh = Localizer.keys(for: .zhHans)
        #expect(!en.isEmpty && en == zh)
    }

    @Test func bothTablesContainAllRequiredKeys() {
        for language in [AppLanguage.en, .zhHans] {
            let keys = Localizer.keys(for: language)
            for key in Self.requiredKeys {
                #expect(keys.contains(key), "missing \(key) in \(language.rawValue)")
            }
        }
    }

    @Test func lookupAndSwitch() {
        let l = Localizer(language: .zhHans)
        #expect(l.t("preset.voice") == "人声")
        l.setLanguage(.en)
        #expect(l.t("preset.voice") == "Voice")
        #expect(l.t("no.such.key") == "no.such.key")
    }

    @Test func placeholderAndSpecialValues() {
        let l = Localizer(language: .en)
        #expect(l.t("device.output") == "Output: %@")
        #expect(l.t("zone.air") == "Air")
        #expect(l.t("editor.smooth") == "Smooth")
        #expect(l.t("editor.zero") == "Reset All")
        l.setLanguage(.zhHans)
        #expect(l.t("device.output") == "输出设备：%@")
        #expect(l.t("zone.air") == "空气感")
        #expect(l.t("editor.smooth") == "平滑")
        #expect(l.t("editor.zero") == "归零")
        #expect(l.t("permission.title") == "简易均衡器需要“系统音频录制”权限才能处理声音")
    }

    @Test func repairStrings() {
        let l = Localizer(language: .zhHans)
        #expect(l.t("engine.repair") == "修复系统声音")
        #expect(l.t("engine.unresponsive") == "系统音频服务没有响应。")
        #expect(l.t("error.repairFailed") == "系统声音修复失败。")
        l.setLanguage(.en)
        #expect(l.t("engine.repair") == "Repair System Audio")
        #expect(l.t("engine.unresponsive") == "The system audio service isn't responding.")
        #expect(l.t("error.repairFailed") == "Couldn't repair system audio.")
    }
}
