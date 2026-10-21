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
    #expect(BuiltInPreset.allCases.map(\.nameKey) == ["preset.voice", "preset.voicePlus", "preset.flat"])
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
