import Foundation

/// OpenAI API service implementation
final class OpenAIService: LLMService {
    let provider: LLMProvider
    private let apiKey: String
    private let modelId: String
    private let baseURL: String

    init(apiKey: String, modelId: String, baseURL: String = "https://api.openai.com/v1", provider: LLMProvider = .openai) {
        self.apiKey = apiKey
        self.modelId = modelId
        self.baseURL = baseURL
        self.provider = provider
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        let startTime = Date()

        guard !apiKey.isEmpty else {
            return .failure("API-Schlüssel fehlt")
        }

        let request: URLRequest
        do {
            request = try makeRequest()
        } catch {
            return .failure("Ungültige URL")
        }

        var body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": "Say 'OK' and nothing else."]
            ],
            "max_tokens": 5
        ]

        applyProviderSpecificBody(to: &body)
        var mutableRequest = request
        mutableRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: mutableRequest)
            let responseTime = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Ungültige Antwort")
            }

            switch httpResponse.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let model = json["model"] as? String {
                    return .success(model: model, responseTime: responseTime)
                }
                return .success(model: modelId, responseTime: responseTime)

            case 401:
                return .failure("Ungültiger API-Schlüssel")

            case 404:
                if provider == .openClaw {
                    return .failure(openClawEndpointErrorMessage)
                }
                return .failure("Modell '\(modelId)' nicht gefunden")

            case 429:
                return .failure("Rate-Limit erreicht")

            default:
                let errorMessage = parseErrorMessage(from: data)
                return .failure("Fehler \(httpResponse.statusCode): \(errorMessage ?? "Unbekannter Fehler")")
            }
        } catch {
            return .failure("Netzwerkfehler: \(error.localizedDescription)")
        }
    }

    func complete(prompt: String, systemPrompt: String?) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        var request = try makeRequest()

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": modelId,
            "messages": messages
        ]

        applyProviderSpecificBody(to: &body)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw LLMError.invalidResponse
            }
            return content

        case 401:
            throw LLMError.invalidAPIKey

        case 404:
            if provider == .openClaw {
                throw LLMError.serverError(404, openClawEndpointErrorMessage)
            }
            throw LLMError.modelNotFound(modelId)

        case 429:
            throw LLMError.rateLimited

        default:
            let errorMessage = parseErrorMessage(from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    private func makeRequest() throws -> URLRequest {
        let url = try chatCompletionsURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyProviderSpecificHeaders(to: &request)
        return request
    }

    private func chatCompletionsURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            throw LLMError.invalidURL
        }

        var path = components.path
        if path == "/" {
            path = ""
        } else if path.hasSuffix("/") {
            path.removeLast()
        }

        if !path.hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }

        components.path = path
        guard let url = components.url else {
            throw LLMError.invalidURL
        }
        return url
    }

    private func applyProviderSpecificHeaders(to request: inout URLRequest) {
        guard provider == .openClaw,
              let agentID = openClawAgentID else {
            return
        }

        request.setValue(agentID, forHTTPHeaderField: "x-openclaw-agent-id")
    }

    private func applyProviderSpecificBody(to body: inout [String: Any]) {
        guard provider == .openClaw else { return }

        if body["user"] == nil {
            body["user"] = "dailybriefing-app"
        }
    }

    private var openClawAgentID: String? {
        guard provider == .openClaw else { return nil }
        guard modelId.lowercased().hasPrefix("openclaw:") else { return nil }
        let rawAgent = String(modelId.dropFirst("openclaw:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawAgent.isEmpty ? nil : rawAgent
    }

    private var openClawEndpointErrorMessage: String {
        "OpenClaw Endpoint nicht gefunden. Prüfe Base URL und aktiviere gateway.http.endpoints.chatCompletions.enabled."
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        return nil
    }
}
