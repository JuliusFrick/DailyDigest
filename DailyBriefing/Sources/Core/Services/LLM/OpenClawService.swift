import Foundation

/// OpenClaw-compatible OpenAI wrapper for VPS-hosted Claude workflows.
/// OpenClaw exposes an OpenAI-compatible `/v1/chat/completions` endpoint where
/// the model is represented as `openclaw:<agentId>`.
final class OpenClawService: LLMService {
    let provider: LLMProvider = .openClaw
    private let openAIService: OpenAIService

    init(baseURL: String, authToken: String, agentId: String) {
        let normalizedBaseURL = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let normalizedAgentId = agentId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "default" : agentId.trimmingCharacters(in: .whitespacesAndNewlines)

        self.openAIService = OpenAIService(
            apiKey: authToken,
            modelId: "openclaw:\(normalizedAgentId)",
            baseURL: normalizedBaseURL.isEmpty ? "http://100.0.0.1:18789" : normalizedBaseURL,
            provider: .openClaw
        )
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        try await openAIService.testConnection()
    }

    func complete(prompt: String, systemPrompt: String?) async throws -> String {
        try await openAIService.complete(prompt: prompt, systemPrompt: systemPrompt)
    }
}
