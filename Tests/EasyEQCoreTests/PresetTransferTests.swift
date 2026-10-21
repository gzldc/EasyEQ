import Foundation
import Testing
@testable import EasyEQCore

private func makePreset(_ name: String, id: UUID = UUID(), group: UUID? = nil) -> Preset {
    Preset(id: id, name: name,
           settings: .init(layout: .ten, gains: [1, 2, 3, 0, -1, -2, 0, 0, 0.5, 12]), groupID: group)
}

@Test func exportRoundTrip() throws {
    let p = makePreset("晚上直播", group: UUID())
    let data = try PresetTransfer.exportData(p)
    #expect(!String(decoding: data, as: UTF8.self).contains("groupID"))
    let result = PresetTransfer.importPresets(from: [("a.json", data)], existing: [], into: nil)
    #expect(result.failedFiles.isEmpty)
    #expect(result.imported.count == 1)
    #expect(result.imported[0].name == p.name)
    #expect(result.imported[0].settings == p.settings)
    #expect(result.imported[0].groupID == nil)
    #expect(result.imported[0].id == p.id)
}

@Test func exportSanitizesSettings() throws {
    let p = Preset(id: UUID(), name: "Loud", settings: .init(layout: .ten, gains: [99, -99]))
    let data = try PresetTransfer.exportData(p)
    let back = PresetTransfer.importPresets(from: [("x.json", data)], existing: [], into: nil).imported
    #expect(back.first?.settings.gains == [12, -12, 0, 0, 0, 0, 0, 0, 0, 0])
}

@Test func importHandlesDuplicatesAndBadFiles() throws {
    let sharedID = UUID()
    let a = try PresetTransfer.exportData(makePreset("X", id: sharedID))
    let b = try PresetTransfer.exportData(makePreset("X", id: sharedID))
    let existing = [makePreset("X")]   // name clash with existing
    let files: [(name: String, data: Data)] = [
        ("one.json", a), ("garbage.json", Data("garbage".utf8)), ("two.json", b),
    ]
    let result = PresetTransfer.importPresets(from: files, existing: existing, into: nil)
    #expect(result.imported.count == 2)
    #expect(result.failedFiles == ["garbage.json"])
    #expect(result.imported.map(\.name) == ["X 2", "X 3"])
    let ids = Set(result.imported.map(\.id) + existing.map(\.id))
    #expect(ids.count == 3)
}

@Test func importRegeneratesIDClashingWithExisting() throws {
    let id = UUID()
    let data = try PresetTransfer.exportData(makePreset("Fresh", id: id))
    let result = PresetTransfer.importPresets(from: [("f.json", data)], existing: [makePreset("Other", id: id)], into: nil)
    #expect(result.imported.count == 1)
    #expect(result.imported[0].id != id)
    #expect(result.imported[0].name == "Fresh")
}

@Test func importSanitizesAndIgnoresFileGroup() {
    let raw = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","groupID":"6F9619FF-8B86-D011-B42D-00C04FC964AA","settings":{"layout":10,"gains":[99,-99,0]}}"#
    let result = PresetTransfer.importPresets(from: [("x.json", Data(raw.utf8))], existing: [], into: nil)
    #expect(result.imported.first?.settings.gains == [12, -12, 0, 0, 0, 0, 0, 0, 0, 0])
    #expect(result.imported.first?.groupID == nil)
}

@Test func importAssignsGroup() throws {
    let g = UUID()
    let data = try PresetTransfer.exportData(makePreset("G"))
    let result = PresetTransfer.importPresets(from: [("g.json", data)], existing: [], into: g)
    #expect(result.imported.first?.groupID == g)
}

@Test func blankNameFallsBackToFileName() throws {
    let blank = try PresetTransfer.exportData(makePreset("   "))
    let result = PresetTransfer.importPresets(
        from: [("Warm Voice.json", blank), ("   .json", blank), ("", blank)], existing: [], into: nil)
    #expect(result.failedFiles.isEmpty)
    #expect(result.imported.map(\.name) == ["Warm Voice", "Preset", "Preset 2"])
    #expect(Set(result.imported.map(\.id)).count == 3)
}

@Test func emptyImportReturnsEmptyResult() {
    #expect(PresetTransfer.importPresets(from: [], existing: [], into: nil) == .init(imported: [], failedFiles: []))
}

@Test func fileNameSanitized() {
    #expect(PresetTransfer.suggestedFileName(for: makePreset("Bass/Boost: 2")) == "Bass-Boost- 2.json")
    #expect(PresetTransfer.suggestedFileName(for: makePreset("Plain")) == "Plain.json")
}
