import EasyEQCore
import SwiftUI

struct PresetSidebar: View {
    static let width: CGFloat = 176

    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle(localizer.t("sidebar.builtIn"))
                    ForEach(Array(BuiltInPreset.allCases.enumerated()), id: \.element) { index, preset in
                        row(.builtIn(preset), title: localizer.t(preset.nameKey), dot: Theme.builtInDots[index])
                    }
                    sectionTitle(localizer.t("sidebar.mine")).padding(.top, 14)
                    ForEach(Array(sortedUserPresets.enumerated()), id: \.element.id) { index, preset in
                        row(.user(preset.id), title: preset.name, dot: Theme.userDot(at: index))
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
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            Button {
                present(NameSheetRequest(mode: .new))
            } label: {
                Label(localizer.t("sidebar.new"), systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        // Clears the traffic lights, which float over the hidden title bar.
        .padding(.top, 38)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(theme.sidebarFill.ignoresSafeArea())
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func row(_ ref: PresetRef, title: String, dot: Color) -> some View {
        PresetRow(title: title, dot: dot, isSelected: model.session.selection == ref) {
            select(ref)
        }
    }

    private var sortedUserPresets: [Preset] {
        model.userPresets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Re-selecting the current preset must not discard unsaved edits, so it is ignored.
    private func select(_ ref: PresetRef) {
        guard ref != model.session.selection else { return }
        withAnimation(.easeOut(duration: 0.2)) { model.select(ref) }
    }
}
