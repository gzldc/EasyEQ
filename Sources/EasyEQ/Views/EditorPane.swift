import EasyEQAudio
import EasyEQCore
import SwiftUI

struct EditorPane: View {
    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        let session = model.session
        let layout = session.current.layout
        VStack(spacing: 12) {
            header(session: session, layout: layout)
            CurveView(settings: session.current)
                .frame(height: 120)
            sliders(session: session, layout: layout)
            footer(session: session)
        }
        .padding(layout == .thirtyOne ? 12 : 20)
    }

    private func header(session: EditingSession, layout: BandLayout) -> some View {
        HStack(spacing: 8) {
            Text(model.displayName(for: session.selection))
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            if session.isDirty {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
            }
            Spacer(minLength: 8)
            Text(localizer.t("editor.bands"))
                .foregroundStyle(.secondary)
            Picker(localizer.t("editor.bands"), selection: Binding(
                get: { model.session.current.layout },
                set: { model.switchLayout($0) })
            ) {
                ForEach(BandLayout.allCases, id: \.self) { Text(String($0.bandCount)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Toggle(localizer.t("editor.effect"), isOn: Binding(
                get: { model.settings.effectEnabled },
                set: { model.setEffectEnabled($0) })
            )
            .toggleStyle(.switch)
        }
    }

    private func sliders(session: EditingSession, layout: BandLayout) -> some View {
        let frequencies = layout.frequencies
        let gains = session.current.gains
        return HStack(alignment: .top, spacing: layout == .thirtyOne ? 0 : 2) {
            ForEach(Array(frequencies.enumerated()), id: \.offset) { index, hz in
                let zone = localizer.t(BandLayout.zoneKey(forFrequency: hz))
                BandSlider(
                    value: index < gains.count ? gains[index] : 0,
                    frequency: hz,
                    label: layout == .ten ? zone : nil,
                    tooltip: layout == .ten ? nil : zone,
                    compact: layout == .thirtyOne,
                    onChange: { model.setGain($0, at: index) },
                    onReset: { model.resetBand(at: index) }
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func footer(session: EditingSession) -> some View {
        HStack {
            DeviceFooter(engine: model.engine)
            Spacer()
            Button(localizer.t("editor.saveAs")) {
                present(NameSheetRequest(mode: .saveAs, initial: model.displayName(for: session.selection)))
            }
            Button(localizer.t("editor.revert")) { model.revert() }
                .disabled(!session.isDirty)
            Button(localizer.t("editor.save")) { model.save() }
        }
    }
}

/// Output device name; observes the engine so it follows device changes.
private struct DeviceFooter: View {
    @ObservedObject var engine: SystemAudioEngine
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var text: String {
        if case .running(let deviceName) = engine.state {
            return String(format: localizer.t("device.output"), deviceName)
        }
        return ""
    }
}
