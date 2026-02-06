import Foundation
import Combine

/// Message in a chat conversation
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Service for chatting about the current briefing
@MainActor
final class BriefingChatService: ObservableObject {

    // MARK: - Singleton

    static let shared = BriefingChatService()

    // MARK: - Published Properties

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?

    // MARK: - Private Properties

    private let keychain = KeychainService.shared
    private let modelService = ModelSelectionService.shared
    private var currentBriefing: Briefing?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Set the current briefing context for chat
    func setBriefingContext(_ briefing: Briefing?) {
        if currentBriefing?.id != briefing?.id {
            // Reset chat when briefing changes
            messages = []
            currentBriefing = briefing
        }
    }

    /// Send a message and get a response
    func sendMessage(_ content: String) async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard currentBriefing != nil else {
            throw ChatError.noBriefingContext
        }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)

        isLoading = true
        lastError = nil

        do {
            // Generate response
            let response = try await generateResponse(for: content)

            // Add assistant message
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)

            isLoading = false
        } catch {
            isLoading = false
            lastError = error
            throw error
        }
    }

    /// Clear the chat history
    func clearChat() {
        messages = []
    }

    // MARK: - Private Methods

    private func generateResponse(for userMessage: String) async throws -> String {
        // Use ModelSelectionService to get the selected model for chat with fallback
        let selectedModel = await modelService.getModelWithFallback(for: .chat)
        
        // Convert ModelProvider to LLMProvider and get model ID
        let (llmProvider, modelId) = convertToLLMProvider(selectedModel)
        
        // Get API key if needed
        let apiKey = keychain.loadLLMAPIKey(for: llmProvider.rawValue)
        if llmProvider.requiresAPIKey && (apiKey == nil || apiKey?.isEmpty == true) {
            throw ChatError.llmNotConfigured
        }

        // Create LLM service
        let llmService = LLMServiceFactory.create(
            provider: llmProvider,
            apiKey: apiKey,
            modelId: modelId,
            ollamaBaseURL: "http://localhost:11434"
        )

        let systemPrompt = buildSystemPrompt()
        let prompt = buildPrompt(userMessage: userMessage)

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
        guard let briefing = currentBriefing else { return "" }

        var context = """
        Du bist ein hilfreicher Assistent, der Fragen zum heutigen Briefing beantwortet.
        Antworte immer auf Deutsch und sei präzise und hilfreich.

        Hier ist das aktuelle Briefing vom \(formatDate(briefing.generatedAt)):

        ZUSAMMENFASSUNG:
        \(briefing.summary)

        DETAILS NACH QUELLEN:
        """

        for section in briefing.sections {
            context += "\n\n## \(section.sourceName) (\(section.items.count) Einträge):"
            for item in section.items {
                context += "\n- \(item.title)"
                if let subtitle = item.subtitle {
                    context += " (\(subtitle))"
                }
                if let body = item.body, !body.isEmpty {
                    context += "\n  Beschreibung: \(body.prefix(200))..."
                }
                if let attendees = item.metadata["attendees"], !attendees.isEmpty {
                    context += "\n  Teilnehmer: \(attendees)"
                }
                if let location = item.metadata["location"], !location.isEmpty {
                    context += "\n  Ort: \(location)"
                }
                if let duration = item.metadata["duration"] {
                    context += "\n  Dauer: \(duration)"
                }
            }
        }

        context += """

        Beantworte Fragen basierend auf diesen Informationen. Wenn du etwas nicht weisst, sag es ehrlich.
        """

        return context
    }

    private func buildPrompt(userMessage: String) -> String {
        // Include recent conversation history for context
        var prompt = ""

        // Add last few messages for context
        let recentMessages = messages.suffix(6)
        for message in recentMessages {
            switch message.role {
            case .user:
                prompt += "Benutzer: \(message.content)\n"
            case .assistant:
                prompt += "Assistent: \(message.content)\n"
            case .system:
                break
            }
        }

        prompt += "Benutzer: \(userMessage)\nAssistent:"

        return prompt
    }

    private func loadLLMConfiguration() -> LLMConfiguration? {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        return LLMConfiguration()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy 'um' HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case noBriefingContext
    case llmNotConfigured
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noBriefingContext:
            return "Kein Briefing vorhanden. Bitte zuerst ein Briefing generieren."
        case .llmNotConfigured:
            return "KI-Provider nicht konfiguriert. Bitte in den Einstellungen einrichten."
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        }
    }
}
