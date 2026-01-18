import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var settings: [UserSettings]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedLanguage = "de"
    @State private var selectedLLMProvider = "openai"
    @State private var selectedTTSProvider = "apple"
    @State private var autoRefreshEnabled = false
    @State private var autoRefreshTime = Date()
    @State private var globalShortcutEnabled = false
    @State private var currentShortcut: KeyboardShortcut = .default

    @StateObject private var schedulingService = SchedulingService.shared
    @StateObject private var shortcutService = GlobalShortcutService.shared

    var body: some View {
        Form {
            briefingSection
            integrationsSection
            llmNavigationSection
            audioSection
            scheduleSection
            shortcutSection
            siriSection
            aboutSection
        }
        .formStyle(.grouped)
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
        if let provider = LLMProvider(rawValue: selectedLLMProvider) {
            return provider.displayName
        }
        return "OpenAI"
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        Section {
            Picker("TTS-Engine", selection: $selectedTTSProvider) {
                Text("Apple Neural TTS").tag("apple")
                Text("OpenAI TTS").tag("openai")
                Text("ElevenLabs").tag("elevenlabs")
            }

            if selectedTTSProvider == "apple" {
                Picker("Stimme", selection: .constant("anna")) {
                    Text("Anna (Deutsch)").tag("anna")
                    Text("Markus (Deutsch)").tag("markus")
                    Text("Samantha (English)").tag("samantha")
                }
            }

            HStack {
                Text("Geschwindigkeit")
                Slider(value: .constant(1.0), in: 0.5...2.0, step: 0.1)
                Text("1.0x")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Audio-Briefing")
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
                Image(systemName: "waveform")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Siri Shortcuts")
                        .font(.headline)
                    Text("\"Hey Siri, Daily Briefing\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Verfügbare Befehle:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    SiriCommandBadge(text: "Briefing generieren")
                    SiriCommandBadge(text: "Briefing anzeigen")
                }
                HStack {
                    SiriCommandBadge(text: "Briefing-Zeit einstellen")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Siri Integration")
        } footer: {
            Text("Nutze Siri um dein Briefing freihändig zu steuern. Die Shortcuts sind automatisch in der Shortcuts App verfügbar.")
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
        guard let userSettings = settings.first else {
            createDefaultSettings()
            return
        }
        selectedLanguage = userSettings.preferredLanguage
        selectedLLMProvider = userSettings.llmProvider
        selectedTTSProvider = userSettings.ttsProvider
        autoRefreshEnabled = userSettings.autoRefreshEnabled
        if let time = userSettings.autoRefreshTime {
            autoRefreshTime = time
        }
        globalShortcutEnabled = userSettings.globalShortcutEnabled
        currentShortcut = KeyboardShortcut(
            keyCode: userSettings.globalShortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: userSettings.globalShortcutModifiers)
        )

        // Sync with services
        if autoRefreshEnabled {
            schedulingService.updateScheduledTime(autoRefreshTime)
            schedulingService.enableScheduling()
        }
        if globalShortcutEnabled {
            shortcutService.updateShortcut(currentShortcut)
            shortcutService.enable()
        }
    }

    private func createDefaultSettings() {
        let defaultSettings = UserSettings()
        modelContext.insert(defaultSettings)
        try? modelContext.save()
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
        guard let userSettings = settings.first else { return }
        userSettings.autoRefreshEnabled = autoRefreshEnabled
        userSettings.autoRefreshTime = autoRefreshTime
        userSettings.globalShortcutEnabled = globalShortcutEnabled
        userSettings.globalShortcutKeyCode = currentShortcut.keyCode
        userSettings.globalShortcutModifiers = currentShortcut.modifiers.rawValue
        try? modelContext.save()
    }
}

// MARK: - Siri Command Badge

struct SiriCommandBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.purple.opacity(0.1))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
