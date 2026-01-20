import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: UserSettingsStore

    @State private var selectedLanguage = "de"
    @State private var autoRefreshEnabled = false
    @State private var autoRefreshTime = Date()
    @State private var globalShortcutEnabled = false
    @State private var currentShortcut: KeyboardShortcut = .default

    // Notification settings state
    @State private var notificationsEnabled = true
    @State private var morningReminderEnabled = false
    @State private var morningReminderTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()

    @StateObject private var schedulingService = SchedulingService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var shortcutService = GlobalShortcutService.shared
    @StateObject private var launchAtLoginService = LaunchAtLoginService.shared
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        Form {
            briefingSection
            integrationsSection
            llmNavigationSection
            transcriptionSection
            audioSection
            scheduleSection
            notificationSection
            shortcutSection
            siriSection
            generalSection
            updatesSection
            privacySection
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.tuiBackground)
        .font(.tuiMonoSmall)
        .controlSize(.small)
        .navigationTitle("Einstellungen")
        .onAppear(perform: loadSettings)
        .onChange(of: autoRefreshEnabled) { _, newValue in
            handleSchedulingChange(enabled: newValue)
        }
        .onChange(of: autoRefreshTime) { _, newValue in
            if autoRefreshEnabled {
                schedulingService.updateScheduledTime(newValue)
            }
        }
        .onChange(of: globalShortcutEnabled) { _, newValue in
            handleShortcutChange(enabled: newValue)
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            handleNotificationsEnabledChange(enabled: newValue)
        }
        .onChange(of: morningReminderEnabled) { _, newValue in
            handleMorningReminderChange(enabled: newValue)
        }
        .onChange(of: morningReminderTime) { _, newValue in
            if morningReminderEnabled {
                notificationService.scheduleMorningReminder(at: newValue)
            }
            saveSettings()
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        Section {
            NavigationLink {
                ServiceIntegrationsView()
            } label: {
                HStack {
                    Label("Dienst-Integrationen", systemImage: "square.stack.3d.up.fill")
                    Spacer()
                    ConnectedServicesCount()
                }
            }
        } header: {
            Text("Datenquellen")
        } footer: {
            Text("Verbinde deine Produktivitäts-Tools um Daten für dein Briefing abzurufen.")
        }
    }

    // MARK: - Briefing Section

    private var briefingSection: some View {
        Section {
            Picker("Sprache", selection: $selectedLanguage) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }

            Picker("Standard-Detailtiefe", selection: .constant("quick")) {
                Text("Quick (2-3 Min)").tag("quick")
                Text("Detailed (5-10 Min)").tag("detailed")
            }
        } header: {
            Text("Briefing")
        }
    }

    // MARK: - LLM Navigation Section

    private var llmNavigationSection: some View {
        Section {
            NavigationLink {
                LLMSettingsView()
                    .navigationTitle("KI-Provider")
            } label: {
                HStack {
                    Label("KI-Provider", systemImage: "brain.head.profile")
                    Spacer()
                    Text(currentProviderName)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("KI-Zusammenfassung")
        } footer: {
            Text("Die KI generiert eine Zusammenfassung deiner Briefing-Daten.")
        }
    }

    private var currentProviderName: String {
        if let provider = LLMProvider(rawValue: settingsStore.settings.llmProvider) {
            return provider.displayName
        }
        return "OpenAI"
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        Section {
            NavigationLink {
                TranscriptionSettingsView()
                    .navigationTitle("Transkription")
            } label: {
                HStack {
                    Label("Transkription", systemImage: "waveform.badge.mic")
                    Spacer()
                    Text(TranscriptionService.shared.transcriptionProvider.displayName)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Meeting-Transkription")
        } footer: {
            Text("Wähle den Dienst für die Umwandlung von Sprache in Text.")
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        Section {
            NavigationLink {
                TTSSettingsView()
                    .navigationTitle("Sprachausgabe")
            } label: {
                HStack {
                    Label("Sprachausgabe", systemImage: "waveform.circle")
                    Spacer()
                    Text(currentTTSProviderName)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Audio-Briefing")
        } footer: {
            Text("Konfiguriere die Text-to-Speech Engine, Stimme und Wiedergabegeschwindigkeit.")
        }
    }

    private var currentTTSProviderName: String {
        switch settingsStore.settings.ttsProvider {
        case "openai":
            return "OpenAI TTS"
        case "elevenlabs":
            return "ElevenLabs"
        default:
            return "Apple Native"
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        Section {
            Toggle("Automatisches Briefing", isOn: $autoRefreshEnabled)

            if autoRefreshEnabled {
                DatePicker(
                    "Uhrzeit",
                    selection: $autoRefreshTime,
                    displayedComponents: .hourAndMinute
                )

                if let nextTime = schedulingService.formattedNextTime {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Nächstes Briefing: \(nextTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Zeitplan")
        } footer: {
            Text("Das Briefing wird automatisch zur eingestellten Zeit generiert und eine Benachrichtigung erscheint.")
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        Section {
            // Permission status display
            HStack {
                Image(systemName: notificationPermissionIcon)
                    .foregroundStyle(notificationPermissionColor)
                Text("Berechtigung")
                Spacer()
                Text(notificationPermissionStatusText)
                    .foregroundStyle(.secondary)
            }

            // Request permission button (shown when denied or not determined)
            if notificationService.authorizationStatus == .denied {
                Button {
                    openSystemNotificationSettings()
                } label: {
                    Label("Berechtigung in Systemeinstellungen erteilen", systemImage: "gear")
                        .foregroundStyle(.orange)
                }
            } else if notificationService.authorizationStatus == .notDetermined {
                Button {
                    Task {
                        await notificationService.requestPermission()
                    }
                } label: {
                    Label("Berechtigung anfragen", systemImage: "bell.badge")
                }
            }

            // Enable/disable notifications toggle
            Toggle("Benachrichtigungen aktivieren", isOn: $notificationsEnabled)
                .disabled(!notificationService.isAuthorized)

            // Morning reminder toggle
            if notificationsEnabled && notificationService.isAuthorized {
                Toggle("Morgen-Erinnerung", isOn: $morningReminderEnabled)

                // Time picker for morning reminder
                if morningReminderEnabled {
                    DatePicker(
                        "Erinnerungszeit",
                        selection: $morningReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            if notificationService.authorizationStatus == .denied {
                Text("Benachrichtigungen wurden verweigert. Bitte erteile die Berechtigung in den Systemeinstellungen.")
            } else if !notificationsEnabled {
                Text("Aktiviere Benachrichtigungen um über neue Briefings informiert zu werden.")
            } else if morningReminderEnabled {
                Text("Du erhältst täglich um \(formattedReminderTime) eine Erinnerung für dein Briefing.")
            } else {
                Text("Aktiviere die Morgen-Erinnerung um täglich an dein Briefing erinnert zu werden.")
            }
        }
    }

    // MARK: - Notification Helpers

    private var notificationPermissionIcon: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .provisional:
            return "checkmark.circle"
        case .notDetermined:
            return "questionmark.circle"
        case .ephemeral:
            return "clock.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var notificationPermissionColor: Color {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .secondary
        }
    }

    private var notificationPermissionStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return "Erteilt"
        case .denied:
            return "Verweigert"
        case .provisional:
            return "Vorläufig"
        case .notDetermined:
            return "Nicht angefragt"
        case .ephemeral:
            return "Temporär"
        @unknown default:
            return "Unbekannt"
        }
    }

    private var formattedReminderTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: morningReminderTime)
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Shortcut Section

    private var shortcutSection: some View {
        Section {
            Toggle("Globale Tastenkombination", isOn: $globalShortcutEnabled)

            if globalShortcutEnabled {
                HStack {
                    Text("Tastenkombination")
                    Spacer()
                    ShortcutRecorderView(shortcut: $currentShortcut)
                        .onChange(of: currentShortcut) { _, newValue in
                            shortcutService.updateShortcut(newValue)
                        }
                }

                if !GlobalShortcutService.hasAccessibilityPermissions() {
                    Button {
                        GlobalShortcutService.requestAccessibilityPermissions()
                    } label: {
                        Label("Bedienungshilfen-Zugriff erlauben", systemImage: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text("Tastenkombination")
        } footer: {
            if globalShortcutEnabled {
                Text("Drücke \(currentShortcut.displayString) um von überall ein Briefing zu generieren.")
            } else {
                Text("Aktiviere eine globale Tastenkombination um von überall ein Briefing zu generieren.")
            }
        }
    }

    // MARK: - Siri Section

    private var siriSection: some View {
        Section {
            HStack {
                Text("Siri Shortcuts")
                Spacer()
                Text("Aktiviert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Verfügbare Befehle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Briefing generieren · Briefing anzeigen · Zeit einstellen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Siri")
        } footer: {
            Text("Die Shortcuts sind automatisch in der Shortcuts App verfügbar.")
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section {
            Toggle("Bei Anmeldung starten", isOn: Binding(
                get: { launchAtLoginService.enabled },
                set: { newValue in
                    if newValue {
                        launchAtLoginService.enable()
                    } else {
                        launchAtLoginService.disable()
                    }
                }
            ))
        } header: {
            Text("Allgemein")
        } footer: {
            Text("Die App wird automatisch gestartet, wenn du dich an deinem Mac anmeldest.")
        }
    }

    // MARK: - Updates Section

    private var updatesSection: some View {
        Section {
            Button("Nach Updates suchen…") {
                updateService.checkForUpdates()
            }
            .disabled(!updateService.canCheckForUpdates)

            Toggle(
                "Automatisch nach Updates suchen",
                isOn: Binding(
                    get: { updateService.automaticallyChecksForUpdates },
                    set: { updateService.setAutomaticChecksEnabled($0) }
                )
            )

            if let error = updateService.lastUpdateError {
                Text("Letzter Update-Fehler: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let details = updateService.lastUpdateErrorDetails {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let feedURL = updateService.resolvedFeedURLString {
                Text("Appcast: \(feedURL)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Wenn aktiviert, prüft die App täglich auf Updates (Sparkle).")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacySettingsView()
                    .navigationTitle("Datenschutz")
            } label: {
                Label("Datenschutz", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Datenschutz")
        } footer: {
            Text("Verwalte deinen Cache, lösche Zugangsdaten oder exportiere deine Daten.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0 (Build 1)")
            LabeledContent("Entwickler", value: "Daily Briefing Team")

            Link(destination: URL(string: "https://github.com")!) {
                Label("GitHub", systemImage: "link")
            }

            Button("Onboarding erneut zeigen") {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                appState.showOnboarding = true
            }
        } header: {
            Text("Über")
        }
    }

    // MARK: - Helpers

    private func loadSettings() {
        let userSettings = settingsStore.settings

        selectedLanguage = userSettings.preferredLanguage
        autoRefreshEnabled = userSettings.autoRefreshEnabled
        if let time = userSettings.autoRefreshTime {
            autoRefreshTime = time
        }
        globalShortcutEnabled = userSettings.globalShortcutEnabled
        currentShortcut = KeyboardShortcut(
            keyCode: userSettings.globalShortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(userSettings.globalShortcutModifiers))
        )

        // Load notification settings
        notificationsEnabled = userSettings.notificationsEnabled
        morningReminderEnabled = userSettings.morningReminderEnabled
        if let reminderTime = userSettings.morningReminderTime {
            morningReminderTime = reminderTime
        }

        // Sync with services
        if autoRefreshEnabled {
            schedulingService.updateScheduledTime(autoRefreshTime)
            schedulingService.enableScheduling()
        }
        if globalShortcutEnabled {
            shortcutService.updateShortcut(currentShortcut)
            shortcutService.enable()
        }

        // Sync notification service
        if morningReminderEnabled && notificationsEnabled {
            notificationService.scheduleMorningReminder(at: morningReminderTime)
        }
    }

    private func createDefaultSettings() {
        settingsStore.resetToDefaults()
    }

    private func handleSchedulingChange(enabled: Bool) {
        if enabled {
            schedulingService.updateScheduledTime(autoRefreshTime)
            schedulingService.enableScheduling()
            Task {
                _ = await schedulingService.requestNotificationPermission()
            }
        } else {
            schedulingService.disableScheduling()
        }
        saveSettings()
    }

    private func handleShortcutChange(enabled: Bool) {
        if enabled {
            if !GlobalShortcutService.hasAccessibilityPermissions() {
                GlobalShortcutService.requestAccessibilityPermissions()
            }
            shortcutService.enable()
        } else {
            shortcutService.disable()
        }
        saveSettings()
    }

    private func saveSettings() {
        settingsStore.update { s in
            s.preferredLanguage = selectedLanguage
            s.autoRefreshEnabled = autoRefreshEnabled
            s.autoRefreshTime = autoRefreshTime
            s.globalShortcutEnabled = globalShortcutEnabled
            s.globalShortcutKeyCode = currentShortcut.keyCode
            s.globalShortcutModifiers = UInt64(currentShortcut.modifiers.rawValue)
            s.notificationsEnabled = notificationsEnabled
            s.morningReminderEnabled = morningReminderEnabled
            s.morningReminderTime = morningReminderTime
        }
    }

    private func handleNotificationsEnabledChange(enabled: Bool) {
        if !enabled {
            // Disable morning reminder when notifications are disabled
            morningReminderEnabled = false
            notificationService.cancelMorningReminder()
        }
        saveSettings()
    }

    private func handleMorningReminderChange(enabled: Bool) {
        if enabled {
            notificationService.scheduleMorningReminder(at: morningReminderTime)
        } else {
            notificationService.cancelMorningReminder()
        }
        saveSettings()
    }
}


// MARK: - Connected Services Count

struct ConnectedServicesCount: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    private var connectedCount: Int {
        connectionManager.connectedSources.count
    }

    var body: some View {
        if connectedCount > 0 {
            Text("\(connectedCount) verbunden")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Keine")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
