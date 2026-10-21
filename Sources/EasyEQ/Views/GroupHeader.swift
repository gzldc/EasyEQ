import EasyEQCore
import SwiftUI

/// A sidebar section title. Collapsible headers (Built-in, user groups) show a chevron and toggle on click;
/// `isCollapsed == nil` is a plain title (My Presets). Passing `onDropPreset` makes it a drop target for
/// dragged user presets.
struct GroupHeader: View {
    let title: String
    var count: Int?
    var isCollapsed: Bool?
    var onToggle: () -> Void = {}
    var onDropPreset: (([String]) -> Bool)?
    @Environment(\.theme) private var theme
    @EnvironmentObject private var localizer: Localizer
    @State private var targeted = false

    var body: some View {
        content
            .modifier(DropModifier(onDrop: onDropPreset, targeted: $targeted))
    }

    @ViewBuilder
    private var content: some View {
        if let isCollapsed {
            Button(action: onToggle) { row(chevron: isCollapsed ? 0 : 90) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue(isCollapsed: isCollapsed))
                .accessibilityAddTraits(.isHeader)
        } else {
            row(chevron: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func accessibilityValue(isCollapsed: Bool) -> String {
        let state = localizer.t(isCollapsed ? "a11y.collapsed" : "a11y.expanded")
        guard let count else { return state }
        return "\(String(format: localizer.t("a11y.presetCount"), count)), \(state)"
    }

    /// The whole padded row is the hit area.
    private func row(chevron: Double?) -> some View {
        label(chevron: chevron)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(targeted ? theme.hoverRowFill : .clear)
            )
            .contentShape(Rectangle())
    }

    private func label(chevron: Double?) -> some View {
        HStack(spacing: 6) {
            Group {
                if let chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(chevron))
                } else {
                    Color.clear
                }
            }
            .frame(width: 10)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .opacity(0.8)
            }
        }
        .foregroundStyle(theme.textSecondary)
    }
}

private struct DropModifier: ViewModifier {
    let onDrop: (([String]) -> Bool)?
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if let onDrop {
            content.dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}
