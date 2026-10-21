import EasyEQCore
import SwiftUI

enum NameSheetMode: Equatable {
    case new
    case saveAs
    case rename(UUID)
    case newGroup
    case renameGroup(UUID)
    /// A new preset placed in the given group.
    case newPresetIn(UUID)
}

struct NameSheet: View {
    @ObservedObject var model: AppModel
    let request: NameSheetRequest
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(localizer.t(isGroupMode ? "sheet.groupName" : "sheet.name"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .focused($focused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .fill(theme.buttonFill)
                        .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                            .strokeBorder(focused ? theme.accentStart : theme.hairline, lineWidth: 1))
                )
            HStack(spacing: 8) {
                Spacer()
                Button(localizer.t("sheet.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SoftButtonStyle())
                Button(localizer.t("sheet.ok"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(isBlank)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(theme.backgroundGradient)
        .onAppear { focused = true }
    }

    private var isGroupMode: Bool {
        switch request.mode {
        case .newGroup, .renameGroup: return true
        default: return false
        }
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
        case .newGroup: model.createGroup(named: name)
        case .renameGroup(let id): model.renameGroup(id, to: name)
        case .newPresetIn(let groupID): model.newPreset(name: name, inGroup: groupID)
        }
        dismiss()
    }
}
