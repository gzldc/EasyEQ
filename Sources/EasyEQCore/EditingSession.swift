import Foundation

/// Identifies which preset the editor is currently based on.
public enum PresetRef: Codable, Hashable, Sendable {
    case builtIn(BuiltInPreset)
    case user(UUID)
}

/// Pure editing state: the live curve (`current`) versus the last saved/loaded one (`saved`).
public struct EditingSession: Equatable {
    public private(set) var selection: PresetRef
    public private(set) var saved: EQSettings
    public private(set) var current: EQSettings

    /// Gains with an absolute value below this snap to 0 dB.
    private static let snapThreshold = 0.3

    public init(selection: PresetRef, saved: EQSettings) {
        self.selection = selection
        self.saved = saved
        self.current = saved
    }

    public var isDirty: Bool { current != saved }

    /// Built-in presets are read-only: changes must go through Save As.
    public var canSaveInPlace: Bool {
        if case .builtIn = selection { return false }
        return true
    }

    /// Sets a band's gain: clamped to ±12 dB, rounded to 0.1 dB, snapped to 0 near zero.
    /// An out-of-range index is ignored.
    public mutating func setGain(_ gain: Double, at index: Int) {
        guard current.gains.indices.contains(index) else { return }
        let clamped = min(max(gain, BandLayout.gainRange.lowerBound), BandLayout.gainRange.upperBound)
        var value = (clamped * 10).rounded() / 10
        if abs(value) < Self.snapThreshold { value = 0 }
        current.gains[index] = value + 0 // + 0 normalizes -0.0 to 0.0
    }

    /// Double-click behavior: puts one band back to 0 dB.
    public mutating func resetBand(at index: Int) {
        guard current.gains.indices.contains(index) else { return }
        current.gains[index] = 0
    }

    public mutating func switchLayout(to layout: BandLayout) {
        guard layout != current.layout else { return }
        current = current.converted(to: layout)
    }

    public mutating func revert() {
        current = saved
    }

    public mutating func markSaved(as ref: PresetRef) {
        saved = current
        selection = ref
    }

    /// Trims `proposed`; returns nil if empty, otherwise a name not in `existing` (appending " 2", " 3", …).
    public static func uniqueName(_ proposed: String, existing: [String]) -> String? {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        let taken = Set(existing)
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    public static func selectionAfterDeleting(_ deleted: UUID, current: PresetRef) -> PresetRef {
        current == .user(deleted) ? .builtIn(.voice) : current
    }
}
