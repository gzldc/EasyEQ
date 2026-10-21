import SwiftUI

/// Every color used by the UI, in a light and a dark variant. Views read tokens from here and never
/// hard-code colors. Obtain the active theme with `@Environment(\.theme)`; the root of each scene /
/// sheet applies `.themed()` so the theme follows the effective color scheme.
struct Theme {
    // Window and surfaces
    let backgroundColors: [Color]
    let sidebarFill: Color
    let cardFill: Color
    let cardStroke: Color
    let cardShadow: Color
    let cardShadowRadius: CGFloat
    let cardShadowOffset: CGFloat

    // Text
    let textPrimary: Color
    let textSecondary: Color

    // Accent
    let accentStart: Color
    let accentEnd: Color
    /// Small text in the accent hue (slider values, selected preset, links): readable on the surfaces.
    let accentText: Color

    // Controls
    let selectedRowFill: Color
    let selectedRowShadow: Color
    let hoverRowFill: Color
    let track: Color
    let segmentSelectedFill: Color
    let buttonFill: Color
    let hairline: Color
    let thumbFill: Color
    let thumbShadow: Color
    let onAccentText: Color

    // Status
    let warning: Color
    let warningFill: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Curve, slider fill, switch and save button.
    var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .leading, endPoint: .trailing)
    }

    var accentGradientVertical: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .top, endPoint: .bottom)
    }

    /// Dots in front of the built-in presets, in `BuiltInPreset.allCases` order (Voice, Voice+, Flat).
    static let builtInDots: [Color] = [0x6E7CFF, 0x9B7CFF, 0x45C9BA].map { Color(hex: $0) }

    /// User presets cycle through these in list order.
    static let userDots: [Color] = [0xFFB36B, 0xFF8FB1, 0x5BC0FF, 0x8BD86A, 0xC79BFF].map { Color(hex: $0) }

    static func userDot(at index: Int) -> Color { userDots[index % userDots.count] }

    static let corner: CGFloat = 14
    static let rowCorner: CGFloat = 9
    static let buttonCorner: CGFloat = 8

    static let light = Theme(
        backgroundColors: [Color(hex: 0xF6F8FF), Color(hex: 0xF9F6FF), Color(hex: 0xF4FBF9)],
        sidebarFill: .white.opacity(0.5),
        cardFill: .white.opacity(0.85),
        cardStroke: .clear,
        cardShadow: Color(hex: 0x3C46A0, opacity: 0.06),
        cardShadowRadius: 16,
        cardShadowOffset: 4,
        textPrimary: Color(hex: 0x1D2340),
        textSecondary: Color(hex: 0x6B7192),
        accentStart: Color(hex: 0x5A68F0),
        accentEnd: Color(hex: 0x2FA89B),
        accentText: Color(hex: 0x4A55D6),
        selectedRowFill: .white,
        selectedRowShadow: Color(hex: 0x3C46A0, opacity: 0.10),
        hoverRowFill: Color(hex: 0x1E285A, opacity: 0.04),
        track: Color(hex: 0x1E285A, opacity: 0.08),
        segmentSelectedFill: .white,
        buttonFill: .white.opacity(0.7),
        hairline: Color(hex: 0x1E285A, opacity: 0.08),
        thumbFill: .white,
        thumbShadow: Color(hex: 0x1E285A, opacity: 0.25),
        onAccentText: .white,
        warning: Color(hex: 0xD9772B),
        warningFill: Color(hex: 0xFFB36B, opacity: 0.22)
    )

    static let dark = Theme(
        backgroundColors: [Color(hex: 0x16182A), Color(hex: 0x1A1730), Color(hex: 0x121F1F)],
        sidebarFill: .white.opacity(0.04),
        cardFill: .white.opacity(0.06),
        cardStroke: .white.opacity(0.08),
        cardShadow: .clear,
        cardShadowRadius: 0,
        cardShadowOffset: 0,
        textPrimary: Color(hex: 0xECEEFA),
        textSecondary: Color(hex: 0x9AA0BF),
        accentStart: Color(hex: 0x8090FF),
        accentEnd: Color(hex: 0x52D6C7),
        accentText: Color(hex: 0x9AA6FF),
        selectedRowFill: .white.opacity(0.10),
        selectedRowShadow: .clear,
        hoverRowFill: .white.opacity(0.05),
        track: .white.opacity(0.12),
        segmentSelectedFill: .white.opacity(0.15),
        buttonFill: .white.opacity(0.08),
        hairline: .white.opacity(0.08),
        thumbFill: .white,
        thumbShadow: .black.opacity(0.4),
        onAccentText: Color(hex: 0x10122A),
        warning: Color(hex: 0xFFB36B),
        warningFill: Color(hex: 0xFFB36B, opacity: 0.14)
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct ThemedModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.theme, scheme == .dark ? .dark : .light)
    }
}

extension View {
    /// Injects the `Theme` matching the effective color scheme.
    func themed() -> some View { modifier(ThemedModifier()) }
}
