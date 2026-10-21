import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    /// Installed by the main window's content so the Dock icon can bring a closed window back.
    var reopenMainWindow: (() -> Void)?

    override init() {
        super.init()
        // Opening a sheet from a menu command must work even when the window was closed.
        model.requestMainWindow = { [weak self] in
            self?.reopenMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

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
        // Destroys the tap first (un-muting system audio). Bounded, so a hung coreaudiod cannot block quitting.
        model.engine.stopForTermination(timeout: 2)
    }
}

/// File-menu commands: New Preset, Save, Save As, and the effect toggle.
struct EasyEQCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var localizer: Localizer

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(localizer.t("menu.newPreset")) {
                model.pendingSheet = NameSheetRequest(mode: .new)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(model.isModalPresented)
        }
        CommandGroup(after: .saveItem) {
            Button(localizer.t("menu.save")) { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.isModalPresented)
            Button(localizer.t("menu.saveAs")) { model.presentSaveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.isModalPresented)
            Divider()
            Button(localizer.t("menu.toggleEffect")) { model.toggleEffect() }
                .keyboardShortcut("e", modifiers: .command)
        }
    }
}

@main
struct EasyEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("EasyEQ", id: "main") {
            MainWindow(model: delegate.model, delegate: delegate)
                .environmentObject(delegate.model.localizer)
                .themed()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { EasyEQCommands(model: delegate.model, localizer: delegate.model.localizer) }

        Settings {
            SettingsView(model: delegate.model)
                .environmentObject(delegate.model.localizer)
                .themed()
        }
    }
}
