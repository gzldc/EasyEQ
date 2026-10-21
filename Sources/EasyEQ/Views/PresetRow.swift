import SwiftUI

/// One sidebar entry: color dot + name. The selected row is a white card (light) / white 10% (dark).
struct PresetRow: View {
    let title: String
    let dot: Color
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? theme.accentStart : theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(isSelected ? theme.selectedRowFill : (hovering ? theme.hoverRowFill : .clear))
                    .shadow(color: isSelected ? theme.selectedRowShadow : .clear, radius: 6, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
