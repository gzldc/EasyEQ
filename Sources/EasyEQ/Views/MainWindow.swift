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
    @State private var sheet: NameSheetRequest?

    var body: some View {
        NavigationSplitView {
            PresetSidebar(model: model, present: { sheet = $0 })
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            VStack(spacing: 0) {
                PermissionBanner(engine: model.engine)
                EditorPane(model: model, present: { sheet = $0 })
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .sheet(item: $sheet) { request in
            NameSheet(model: model, request: request)
        }
        .alert(localizer.t("app.name"), isPresented: errorBinding) {
            Button(localizer.t("sheet.ok")) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onChange(of: model.showBuiltInReadOnlyHint) { _, shown in
            guard shown else { return }
            model.showBuiltInReadOnlyHint = false
            sheet = NameSheetRequest(mode: .saveAs,
                                     initial: model.displayName(for: model.session.selection),
                                     message: localizer.t("editor.builtInReadOnly"))
        }
        .onAppear { delegate.reopenMainWindow = { openWindow(id: "main") } }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } })
    }
}
