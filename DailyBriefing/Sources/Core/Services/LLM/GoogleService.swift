import Foundation

/// Google Gemini API service implementation
final class GoogleService: LLMService {
    let provider: LLMProvider = .google
    private let apiKey: String
    private let modelId: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(apiKey: String, modelId: String) {
        self.apiKey = apiKey
        self.modelId = modelId
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        let startTime = Date()

        guard !apiKey.isEmpty else {
            return .failure("API-Schlüssel fehlt")
        }

        let url = URL(string: "\(baseURL)/models/\(modelId):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "Say 'OK' and nothing else."]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 10
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
                return .success(model: modelId, responseTime: responseTime)

            case 400:
                let errorMessage = parseErrorMessage(from: data)
                if errorMessage?.contains("API_KEY") == true {
                    return .failure("Ungültiger API-Schlüssel")
                }
                return .failure("Fehler: \(errorMessage ?? "Ungültige Anfrage")")

            case 403:
                return .failure("Zugriff verweigert. API-Schlüssel überprüfen.")

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

        let url = URL(string: "\(baseURL)/models/\(modelId):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var contents: [[String: Any]] = []

        // Combine system prompt and user prompt for Gemini
        let fullPrompt: String
        if let systemPrompt = systemPrompt {
            fullPrompt = "\(systemPrompt)\n\n\(prompt)"
        } else {
            fullPrompt = prompt
        }

        contents.append([
            "parts": [
                ["text": fullPrompt]
            ]
        ])

        let body: [String: Any] = [
            "contents": contents
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw LLMError.invalidResponse
            }
            return text

        case 400, 403:
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
