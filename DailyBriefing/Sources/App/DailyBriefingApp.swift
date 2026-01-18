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
        .defaultSize(width: 700, height: 500)
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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("DAILY BRIEFING")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)

                Spacer()

                Text(appState.isOnline ? "●" : "○")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(appState.isOnline ? .green : .orange)
            }
            .padding(Spacing.md)

            Divider()

            // Quick status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let briefing = appState.currentBriefing {
                    Text(briefing.summary)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .foregroundStyle(.secondary)

                    Text(formatDate(briefing.generatedAt))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("no briefing yet")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Spacing.md)

            Divider()

            // Actions
            VStack(spacing: 2) {
                if !appState.isOnline && appState.hasCachedBriefing && appState.currentBriefing == nil {
                    MenuBarButton(title: "load cached", shortcut: nil) {
                        appState.loadCachedBriefing()
                    }
                }

                MenuBarButton(
                    title: appState.isLoadingBriefing ? "generating..." : "generate",
                    shortcut: "⌘R",
                    isLoading: appState.isLoadingBriefing
                ) {
                    Task { await appState.refreshBriefing() }
                }
                .disabled(appState.isLoadingBriefing || (!appState.isOnline && !appState.isOllamaConfigured))

                MenuBarButton(title: "open app", shortcut: nil) {
                    openMainWindow()
                }
            }
            .padding(.vertical, Spacing.xs)

            Divider()

            // Info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if appState.isSchedulingEnabled, let nextTime = appState.nextScheduledBriefingTime {
                    Text("next: \(nextTime)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text("shortcut: \(appState.currentShortcut.displayString)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .padding(Spacing.md)

            Divider()

            // Bottom actions
            VStack(spacing: 2) {
                MenuBarButton(title: "settings", shortcut: "⌘,") {
                    openSettings()
                }

                MenuBarButton(title: "quit", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .frame(width: 240)
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

// MARK: - Menu Bar Button

struct MenuBarButton: View {
    let title: String
    let shortcut: String?
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }

                Text(title)
                    .font(.system(.caption, design: .monospaced))

                Spacer()

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - App Shortcuts Registration

@available(macOS 13.0, *)
extension DailyBriefingApp {
    // App Intents are automatically discovered and registered
    // The DailyBriefingShortcuts provider exposes them to Siri and Shortcuts app
}
