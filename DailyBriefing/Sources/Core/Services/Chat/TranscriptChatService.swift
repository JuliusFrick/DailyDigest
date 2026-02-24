import Foundation
import Combine

// MARK: - Transcript Chat Message

/// Message in a transcript chat conversation
struct TranscriptChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let relatedChunks: [TranscriptChunk]?
    
    enum Role: String {
        case user
        case assistant
        case system
    }
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        relatedChunks: [TranscriptChunk]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.relatedChunks = relatedChunks
    }
    
    static func == (lhs: TranscriptChatMessage, rhs: TranscriptChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transcript Chat Service

/// Service for chatting about meeting transcripts using RAG (Retrieval-Augmented Generation)
@MainActor
final class TranscriptChatService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = TranscriptChatService()
    
    // MARK: - Published Properties
    
    @Published private(set) var messages: [String: [TranscriptChatMessage]] = [:] // meetingId -> messages
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private let embeddingService = TranscriptEmbeddingService.shared
    private let vectorStore = VectorStore.shared
    private let modelService = ModelSelectionService.shared
    private let keychain = KeychainService.shared
    
    // Configuration
    private let topK = 5 // Number of relevant chunks to retrieve
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Send a message and get a response
    /// - Parameters:
    ///   - text: User message
    ///   - meetingId: Meeting identifier
    func sendMessage(_ text: String, meetingId: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Check if transcript chunks exist
        guard vectorStore.hasChunks(for: meetingId) else {
            throw TranscriptChatError.noTranscriptAvailable
        }
        
        // Add user message
        let userMessage = TranscriptChatMessage(role: .user, content: text)
        addMessage(userMessage, for: meetingId)
        
        isGenerating = true
        lastError = nil
        
        do {
            // 1. Search for relevant chunks
            let relevantChunks = try await vectorStore.search(
                query: text,
                meetingId: meetingId,
                topK: topK
            )
            
            // 2. Build context with top chunks
            let context = buildContext(from: relevantChunks)
            
            // 3. Generate response using LLM
            let response = try await generateResponse(
                query: text,
                context: context,
                meetingId: meetingId
            )
            
            // 4. Add assistant message with citations
            let chunks = relevantChunks.map { $0.chunk }
            let assistantMessage = TranscriptChatMessage(
                role: .assistant,
                content: response,
                relatedChunks: chunks
            )
            addMessage(assistantMessage, for: meetingId)
            
            isGenerating = false
        } catch {
            isGenerating = false
            lastError = error
            throw error
        }
    }
    
    /// Get messages for a specific meeting
    func getMessages(for meetingId: String) -> [TranscriptChatMessage] {
        return messages[meetingId] ?? []
    }
    
    /// Clear chat history for a meeting
    func clearChat(for meetingId: String) {
        messages[meetingId] = []
    }
    
    /// Clear all chat histories
    func clearAllChats() {
        messages.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func addMessage(_ message: TranscriptChatMessage, for meetingId: String) {
        if messages[meetingId] == nil {
            messages[meetingId] = []
        }
        messages[meetingId]?.append(message)
    }
    
    private func buildContext(from results: [(chunk: TranscriptChunk, similarity: Float)]) -> String {
        var context = "Relevante Abschnitte aus dem Transkript:\n\n"
        
        for (index, result) in results.enumerated() {
            context += "[\(index + 1)] (\(result.chunk.formattedStartTime()))\n"
            context += result.chunk.text
            context += "\n\n"
        }
        
        return context
    }
    
    private func generateResponse(
        query: String,
        context: String,
        meetingId: String
    ) async throws -> String {
        // Use ModelSelectionService to get the selected model for chat
        let selectedModel = modelService.getModel(for: .chat)
        
        // Convert ModelProvider to LLMProvider and get model ID
        let (llmProvider, modelId) = convertToLLMProvider(selectedModel)
        
        // Get API key if needed
        let apiKey = keychain.loadLLMAPIKey(for: llmProvider.rawValue)
        if llmProvider.requiresAPIKey && (apiKey == nil || apiKey?.isEmpty == true) {
            throw TranscriptChatError.llmNotConfigured
        }

        let config = loadLLMConfiguration()
        
        // Create LLM service
        let llmService = LLMServiceFactory.create(
            provider: llmProvider,
            apiKey: apiKey,
            modelId: modelId,
            ollamaBaseURL: "http://localhost:11434",
            openClawBaseURL: config.openClawBaseURL,
            openClawAgentId: config.openClawAgentId
        )
        
        let systemPrompt = buildSystemPrompt()
        let prompt = buildPrompt(query: query, context: context, meetingId: meetingId)
        
        return try await llmService.complete(prompt: prompt, systemPrompt: systemPrompt)
    }
    
    /// Convert ModelProvider to LLMProvider format
    private func convertToLLMProvider(_ modelProvider: ModelProvider) -> (LLMProvider, String) {
        switch modelProvider {
        case .ollama(let model):
            return (.ollama, model)
        case .openai(let model):
            return (.openai, model)
        case .anthropic(let model):
            return (.anthropic, model)
        default:
            // Fallback to a sensible default
            return (.openai, "gpt-4o-mini")
        }
    }
    
    private func buildSystemPrompt() -> String {
        """
        Du bist ein hilfreicher Assistent, der Fragen zu Meeting-Transkripten beantwortet.
        Du erhältst relevante Abschnitte aus dem Transkript und sollst darauf basierend Fragen beantworten.
        
        WICHTIG:
        - Antworte immer auf Deutsch
        - Beziehe dich nur auf Informationen aus dem bereitgestellten Transkript
        - Wenn du etwas nicht weißt oder es nicht im Transkript steht, sage das ehrlich
        - Gib konkrete Zeitstempel an, wenn du auf bestimmte Stellen verweist
        - Sei präzise, hilfreich und freundlich
        """
    }
    
    private func buildPrompt(query: String, context: String, meetingId: String) -> String {
        var prompt = context + "\n"
        
        // Add conversation history if exists
        if let history = messages[meetingId], !history.isEmpty {
            prompt += "Bisheriger Gesprächsverlauf:\n"
            for message in history.suffix(6) { // Last 3 exchanges
                switch message.role {
                case .user:
                    prompt += "Benutzer: \(message.content)\n"
                case .assistant:
                    prompt += "Assistent: \(message.content)\n"
                case .system:
                    break
                }
            }
            prompt += "\n"
        }
        
        prompt += "Neue Frage: \(query)\n\n"
        prompt += "Antwort:"
        
        return prompt
    }

    private func loadLLMConfiguration() -> LLMConfiguration {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        
        if let data = UserDefaults.standard.data(forKey: "llmConfiguration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        
        return LLMConfiguration()
    }
}

// MARK: - Errors

enum TranscriptChatError: LocalizedError {
    case noTranscriptAvailable
    case llmNotConfigured
    case embeddingFailed
    case searchFailed
    
    var errorDescription: String? {
        switch self {
        case .noTranscriptAvailable:
            return "Kein Transkript verfügbar. Bitte zuerst eine Aufnahme transkribieren."
        case .llmNotConfigured:
            return "KI-Provider nicht konfiguriert. Bitte in den Einstellungen einrichten."
        case .embeddingFailed:
            return "Fehler beim Generieren der Embeddings."
        case .searchFailed:
            return "Fehler bei der Suche im Transkript."
        }
    }
}
