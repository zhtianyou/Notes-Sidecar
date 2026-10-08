import SwiftUI

enum SidecarTheme: String, Sendable {
    case light
    case dark
    case technology

    var isDark: Bool { self != .light }
}

private struct SidecarThemeKey: EnvironmentKey {
    static let defaultValue: SidecarTheme = .light
}

extension EnvironmentValues {
    var sidecarTheme: SidecarTheme {
        get { self[SidecarThemeKey.self] }
        set { self[SidecarThemeKey.self] = newValue }
    }
}

/// `设计草图/liquid设计` 中定义的玻璃质感视觉令牌。
/// 青色只表达交互，绿色、黄色、红色只表达真实状态。
enum Tokens {
    enum Palette {
        // Figma “黑灰色 UI 设计规范” (26:6928 / 26:6972).
        static let darkCanvas = Color(hex: 0x1A1A1A)
        static let darkGlassBase = Color(hex: 0x0F0F0F)
        static let darkSurface = Color(hex: 0x202020)
        static let darkRaised = Color(hex: 0x262626)
        static let darkInset = Color(hex: 0x202020)
        static let darkPrimaryText = Color(hex: 0xF5F5F7)
        static let darkSecondaryText = Color(hex: 0xA1A1AA)
        static let darkPlaceholder = Color(hex: 0x98989F)
        static let darkBorder = Color.white.opacity(0.18)
        static let accentDark = Color(hex: 0xF2C76C)
        static let accentStrongDark = Color(hex: 0xFFD978)
        static let warningDark = Color(hex: 0xE6BB68)
        static let errorDark = Color(hex: 0xF28B91)
        static let successDark = Color(hex: 0x8CCFA6)

        // Existing blue-green dark palette is retained as the Technology theme.
        static let technologyCanvas = Color(hex: 0x0D1821)
        static let technologySurface = Color(hex: 0x182B37)
        static let technologyRaised = Color(hex: 0x203542)
        static let technologyInset = Color(hex: 0x213F4A)
        static let technologyBorder = Color(hex: 0x47616F)
        static let accentTechnology = Color(hex: 0x57D3DE)
        static let accentStrongTechnology = Color(hex: 0x7DE0E8)

        static let accentLight = Color(hex: 0x087E8B)
        static let accentStrongLight = Color(hex: 0x066C78)

        // 兼容旧的语义名称；新版统一为单一产品强调色。
        static let contextAmberLight = accentLight
        static let contextAmberDark = accentDark
        static let agentMintLight = accentLight
        static let agentMintDark = accentDark
        static let capabilityVioletLight = accentLight
        static let capabilityVioletDark = accentDark

        static let warningLight = Color(hex: 0x8C5C0B)
        static let errorLight = Color(hex: 0xB93545)
        static let successLight = Color(hex: 0x17754D)
        static let warning = warningDark
        static let error = errorDark
        static let success = successDark

        // Light theme from the light Figma specification.
        static let lightCanvas = Color(hex: 0xEDF3F6)
        static let lightSurface = Color(hex: 0xF6F9FB)
        static let lightRaised = Color.white
        static let lightInset = Color(hex: 0xE0F2F4)
        static let lightBorder = Color(hex: 0xCAD7DF)
        static let lightControlBorder = Color(hex: 0x7C929F)
        static let lightPlaceholder = Color(hex: 0x607785)
        static let lightDisabledFill = Color(hex: 0xE3EAF0)
        static let lightDisabledText = Color(hex: 0x73838E)
        static let lightSuccessFill = Color(hex: 0xE4F3EA)
        static let lightWarningFill = Color(hex: 0xFFF2D8)
        static let lightErrorFill = Color(hex: 0xFBE9EC)

        static let darkChrome = darkSurface
        static let hairline = darkBorder.opacity(0.72)

