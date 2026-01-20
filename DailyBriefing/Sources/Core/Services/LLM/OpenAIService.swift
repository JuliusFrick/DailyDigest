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

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": "Say 'OK' and nothing else."]
            ],
            "max_tokens": 5
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

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": modelId,
            "messages": messages
        ]

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
