import EasyEQCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        Picker(localizer.t("settings.language"), selection: Binding(
            get: { model.settings.language },
            set: { model.setLanguage($0) })
        ) {
            Text(localizer.t("settings.system")).tag(LanguageChoice.system)
            Text("中文").tag(LanguageChoice.chinese)
            Text("English").tag(LanguageChoice.english)
        }
        .padding(24)
        .frame(width: 320)
    }
}
