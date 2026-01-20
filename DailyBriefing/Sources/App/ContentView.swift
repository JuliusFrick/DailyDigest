import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.showOnboarding {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showSources = false
    @State private var showHistory = false
    @State private var showMeetings = false

    var body: some View {
        ZStack {
            Color.tuiBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                TopBar(
                    showSettings: $showSettings,
                    showSources: $showSources,
                    showHistory: $showHistory,
                    showMeetings: $showMeetings
                )

                // Main content
                TUIDashboardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom status bar
                StatusBar()
            }

            // Modal overlays
            if showSettings {
                ModalOverlay(isPresented: $showSettings, title: "Einstellungen", showsHeader: false) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Fertig") {
                                        showSettings = false
                                    }
                                }
                            }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }

            if showSources {
                ModalOverlay(isPresented: $showSources, title: "Sources") {
                    TUISourcesView()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }

            if showHistory {
                ModalOverlay(isPresented: $showHistory, title: "History") {
                    TUIHistoryView()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }

            if showMeetings {
                ModalOverlay(isPresented: $showMeetings, title: "Meetings") {
                    MeetingsView()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }
        }
        .animation(.tuiSnappy, value: showSettings)
        .animation(.tuiSnappy, value: showSources)
        .animation(.tuiSnappy, value: showHistory)
        .animation(.tuiSnappy, value: showMeetings)
        .onKeyPress(.escape) {
            if showSettings || showSources || showHistory || showMeetings {
                showSettings = false
                showSources = false
                showHistory = false
                showMeetings = false
                return .handled
            }
            return .ignored
        }
        .modifier(ContentViewKeyboardModifier(
            showSettings: $showSettings,
            showSources: $showSources,
            showHistory: $showHistory,
            showMeetings: $showMeetings
        ))
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @Binding var showSettings: Bool
    @Binding var showSources: Bool
    @Binding var showHistory: Bool
    @Binding var showMeetings: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Logo/Title
            Text("DAILY BRIEFING")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Spacer()

            // Nav items
            HStack(spacing: 2) {
                NavButton(label: "1", title: "Home", isActive: !showHistory && !showSources && !showSettings && !showMeetings) {
                    showHistory = false; showSources = false; showSettings = false; showMeetings = false
                }
                NavButton(label: "2", title: "History", isActive: showHistory) {
                    showHistory.toggle(); showSources = false; showSettings = false; showMeetings = false
                }
                NavButton(label: "3", title: "Sources", isActive: showSources) {
                    showSources.toggle(); showHistory = false; showSettings = false; showMeetings = false
                }
                NavButton(label: "4", title: "Meetings", isActive: showMeetings) {
                    showMeetings.toggle(); showHistory = false; showSources = false; showSettings = false
                }
                NavButton(label: ",", title: "Settings", isActive: showSettings) {
                    showSettings.toggle(); showHistory = false; showSources = false; showMeetings = false
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

struct NavButton: View {
    let label: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("⌘\(label)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(title)
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.tuiHighlight : (isHovered ? Color.tuiHover : Color.clear))
            )
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Online status
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isOnline ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(appState.isOnline ? "online" : "offline")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            // Connected sources indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionManager.connectedSources.isEmpty ? Color.secondary : Color.blue)
                    .frame(width: 6, height: 6)
                Text("\(connectionManager.connectedSources.count) src")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Keyboard hints - context-aware
            HStack(spacing: Spacing.sm) {
                if appState.currentBriefing != nil {
                    KeyHint(key: "SPC", action: appState.isPlayingAudio ? "pause" : "play")
                    if appState.isPlayingAudio {
                        KeyHint(key: "⌘.", action: "stop")
                    }
                }
                
                KeyHint(key: "⌘R", action: "refresh")
                KeyHint(key: "⌘⇧Q", action: "quick")
                KeyHint(key: "⌘⇧D", action: "detail")
                KeyHint(key: "ESC", action: "close")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.tuiBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

struct KeyHint: View {
    let key: String
    let action: String
    
    var body: some View {
        Text("\(key) \(action)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Content View Keyboard Modifier

struct ContentViewKeyboardModifier: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showSources: Bool
    @Binding var showHistory: Bool
    @Binding var showMeetings: Bool

    func body(content: Content) -> some View {
        content
            .onKeyPress("w", modifiers: .command) {
                if showSettings || showSources || showHistory || showMeetings {
                    showSettings = false
                    showSources = false
                    showHistory = false
                    showMeetings = false
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("1", modifiers: .command) {
                showHistory = false; showSources = false; showSettings = false; showMeetings = false
                return .handled
            }
            .onKeyPress("2", modifiers: .command) {
                showHistory.toggle(); showSources = false; showSettings = false; showMeetings = false
                return .handled
            }
            .onKeyPress("3", modifiers: .command) {
                showSources.toggle(); showHistory = false; showSettings = false; showMeetings = false
                return .handled
            }
            .onKeyPress("4", modifiers: .command) {
                showMeetings.toggle(); showHistory = false; showSources = false; showSettings = false
                return .handled
            }
            .onKeyPress(",", modifiers: .command) {
                showSettings.toggle(); showHistory = false; showSources = false; showMeetings = false
                return .handled
            }
    }
}

// MARK: - Modal Overlay

struct ModalOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    var showsHeader: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Modal
            VStack(spacing: 0) {
                if showsHeader {
                    // Header
                    HStack {
                        Text(title.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)

                        Spacer()

                        Button {
                            isPresented = false
                        } label: {
                            Text("[ESC]")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Spacing.md)
                    .background(Color.tuiBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                }

                // Content
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 600, maxHeight: 500)
            .background(Color.tuiBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}
