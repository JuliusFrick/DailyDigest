import SwiftUI
import AppIntents

@main
struct DailyBriefingApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = UserSettingsStore.shared

    // Services (initialized as singletons, referenced here to ensure they're started)
    private let briefingService = BriefingGenerationService.shared
    private let schedulingService = SchedulingService.shared
    private let shortcutService = GlobalShortcutService.shared
    private let notificationService = NotificationService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .onAppear {
                    setupMenuBarIcon()
                    setupNotificationHandling()
                    requestNotificationPermissionIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 420, height: 680)
        .commands {
            // Add keyboard shortcut for refreshing briefing
            CommandGroup(after: .newItem) {
                Button("Briefing aktualisieren") {
                    Task { await appState.refreshBriefing() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
        }

        // Register menu bar extra for quick access
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
        } label: {
            Image(systemName: appState.isOnline ? "sun.horizon.fill" : "sun.horizon")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.isOnline ? .orange : .gray)
        }
        .menuBarExtraStyle(.window)
    }

    private func setupMenuBarIcon() {
        // Ensure the app stays running in the menu bar
        NSApp.setActivationPolicy(.regular)
    }

    private func setupNotificationHandling() {
        // Set up callback for when user taps notification to open dashboard
        notificationService.onOpenDashboardRequested = { [weak appState] in
            appState?.selectedTab = .dashboard
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        Task {
            // Request permission on first start if not already determined
            let hasRequested = await notificationService.hasRequestedPermission()
            if !hasRequested {
                await notificationService.requestPermission()
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: appState.isOnline ? "sun.horizon.fill" : "sun.horizon")
                    .foregroundStyle(appState.isOnline ? .orange : .gray)
                Text("Daily Briefing")
                    .font(.headline)
                Spacer()
                if !appState.isOnline {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Quick status
            if let briefing = appState.currentBriefing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Letztes Briefing")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(briefing.summary)
                        .font(.caption)
                        .lineLimit(3)

                    Text(formatDate(briefing.generatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Noch kein Briefing generiert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Offline: Load cached briefing button
            if !appState.isOnline && appState.hasCachedBriefing && appState.currentBriefing == nil {
                Button {
                    appState.loadCachedBriefing()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Letztes Briefing anzeigen")
                    }
                }
            }

            // Actions
            Button {
                Task { await appState.refreshBriefing() }
            } label: {
                HStack {
                    if appState.isLoadingBriefing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(appState.isLoadingBriefing ? "Generiere..." : "Briefing generieren")
                }
            }
            .disabled(appState.isLoadingBriefing || (!appState.isOnline && !appState.isOllamaConfigured))

            Button {
                openMainWindow()
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text("App öffnen")
                }
            }

            Divider()

            // Schedule info
            if appState.isSchedulingEnabled {
                if let nextTime = appState.nextScheduledBriefingTime {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Nächstes: \(nextTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Shortcut hint
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text(appState.currentShortcut.displayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Einstellungen...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 280)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Daily Briefing" || $0.title == "" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - App Shortcuts Registration

@available(macOS 13.0, *)
extension DailyBriefingApp {
    // App Intents are automatically discovered and registered
    // The DailyBriefingShortcuts provider exposes them to Siri and Shortcuts app
}
