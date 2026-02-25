import Foundation

/// OpenClaw-compatible OpenAI wrapper for VPS-hosted Claude workflows.
/// OpenClaw exposes an OpenAI-compatible `/v1/chat/completions` endpoint where
/// the model is represented as `openclaw:<agentId>`.
final class OpenClawService: LLMService {
    let provider: LLMProvider = .openClaw
    private let openAIService: OpenAIService
    private static let fallbackGatewayBaseURL = "http://100.0.0.1:18789"

    init(baseURL: String, authToken: String, agentId: String) {
        let normalizedBaseURL = Self.normalizedGatewayBaseURL(from: baseURL)

        let normalizedAgentId = agentId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "default" : agentId.trimmingCharacters(in: .whitespacesAndNewlines)

        self.openAIService = OpenAIService(
            apiKey: authToken,
            modelId: "openclaw:\(normalizedAgentId)",
            baseURL: normalizedBaseURL,
            provider: .openClaw
        )
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        try await openAIService.testConnection()
    }

    func complete(prompt: String, systemPrompt: String?) async throws -> String {
        try await openAIService.complete(prompt: prompt, systemPrompt: systemPrompt)
    }

    private static func normalizedGatewayBaseURL(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "\(fallbackGatewayBaseURL)/v1"

        let candidate = trimmed.isEmpty ? fallbackGatewayBaseURL : trimmed
        guard let parsed = URL(string: candidate),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              parsed.host != nil else {
            return fallback
        }

        var normalized = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/chat/completions") {
            normalized = String(normalized.dropLast("/chat/completions".count))
        }

        if normalized.hasSuffix("/v1") {
            return normalized
        }

        return "\(normalized)/v1"
    }
}
