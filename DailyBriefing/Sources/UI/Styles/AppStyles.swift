import SwiftUI

// MARK: - TUI Design System

// MARK: - TUI Panel Style

struct TUIPanelStyle: ViewModifier {
    var padding: CGFloat = Spacing.md
    var showBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.tuiPanel)
            .overlay {
                if showBorder {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.tuiBorder, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

extension View {
    func tuiPanel(padding: CGFloat = Spacing.md, showBorder: Bool = true) -> some View {
        modifier(TUIPanelStyle(padding: padding, showBorder: showBorder))
    }

    func cardStyle(padding: CGFloat = Spacing.md) -> some View {
        modifier(TUIPanelStyle(padding: padding, showBorder: true))
    }
}

// MARK: - TUI Button Styles

struct TUIButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed ? Color.tuiHighlight : (isHovered ? Color.tuiHover : Color.tuiPanel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.tuiSnappy, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct TUIPrimaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.medium)
            .foregroundStyle(Color.tuiButtonText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed ? Color.tuiButtonBackground.opacity(0.8) : (isHovered ? Color.tuiButtonBackground.opacity(0.95) : Color.tuiButtonBackground))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.tuiSnappy, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct TUIGhostButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? Color.tuiHover : Color.clear)
            )
            .animation(.tuiSnappy, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == TUIButtonStyle {
    static var tui: TUIButtonStyle { .init() }
}

extension ButtonStyle where Self == TUIPrimaryButtonStyle {
    static var tuiPrimary: TUIPrimaryButtonStyle { .init() }
    static var prominent: TUIPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == TUIGhostButtonStyle {
    static var tuiGhost: TUIGhostButtonStyle { .init() }
    static var subtle: TUIGhostButtonStyle { .init() }
    static var minimal: TUIGhostButtonStyle { .init() }
}

// MARK: - TUI Colors (Adaptive Light/Dark Mode)

extension Color {
    // MARK: - Adaptive Background Colors

    /// Main background - adapts to system appearance
    static let tuiBackground = Color(
        light: Color(red: 0.98, green: 0.98, blue: 0.97),  // Warm off-white
        dark: Color(red: 0.08, green: 0.08, blue: 0.09)    // Deep charcoal
    )

    /// Panel/Card background - slightly elevated from main background
    static let tuiPanel = Color(
        light: Color(red: 1.0, green: 1.0, blue: 1.0),     // Pure white
        dark: Color(red: 0.11, green: 0.11, blue: 0.12)    // Elevated dark
    )

    /// Hover state background
    static let tuiHover = Color(
        light: Color.black.opacity(0.04),
        dark: Color.white.opacity(0.05)
    )

    /// Highlight/Selected state background
    static let tuiHighlight = Color(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.08)
    )

    // MARK: - Adaptive Border & Accents

    /// Subtle border color
    static let tuiBorder = Color(
        light: Color.black.opacity(0.1),
        dark: Color.white.opacity(0.1)
    )

    /// Primary accent color - high contrast
    static let tuiAccent = Color(
        light: Color(red: 0.1, green: 0.1, blue: 0.12),    // Near black
        dark: Color(red: 0.95, green: 0.95, blue: 0.93)    // Warm white
    )

    // MARK: - Adaptive Text Colors

    /// Primary text - maximum contrast
    static let tuiTextPrimary = Color(
        light: Color(red: 0.1, green: 0.1, blue: 0.12),    // Dark text on light
        dark: Color(red: 0.95, green: 0.95, blue: 0.93)    // Light text on dark
    )

    /// Secondary text - reduced emphasis
    static let tuiTextSecondary = Color(
        light: Color(red: 0.4, green: 0.4, blue: 0.42),    // Medium gray
        dark: Color(red: 0.65, green: 0.65, blue: 0.63)    // Light gray
    )

    /// Tertiary text - subtle labels
    static let tuiTextTertiary = Color(
        light: Color(red: 0.55, green: 0.55, blue: 0.57),
        dark: Color(red: 0.5, green: 0.5, blue: 0.48)
    )

    // MARK: - Dithering Palette (Adaptive)

    static let ditherLight = Color(
        light: Color(red: 0.15, green: 0.15, blue: 0.16),  // Dark on light mode
        dark: Color(red: 0.95, green: 0.95, blue: 0.93)    // Light on dark mode
    )

    static let ditherMid = Color(red: 0.5, green: 0.5, blue: 0.52)

    static let ditherDark = Color(
        light: Color(red: 0.92, green: 0.92, blue: 0.90),  // Light gray
        dark: Color(red: 0.15, green: 0.15, blue: 0.16)    // Charcoal
    )

    static let ditherDarkBg = Color(
        light: Color(red: 0.96, green: 0.96, blue: 0.95),
        dark: Color(red: 0.06, green: 0.06, blue: 0.07)
    )

    static let ditherAccent = Color(
        light: Color(red: 0.35, green: 0.35, blue: 0.38),  // Darker accent for light
        dark: Color(red: 0.7, green: 0.7, blue: 0.65)      // Warm gray for dark
    )

    // MARK: - Recording State Colors (Consistent across modes)

    static let recordingActive = Color(red: 0.9, green: 0.3, blue: 0.3)
    static let recordingIdle = Color(
        light: Color(red: 0.45, green: 0.5, blue: 0.55),
        dark: Color(red: 0.6, green: 0.65, blue: 0.7)
    )

    // MARK: - Overlay Colors (Adaptive)

    /// Modal backdrop overlay
    static let tuiOverlayBackdrop = Color(
        light: Color.black.opacity(0.4),   // Lighter overlay for light mode
        dark: Color.black.opacity(0.85)    // Darker overlay for dark mode
    )

    // MARK: - Button Colors (Adaptive)

    /// Primary button background - inverted from main background
    static let tuiButtonBackground = Color(
        light: Color(red: 0.12, green: 0.12, blue: 0.14),  // Dark button on light
        dark: Color(red: 0.95, green: 0.95, blue: 0.93)    // Light button on dark
    )

    /// Primary button text - high contrast against button background
    static let tuiButtonText = Color(
        light: Color(red: 0.98, green: 0.98, blue: 0.97),  // Light text on dark button
        dark: Color(red: 0.08, green: 0.08, blue: 0.09)    // Dark text on light button
    )

    // MARK: - Legacy Compatibility

    static let briefingBackground = tuiBackground
    static let cardBackground = tuiPanel
    static let subtleBackground = tuiHover
    static let border = tuiBorder
    static let invertedText = tuiBackground
}

// MARK: - Adaptive Color Initializer

extension Color {
    /// Creates an adaptive color that switches between light and dark variants
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.name == .darkAqua ||
                         appearance.name.rawValue.lowercased().contains("dark")
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - Gradients (Adaptive)

extension LinearGradient {
    /// Glass overlay effect - adapts to appearance
    static var glassOverlay: LinearGradient {
        LinearGradient(
            colors: [Color.tuiGlassHighlight, Color.tuiGlassHighlight.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle border gradient - adapts to appearance
    static var subtleBorder: LinearGradient {
        LinearGradient(
            colors: [Color.tuiBorder.opacity(1.5), Color.tuiBorder.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    /// Glass highlight for overlays
    static let tuiGlassHighlight = Color(
        light: Color.white.opacity(0.6),
        dark: Color.white.opacity(0.05)
    )
}

// MARK: - Glassmorphism Effect

struct GlassmorphismModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var showBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.tuiPanel.opacity(0.8)
                    LinearGradient.glassOverlay
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.tuiBorder, lineWidth: showBorder ? 1 : 0)
            )
    }
}

extension View {
    func glassmorphism(cornerRadius: CGFloat = 16, showBorder: Bool = true) -> some View {
        modifier(GlassmorphismModifier(cornerRadius: cornerRadius, showBorder: showBorder))
    }

    func glowEffect(color: Color = .white, radius: CGFloat = 20) -> some View {
        self.shadow(color: color.opacity(0.3), radius: radius)
    }
}

// MARK: - TUI Animations

extension Animation {
    static let tuiSnappy = Animation.spring(response: 0.25, dampingFraction: 0.9)
    static let tuiFast = Animation.easeOut(duration: 0.15)
    static let tuiSmooth = Animation.easeInOut(duration: 0.2)

    // Legacy compatibility
    static let briefingSpring = tuiSnappy
    static let briefingEaseOut = tuiFast
}

// MARK: - Spacing Constants

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - TUI Text Styles

extension Font {
    static let tuiMono = Font.system(.body, design: .monospaced)
    static let tuiMonoSmall = Font.system(.caption, design: .monospaced)
    static let tuiMonoTiny = Font.system(.caption2, design: .monospaced)
}

// MARK: - TUI Row Style

struct TUIRowStyle: ViewModifier {
    @State private var isHovered = false
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? Color.tuiHighlight : (isHovered ? Color.tuiHover : Color.clear))
            )
            .animation(.tuiFast, value: isHovered)
            .animation(.tuiFast, value: isSelected)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func tuiRow(isSelected: Bool = false) -> some View {
        modifier(TUIRowStyle(isSelected: isSelected))
    }
}

// MARK: - Keyboard Shortcut Badge

struct KeyBadge: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.tuiMonoTiny)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.tuiHover)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
    }
}
