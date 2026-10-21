import SwiftUI
import EasyEQAudio
import EasyEQCore

// Temporary wiring for the Task 7 manual check; Task 8 replaces it with the real UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = SystemAudioEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.processor.update(settings: BuiltInPreset.voice.settings(for: .ten), enabled: true)
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}

struct EngineStateView: View {
    @ObservedObject var engine: SystemAudioEngine

    var body: some View {
        Text(String(describing: engine.state))
            .padding(24)
            .frame(minWidth: 320)
    }
}

@main
struct EasyEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("EasyEQ", id: "main") {
            EngineStateView(engine: delegate.engine)
        }
    }
}
