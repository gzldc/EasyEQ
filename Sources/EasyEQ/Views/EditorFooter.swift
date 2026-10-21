import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

/// Bottom row: output device / engine status on the left, Save As / Revert / Save on the right.
struct EditorFooter: View {
    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        let session = model.session
        HStack(spacing: 8) {
            DeviceFooter(engine: model.engine)
            Spacer(minLength: 12)
            Button(localizer.t("editor.saveAs")) {
                present(NameSheetRequest(mode: .saveAs, initial: model.displayName(for: session.selection)))
            }
            .buttonStyle(SoftButtonStyle())
            Button(localizer.t("editor.revert")) {
                withAnimation(.easeOut(duration: 0.2)) { model.revert() }
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(!session.isDirty)
            Button(localizer.t("editor.save")) { model.save() }
                .buttonStyle(AccentButtonStyle())
        }
    }
}

/// Output device name; observes the engine so it follows device changes.
private struct DeviceFooter: View {
    @ObservedObject var engine: SystemAudioEngine
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(isFailed ? theme.warning : theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if isFailed {
                Button(localizer.t("engine.retry")) { engine.retry() }
                    .buttonStyle(SoftButtonStyle())
            }
            // Low-key hint: silence while other apps hold output streams is also the normal idle state.
            if engine.permissionSuspected && engine.state != .permissionDenied {
                Button(localizer.t("permission.check")) {
                    NSWorkspace.shared.open(PermissionBanner.settingsURL)
                }
                .buttonStyle(AccentLinkStyle())
            }
        }
    }

    private var dotColor: Color {
        switch engine.state {
        case .running: return theme.accentEnd
        case .failed: return theme.warning
        case .starting, .stopped, .permissionDenied: return theme.textSecondary.opacity(0.5)
        }
    }

    private var text: String {
        switch engine.state {
        case .running(let deviceName): return String(format: localizer.t("device.output"), deviceName)
        case .starting: return localizer.t("engine.starting")
        case .failed: return localizer.t("engine.failed")   // the technical reason is in the log, not the UI
        case .stopped, .permissionDenied: return ""
        }
    }

    private var isFailed: Bool {
        if case .failed = engine.state { return true }
        return false
    }
}
