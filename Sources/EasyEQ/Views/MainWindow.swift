import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

/// A request to show `NameSheet`, shared by the sidebar (new / rename) and the editor (save as).
struct NameSheetRequest: Identifiable {
    let id = UUID()
    let mode: NameSheetMode
    var initial: String = ""
    /// Optional explanatory line shown above the text field (e.g. the built-in read-only hint).
    var message: String?
}

struct MainWindow: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            PresetSidebar(model: model, present: { model.pendingSheet = $0 })
            VStack(spacing: 0) {
                PermissionBanner(engine: model.engine)
                EditorPane(model: model, present: { model.pendingSheet = $0 })
            }
            // Clears the traffic lights, which float over the hidden title bar.
            .padding(.top, 28)
        }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 560)
        .sheet(item: $model.pendingSheet) { request in
            NameSheet(model: model, request: request)
        }
        .alert(localizer.t("app.name"), isPresented: errorBinding) {
            Button(localizer.t("sheet.ok")) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onAppear { delegate.reopenMainWindow = { openWindow(id: "main") } }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } })
    }
}
