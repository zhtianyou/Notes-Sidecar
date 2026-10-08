import SwiftUI

// Liquid Glass 风格：macOS 26 用原生 .glassEffect，旧系统回退 NSVisualEffectView 视觉近似。
enum GlassLevel {
    case regular
    case chrome
    case overlay
}

struct GlassStyle: ViewModifier {
    let level: GlassLevel
    let corner: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.sidecarTheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Tokens.Palette.raisedSurface(for: scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1)
                        )
                }
        } else if #available(macOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(surfaceFill)
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(
                            level == .chrome
                                ? Tokens.Palette.accent(for: scheme).opacity(contrast == .increased ? 0.72 : 0.34)
                                : Tokens.Palette.separator(for: scheme),
                            lineWidth: 1
                        )
                }
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(surfaceFill)
                        .background(FallbackGlass(level: level, corner: corner))
                        .overlay {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .stroke(
                                    level == .chrome
                                        ? Tokens.Palette.accent(for: scheme).opacity(0.34)
                                        : Tokens.Palette.separator(for: scheme),
                                    lineWidth: 1
                                )
                        }
                }
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        }
    }

    private var surfaceFill: Color {
        switch level {
        case .regular: return Tokens.Palette.glassSurface(for: scheme)
        case .chrome: return Tokens.Palette.workspaceGlassSurface(for: scheme)
        case .overlay: return Tokens.Palette.dialogGlassSurface(for: scheme)
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(scheme.isDark ? 0.18 : (level == .overlay ? 0.16 : level == .chrome ? 0.12 : 0.06))
    }

    private var shadowRadius: CGFloat {
        switch level { case .regular: return 8; case .chrome: return 24; case .overlay: return 48 }
    }

    private var shadowY: CGFloat {
        switch level { case .regular: return 2; case .chrome: return 8; case .overlay: return 16 }
    }
}

struct FallbackGlass: NSViewRepresentable {
    let level: GlassLevel
    let corner: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.state = .active
        v.blendingMode = .behindWindow
        v.isEmphasized = (level == .chrome)
        v.wantsLayer = true
        v.layer?.cornerRadius = corner
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = .active
        nsView.isEmphasized = (level == .chrome)
        nsView.layer?.cornerRadius = corner
    }

    private var material: NSVisualEffectView.Material {
        switch level {
        case .regular: return .sidebar
        case .chrome:  return .headerView
        case .overlay: return .menu
        }
    }
}

extension View {
    func glass(level: GlassLevel = .regular, corner: CGFloat = Tokens.Radius.card) -> some View {
        modifier(GlassStyle(level: level, corner: corner))
    }

    /// Input treatment from the liquid specification: quiet fill, one-pixel
    /// outline and no nested system bezel.
    func liquidField(horizontal: CGFloat = 12, vertical: CGFloat = 8) -> some View {
        modifier(LiquidFieldModifier(horizontal: horizontal, vertical: vertical))
    }
}

private struct LiquidFieldModifier: ViewModifier {
    let horizontal: CGFloat
    let vertical: CGFloat
    @Environment(\.sidecarTheme) private var scheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
            .tint(Tokens.Palette.accent(for: scheme))
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.input, style: .continuous)
                    .fill(Tokens.Palette.controlFill(for: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.input, style: .continuous)
                            .stroke(Tokens.Palette.controlBorder(for: scheme), lineWidth: 1)
                    )
            )
    }
}

// 主行动胶囊（min-cap 主按钮）
struct LuminousDot: View {
    let color: Color
    var active: Bool = true
    var size: CGFloat = Tokens.Radius.orb
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.95 : 0.45))
                .frame(width: size, height: size)
            if active {
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 1)
                    .frame(width: size + 10, height: size + 10)
            }
        }
    }
}
