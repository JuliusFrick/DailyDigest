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

    var body: some View {
        Form {
            briefingSection
            integrationsSection
            llmNavigationSection
            audioSection
            scheduleSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .onAppear(perform: loadSettings)
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
            }
        } header: {
            Text("Zeitplan")
        } footer: {
            Text("Das Briefing wird automatisch zur eingestellten Zeit generiert.")
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
    }

    private func createDefaultSettings() {
        let defaultSettings = UserSettings()
        modelContext.insert(defaultSettings)
        try? modelContext.save()
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
