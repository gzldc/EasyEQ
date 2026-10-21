import EasyEQCore
import SwiftUI

enum NameSheetMode: Equatable {
    case new
    case saveAs
    case rename(UUID)
}

struct NameSheet: View {
    @ObservedObject var model: AppModel
    let request: NameSheetRequest
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool

    init(model: AppModel, request: NameSheetRequest) {
        self.model = model
        self.request = request
        _name = State(initialValue: request.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = request.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(localizer.t("sheet.name"))
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button(localizer.t("sheet.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(localizer.t("sheet.ok"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBlank)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit() {
        guard !isBlank else { return }
        switch request.mode {
        case .new: model.newPreset(name: name)
        case .saveAs: model.saveAs(name: name)
        case .rename(let id): model.rename(id, to: name)
        }
        dismiss()
    }
}
