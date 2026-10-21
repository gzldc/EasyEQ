import Foundation
import Testing
@testable import EasyEQCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("groups.json")
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func groupLayoutRoundTripAndTolerance() throws {
    let url = tempFile(); defer { cleanup(url) }
    let store = GroupStore(fileURL: url)
    #expect(store.load() == GroupLayout())   // missing file

    var layout = GroupLayout()
    let g = layout.addGroup(named: "Work")!
    layout.toggleCollapsed(g.id.uuidString)
    layout.toggleCollapsed(GroupLayout.builtInSectionKey)
    try store.save(layout)
    #expect(store.load() == layout)

    try "not json".write(to: url, atomically: true, encoding: .utf8)
    #expect(store.load() == GroupLayout())
    try "{}".write(to: url, atomically: true, encoding: .utf8)
    #expect(store.load() == GroupLayout())
}

@Test func addRenameRemoveGroups() {
    var layout = GroupLayout()
    let blank = layout.addGroup(named: "   ")
    #expect(blank == nil)
    let a = layout.addGroup(named: " Music ")!
    #expect(a.name == "Music")
    let b = layout.addGroup(named: "Music")!
    #expect(b.name == "Music 2")
    #expect(layout.groups.map(\.id) == [a.id, b.id])

    let r1 = layout.renameGroup(a.id, to: "Film")
    #expect(r1)
    #expect(layout.groups[0].name == "Film")
    let r2 = layout.renameGroup(a.id, to: "  ")
    let r3 = layout.renameGroup(UUID(), to: "Nope")
    #expect(!r2 && !r3)
    let r4 = layout.renameGroup(b.id, to: "Film")
    #expect(r4)
    #expect(layout.groups[1].name == "Film 2")
    let r5 = layout.renameGroup(b.id, to: "Film 2")   // renaming to own name is fine
    #expect(r5)
    #expect(layout.groups[1].name == "Film 2")

    layout.toggleCollapsed(a.id.uuidString)
    layout.removeGroup(a.id)
    #expect(layout.groups.map(\.id) == [b.id])
    #expect(!layout.collapsed.contains(a.id.uuidString))
}

@Test func orphanedPresetsAreUngrouped() {
    let live = PresetGroup(id: UUID(), name: "Live")
    let gone = UUID()
    let flat = EQSettings.flat(.ten)
    let inGroup = Preset(id: UUID(), name: "B", settings: flat, groupID: live.id)
    let inGroup2 = Preset(id: UUID(), name: "A", settings: flat, groupID: live.id)
    let ungrouped = Preset(id: UUID(), name: "Z", settings: flat)
    let orphan = Preset(id: UUID(), name: "C", settings: flat, groupID: gone)
    let all = [inGroup, ungrouped, orphan, inGroup2]

    #expect(GroupLayout.members(of: live.id, in: all, validGroups: [live]).map(\.name) == ["A", "B"])
    #expect(GroupLayout.members(of: nil, in: all, validGroups: [live]).map(\.name) == ["C", "Z"])
}

@Test func collapsedStateToggles() {
    var layout = GroupLayout()
    let key = GroupLayout.builtInSectionKey
    #expect(key == "builtin")
    #expect(!layout.isCollapsed(key))
    layout.toggleCollapsed(key)
    #expect(layout.isCollapsed(key))
    layout.toggleCollapsed(key)
    #expect(!layout.isCollapsed(key))
}

@Test func duplicateGroupIDsAreDroppedOnDecode() throws {
    let raw = #"{"groups":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"First"},{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Second"},{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Third"}]}"#
    let layout = try JSONDecoder().decode(GroupLayout.self, from: Data(raw.utf8))
    #expect(layout.groups.map(\.name) == ["First", "Third"])
}

@Test func corruptGroupsFileIsMovedAsideNotOverwritten() throws {
    let url = tempFile(); defer { cleanup(url) }
    let store = GroupStore(fileURL: url)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let damaged = #"{"groups":[{"id":"oops","name":"Work"}"#   // truncated
    try damaged.write(to: url, atomically: true, encoding: .utf8)

    #expect(store.load() == GroupLayout())
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
    let backups = siblings.filter { $0.hasPrefix("groups.json.corrupt-") }
    #expect(backups.count == 1)
    let stamp = String(backups[0].dropFirst("groups.json.corrupt-".count))
    #expect(stamp.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression) != nil)
    let kept = try String(contentsOf: url.deletingLastPathComponent().appendingPathComponent(backups[0]), encoding: .utf8)
    #expect(kept == damaged)

    // A later save writes a fresh file and leaves the backup alone.
    var layout = GroupLayout(); layout.addGroup(named: "New")
    try store.save(layout)
    #expect(store.load() == layout)
    #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        .filter { $0.hasPrefix("groups.json.corrupt-") }.count == 1)
}

@Test func missingGroupsFileCreatesNoBackup() throws {
    let url = tempFile(); defer { cleanup(url) }
    #expect(GroupStore(fileURL: url).load() == GroupLayout())
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
}
