import Foundation

/// Anthropic Claude API service implementation
final class AnthropicService: LLMService {
    let provider: LLMProvider = .anthropic
    private let apiKey: String
    private let modelId: String
    private let baseURL = "https://api.anthropic.com/v1"
    private let apiVersion = "2023-06-01"

    init(apiKey: String, modelId: String) {
        self.apiKey = apiKey
        self.modelId = modelId
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        let startTime = Date()

        guard !apiKey.isEmpty else {
            return .failure("API-Schlüssel fehlt")
        }

        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelId,
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "Say 'OK' and nothing else."]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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

        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": modelId,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let text = firstBlock["text"] as? String else {
                throw LLMError.invalidResponse
            }
            return text

        case 401:
            throw LLMError.invalidAPIKey

        case 429:
            throw LLMError.rateLimited

        default:
            let errorMessage = parseErrorMessage(from: data)
            throw LLMError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