        static func canvas(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightCanvas; case .dark: darkCanvas; case .technology: technologyCanvas }
        }
        static func contentSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightSurface; case .dark: darkSurface; case .technology: technologySurface }
        }
        static func raisedSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightRaised; case .dark: darkRaised; case .technology: technologyRaised }
        }
        static func insetSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightInset; case .dark: darkInset; case .technology: technologyInset }
        }
        static func glassSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color.white.opacity(0.88); case .dark: darkGlassBase.opacity(0.88); case .technology: technologyRaised.opacity(0.88) }
        }
        static func workspaceGlassSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color.white.opacity(0.72); case .dark: darkGlassBase.opacity(0.72); case .technology: technologySurface.opacity(0.82) }
        }
        static func dialogGlassSurface(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color.white.opacity(0.92); case .dark: darkGlassBase.opacity(0.92); case .technology: technologyRaised.opacity(0.94) }
        }
        static func separator(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightBorder; case .dark: darkBorder; case .technology: technologyBorder.opacity(0.72) }
        }
        static func controlFill(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightSurface; case .dark: darkRaised; case .technology: technologyInset }
        }
        static func controlBorder(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightControlBorder; case .dark: darkBorder; case .technology: technologyBorder }
        }
        static func selectedFill(for scheme: SidecarTheme) -> Color {
            scheme == .light ? lightInset : accent(for: scheme).opacity(0.14)
        }
        static func disabledFill(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightDisabledFill; case .dark: Color(hex: 0x303030); case .technology: Color(hex: 0x2B3E49) }
        }
        static func disabledText(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightDisabledText; case .dark: Color(hex: 0x71717A); case .technology: Color(hex: 0x8297A3) }
        }
        static func placeholderText(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightPlaceholder; case .dark: darkPlaceholder; case .technology: Color(hex: 0x8FA7B5) }
        }
        static func hoverFill(for scheme: SidecarTheme) -> Color {
            accent(for: scheme).opacity(scheme == .light ? 0.09 : 0.12)
        }
        static func accent(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: accentLight; case .dark: accentDark; case .technology: accentTechnology }
        }
        static func accentStrong(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: accentStrongLight; case .dark: accentStrongDark; case .technology: accentStrongTechnology }
        }
        static func primaryHover(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color(hex: 0x066C78); case .dark: Color(hex: 0xFFD978); case .technology: Color(hex: 0x65DCE5) }
        }
        static func primaryPressed(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color(hex: 0x055762); case .dark: Color(hex: 0xD9AD55); case .technology: Color(hex: 0x41BBC7) }
        }
        static func secondaryHoverFill(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightCanvas; case .dark: Color(hex: 0x303030); case .technology: Color(hex: 0x294652) }
        }
        static func secondaryPressedFill(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: lightInset; case .dark: Color(hex: 0x363024); case .technology: Color(hex: 0x31525E) }
        }
        static func accentForeground(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: .white; case .dark: Color(hex: 0x241D0E); case .technology: Color(hex: 0x082B33) }
        }
        static func statusWarning(for scheme: SidecarTheme) -> Color {
            scheme == .light ? warningLight : warningDark
        }
        static func statusError(for scheme: SidecarTheme) -> Color {
            scheme == .light ? errorLight : errorDark
        }
        static func statusSuccess(for scheme: SidecarTheme) -> Color {
            scheme == .light ? successLight : successDark
        }
        static func statusFill(for color: StatusColor, scheme: SidecarTheme) -> Color {
            if scheme == .light {
                switch color { case .success: lightSuccessFill; case .warning: lightWarningFill; case .error: lightErrorFill }
            } else {
                switch color { case .success: statusSuccess(for: scheme).opacity(0.12); case .warning: statusWarning(for: scheme).opacity(0.12); case .error: statusError(for: scheme).opacity(0.12) }
            }
        }
        static func primaryText(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color(hex: 0x172B36); case .dark: darkPrimaryText; case .technology: Color(hex: 0xF0F6F9) }
        }
        static func secondaryText(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color(hex: 0x475E6B); case .dark: darkSecondaryText; case .technology: Color(hex: 0xB4C7D2) }
        }
        static func tertiaryText(for scheme: SidecarTheme) -> Color {
            switch scheme { case .light: Color(hex: 0x73838E); case .dark: darkPlaceholder; case .technology: Color(hex: 0x8FA7B5) }
        }
        static func contextAmber(for scheme: SidecarTheme) -> Color { accent(for: scheme) }
        static func agentMint(for scheme: SidecarTheme) -> Color { accent(for: scheme) }
        static func capabilityViolet(for scheme: SidecarTheme) -> Color { accent(for: scheme) }
        static func surface(for scheme: SidecarTheme) -> Color { contentSurface(for: scheme) }
    }

    enum Font {
        static let pageTitle: CGFloat = 28
        static let headerTitle: CGFloat = 20
        static let sectionTitle: CGFloat = 18
        static let answer: CGFloat = 14
        static let body: CGFloat = 14
        static let label: CGFloat = 13
        static let meta: CGFloat = 12
        static let code: CGFloat = 12
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    enum Radius {
        static let inner: CGFloat = 8
        static let input: CGFloat = 10
        static let card: CGFloat = 12
        static let panel: CGFloat = 16
        static let chip: CGFloat = 999
        static let orb: CGFloat = 18
    }

    enum StatusColor {
        case success, warning, error
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
