import SwiftUI
import AppIntents

@main
struct DailyBriefingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var settingsStore = UserSettingsStore.shared
    @StateObject private var updateService = UpdateService.shared

    // Services (initialized as singletons, referenced here to ensure they're started)
    private let briefingService = BriefingGenerationService.shared
    private let schedulingService = SchedulingService.shared
    private let shortcutService = GlobalShortcutService.shared
    private let notificationService = NotificationService.shared
    private let recordingHUDManager = RecordingHUDManager.shared

    init() {
        // Window is shown by AppDelegate after NSApplication finished launching.
    }

    var body: some Scene {
        Window("Daily Briefing", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .background(OpenWindowRegistrar())
                .onOpenURL { url in
                    OAuthCallbackRouter.shared.handleIncomingURL(url)
                }
                .onAppear {
                    AppIconService.shared.start()
                    MeetingPresenceService.shared.startMonitoring()
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

            // macOS-standard: App menu → "Nach Updates suchen…"
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
        }

        Settings {
            NavigationStack {
                SettingsView()
                    .environmentObject(appState)
                    .environmentObject(settingsStore)
                    .onOpenURL { url in
                        OAuthCallbackRouter.shared.handleIncomingURL(url)
                    }
            }
        }

        // Register menu bar extra for quick access
        MenuBarExtra {
            MenuBarCommandCenter()
                .environmentObject(appState)
                .environmentObject(settingsStore)
        } label: {
            Image(systemName: "sun.max")
                .symbolRenderingMode(.monochrome)
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


// MARK: - Window Registration

private struct OpenWindowRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                MainWindowCoordinator.shared.register(openWindow: openWindow)
            }
    }
}

// MARK: - App Shortcuts Registration

@available(macOS 13.0, *)
extension DailyBriefingApp {
    // App Intents are automatically discovered and registered
    // The DailyBriefingShortcuts provider exposes them to Siri and Shortcuts app
}
