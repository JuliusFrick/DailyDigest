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
    @State private var selectedDashboardTab: TUIDashboardView.DashboardTab = .briefing

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

            NavigationSplitView {
                WorkspaceSidebar(
                    selectedPanel: $appState.selectedPanel,
                    openSources: {
                        showSources = true
                        showSettings = false
                    },
                    openSettings: {
                        showSettings = true
                        showSources = false
                    }
                )
            } detail: {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.md) {
                        Text("DAILY BRIEFING")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(appState.selectedPanel.title.uppercased())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tuiBackground.opacity(0.9))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }

                    panelContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    StatusBar()
                }
            }
            .navigationSplitViewStyle(.balanced)

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

            if appState.selectedPanel == .dashboard && !showSettings && !showSources {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Dashboard und neue Bereiche lassen sich auch über das Seitenmenü wechseln.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.quaternary.opacity(0.9))
                            .padding(Spacing.sm)
                            .background(Color.tuiPanel.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

        }
        .animation(.tuiSnappy, value: showSettings)
        .animation(.tuiSnappy, value: showSources)
        .modifier(MainViewKeyboardModifier(
            showSettings: $showSettings,
            showSources: $showSources,
            selectedPanel: $appState.selectedPanel
        ))
        .onKeyPress(.escape) {
            if showSettings || showSources {
                showSettings = false
                showSources = false
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch appState.selectedPanel {
        case .dashboard:
            TUIDashboardView(selectedTab: $selectedDashboardTab)
        case .claudeChat:
            PanelPlaceholderView(
                title: "CLAUDE CHAT",
                subtitle: "Der dedizierte Claude-Bereich wird in der nächsten Phase ergänzt."
            )
        case .slack:
            PanelPlaceholderView(
                title: "SLACK",
                subtitle: "Das Slack-Panel mit mentions/starred und Thread-Kontext folgt in Phase 4a."
            )
        case .jira:
            PanelPlaceholderView(
                title: "JIRA",
                subtitle: "Die Jira-Übersicht mit Filter/Detailansicht folgt in Phase 4b."
            )
        case .mail:
            PanelPlaceholderView(
                title: "MAIL",
                subtitle: "Das Mail-Inbox-Panel folgt in Phase 4c."
            )
        case .terminals:
            PanelPlaceholderView(
                title: "TERMINALS",
                subtitle: "Die integrierten Terminals folgen in Phase 5."
            )
        }
    }
}

// MARK: - Workspace Sidebar

struct WorkspaceSidebar: View {
    @Binding var selectedPanel: AppState.AppPanel
    let openSources: () -> Void
    let openSettings: () -> Void

    var body: some View {
        List {
            Section("HUB") {
                ForEach(AppState.AppPanel.allCases) { panel in
                    Button {
                        selectedPanel = panel
                    } label: {
                        Label {
                            Text(panel.title)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(selectedPanel == panel ? .primary : .secondary)
                                .fontWeight(selectedPanel == panel ? .semibold : .regular)
                        } icon: {
                            Image(systemName: panel.icon)
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedPanel == panel
                        ? Color.tuiHighlight.opacity(0.25)
                        : Color.clear
                    )
                }
            }

            Section("SYSTEM") {
                Button {
                    openSources()
                } label: {
                    Label {
                        Text("Quellen")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    openSettings()
                } label: {
                    Label {
                        Text("Einstellungen")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Daily Briefing")
    }
}

struct PanelPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.tuiPanel
                .opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                Text(title)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.xl)

                Text(subtitle)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)

                HStack(spacing: Spacing.sm) {
                    Text("Shortcut")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                    Text("⌘1-⌘6")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.md)
            }
            .frame(maxWidth: 520)
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.tuiBorder, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.tuiBackground.opacity(0.8)))
            )
            .padding()
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

// MARK: - Main View Keyboard Modifier

struct MainViewKeyboardModifier: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showSources: Bool
    @Binding var selectedPanel: AppState.AppPanel

    func body(content: Content) -> some View {
        content
            .onKeyPress("w", modifiers: .command) {
                if showSettings || showSources {
                    showSettings = false
                    showSources = false
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("1", modifiers: .command) {
                selectedPanel = .dashboard
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("2", modifiers: .command) {
                selectedPanel = .claudeChat
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("3", modifiers: .command) {
                selectedPanel = .slack
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("4", modifiers: .command) {
                selectedPanel = .jira
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("5", modifiers: .command) {
                selectedPanel = .mail
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("6", modifiers: .command) {
                selectedPanel = .terminals
                showSettings = false
                showSources = false
                return .handled
            }
            .onKeyPress("s", modifiers: .command) {
                showSources.toggle()
                showSettings = false
                return .handled
            }
            .onKeyPress(",", modifiers: .command) {
                showSettings.toggle()
                showSources = false
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
            // Semi-transparent backdrop - adapts to appearance
            Color.tuiOverlayBackdrop
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
    }
}
