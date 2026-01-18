import Foundation

/// Protocol defining the interface for LLM services
protocol LLMService {
    var provider: LLMProvider { get }

    /// Test connection to the LLM provider
    func testConnection() async throws -> LLMConnectionTestResult

    /// Generate a completion for the given prompt
    func complete(prompt: String, systemPrompt: String?) async throws -> String
}

/// Result of a connection test
struct LLMConnectionTestResult {
    let success: Bool
    let message: String
    let modelName: String?
    let responseTime: TimeInterval?

    static func success(model: String, responseTime: TimeInterval) -> LLMConnectionTestResult {
        LLMConnectionTestResult(
            success: true,
            message: "Verbindung erfolgreich",
            modelName: model,
            responseTime: responseTime
        )
    }

    static func failure(_ message: String) -> LLMConnectionTestResult {
        LLMConnectionTestResult(
            success: false,
            message: message,
            modelName: nil,
            responseTime: nil
        )
    }
}

/// Errors that can occur during LLM operations
enum LLMError: LocalizedError {
    case invalidAPIKey
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(Int, String?)
    case modelNotFound(String)
    case ollamaNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Ungültiger API-Schlüssel"
        case .invalidURL:
            return "Ungültige URL"
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        case .invalidResponse:
            return "Ungültige Antwort vom Server"
        case .rateLimited:
            return "Rate-Limit erreicht. Bitte warten Sie einen Moment."
        case .serverError(let code, let message):
            if let message = message {
                return "Serverfehler (\(code)): \(message)"
            }
            return "Serverfehler: \(code)"
        case .modelNotFound(let model):
            return "Modell '\(model)' nicht gefunden"
        case .ollamaNotRunning:
            return "Ollama ist nicht erreichbar. Bitte starten Sie Ollama."
        }
    }
}

/// Factory for creating LLM services
enum LLMServiceFactory {
    static func create(
        provider: LLMProvider,
        apiKey: String?,
        modelId: String,
        ollamaBaseURL: String = "http://localhost:11434"
    ) -> LLMService {
        switch provider {
        case .openai:
            return OpenAIService(apiKey: apiKey ?? "", modelId: modelId)
        case .anthropic:
            return AnthropicService(apiKey: apiKey ?? "", modelId: modelId)
        case .google:
            return GoogleService(apiKey: apiKey ?? "", modelId: modelId)
        case .ollama:
            return OllamaService(baseURL: ollamaBaseURL, modelId: modelId)
        }
    }
}
