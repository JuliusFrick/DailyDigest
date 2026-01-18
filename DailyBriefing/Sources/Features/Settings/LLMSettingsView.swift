import SwiftUI

/// Settings view for LLM provider configuration
struct LLMSettingsView: View {
    @EnvironmentObject private var settingsStore: UserSettingsStore

    @State private var selectedProvider: LLMProvider = .openai
    @State private var selectedModelId: String = ""
    @State private var apiKey: String = ""
    @State private var ollamaURL: String = "http://localhost:11434"
    @State private var ollamaModels: [String] = []

    @State private var isTestingConnection = false
    @State private var testResult: LLMConnectionTestResult?
    @State private var showTestResult = false
    @State private var isFetchingOllamaModels = false

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
            selectedModelId = newProvider.defaultModel.id
            saveSettings()
            testResult = nil

            if newProvider == .ollama {
                fetchOllamaModels()
            }
        }
        .onChange(of: selectedModelId) { _, _ in
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
                Text("Der API-Schlüssel wird sicher in der macOS Keychain gespeichert.")
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
            return !apiKey.isEmpty
        }
        return !ollamaURL.isEmpty
    }

    // MARK: - Actions

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            let service = LLMServiceFactory.create(
                provider: selectedProvider,
                apiKey: apiKey,
                modelId: selectedModelId,
                ollamaBaseURL: ollamaURL
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
                        selectedModelId = models.first!
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
        if let data = UserDefaults.standard.data(forKey: "llmConfiguration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            selectedModelId = config.modelId
            ollamaURL = config.ollamaBaseURL
        } else {
            selectedModelId = selectedProvider.defaultModel.id
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

        // Save configuration to UserDefaults
        let config = LLMConfiguration(
            provider: selectedProvider,
            modelId: selectedModelId,
            ollamaBaseURL: ollamaURL
        )
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "llmConfiguration")
        }
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
        case .anthropic:
            return "Claude Sonnet, Claude Opus"
        case .google:
            return "Gemini Pro, Gemini Flash"
        case .ollama:
            return "Lokal, Datenschutz-freundlich"
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

