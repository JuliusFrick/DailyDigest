import SwiftUI
import SwiftData

struct TTSSettingsView: View {
    @Query private var settings: [UserSettings]
    @Environment(\.modelContext) private var modelContext
    @StateObject private var ttsService = TTSService.shared

    @State private var selectedProvider: String = "apple"
    @State private var selectedVoiceId: String = ""
    @State private var playbackSpeed: Double = 1.0
    @State private var isPreviewing: Bool = false

    private var userSettings: UserSettings? {
        settings.first
    }

    var body: some View {
        Form {
            engineSection
            voiceSection
            speedSection
            previewSection
        }
        .formStyle(.grouped)
        .navigationTitle("Sprachausgabe")
        .onAppear(perform: loadSettings)
        .onChange(of: selectedProvider) { _, newValue in
            handleProviderChange(newValue)
        }
        .onChange(of: selectedVoiceId) { _, _ in
            saveSettings()
        }
        .onChange(of: playbackSpeed) { _, newValue in
            handleSpeedChange(newValue)
        }
    }

    // MARK: - Engine Section

    private var engineSection: some View {
        Section {
            Picker("TTS-Engine", selection: $selectedProvider) {
                Text("Apple Native").tag("apple")
                Text("OpenAI TTS").tag("openai")
            }
            .pickerStyle(.menu)

            if selectedProvider == "openai" {
                openAIStatusRow
            }
        } header: {
            Text("Engine")
        } footer: {
            Text(engineFooterText)
        }
    }

