import EasyEQCore
import SwiftUI

struct PresetSidebar: View {
    static let width: CGFloat = 176

    @ObservedObject var model: AppModel
    let present: (NameSheetRequest) -> Void
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.theme) private var theme
    /// Bumped on each click so the key catcher takes first responder again.
    @State private var keyActivation = 0

    private static let collapseAnimation = Animation.easeOut(duration: 0.2)

    var body: some View {
        let sorted = sortedUserPresets
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    GroupHeader(title: localizer.t("sidebar.builtIn"),
                                isCollapsed: builtInCollapsed,
                                onToggle: { toggle(GroupLayout.builtInSectionKey) })
                    if !builtInCollapsed {
                        ForEach(Array(BuiltInPreset.allCases.enumerated()), id: \.element) { index, preset in
                            row(.builtIn(preset), title: localizer.t(preset.nameKey), dot: Theme.builtInDots[index])
                        }
                    }

                    GroupHeader(title: localizer.t("sidebar.mine"),
                                onDropPreset: { drop($0, toGroup: nil) })
                        .padding(.top, 10)
                    ForEach(ungroupedPresets) { preset in
                        userRow(preset, in: sorted)
                    }

                    ForEach(model.groupLayout.groups) { group in
                        let collapsed = model.groupLayout.isCollapsed(group.id.uuidString)
                        let members = members(of: group)
                        GroupHeader(title: group.name,
                                    count: members.count,
                                    isCollapsed: collapsed,
                                    onToggle: { toggle(group.id.uuidString) },
                                    onDropPreset: { drop($0, toGroup: group.id) })
                            .padding(.top, 6)
                            .contextMenu { groupMenu(group) }
                        if !collapsed {
                            ForEach(members) { preset in
                                userRow(preset, in: sorted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            addMenu
        }
        // Arrow keys move the selection through the same guard as clicks.
        .background(ArrowKeyCatcher(onMove: { moveSelection(by: $0) }, activation: keyActivation))
        // Clears the traffic lights, which float over the hidden title bar.
        .padding(.top, 38)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(theme.sidebarFill.ignoresSafeArea())
        .confirmationDialog(
            String(format: localizer.t("confirm.deletePreset.title"), model.pendingDelete?.name ?? ""),
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: model.pendingDelete
        ) { preset in
            Button(localizer.t("confirm.delete"), role: .destructive) {
                model.deletePresetConfirmed(preset.id)
            }
            Button(localizer.t("sheet.cancel"), role: .cancel) {}
        } message: { _ in
            Text(localizer.t("confirm.deletePreset.message"))
        }
    }

    // MARK: - Pieces

    private var addMenu: some View {
        Menu {
            Button(localizer.t("sidebar.new")) { present(NameSheetRequest(mode: .new)) }
            Button(localizer.t("sidebar.newGroup")) { present(NameSheetRequest(mode: .newGroup)) }
            Divider()
            Button(localizer.t("sidebar.import")) { model.importPresets() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 12)
        .accessibilityLabel(localizer.t("sidebar.new"))
    }

    private func row(_ ref: PresetRef, title: String, dot: Color) -> some View {
        PresetRow(title: title, dot: dot, isSelected: model.session.selection == ref) {
            select(ref)
        }
    }

    private func userRow(_ preset: Preset, in sorted: [Preset]) -> some View {
        let index = sorted.firstIndex(where: { $0.id == preset.id }) ?? 0
        return row(.user(preset.id), title: preset.name, dot: Theme.userDot(at: index))
            .draggable(preset.id.uuidString)
            .contextMenu { presetMenu(preset) }
    }

    @ViewBuilder
    private func presetMenu(_ preset: Preset) -> some View {
        Button(localizer.t("menu.rename")) {
            present(NameSheetRequest(mode: .rename(preset.id), initial: preset.name))
        }
        if !model.groupLayout.groups.isEmpty {
            let current = effectiveGroupID(of: preset)
            Menu(localizer.t("menu.moveToGroup")) {
                ForEach(model.groupLayout.groups) { group in
                    Button {
                        model.move(preset.id, toGroup: group.id)
                    } label: {
                        if current == group.id { Label(group.name, systemImage: "checkmark") } else { Text(group.name) }
                    }
                }
                Divider()
                Button {
                    model.move(preset.id, toGroup: nil)
                } label: {
                    if current == nil { Label(localizer.t("menu.ungrouped"), systemImage: "checkmark") }
                    else { Text(localizer.t("menu.ungrouped")) }
                }
            }
        }
        Button(localizer.t("menu.export")) { model.exportPreset(preset.id) }
        Divider()
        Button(localizer.t("menu.delete"), role: .destructive) { model.pendingDelete = preset }
    }

    @ViewBuilder
    private func groupMenu(_ group: PresetGroup) -> some View {
        Button(localizer.t("menu.renameGroup")) {
            present(NameSheetRequest(mode: .renameGroup(group.id), initial: group.name))
        }
        Button(localizer.t("menu.newPresetHere")) {
            present(NameSheetRequest(mode: .newPresetIn(group.id)))
        }
        Divider()
        // Deleting a group never deletes its presets, so no confirmation is needed.
        Button(localizer.t("menu.deleteGroup"), role: .destructive) { model.deleteGroup(group.id) }
    }

    // MARK: - Data

    private var builtInCollapsed: Bool { model.groupLayout.isCollapsed(GroupLayout.builtInSectionKey) }

    private var sortedUserPresets: [Preset] {
        model.userPresets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "My Presets": ungrouped presets plus orphans of deleted groups.
    private var ungroupedPresets: [Preset] {
        GroupLayout.members(of: nil, in: model.userPresets, validGroups: model.groupLayout.groups)
    }

    private func members(of group: PresetGroup) -> [Preset] {
        GroupLayout.members(of: group.id, in: model.userPresets, validGroups: model.groupLayout.groups)
    }

    /// The group a preset is shown in; `nil` for ungrouped and for orphans of deleted groups.
    private func effectiveGroupID(of preset: Preset) -> UUID? {
        guard let id = preset.groupID, model.groupLayout.groups.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Every preset in on-screen order, ignoring collapsed sections.
    private var fullOrderRefs: [PresetRef] {
        BuiltInPreset.allCases.map { PresetRef.builtIn($0) }
            + ungroupedPresets.map { PresetRef.user($0.id) }
            + model.groupLayout.groups.flatMap { members(of: $0).map { PresetRef.user($0.id) } }
    }

    /// Presets currently shown, in on-screen order (skips collapsed sections).
    private var visibleRefs: [PresetRef] {
        var refs: [PresetRef] = []
        if !builtInCollapsed { refs += BuiltInPreset.allCases.map { PresetRef.builtIn($0) } }
        refs += ungroupedPresets.map { PresetRef.user($0.id) }
        for group in model.groupLayout.groups where !model.groupLayout.isCollapsed(group.id.uuidString) {
            refs += members(of: group).map { PresetRef.user($0.id) }
        }
        return refs
    }

    // MARK: - Actions

    private func toggle(_ key: String) {
        keyActivation += 1
        withAnimation(Self.collapseAnimation) { model.toggleCollapsed(key) }
    }

    /// Drops carry the preset id as a string; anything else is ignored.
    private func drop(_ items: [String], toGroup groupID: UUID?) -> Bool {
        let ids = items.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return false }
        withAnimation(Self.collapseAnimation) {
            for id in ids { model.move(id, toGroup: groupID) }
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        // A hidden selection (collapsed section) steps to the nearest visible neighbour.
        guard let next = SidebarOrder.nextVisible(from: model.session.selection, delta: delta,
                                                  fullOrder: fullOrderRefs, visible: visibleRefs) else { return }
        select(next)
    }

    /// Re-selecting the current preset must not discard unsaved edits, so it is ignored.
    private func select(_ ref: PresetRef) {
        keyActivation += 1   // so arrow keys keep working after a click
        guard ref != model.session.selection else { return }
        withAnimation(.easeOut(duration: 0.2)) { model.select(ref) }
    }
}
