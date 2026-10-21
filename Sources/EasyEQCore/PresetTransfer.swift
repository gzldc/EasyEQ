import Foundation

/// Pure import / export logic for preset files. No file I/O: the UI owns the open / save panels.
public enum PresetTransfer {
    public struct ImportResult: Equatable {
        public var imported: [Preset]
        /// Names (as passed in) of files that could not be decoded as a preset.
        public var failedFiles: [String]

        public init(imported: [Preset], failedFiles: [String]) {
            self.imported = imported
            self.failedFiles = failedFiles
        }
    }

    /// Pretty JSON of the sanitized preset. `groupID` is stripped because groups are local to a machine.
    public static func exportData(_ preset: Preset) throws -> Data {
        var copy = preset.sanitized()
        copy.groupID = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(copy)
    }

    /// `"<name>.json"` with path-hostile `/` and `:` replaced by `-`.
    public static func suggestedFileName(for preset: Preset) -> String {
        let safe = preset.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safe).json"
    }

    /// Imports every decodable file. Each good file is sanitized, gets a fresh id if its id clashes with
    /// `existing` or an earlier import, gets a name unique among `existing` + earlier imports, and is placed
    /// in `groupID`. Undecodable files are reported by name and never block the others. A preset whose name is
    /// blank falls back to the file name without extension, then to "Preset".
    public static func importPresets(
        from files: [(name: String, data: Data)],
        existing: [Preset],
        into groupID: UUID?
    ) -> ImportResult {
        let decoder = JSONDecoder()
        var usedIDs = Set(existing.map(\.id))
        var usedNames = existing.map(\.name)
        var imported: [Preset] = []
        var failed: [String] = []

        for file in files {
            guard let decoded = try? decoder.decode(Preset.self, from: file.data) else {
                failed.append(file.name)
                continue
            }
            var preset = decoded.sanitized()
            while usedIDs.contains(preset.id) { preset.id = UUID() }
            let proposed = EditingSession.uniqueName(preset.name, existing: usedNames) != nil
                ? preset.name : fallbackName(forFile: file.name)
            preset.name = EditingSession.uniqueName(proposed, existing: usedNames) ?? "Preset"
            preset.groupID = groupID
            usedIDs.insert(preset.id)
            usedNames.append(preset.name)
            imported.append(preset)
        }
        return ImportResult(imported: imported, failedFiles: failed)
    }

    private static func fallbackName(forFile fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Preset" : stem
    }
}
