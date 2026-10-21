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
    @State private var targeted = false

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(targeted ? theme.hoverRowFill : .clear)
            )
            .contentShape(Rectangle())
            .modifier(DropModifier(onDrop: onDropPreset, targeted: $targeted))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        if let isCollapsed {
            Button(action: onToggle) { label(chevron: isCollapsed ? 0 : 90) }
                .buttonStyle(.plain)
                .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
        } else {
            label(chevron: nil)
        }
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
        .contentShape(Rectangle())
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
