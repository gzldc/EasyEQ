import SwiftUI

/// Rounded card surface (14 pt): translucent white in light mode with a soft shadow, a faint white fill with an
/// inner hairline in dark mode.
private struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(theme.cardFill)
                    .shadow(color: theme.cardShadow, radius: theme.cardShadowRadius, y: theme.cardShadowOffset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Light-background button (Save As, Revert, Retry, Open System Settings, Cancel).
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(theme.buttonFill)
                    .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// Accent-gradient pill (Save, OK).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.onAccentText)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.accentGradient))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Inline text link in the accent color.
struct AccentLinkStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(theme.accentText)
            .underline(configuration.isPressed)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Switch whose "on" track is the accent gradient.
struct GradientSwitchStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                configuration.label
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textSecondary)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(theme.track)
                    Capsule().fill(theme.accentGradient).opacity(configuration.isOn ? 1 : 0)
                    Circle()
                        .fill(theme.thumbFill)
                        .shadow(color: theme.thumbShadow.opacity(0.6), radius: 1.5, y: 1)
                        .padding(2)
                }
                .frame(width: 38, height: 22)
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
