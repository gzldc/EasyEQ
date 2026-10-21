import Combine
import EasyEQAudio
import EasyEQCore
import Foundation
import os

private let presetLog = Logger(subsystem: "app.easyeq.EasyEQ", category: "presets")

/// Single source of truth for the app: wires the pure Core logic (`EditingSession`, stores) to the audio engine.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: EditingSession
    @Published private(set) var userPresets: [Preset]
    @Published private(set) var settings: AppSettings
    /// Last preset-file/IO failure, for the UI to surface. Never cleared automatically.
    @Published var lastError: String?
    /// Set when `save()` is invoked on a built-in preset; the UI shows the hint and opens Save As.
    @Published var showBuiltInReadOnlyHint = false

    let localizer: Localizer
    let engine: SystemAudioEngine

    private let presetStore: PresetStore
    private let settingsStore: SettingsStore

    init(presetStore: PresetStore = PresetStore(directory: PresetStore.defaultDirectory),
         settingsStore: SettingsStore = SettingsStore(defaults: .standard),
         engine: SystemAudioEngine? = nil) {
        self.presetStore = presetStore
        self.settingsStore = settingsStore
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
        self.session = EditingSession(selection: selection, saved: saved)
        self.localizer = Localizer(language: AppSettings.resolve(loaded.language, preferredLanguages: Locale.preferredLanguages))

        settingsStore.save(loaded)
        applyToEngine()
    }

    /// Starts system-wide processing with the restored curve.
    func start() {
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
        guard write(Preset(id: id, name: existing.name, settings: session.current)) else { return }
        session.markSaved(as: .user(id))
        reloadUserPresets()
        persistSettings()
    }

    @discardableResult
    func saveAs(name: String) -> Bool { createPreset(named: name) }

    /// Starts from the current curve, like Save As.
    @discardableResult
    func newPreset(name: String) -> Bool { createPreset(named: name) }

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

    func delete(_ id: UUID) {
        do {
            try presetStore.delete(id: id)
        } catch {
            report("Could not delete preset: \(error.localizedDescription)")
            return
        }
        reloadUserPresets()
        let next = EditingSession.selectionAfterDeleting(id, current: session.selection)
        if next != session.selection { select(next) }
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

    func displayName(for ref: PresetRef) -> String {
        switch ref {
        case .builtIn(let preset): return localizer.t(preset.nameKey)
        case .user(let id): return userPresets.first(where: { $0.id == id })?.name ?? ""
        }
    }

    // MARK: - Private

    private func createPreset(named name: String) -> Bool {
        guard let unique = EditingSession.uniqueName(name, existing: userPresets.map(\.name)) else { return false }
        let id = UUID()
        guard write(Preset(id: id, name: unique, settings: session.current)) else { return false }
        session.markSaved(as: .user(id))
        reloadUserPresets()
        persistSettings()
        return true
    }

    private func write(_ preset: Preset) -> Bool {
        do {
            try presetStore.save(preset)
            return true
        } catch {
            report("Could not save preset: \(error.localizedDescription)")
            return false
        }
    }

    private func reloadUserPresets() {
        userPresets = presetStore.loadAll()
    }

    private func report(_ message: String) {
        presetLog.error("\(message, privacy: .public)")
        lastError = message
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

    private func applyToEngine() {
        engine.processor.update(settings: session.current, enabled: settings.effectEnabled)
    }
}
