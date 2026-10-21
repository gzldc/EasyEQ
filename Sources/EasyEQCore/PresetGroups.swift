import Foundation

public struct PresetGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Persisted sidebar layout: user groups (in display order) and which sections are collapsed.
public struct GroupLayout: Codable, Equatable, Sendable {
    public static let builtInSectionKey = "builtin"

    public var groups: [PresetGroup] = []
    /// `group.id.uuidString` for user groups, `GroupLayout.builtInSectionKey` for the built-in section.
    public var collapsed: Set<String> = []

    public init(groups: [PresetGroup] = [], collapsed: Set<String> = []) {
        self.groups = groups
        self.collapsed = collapsed
    }

    private enum CodingKeys: String, CodingKey { case groups, collapsed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([PresetGroup].self, forKey: .groups) ?? []
        var seen = Set<UUID>()
        groups = decoded.filter { seen.insert($0.id).inserted }   // keep first of duplicate ids
        collapsed = try c.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? []
    }

    @discardableResult
    public mutating func addGroup(named name: String) -> PresetGroup? {
        guard let unique = EditingSession.uniqueName(name, existing: groups.map(\.name)) else { return nil }
        let group = PresetGroup(id: UUID(), name: unique)
        groups.append(group)
        return group
    }

    @discardableResult
    public mutating func renameGroup(_ id: UUID, to name: String) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        let others = groups.filter { $0.id != id }.map(\.name)
        guard let unique = EditingSession.uniqueName(name, existing: others) else { return false }
        groups[index].name = unique
        return true
    }

    public mutating func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        collapsed.remove(id.uuidString)
    }

    public mutating func toggleCollapsed(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    public func isCollapsed(_ key: String) -> Bool { collapsed.contains(key) }

    /// Presets in `groupID` sorted by name. For `nil`, also includes presets whose group no longer exists.
    public static func members(of groupID: UUID?, in presets: [Preset], validGroups: [PresetGroup]) -> [Preset] {
        let valid = Set(validGroups.map(\.id))
        return presets
            .filter { preset in
                if let groupID { return preset.groupID == groupID }
                guard let own = preset.groupID else { return true }
                return !valid.contains(own)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public final class GroupStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/EasyEQ/groups.json`
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("EasyEQ", isDirectory: true).appendingPathComponent("groups.json")
    }

    /// Missing or corrupt file yields an empty layout (presets themselves are never affected).
    public func load() -> GroupLayout {
        guard let data = try? Data(contentsOf: fileURL),
              let layout = try? JSONDecoder().decode(GroupLayout.self, from: data) else { return GroupLayout() }
        return layout
    }

    public func save(_ layout: GroupLayout) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: fileURL, options: .atomic)
    }
}
