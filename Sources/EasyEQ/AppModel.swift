import AppKit
import Combine
import EasyEQAudio
import EasyEQCore
import Foundation
import os
import UniformTypeIdentifiers

private let presetLog = Logger(subsystem: "app.easyeq.EasyEQ", category: "presets")

/// Single source of truth for the app: wires the pure Core logic (`EditingSession`, stores) to the audio engine.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: EditingSession
    @Published private(set) var userPresets: [Preset]
    @Published private(set) var settings: AppSettings
    /// User groups (display order) and which sidebar sections are collapsed; persisted in `groups.json`.
    @Published private(set) var groupLayout: GroupLayout
    /// Last preset-file/IO failure, for the UI to surface. Never cleared automatically.
    @Published var lastError: String?
    /// Set when `save()` is invoked on a built-in preset; the UI shows the hint and opens Save As.
    @Published var showBuiltInReadOnlyHint = false

    let localizer: Localizer
    let engine: SystemAudioEngine

    private let presetStore: PresetStore
    private let settingsStore: SettingsStore
    private let groupStore: GroupStore

    init(presetStore: PresetStore = PresetStore(directory: PresetStore.defaultDirectory),
         settingsStore: SettingsStore = SettingsStore(defaults: .standard),
         groupStore: GroupStore = GroupStore(fileURL: GroupStore.defaultFileURL),
         engine: SystemAudioEngine? = nil) {
        self.presetStore = presetStore
        self.settingsStore = settingsStore
        self.groupStore = groupStore
        self.engine = engine ?? SystemAudioEngine()

        var loaded = settingsStore.load()
        let presets = presetStore.loadAll()

        // Restore the selection; a missing user preset falls back to Voice.
        var selection = loaded.selection
        var saved: EQSettings
        switch selection {
        case .builtIn(let preset):
            saved = preset.settings(for: loaded.lastLayout)
        case .user(let id):
            if let preset = presets.first(where: { $0.id == id }) {
                saved = preset.settings
            } else {
                selection = .builtIn(.voice)
                saved = BuiltInPreset.voice.settings(for: loaded.lastLayout)
            }
        }
        loaded.selection = selection
        loaded.lastLayout = saved.layout

        self.settings = loaded
        self.userPresets = presets
        self.groupLayout = groupStore.load()
        self.session = EditingSession(selection: selection, saved: saved)
        self.localizer = Localizer(language: AppSettings.resolve(loaded.language, preferredLanguages: Locale.preferredLanguages))

        settingsStore.save(loaded)
        applyToEngine()
    }

    /// Starts system-wide processing with the restored curve.
    func start() {
        applyAppearance()
        applyToEngine()
        engine.start()
    }

    // MARK: - Selection and editing

    func select(_ ref: PresetRef) {
        switch ref {
        case .builtIn(let preset):
            // Built-ins follow the layout currently on screen.
            session = EditingSession(selection: ref, saved: preset.settings(for: session.current.layout))
        case .user(let id):
            guard let preset = userPresets.first(where: { $0.id == id }) else {
                presetLog.error("Cannot select missing user preset \(id.uuidString, privacy: .public)")
                return
            }
            session = EditingSession(selection: ref, saved: preset.settings)
        }
        selectionOrLayoutChanged()
    }

    func setGain(_ gain: Double, at index: Int) {
        session.setGain(gain, at: index)
        applyToEngine()
    }

    /// Applies a painted stroke: every update goes through the session's rounding / snap rules, but the
    /// session is published and the engine updated once per call, not once per band.
    func setGains(_ updates: [(index: Int, gain: Double)]) {
        guard !updates.isEmpty else { return }
        var edited = session
        for update in updates { edited.setGain(update.gain, at: update.index) }
        guard edited != session else { return }
        session = edited
        applyToEngine()
    }

    /// One light smoothing pass over the whole curve (Revert undoes it).
    func smoothCurve() {
        session.replaceCurrent(with: session.current.smoothed())
        applyToEngine()
    }

    /// All bands back to 0 dB (Revert undoes it).
    func zeroAllBands() {
        session.replaceCurrent(with: session.current.zeroed())
        applyToEngine()
    }

    func resetBand(at index: Int) {
        session.resetBand(at: index)
        applyToEngine()
    }

    func switchLayout(_ layout: BandLayout) {
        session.switchLayout(to: layout)
        selectionOrLayoutChanged()
    }

    func revert() {
        session.revert()
        // Reverting can undo an unsaved layout switch, so keep lastLayout in sync.
        selectionOrLayoutChanged()
    }

    // MARK: - Saving

    /// Saves in place for user presets. For built-ins nothing is written; the UI is asked to show the hint.
    func save() {
        guard session.canSaveInPlace else {
            showBuiltInReadOnlyHint = true
            return
        }
        guard case .user(let id) = session.selection,
              let existing = userPresets.first(where: { $0.id == id }) else {
            presetLog.error("Save requested but the selected user preset no longer exists")
            return
        }
        guard write(Preset(id: id, name: existing.name, settings: session.current, groupID: existing.groupID)) else { return }
        session.markSaved(as: .user(id))
        reloadUserPresets()
        persistSettings()
    }

    @discardableResult
    func saveAs(name: String) -> Bool { createPreset(named: name, inGroup: selectedPresetGroupID) }

    /// Starts from the current curve, like Save As. Goes into `groupID` when given, otherwise into the
    /// group of the currently selected user preset.
    @discardableResult
    func newPreset(name: String, inGroup groupID: UUID? = nil) -> Bool {
        createPreset(named: name, inGroup: groupID ?? selectedPresetGroupID)
    }

    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        guard let existing = userPresets.first(where: { $0.id == id }) else { return false }
        let others = userPresets.filter { $0.id != id }.map(\.name)
        guard let unique = EditingSession.uniqueName(name, existing: others) else { return false }
        if unique == existing.name { return true }
        var renamed = existing
        renamed.name = unique
        guard write(renamed) else { return false }
        reloadUserPresets()
        return true
    }

    /// Permanently deletes a user preset. The UI asks for confirmation first.
    func deletePresetConfirmed(_ id: UUID) {
        do {
            try presetStore.delete(id: id)
        } catch {
            report(key: "error.deleteFailed", underlying: error)
            return
        }
        reloadUserPresets()
        let next = EditingSession.selectionAfterDeleting(id, current: session.selection)
        if next != session.selection { select(next) }
    }

    // MARK: - Groups

    @discardableResult
    func createGroup(named name: String) -> Bool {
        var layout = groupLayout
        guard layout.addGroup(named: name) != nil else { return false }
        commit(layout)
        return true
    }

    @discardableResult
    func renameGroup(_ id: UUID, to name: String) -> Bool {
        var layout = groupLayout
        guard layout.renameGroup(id, to: name) else { return false }
        commit(layout)
        return true
    }

    /// Removes the group only. Its presets keep their files and show up under "My Presets" again.
    func deleteGroup(_ id: UUID) {
        var layout = groupLayout
        layout.removeGroup(id)
        commit(layout)
    }

    /// Moves a user preset into `groupID` (`nil` = ungrouped). Unknown presets and groups are ignored.
    func move(_ presetID: UUID, toGroup groupID: UUID?) {
        guard var preset = userPresets.first(where: { $0.id == presetID }) else { return }
        if let groupID, !groupLayout.groups.contains(where: { $0.id == groupID }) { return }
        guard preset.groupID != groupID else { return }
        preset.groupID = groupID
        guard write(preset) else { return }
        reloadUserPresets()
        // Keep the selected preset visible if it was just moved into a collapsed group.
        if let groupID, session.selection == .user(presetID) { expandGroup(groupID) }
    }

    func toggleCollapsed(_ key: String) {
        var layout = groupLayout
        layout.toggleCollapsed(key)
        commit(layout)
    }

    // MARK: - Import and export

    func exportPreset(_ id: UUID) {
        guard let preset = userPresets.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.exportFileName(for: preset)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PresetTransfer.exportData(preset).write(to: url, options: .atomic)
        } catch {
            report(key: "error.exportFailed", underlying: error)
        }
    }

    /// Lets the user pick `.json` files and imports them next to the selected preset (its group, if any).
    func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var files: [(name: String, data: Data)] = []
        var unreadable: [String] = []
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) {
                files.append((url.lastPathComponent, data))
            } else {
                unreadable.append(url.lastPathComponent)
            }
        }
        importPresets(files: files, alsoFailed: unreadable)
    }

    private func importPresets(files: [(name: String, data: Data)], alsoFailed: [String]) {
        let target = selectedPresetGroupID
        let result = PresetTransfer.importPresets(from: files, existing: userPresets, into: target)
        var failed = alsoFailed + result.failedFiles
        var wroteAny = false
        for preset in result.imported {
            do {
                try presetStore.save(preset)
                wroteAny = true
            } catch {
                presetLog.error("import save failed: \(error.localizedDescription, privacy: .public)")
                failed.append(preset.name)
            }
        }
        if wroteAny {
            reloadUserPresets()
            if let target { expandGroup(target) }
        }
        if !failed.isEmpty {
            lastError = String(format: localizer.t("error.importFailed"), failed.joined(separator: ", "))
        }
    }

    /// `PresetTransfer.suggestedFileName`, but never empty or a hidden file.
    static func exportFileName(for preset: Preset) -> String {
        let suggestion = PresetTransfer.suggestedFileName(for: preset).trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestion.hasPrefix(".") || suggestion.isEmpty ? "Preset.json" : suggestion
    }

    // MARK: - Settings

    func setEffectEnabled(_ on: Bool) {
        settings.effectEnabled = on
        persistSettings()
        applyToEngine()
    }

    func setLanguage(_ choice: LanguageChoice) {
        settings.language = choice
        persistSettings()
        localizer.setLanguage(AppSettings.resolve(choice, preferredLanguages: Locale.preferredLanguages))
    }

    func setAppearance(_ choice: AppearanceChoice) {
        settings.appearance = choice
        persistSettings()
        applyAppearance()
    }

    func displayName(for ref: PresetRef) -> String {
        switch ref {
        case .builtIn(let preset): return localizer.t(preset.nameKey)
        case .user(let id): return userPresets.first(where: { $0.id == id })?.name ?? ""
        }
    }

    // MARK: - Private

    /// The group of the selected user preset, if that group still exists.
    private var selectedPresetGroupID: UUID? {
        guard case .user(let id) = session.selection,
              let groupID = userPresets.first(where: { $0.id == id })?.groupID,
              groupLayout.groups.contains(where: { $0.id == groupID }) else { return nil }
        return groupID
    }

    private func createPreset(named name: String, inGroup groupID: UUID?) -> Bool {
        guard let unique = EditingSession.uniqueName(name, existing: userPresets.map(\.name)) else { return false }
        let id = UUID()
        guard write(Preset(id: id, name: unique, settings: session.current, groupID: groupID)) else { return false }
        session.markSaved(as: .user(id))
        reloadUserPresets()
        persistSettings()
        if let groupID { expandGroup(groupID) }   // the new preset is selected, so it must be visible
        return true
    }

    private func expandGroup(_ id: UUID) {
        guard groupLayout.isCollapsed(id.uuidString) else { return }
        var layout = groupLayout
        layout.toggleCollapsed(id.uuidString)
        commit(layout)
    }

    /// Applies and persists a new layout. The in-memory layout changes even if the write fails.
    private func commit(_ layout: GroupLayout) {
        groupLayout = layout
        do {
            try groupStore.save(layout)
        } catch {
            report(key: "error.groupSaveFailed", underlying: error)
        }
    }

    private func write(_ preset: Preset) -> Bool {
        do {
            try presetStore.save(preset)
            return true
        } catch {
            report(key: "error.saveFailed", underlying: error)
            return false
        }
    }

    private func reloadUserPresets() {
        userPresets = presetStore.loadAll()
    }

    /// Logs the underlying error; the UI only ever shows the localized text for `key`.
    private func report(key: String, underlying error: Error) {
        presetLog.error("\(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        lastError = localizer.t(key)
    }

    private func selectionOrLayoutChanged() {
        settings.selection = session.selection
        settings.lastLayout = session.current.layout
        persistSettings()
        applyToEngine()
    }

    private func persistSettings() {
        settings.selection = session.selection
        settings.lastLayout = session.current.layout
        settingsStore.save(settings)
    }

    /// `nil` follows the system; the others pin the whole app (main and settings windows) to light or dark.
    private func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyToEngine() {
        engine.processor.update(settings: session.current, enabled: settings.effectEnabled)
    }
}
