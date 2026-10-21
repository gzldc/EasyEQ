import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    /// Installed by the main window's content so the Dock icon can bring a closed window back.
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model.start()
    }

    /// Closing the window must not quit: the EQ keeps running in the background.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenMainWindow?() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.engine.stop()
    }
}

// Stub views; the real UI is built in Task 9.
private struct EngineStateText: View {
    @ObservedObject var engine: SystemAudioEngine

    var body: some View {
        Text(String(describing: engine.state)).foregroundStyle(.secondary)
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text(model.displayName(for: model.session.selection)).font(.title2)
            Toggle("Effect", isOn: Binding(get: { model.settings.effectEnabled },
                                           set: { model.setEffectEnabled($0) }))
                .toggleStyle(.switch)
            EngineStateText(engine: model.engine)
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 460)
        .onAppear { delegate.reopenMainWindow = { openWindow(id: "main") } }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Picker("Language", selection: Binding(get: { model.settings.language },
                                              set: { model.setLanguage($0) })) {
            ForEach(LanguageChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .padding(24)
        .frame(width: 320)
    }
}

@main
struct EasyEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("EasyEQ", id: "main") {
            MainView(model: delegate.model, delegate: delegate)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
