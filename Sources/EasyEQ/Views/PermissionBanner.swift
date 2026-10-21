import AppKit
import EasyEQAudio
import EasyEQCore
import SwiftUI

struct PermissionBanner: View {
    @ObservedObject var engine: SystemAudioEngine
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    var body: some View {
        if engine.state == .permissionDenied {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                Text(localizer.t("permission.title"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(localizer.t("permission.open")) {
                    NSWorkspace.shared.open(Self.settingsURL)
                }
                .buttonStyle(SoftButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(theme.warningFill))
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }
}
