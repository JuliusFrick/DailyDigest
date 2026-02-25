import SwiftUI

/// Settings view for LLM provider configuration
struct LLMSettingsView: View {
    @EnvironmentObject private var settingsStore: UserSettingsStore

    @State private var selectedProvider: LLMProvider = .openai
    @State private var selectedModelId: String = ""
    @State private var apiKey: String = ""
    @State private var ollamaURL: String = "http://localhost:11434"
    @State private var ollamaModels: [String] = []
    @State private var openClawBaseURL: String = "http://100.0.0.1:18789"
    @State private var openClawAgentId: String = "default"

    @State private var isTestingConnection = false
    @State private var testResult: LLMConnectionTestResult?
    @State private var showTestResult = false
    @State private var isFetchingOllamaModels = false

    private let llmConfigurationStorageKey = "llm_configuration"
    private let legacyLLMConfigurationStorageKey = "llmConfiguration"

    private let keychain = KeychainService.shared

    var body: some View {
        Form {
            providerSection
            modelSection
            credentialsSection
            connectionTestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.tuiBackground)
        .font(.tuiMonoSmall)
        .controlSize(.small)
        .onAppear(perform: loadSettings)
        .onChange(of: selectedProvider) { _, newProvider in
            loadAPIKey(for: newProvider)
            if newProvider == .openClaw {
                let normalizedBaseURL = openClawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                openClawBaseURL = normalizedBaseURL.isEmpty ? "http://100.0.0.1:18789" : normalizedBaseURL
                let normalizedAgentId = openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
                openClawAgentId = normalizedAgentId.isEmpty ? "default" : normalizedAgentId
                selectedModelId = openClawAgentId.isEmpty ? "default" : openClawAgentId
            } else {
                selectedModelId = newProvider.defaultModel.id
            }
            saveSettings()
            testResult = nil

            if newProvider == .ollama {
                fetchOllamaModels()
            }
        }
        .onChange(of: selectedModelId) { _, _ in
            if selectedProvider == .openClaw {
                let normalizedAgentId = selectedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
                openClawAgentId = normalizedAgentId.isEmpty ? "default" : normalizedAgentId
            }
            saveSettings()
            testResult = nil
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        Section {
            ForEach(LLMProvider.allCases) { provider in
                ProviderRow(
                    provider: provider,
                    isSelected: selectedProvider == provider,
                    hasAPIKey: provider.requiresAPIKey ? keychain.hasLLMAPIKey(for: provider.rawValue) : true
                ) {
                    withAnimation(.briefingSpring) {
                        selectedProvider = provider
                    }
                }
            }
        } header: {
            Text("KI-Provider")
        } footer: {
            Text("Wähle deinen bevorzugten LLM-Provider für die Zusammenfassungen.")
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section {
            if selectedProvider == .ollama {
                ollamaModelPicker
            } else if selectedProvider == .openClaw {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("OpenClaw Agent ID", text: $selectedModelId, prompt: Text("default"))
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Der Agent wird als `openclaw:<Agent-ID>` an den VPS weitergeleitet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Modell", selection: $selectedModelId) {
                    ForEach(selectedProvider.availableModels) { model in
                        VStack(alignment: .leading) {
                            Text(model.name)
                            Text(model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let model = selectedProvider.availableModels.first(where: { $0.id == selectedModelId }) {
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Modell")
        }
    }

    private var ollamaModelPicker: some View {
        Group {
            if isFetchingOllamaModels {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Lade Modelle...")
                        .foregroundStyle(.secondary)
                }
            } else if ollamaModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Modell", selection: $selectedModelId) {
                        ForEach(selectedProvider.availableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Installierte Modelle laden") {
                        fetchOllamaModels()
                    }
                    .font(.caption)
                }
            } else {
                Picker("Modell", selection: $selectedModelId) {
                    ForEach(ollamaModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                Button("Modelle aktualisieren") {
                    fetchOllamaModels()
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        Section {
            if selectedProvider == .openClaw {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("OpenClaw Base URL", text: $openClawBaseURL, prompt: Text("http://100.0.0.1:18789"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openClawBaseURL) { _, _ in
                            saveSettings()
                            testResult = nil
                        }

                    Text("Tipp: `http://host:port` reicht, `/v1` wird automatisch ergänzt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedProvider.requiresAPIKey {
                SecureField("API-Schlüssel", text: $apiKey, prompt: Text(selectedProvider.apiKeyPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, newValue in
                        saveAPIKey(newValue)
                        testResult = nil
                    }

                if let helpURL = selectedProvider.apiKeyHelpURL {
                    Link(destination: helpURL) {
                        Label("API-Schlüssel erstellen", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            } else {
                TextField("Ollama URL", text: $ollamaURL, prompt: Text("http://localhost:11434"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: ollamaURL) { _, _ in
                        saveSettings()
                        testResult = nil
                    }

                if let helpURL = selectedProvider.apiKeyHelpURL {
                    Link(destination: helpURL) {
                        Label("Ollama herunterladen", systemImage: "arrow.down.circle")
                    }
                    .font(.caption)
                }
            }
        } header: {
            Text(selectedProvider.requiresAPIKey ? "API-Schlüssel" : "Verbindung")
        } footer: {
            if selectedProvider.requiresAPIKey {
                if let validation = openClawValidationMessage {
                    Text(validation)
                        .foregroundStyle(.orange)
                } else {
                    Text("Der API-Schlüssel wird sicher in der macOS Keychain gespeichert.")
                }
            } else {
                Text("Ollama muss lokal installiert und gestartet sein.")
            }
        }
    }

    // MARK: - Connection Test Section

    private var connectionTestSection: some View {
        Section {
            Button(action: testConnection) {
                HStack {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Teste Verbindung...")
                    } else {
                        Image(systemName: "network")
                        Text("Verbindung testen")
                    }
                }
            }
            .disabled(isTestingConnection || !canTestConnection)

            if let result = testResult {
                ConnectionTestResultView(result: result)
            }
        } header: {
            Text("Verbindungstest")
        }
    }

    private var canTestConnection: Bool {
        if selectedProvider.requiresAPIKey {
            if selectedProvider == .openClaw {
                return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !openClawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !selectedModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    isValidOpenClawURL(openClawBaseURL)
            }
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            let normalizedModelId = selectedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOllamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOpenClawBaseURL = openClawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOpenClawAgentId = openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedOpenClawModel = selectedProvider == .openClaw
                ? (normalizedOpenClawAgentId.isEmpty ? "default" : normalizedOpenClawAgentId)
                : normalizedModelId
            let resolvedOpenClawBaseURL = selectedProvider == .openClaw
                ? (normalizedOpenClawBaseURL.isEmpty ? "http://100.0.0.1:18789" : normalizedOpenClawBaseURL)
                : normalizedOpenClawBaseURL

            if selectedProvider == .openClaw && !isValidOpenClawURL(resolvedOpenClawBaseURL) {
                await MainActor.run {
                    testResult = .failure("OpenClaw Base URL ist ungültig. Bitte prüfe das Format.")
                    isTestingConnection = false
                }
                return
            }

            let service = LLMServiceFactory.create(
                provider: selectedProvider,
                apiKey: normalizedAPIKey,
                modelId: resolvedOpenClawModel,
                ollamaBaseURL: normalizedOllamaURL,
                openClawBaseURL: resolvedOpenClawBaseURL,
                openClawAgentId: resolvedOpenClawModel
            )

            do {
                let result = try await service.testConnection()
                await MainActor.run {
                    testResult = result
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }

    private func fetchOllamaModels() {
        isFetchingOllamaModels = true

        Task {
            let service = OllamaService(baseURL: ollamaURL, modelId: selectedModelId)
            do {
                let models = try await service.fetchAvailableModels()
                await MainActor.run {
                    ollamaModels = models
                    if !models.isEmpty && !models.contains(selectedModelId) {
                        selectedModelId = models.first ?? "gpt-4o"
                    }
                    isFetchingOllamaModels = false
                }
            } catch {
                await MainActor.run {
                    ollamaModels = []
                    isFetchingOllamaModels = false
                }
            }
        }
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        if let provider = LLMProvider(rawValue: settingsStore.settings.llmProvider) {
            selectedProvider = provider
            loadAPIKey(for: provider)
        }

        // Load LLM configuration from UserDefaults for model and URL
        if let config = loadLLMConfiguration(),
           config.provider == selectedProvider {
            applyConfiguration(config)
        } else {
            selectedModelId = selectedProvider.defaultModel.id
            ollamaURL = "http://localhost:11434"
            openClawBaseURL = "http://100.0.0.1:18789"
            openClawAgentId = "default"
            if selectedProvider == .openClaw {
                selectedModelId = openClawAgentId
            }
        }

        if selectedProvider == .ollama {
            fetchOllamaModels()
        }
    }

    private func loadAPIKey(for provider: LLMProvider) {
        if provider.requiresAPIKey {
            apiKey = keychain.loadLLMAPIKey(for: provider.rawValue) ?? ""
        } else {
            apiKey = ""
        }
    }

    private func saveAPIKey(_ key: String) {
        guard selectedProvider.requiresAPIKey else { return }

        if key.isEmpty {
            try? keychain.deleteLLMAPIKey(for: selectedProvider.rawValue)
        } else {
            try? keychain.saveLLMAPIKey(key, for: selectedProvider.rawValue)
        }
    }

    private func saveSettings() {
        // Save provider to app settings
        settingsStore.update { s in
            s.llmProvider = selectedProvider.rawValue
        }

        let normalizedModelId = selectedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOpenClawAgentId = openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveOpenClawAgentId = selectedProvider == .openClaw
            ? (normalizedOpenClawAgentId.isEmpty ? "default" : normalizedOpenClawAgentId)
            : normalizedOpenClawAgentId
        let effectiveModelId = selectedProvider == .openClaw
            ? effectiveOpenClawAgentId
            : normalizedModelId.isEmpty
            ? selectedProvider.defaultModel.id
            : normalizedModelId

        if selectedProvider == .openClaw {
            openClawAgentId = effectiveOpenClawAgentId
            selectedModelId = effectiveModelId
        }
        let normalizedOllamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOpenClawBaseURL = openClawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = LLMConfiguration(
            provider: selectedProvider,
            modelId: effectiveModelId,
            ollamaBaseURL: normalizedOllamaURL.isEmpty ? "http://localhost:11434" : normalizedOllamaURL,
            openClawBaseURL: normalizedOpenClawBaseURL.isEmpty ? "http://100.0.0.1:18789" : normalizedOpenClawBaseURL,
            openClawAgentId: effectiveOpenClawAgentId
        )
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: llmConfigurationStorageKey)
            UserDefaults.standard.set(data, forKey: legacyLLMConfigurationStorageKey)
        }
    }

    private func loadLLMConfiguration() -> LLMConfiguration? {
        if let data = UserDefaults.standard.data(forKey: llmConfigurationStorageKey),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }

        if let data = UserDefaults.standard.data(forKey: legacyLLMConfigurationStorageKey),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            UserDefaults.standard.set(data, forKey: llmConfigurationStorageKey)
            return config
        }

        return nil
    }

    private func applyConfiguration(_ config: LLMConfiguration) {
        selectedModelId = config.modelId
        ollamaURL = config.ollamaBaseURL
        openClawBaseURL = config.openClawBaseURL
        openClawAgentId = config.openClawAgentId.isEmpty ? "default" : config.openClawAgentId

        if selectedProvider == .openClaw {
            selectedModelId = openClawAgentId
        }
    }

    // MARK: - OpenClaw Validation

    private var openClawValidationMessage: String? {
        guard selectedProvider == .openClaw else { return nil }

        let baseURL = openClawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBaseURL = baseURL.isEmpty ? "http://100.0.0.1:18789" : baseURL

        if !isValidOpenClawURL(effectiveBaseURL) {
            return "Die OpenClaw Base URL ist ungültig. Beispiel: http://100.0.0.1:18789"
        }

        return nil
    }

    private func isValidOpenClawURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let provider: LLMProvider
    let isSelected: Bool
    let hasAPIKey: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.title2)
                    .foregroundStyle(provider.brandColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(providerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                } else if provider.requiresAPIKey && !hasAPIKey {
                    Image(systemName: "key")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var providerSubtitle: String {
        switch provider {
        case .openai:
            return "GPT-4, GPT-4o"
        case .groq:
            return "Llama 3, Mixtral (Sehr schnell)"
        case .anthropic:
            return "Claude Sonnet, Claude Opus"
        case .google:
            return "Gemini Pro, Gemini Flash"
        case .mistral:
            return "Mistral Large, Codestral"
        case .ollama:
            return "Lokal, Datenschutz-freundlich"
        case .openClaw:
            return "VPS-gebundener Claude-Agent"
        }
    }
}

// MARK: - Connection Test Result View

private struct ConnectionTestResultView: View {
    let result: LLMConnectionTestResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(result.success ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.success ? "Verbindung erfolgreich" : "Verbindung fehlgeschlagen")
                    .fontWeight(.medium)

                if result.success {
                    if let model = result.modelName {
                        Text("Modell: \(model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let time = result.responseTime {
                        Text("Antwortzeit: \(String(format: "%.2f", time))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
