import Foundation

/// Service for summarizing meeting notes
@MainActor
final class MeetingSummarizerService: ObservableObject {
    static let shared = MeetingSummarizerService()
    
    @Published private(set) var isSummarizing = false
    
    private let keychain = KeychainService.shared
    
    private init() {}
    
    /// Summarize meeting notes using the configured LLM provider
    /// - Parameter notes: The meeting notes to summarize
    /// - Returns: The generated summary
    func summarize(notes: String) async throws -> String {
        isSummarizing = true
        defer { isSummarizing = false }
        
        let settings = UserSettingsStore.shared.settings
        guard let provider = LLMProvider(rawValue: settings.llmProvider) else {
            throw LLMError.modelNotFound("Kein Provider ausgewählt")
        }
        
        let apiKey = keychain.loadLLMAPIKey(for: provider.rawValue)
        
        // Load configuration from UserDefaults
        var modelId = provider.defaultModel.id
        var ollamaURL = "http://localhost:11434"
        var openClawBaseURL = "http://100.0.0.1:18789"
        var openClawAgentId = "default"
        
        if let config = loadLLMConfiguration() {
            modelId = config.modelId
            ollamaURL = config.ollamaBaseURL
            openClawBaseURL = config.openClawBaseURL
            openClawAgentId = config.openClawAgentId.isEmpty ? "default" : config.openClawAgentId
        }
        
        let service = LLMServiceFactory.create(
            provider: provider,
            apiKey: apiKey,
            modelId: modelId,
            ollamaBaseURL: ollamaURL,
            openClawBaseURL: openClawBaseURL,
            openClawAgentId: openClawAgentId
        )
        
        let prompt = """
        Erstelle eine prägnante Zusammenfassung der folgenden Meeting-Notizen. 
        Konzentriere dich auf die wichtigsten Punkte, Entscheidungen und Aufgaben.
        
        Notizen:
        \(notes)
        """
        
        let systemPrompt = "Du bist ein hilfreicher Assistent, der Meeting-Transkripte zusammenfasst."
        
        return try await service.complete(prompt: prompt, systemPrompt: systemPrompt)
    }

    private func loadLLMConfiguration() -> LLMConfiguration? {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        
        if let data = UserDefaults.standard.data(forKey: "llmConfiguration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        
        return nil
    }
}
