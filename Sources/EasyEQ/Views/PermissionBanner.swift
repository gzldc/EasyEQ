import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

struct PermissionBanner: View {
    @ObservedObject var engine: SystemAudioEngine
    @EnvironmentObject private var localizer: Localizer

    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    var body: some View {
        if engine.state == .permissionDenied {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(localizer.t("permission.title"))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(localizer.t("permission.open")) {
                    NSWorkspace.shared.open(Self.settingsURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.15))
        }
    }
}
