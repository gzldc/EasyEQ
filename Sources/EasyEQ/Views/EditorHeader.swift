import EasyEQCore
import SwiftUI

/// Preset name (+ one-line description for built-ins), band-count pill and effect switch.
struct EditorHeader: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    var body: some View {
        let session = model.session
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName(for: session.selection))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if session.isDirty {
                        Circle().fill(theme.warning).frame(width: 8, height: 8)
                    }
                }
                if case .builtIn(let preset) = session.selection {
                    Text(localizer.t(preset.descriptionKey))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(localizer.t("editor.bands"))
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            BandCountPicker(selection: session.current.layout) { layout in
                guard layout != model.session.current.layout else { return }
                withAnimation(.easeOut(duration: 0.2)) { model.switchLayout(layout) }
            }
            Button(localizer.t("editor.smooth")) {
                withAnimation(.easeOut(duration: 0.2)) { model.smoothCurve() }
            }
            .buttonStyle(SoftButtonStyle(small: true))
            .fixedSize()
            .disabled(session.current.smoothed() == session.current)
            Button(localizer.t("editor.zero")) {
                withAnimation(.easeOut(duration: 0.2)) { model.zeroAllBands() }
            }
            .buttonStyle(SoftButtonStyle(small: true))
            .fixedSize()
            .disabled(session.current == session.current.zeroed())
            Toggle(localizer.t("editor.effect"), isOn: Binding(
                get: { model.settings.effectEnabled },
                set: { model.setEffectEnabled($0) })
            )
            .toggleStyle(GradientSwitchStyle())
        }
    }
}
