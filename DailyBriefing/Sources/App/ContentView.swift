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
        .frame(minWidth: 640, minHeight: 460)
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color.tuiBackground
                .ignoresSafeArea()

            DitheringBackgroundView(
                shape: .simplex,
                ditherType: .bayer8x8,
                colorBack: Color.clear,
                colorFront: Color.primary.opacity(0.02),
                pixelSize: 4,
                speed: 0.1,
                opacity: 0.5
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                NavigationSplitView {
                    SidebarView(selectedPanel: $appState.selectedPanel)
                } detail: {
                    PanelContent(selectedPanel: $appState.selectedPanel, selectedDashboardTab: $appState.selectedTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBar()
            }
        }
        .modifier(ContentViewKeyboardModifier(appState: appState))
    }
}

private struct PanelContent: View {
    @Binding var selectedPanel: AppState.AppPanel
    @Binding var selectedDashboardTab: TUIDashboardView.DashboardTab

    var body: some View {
        Group {
            switch selectedPanel {
            case .dashboard:
                TUIDashboardView(selectedTab: $selectedDashboardTab)
            case .claudeChat:
                BriefingChatView()
            case .slack:
                SlackPanelView()
            case .jira:
                JiraPanelView()
            case .mail:
                MailPanelView()
            case .terminals:
                TerminalsPanelView()
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tuiBackground)
    }
}

private struct AppPanelPlaceholder: View {
    let title: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text(title)
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xl)

            Text("Dieser Bereich ist in der aktuellen Implementierung noch nicht vollständig eingebunden.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}

struct ContentViewKeyboardModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onKeyPress("1", modifiers: .command) {
                appState.selectedPanel = .dashboard
                return .handled
            }
            .onKeyPress("2", modifiers: .command) {
                appState.selectedPanel = .claudeChat
                return .handled
            }
            .onKeyPress("3", modifiers: .command) {
                appState.selectedPanel = .slack
                return .handled
            }
            .onKeyPress("4", modifiers: .command) {
                appState.selectedPanel = .jira
                return .handled
            }
            .onKeyPress("5", modifiers: .command) {
                appState.selectedPanel = .mail
                return .handled
            }
            .onKeyPress("6", modifiers: .command) {
                appState.selectedPanel = .terminals
                return .handled
            }
            .onKeyPress(",", modifiers: .command) {
                appState.selectedPanel = .settings
                return .handled
            }
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
        .background(Color.tuiBackground.opacity(0.9))
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

