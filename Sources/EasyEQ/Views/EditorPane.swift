import EasyEQCore
import SwiftUI

struct EditorPane: View {
    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        let session = model.session
        let layout = session.current.layout
        let compact = layout == .thirtyOne
        VStack(spacing: 14) {
            EditorHeader(model: model)
            CurveView(settings: session.current)
                .frame(height: 120)
                .padding(10)
                .card()
            sliders(session: session, layout: layout)
                .padding(.horizontal, compact ? 8 : 14)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)
                .card()
            EditorFooter(model: model, present: present)
        }
        .padding(.horizontal, compact ? 16 : 22)
        .padding(.bottom, 16)
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
    }
}
