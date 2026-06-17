import SwiftUI

struct LiquidGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                LiquidGlassSurface(cornerRadius: cornerRadius)
            }
    }
}

private struct LiquidGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let surfaceTint = colorScheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.12).opacity(0.74)
            : Color(red: 0.97, green: 0.99, blue: 0.98).opacity(0.88)

        shape
            .fill(surfaceTint)
            .background {
                shape
                    .fill(.regularMaterial)
                    .opacity(colorScheme == .dark ? 0.68 : 0.42)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.20 : 0.42),
                                Color.cyan.opacity(colorScheme == .dark ? 0.06 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.46 : 0.92),
                                .white.opacity(colorScheme == .dark ? 0.18 : 0.36),
                                .black.opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.34 : 0.74), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 22, x: 0, y: 14)
            .shadow(color: .white.opacity(colorScheme == .dark ? 0.10 : 0.35), radius: 1, x: 0, y: -1)
    }
}

private struct FallbackGlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let active = isHovering && isEnabled
        let pressed = configuration.isPressed && isEnabled
        let enabledForeground: Color = prominent ? .white : .primary
        let disabledForeground: Color = colorScheme == .dark ? .white.opacity(0.36) : .black.opacity(0.34)
        let fill = prominent
            ? LinearGradient(
                colors: [
                    Color.accentColor.opacity(active ? 0.92 : 0.82),
                    Color.cyan.opacity(active ? 0.82 : 0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? (active ? 0.24 : 0.18) : (active ? 0.86 : 0.74)),
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? enabledForeground : disabledForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule(style: .continuous).fill(fill)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                prominent
                                    ? .white.opacity(pressed ? 0.88 : active ? 0.76 : 0.58)
                                    : .white.opacity(colorScheme == .dark ? (active ? 0.42 : 0.30) : (active ? 0.94 : 0.76)),
                                lineWidth: active ? 1.25 : 1
                            )
                    }
                    .shadow(
                        color: .black.opacity(pressed ? 0.07 : active ? 0.18 : 0.13),
                        radius: pressed ? 4 : active ? 16 : 10,
                        x: 0,
                        y: pressed ? 2 : active ? 10 : 7
                    )
            }
            .scaleEffect(pressed ? 0.965 : active ? 1.025 : 1)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: pressed)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: active)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 26, padding: CGFloat = 16) -> some View {
        modifier(LiquidGlassPanel(cornerRadius: cornerRadius, padding: padding))
    }

    @ViewBuilder
    func video2LiveGlassButtonStyle(prominent: Bool = false) -> some View {
        buttonStyle(FallbackGlassButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat? = nil) -> some View {
        self
    }
}
