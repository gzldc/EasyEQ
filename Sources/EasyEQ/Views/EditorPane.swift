import EasyEQCore
import SwiftUI

struct EditorPane: View {
    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void

    var body: some View {
        let session = model.session
        let compact = session.current.layout == .thirtyOne
        VStack(spacing: 14) {
            EditorHeader(model: model)
            CurveView(settings: session.current, onPaint: { model.setGains($0) })
                .frame(height: 120)
                .padding(10)
                .card()
            BandStrip(model: model)
                .padding(.horizontal, compact ? 8 : 14)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)
                .card()
            EditorFooter(model: model, present: present)
        }
        .padding(.horizontal, compact ? 16 : 22)
        .padding(.bottom, 16)
    }
}
