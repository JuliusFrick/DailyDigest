import SwiftUI

/// Reusable empty state view with icon, title, message and optional action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var style: Style = .default
    
    enum Style {
        case `default`
        case subtle
        case compact
    }
    
    var body: some View {
        VStack(spacing: style == .compact ? Spacing.sm : Spacing.md) {
            // Animated icon
            iconView
            
            // Text content
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(style == .compact ? .tuiMonoSmall : .tuiMonoMedium)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(style == .compact ? .tuiMonoTiny : .tuiMonoSmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Action button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.tuiMonoSmall)
                        .fontWeight(.medium)
                }
                .buttonStyle(TUIButtonStyle())
                .padding(.top, Spacing.xs)
            }
        }
        .padding(style == .compact ? Spacing.md : Spacing.lg)
        .frame(maxWidth: style == .compact ? 250 : 300)
    }
    
    @ViewBuilder
    private var iconView: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.1), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: style == .compact ? 30 : 50
                    )
                )
                .frame(width: style == .compact ? 60 : 100, height: style == .compact ? 60 : 100)
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: style == .compact ? 24 : 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary.opacity(0.6), .secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)
        }
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    /// No meetings today
    static func noMeetings(onConnect: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            icon: "calendar.badge.clock",
            title: "Keine Termine",
            message: "Dein Kalender ist leer. Verbinde einen Kalender um Termine zu sehen.",
            actionTitle: onConnect != nil ? "Kalender verbinden" : nil,
            action: onConnect
        )
    }
    
    /// No briefing generated yet
    static func noBriefing(onGenerate: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "Kein Briefing",
            message: "Generiere dein erstes Daily Briefing um loszulegen.",
            actionTitle: onGenerate != nil ? "Briefing generieren" : nil,
            action: onGenerate
        )
    }
    
    /// No action items
    static func noActionItems() -> EmptyStateView {
        EmptyStateView(
            icon: "checkmark.circle",
            title: "Alles erledigt!",
            message: "Keine offenen Action Items. Genieße den Moment.",
            style: .subtle
        )
    }
    
    /// No search results
    static func noResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Keine Ergebnisse",
            message: "Keine Treffer für \"\(query)\". Versuche andere Suchbegriffe.",
            style: .compact
        )
    }
    
    /// No chat history
    static func noChat() -> EmptyStateView {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "Starte ein Gespräch",
            message: "Frag mich etwas über dein Briefing oder deine Meetings.",
            style: .compact
        )
    }
    
    /// No notes for meeting
    static func noNotes(onAdd: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            icon: "note.text.badge.plus",
            title: "Keine Notizen",
            message: "Füge Notizen hinzu um wichtige Punkte festzuhalten.",
            actionTitle: onAdd != nil ? "Notiz hinzufügen" : nil,
            action: onAdd,
            style: .compact
        )
    }
    
    /// Offline state
    static func offline() -> EmptyStateView {
        EmptyStateView(
            icon: "wifi.slash",
            title: "Offline",
            message: "Keine Internetverbindung. Einige Funktionen sind eingeschränkt.",
            style: .subtle
        )
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    var message: String = "Laden..."
    var style: EmptyStateView.Style = .default
    
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: style == .compact ? Spacing.sm : Spacing.md) {
            // Animated loader
            ZStack {
                Circle()
                    .stroke(Color.tuiBorder, lineWidth: 3)
                    .frame(width: style == .compact ? 32 : 48, height: style == .compact ? 32 : 48)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: style == .compact ? 32 : 48, height: style == .compact ? 32 : 48)
                    .rotationEffect(.degrees(rotation))
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            
            Text(message)
                .font(style == .compact ? .tuiMonoTiny : .tuiMonoSmall)
                .foregroundColor(.secondary)
        }
        .padding(style == .compact ? Spacing.md : Spacing.lg)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            EmptyStateView.noMeetings(onConnect: {})
            EmptyStateView.noBriefing(onGenerate: {})
            EmptyStateView.noActionItems()
            EmptyStateView.noChat()
            LoadingStateView()
            LoadingStateView(message: "Briefing wird generiert...", style: .compact)
        }
        .padding()
    }
    .background(Color.tuiBackground)
}
