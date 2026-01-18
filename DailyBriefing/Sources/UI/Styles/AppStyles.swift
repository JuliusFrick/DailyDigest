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
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.tuiBorder, lineWidth: 1)
                }
            }
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(configuration.isPressed ? Color.tuiHighlight : (isHovered ? Color.tuiHover : Color.tuiPanel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
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
            .foregroundStyle(Color.tuiBackground)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.8) : (isHovered ? Color.primary.opacity(0.9) : Color.primary))
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
                RoundedRectangle(cornerRadius: 2)
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

// MARK: - TUI Colors

extension Color {
    // Background colors
    static let tuiBackground = Color(nsColor: .windowBackgroundColor)
    static let tuiPanel = Color(nsColor: .controlBackgroundColor)
    static let tuiHover = Color.primary.opacity(0.05)
    static let tuiHighlight = Color.primary.opacity(0.1)

    // Border & accents
    static let tuiBorder = Color.primary.opacity(0.12)
    static let tuiAccent = Color.primary

    // Legacy compatibility
    static let briefingBackground = tuiBackground
    static let cardBackground = tuiPanel
    static let subtleBackground = tuiHover
    static let border = tuiBorder
    static let invertedText = tuiBackground
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
                RoundedRectangle(cornerRadius: 2)
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
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.tuiHover)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
    }
}
