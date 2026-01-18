import Foundation

/// Ollama local LLM service implementation
final class OllamaService: LLMService {
    let provider: LLMProvider = .ollama
    private let baseURL: String
    private let modelId: String

    init(baseURL: String, modelId: String) {
        // Ensure URL doesn't have trailing slash
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.modelId = modelId
    }

    func testConnection() async throws -> LLMConnectionTestResult {
        let startTime = Date()

        // First check if Ollama is running by hitting the tags endpoint
        guard let tagsURL = URL(string: "\(baseURL)/api/tags") else {
            return .failure("Ungültige Ollama URL")
        }

        do {
            let (tagsData, tagsResponse) = try await URLSession.shared.data(from: tagsURL)

            guard let httpResponse = tagsResponse as? HTTPURLResponse else {
                return .failure("Ollama ist nicht erreichbar")
            }

            if httpResponse.statusCode != 200 {
                return .failure("Ollama ist nicht erreichbar (Status: \(httpResponse.statusCode))")
            }

            // Check if the model is available
            if let json = try? JSONSerialization.jsonObject(with: tagsData) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let availableModels = models.compactMap { $0["name"] as? String }
                let modelExists = availableModels.contains { name in
                    name == modelId || name.hasPrefix("\(modelId):")
                }

                if !modelExists && !availableModels.isEmpty {
                    return .failure("Modell '\(modelId)' nicht gefunden. Verfügbar: \(availableModels.joined(separator: ", "))")
                }
            }

            // Now test the model with a simple generation
            guard let generateURL = URL(string: "\(baseURL)/api/generate") else {
                return .failure("Ungültige Ollama URL")
            }

            var request = URLRequest(url: generateURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            let body: [String: Any] = [
                "model": modelId,
                "prompt": "Say OK",
                "stream": false,
                "options": [
                    "num_predict": 5
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let responseTime = Date().timeIntervalSince(startTime)

            guard let genResponse = response as? HTTPURLResponse else {
                return .failure("Ungültige Antwort von Ollama")
            }

            if genResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let model = json["model"] as? String {
                    return .success(model: model, responseTime: responseTime)
                }
                return .success(model: modelId, responseTime: responseTime)
            } else {
                let errorMessage = parseErrorMessage(from: data)
                return .failure("Fehler: \(errorMessage ?? "Modell konnte nicht geladen werden")")
            }
        } catch let error as URLError {
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                return .failure("Ollama ist nicht erreichbar. Läuft Ollama unter \(baseURL)?")
            }
            return .failure("Netzwerkfehler: \(error.localizedDescription)")
        } catch {
            return .failure("Fehler: \(error.localizedDescription)")
        }
    }

    func complete(prompt: String, systemPrompt: String?) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": modelId,
            "prompt": prompt,
            "stream": false
        ]

        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let responseText = json["response"] as? String else {
                    throw LLMError.invalidResponse
                }
                return responseText

            case 404:
                throw LLMError.modelNotFound(modelId)

            default:
                let errorMessage = parseErrorMessage(from: data)
                throw LLMError.serverError(httpResponse.statusCode, errorMessage)
            }
        } catch let error as URLError {
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                throw LLMError.ollamaNotRunning
            }
            throw LLMError.networkError(error)
        }
    }

    /// Fetch available models from Ollama
    func fetchAvailableModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw LLMError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.ollamaNotRunning
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }

        return models.compactMap { $0["name"] as? String }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else {
            return nil
        }
        return error
    }
}
