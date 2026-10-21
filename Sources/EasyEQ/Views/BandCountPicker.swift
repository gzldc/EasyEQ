import EasyEQCore
import SwiftUI

/// Pill-shaped segmented control for the band count (10 / 15 / 31).
struct BandCountPicker: View {
    let selection: BandLayout
    let onSelect: (BandLayout) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BandLayout.allCases, id: \.self) { layout in
                let selected = layout == selection
                Button { onSelect(layout) } label: {
                    Text(String(layout.bandCount))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                        .frame(minWidth: 30)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selected ? theme.segmentSelectedFill : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.track))
        .accessibilityElement(children: .contain)
    }
}
