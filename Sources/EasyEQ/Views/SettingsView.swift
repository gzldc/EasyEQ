import EasyEQCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            row(localizer.t("settings.language")) {
                Picker(localizer.t("settings.language"), selection: Binding(
                    get: { model.settings.language },
                    set: { model.setLanguage($0) })
                ) {
                    Text(localizer.t("settings.system")).tag(LanguageChoice.system)
                    Text("中文").tag(LanguageChoice.chinese)
                    Text("English").tag(LanguageChoice.english)
                }
            }
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.horizontal, 16)
            row(localizer.t("settings.appearance")) {
                Picker(localizer.t("settings.appearance"), selection: Binding(
                    get: { model.settings.appearance },
                    set: { model.setAppearance($0) })
                ) {
                    Text(localizer.t("settings.system")).tag(AppearanceChoice.system)
                    Text(localizer.t("appearance.light")).tag(AppearanceChoice.light)
                    Text(localizer.t("appearance.dark")).tag(AppearanceChoice.dark)
                }
            }
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(localizer.t("settings.launchAtLogin"))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 12)
                    Toggle(localizer.t("settings.launchAtLogin"), isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.accentStart)
                    .disabled(!model.launchAtLoginAvailable)
                }
                if !model.launchAtLoginAvailable {
                    Text(localizer.t("settings.launchAtLogin.moveHint"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message = model.loginItemError {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .card()
        .padding(24)
        .frame(width: 340)
        .background(theme.backgroundGradient.ignoresSafeArea())
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .tint(theme.accentStart)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
