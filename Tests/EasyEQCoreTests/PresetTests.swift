import Foundation
import Testing
@testable import EasyEQCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Test func saveLoadRoundTrip() throws {
    let store = PresetStore(directory: tempDir())
    let p = Preset(id: UUID(), name: "晚上直播", settings: .init(layout: .fifteen, gains: Array(repeating: -2, count: 15)))
    try store.save(p)
    #expect(store.loadAll() == [p])
}

@Test func corruptAndInvalidFilesAreHandled() throws {
    let dir = tempDir(); let store = PresetStore(directory: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "not json".write(to: dir.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)
    let raw = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","formatVersion":1,"settings":{"layout":10,"gains":[99,-99,0]}}"#
    try raw.write(to: dir.appendingPathComponent("6F9619FF-8B86-D011-B42D-00C04FC964FF.json"), atomically: true, encoding: .utf8)
    let all = store.loadAll()
    #expect(all.count == 1)
    #expect(all[0].settings.gains == [12, -12, 0, 0, 0, 0, 0, 0, 0, 0])
}

@Test func builtInVoiceMatchesSpec() {
    #expect(BuiltInPreset.voice.settings(for: .ten).gains == [-6,-5,-4,-3,-1,0,2,2.5,0,0])
    #expect(BuiltInPreset.voicePlus.settings(for: .ten).gains == [-10,-9,-7,-5,-2,0,3,3,0,-1])
    #expect(BuiltInPreset.flat.settings(for: .thirtyOne) == .flat(.thirtyOne))
    #expect(BuiltInPreset.voice.settings(for: .fifteen).gains.count == 15)
}

@Test func builtInPresetsMatchSpec() {
    let expected: [(BuiltInPreset, String, [Double])] = [
        (.voice, "voice", [-6, -5, -4, -3, -1, 0, 2, 2.5, 0, 0]),
        (.voicePlus, "voicePlus", [-10, -9, -7, -5, -2, 0, 3, 3, 0, -1]),
        (.podcast, "podcast", [-6, -4, -2, -1, 0, 1, 3, 2, -1, -2]),
        (.movie, "movie", [2, 2, 0, -1, 0, 1, 2, 2, 1, 0]),
        (.music, "music", [3, 2, 1, 0, -1, -1, 0, 1, 2, 2]),
        (.night, "night", [-8, -6, -4, -2, 0, 1, 2, 2, 0, -1]),
        (.lessBass, "lessBass", [-8, -7, -5, -3, -1, 0, 0, 0, 0, 0]),
        (.bassBoost, "bassBoost", [5, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        (.trebleBoost, "trebleBoost", [0, 0, 0, 0, 0, 1, 2, 3, 4, 4]),
        (.flat, "flat", Array(repeating: 0, count: 10)),
    ]
    #expect(BuiltInPreset.allCases.map(\.rawValue) == expected.map(\.1))
    #expect(BuiltInPreset.allCases.map(\.nameKey) == expected.map { "preset.\($0.1)" })
    #expect(BuiltInPreset.allCases.map(\.descriptionKey) == expected.map { "preset.\($0.1).desc" })
    for (preset, name, gains) in expected {
        #expect(preset.settings(for: .ten).gains == gains, "\(name)")
    }
}

@Test func deleteRemovesFile() throws {
    let dir = tempDir()
    let store = PresetStore(directory: dir)
    let p = Preset(id: UUID(), name: "temp", settings: .flat(.ten))
    try store.save(p)
    let file = dir.appendingPathComponent("\(p.id.uuidString).json")
    #expect(FileManager.default.fileExists(atPath: file.path))
    try store.delete(id: p.id)
    #expect(store.loadAll().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func deleteOfMissingPresetDoesNotThrow() throws {
    let store = PresetStore(directory: tempDir())
    try store.delete(id: UUID())
}

@Test func sanitizedFixesGainsAndCount() {
    let short = Preset(id: UUID(), name: "s", settings: .init(layout: .fifteen, gains: [1.26, .nan, .infinity, -0.04]))
    let s = short.sanitized().settings.gains
    #expect(s.count == 15)
    #expect(s[0] == 1.3)
    #expect(s[1] == 0)
    #expect(s[2] == 0)
    #expect(s[3].sign == .plus && s[3] == 0)   // -0.04 rounds to 0, not -0
    let long = Preset(id: UUID(), name: "l", settings: .init(layout: .ten, gains: Array(repeating: 1, count: 20)))
    #expect(long.sanitized().settings.gains.count == 10)
}

@Test func loadAllSortsByNameAndSanitizes() throws {
    let store = PresetStore(directory: tempDir())
    try store.save(Preset(id: UUID(), name: "b", settings: .flat(.ten)))
    try store.save(Preset(id: UUID(), name: "A", settings: .flat(.ten)))
    try store.save(Preset(id: UUID(), name: "a10", settings: .flat(.ten)))
    try store.save(Preset(id: UUID(), name: "a2", settings: .flat(.ten)))
    #expect(store.loadAll().map(\.name) == ["A", "a2", "a10", "b"])
}

@Test func savedFileIsPrettyPrintedWithSortedKeys() throws {
    let dir = tempDir()
    let store = PresetStore(directory: dir)
    let p = Preset(id: UUID(), name: "n", settings: .flat(.ten))
    try store.save(p)
    let text = try String(contentsOf: dir.appendingPathComponent("\(p.id.uuidString).json"), encoding: .utf8)
    #expect(text.contains("\n"))
    let positions: [Int] = ["formatVersion", "id", "name", "settings"].map { key in
        let r = text.range(of: "\"\(key)\"")!
        return text.distance(from: text.startIndex, to: r.lowerBound)
    }
    #expect(positions == positions.sorted())
}

@Test func oldPresetJSONDecodesUngrouped() throws {
    let raw = #"{"formatVersion":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"old","settings":{"gains":[1,2,3,4,5,6,7,8,9,10],"layout":10}}"#
    let decoded = try JSONDecoder().decode(Preset.self, from: Data(raw.utf8))
    #expect(decoded.groupID == nil)
    #expect(decoded.name == "old")
    // formatVersion missing defaults to 1
    let noVersion = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","settings":{"gains":[0,0,0,0,0,0,0,0,0,0],"layout":10}}"#
    #expect(try JSONDecoder().decode(Preset.self, from: Data(noVersion.utf8)).formatVersion == 1)

    let ungrouped = Preset(id: UUID(), name: "u", settings: .flat(.ten))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(ungrouped), as: UTF8.self)
    #expect(!json.contains("groupID"))

    let gid = UUID()
    let grouped = Preset(id: UUID(), name: "g", settings: .flat(.ten), groupID: gid)
    let data = try encoder.encode(grouped)
    #expect(try JSONDecoder().decode(Preset.self, from: data).groupID == gid)
    #expect(grouped.sanitized().groupID == gid)
}

@Test func groupedPresetSurvivesStore() throws {
    let store = PresetStore(directory: tempDir())
    let p = Preset(id: UUID(), name: "g", settings: .flat(.ten), groupID: UUID())
    try store.save(p)
    #expect(store.loadAll() == [p])
}

@Test func malformedOptionalFieldsDoNotDropPreset() throws {
    let base = #""id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","settings":{"gains":[0,0,0,0,0,0,0,0,0,0],"layout":10}"#
    for extra in [#""groupID":"abc""#, #""groupID":"""#, #""groupID":42"#, #""groupID":null"#,
                  #""formatVersion":"1""#, #""formatVersion":null"#] {
        let p = try JSONDecoder().decode(Preset.self, from: Data("{\(base),\(extra)}".utf8))
        #expect(p.groupID == nil)
        #expect(p.formatVersion == 1)
        #expect(p.name == "x")
    }
    // Core fields stay fatal.
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Preset.self, from: Data(#"{"id":"abc","name":"x","settings":{"gains":[],"layout":10}}"#.utf8))
    }
}
