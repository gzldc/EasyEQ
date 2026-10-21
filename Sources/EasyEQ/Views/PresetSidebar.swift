import EasyEQCore
import SwiftUI

struct PresetSidebar: View {
    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                Section(localizer.t("sidebar.builtIn")) {
                    ForEach(BuiltInPreset.allCases, id: \.self) { preset in
                        Text(localizer.t(preset.nameKey))
                            .tag(PresetRef.builtIn(preset))
                    }
                }
                Section(localizer.t("sidebar.mine")) {
                    ForEach(sortedUserPresets) { preset in
                        Text(preset.name)
                            .tag(PresetRef.user(preset.id))
                            .contextMenu {
                                Button(localizer.t("menu.rename")) {
                                    present(NameSheetRequest(mode: .rename(preset.id), initial: preset.name))
                                }
                                Button(localizer.t("menu.delete"), role: .destructive) {
                                    model.delete(preset.id)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Button {
                present(NameSheetRequest(mode: .new))
            } label: {
                Label(localizer.t("sidebar.new"), systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var sortedUserPresets: [Preset] {
        model.userPresets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Re-selecting the current preset must not discard unsaved edits, so it is ignored.
    private var selectionBinding: Binding<PresetRef?> {
        Binding(get: { model.session.selection },
                set: { newValue in
                    guard let newValue, newValue != model.session.selection else { return }
                    model.select(newValue)
                })
    }
}