    private var openAIStatusRow: some View {
        HStack {
            Image(systemName: hasOpenAIKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(hasOpenAIKey ? .green : .orange)
            Text("API-Schlüssel")
            Spacer()
            Text(hasOpenAIKey ? "Konfiguriert" : "Nicht konfiguriert")
                .foregroundStyle(.secondary)
        }
    }

    private var hasOpenAIKey: Bool {
        KeychainService.shared.loadLLMAPIKey(for: "openai") != nil
    }

    private var engineFooterText: String {
        switch selectedProvider {
        case "openai":
            if hasOpenAIKey {
                return "OpenAI TTS nutzt die OpenAI Audio API für natürliche Sprachsynthese. Der API-Schlüssel wird mit dem KI-Provider geteilt."
            } else {
                return "Für OpenAI TTS wird ein API-Schlüssel benötigt. Konfiguriere diesen unter KI-Provider Einstellungen."
            }
        default:
            return "Apple Native TTS nutzt die integrierten Systemstimmen ohne zusätzliche Kosten."
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        Section {
            if availableVoices.isEmpty {
                Text("Keine Stimmen verfügbar")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Stimme", selection: $selectedVoiceId) {
                    ForEach(availableVoices) { voice in
                        Text(voiceDisplayName(voice))
                            .tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Stimme")
        } footer: {
            if selectedProvider == "apple" {
                Text("Die verfügbaren Stimmen hängen von den auf deinem System installierten Sprachen ab.")
            } else {
                Text("OpenAI bietet mehrere charakteristische Stimmen für verschiedene Anwendungsfälle.")
            }
        }
    }

    private var availableVoices: [TTSVoice] {
        switch selectedProvider {
        case "openai":
            return openAIVoices
        default:
            return filteredAppleVoices
        }
    }

    private var openAIVoices: [TTSVoice] {
        [
            TTSVoice(id: "alloy", name: "Alloy", language: "multilingual", isDefault: false),
            TTSVoice(id: "echo", name: "Echo", language: "multilingual", isDefault: false),
            TTSVoice(id: "fable", name: "Fable", language: "multilingual", isDefault: false),
            TTSVoice(id: "onyx", name: "Onyx", language: "multilingual", isDefault: false),
            TTSVoice(id: "nova", name: "Nova", language: "multilingual", isDefault: true),
            TTSVoice(id: "shimmer", name: "Shimmer", language: "multilingual", isDefault: false)
        ]
    }

    private var filteredAppleVoices: [TTSVoice] {
        // Filter to show German and English voices for better UX
        let preferredLanguages = ["de", "en"]
        return ttsService.availableVoices.filter { voice in
            preferredLanguages.contains(where: { voice.language.hasPrefix($0) })
        }
    }

    private func voiceDisplayName(_ voice: TTSVoice) -> String {
        if selectedProvider == "openai" {
            return openAIVoiceDescription(voice.id)
        } else {
            let languageDisplay = formatLanguage(voice.language)
            return "\(voice.name) (\(languageDisplay))"
        }
    }

    private func openAIVoiceDescription(_ voiceId: String) -> String {
        switch voiceId {
        case "alloy": return "Alloy - Neutral und ausgewogen"
        case "echo": return "Echo - Warm und klar"
        case "fable": return "Fable - Ausdrucksstark und dynamisch"
        case "onyx": return "Onyx - Tief und autoritär"
        case "nova": return "Nova - Freundlich und natürlich"
        case "shimmer": return "Shimmer - Hell und optimistisch"
        default: return voiceId
        }
    }

    private func formatLanguage(_ languageCode: String) -> String {
        if languageCode.hasPrefix("de") {
            return "Deutsch"
        } else if languageCode.hasPrefix("en") {
            if languageCode.contains("US") {
                return "English US"
            } else if languageCode.contains("GB") {
                return "English UK"
            }
            return "English"
        }
        return languageCode
    }

    // MARK: - Speed Section

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Geschwindigkeit")
                    Spacer()
                    Text(String(format: "%.1fx", playbackSpeed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $playbackSpeed, in: 0.5...2.0, step: 0.1)

                HStack {
                    Text("0.5x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("1.0x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("2.0x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("Standard-Geschwindigkeit ist 1.0x. Erhöhe für schnellere Wiedergabe oder reduziere für bessere Verständlichkeit.")
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            Button {
                previewVoice()
            } label: {
                HStack {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    Text(isPreviewing ? "Stoppen" : "Stimme testen")
                }
            }
            .disabled(selectedProvider == "openai" && !hasOpenAIKey)
        } header: {
            Text("Vorschau")
        } footer: {
            Text("Teste die ausgewählte Stimme mit einem kurzen Beispieltext.")
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let userSettings else {
            createDefaultSettings()
            return
        }

        selectedProvider = userSettings.ttsProvider
        playbackSpeed = userSettings.playbackSpeed

        // Load voice ID or select default
        if let voiceId = userSettings.ttsVoiceId {
            selectedVoiceId = voiceId
        } else {
            selectDefaultVoice()
        }

        // Sync with TTS service
        ttsService.setRate(Float(playbackSpeed))
        if let voice = availableVoices.first(where: { $0.id == selectedVoiceId }) {
            ttsService.setVoice(voice)
        }
    }

    private func createDefaultSettings() {
        let defaultSettings = UserSettings()
        modelContext.insert(defaultSettings)
        try? modelContext.save()

        selectedProvider = defaultSettings.ttsProvider
        playbackSpeed = defaultSettings.playbackSpeed
        selectDefaultVoice()
    }

    private func selectDefaultVoice() {
        let voices = availableVoices
        if let defaultVoice = voices.first(where: { $0.isDefault }) {
            selectedVoiceId = defaultVoice.id
        } else if let firstVoice = voices.first {
            selectedVoiceId = firstVoice.id
        }
    }

    private func handleProviderChange(_ provider: String) {
        // Update voice selection for new provider
        selectDefaultVoice()

        // Update TTS service
        ttsService.switchProvider(to: provider)

        saveSettings()
    }

    private func handleSpeedChange(_ speed: Double) {
        ttsService.setRate(Float(speed))
        saveSettings()
    }

    private func saveSettings() {
        guard let userSettings else { return }

        userSettings.ttsProvider = selectedProvider
        userSettings.ttsVoiceId = selectedVoiceId
        userSettings.playbackSpeed = playbackSpeed

        try? modelContext.save()
    }

    private func previewVoice() {
        if isPreviewing {
            ttsService.stop()
            isPreviewing = false
        } else {
            // Apply current settings before preview
            if let voice = availableVoices.first(where: { $0.id == selectedVoiceId }) {
                ttsService.setVoice(voice)
            }
            ttsService.setRate(Float(playbackSpeed))

            let previewText = previewTextForLanguage()
            ttsService.speak(text: previewText)
            isPreviewing = true

            // Listen for completion
            Task { @MainActor in
                // Simple polling to detect when playback stops
                while ttsService.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                isPreviewing = false
            }
        }
    }

    private func previewTextForLanguage() -> String {
        if selectedProvider == "openai" {
            return "Dies ist eine Vorschau der ausgewählten Stimme. Die Sprachqualität von OpenAI TTS ist besonders natürlich."
        }

        // For Apple voices, check selected voice language
        if let voice = availableVoices.first(where: { $0.id == selectedVoiceId }) {
            if voice.language.hasPrefix("de") {
                return "Dies ist eine Vorschau der ausgewählten Stimme für dein Daily Briefing."
            } else if voice.language.hasPrefix("en") {
                return "This is a preview of the selected voice for your daily briefing."
            }
        }

        return "Dies ist eine Vorschau der ausgewählten Stimme."
    }
}

#Preview {
    NavigationStack {
        TTSSettingsView()
    }
}
