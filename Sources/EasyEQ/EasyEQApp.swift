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

        Settings {
            SettingsView(model: delegate.model)
                .environmentObject(delegate.model.localizer)
                .themed()
        }
    }
}
