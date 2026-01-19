import Foundation

/// Service for transcribing audio using OpenAI Whisper API
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    
    private let keychain = KeychainService.shared
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    
    private init() {}
    
    // MARK: - Transcription
    
    /// Transcribe audio file using OpenAI Whisper API
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Transcribed text
    func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = keychain.loadLLMAPIKey(for: "openai"),
              !apiKey.isEmpty else {
            throw TranscriptionError.apiKeyMissing
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        // Read audio file
        let audioData = try Data(contentsOf: audioURL)
        
        // Create multipart form data
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add language (optional, helps with accuracy)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("de".data(using: .utf8)!) // German
        body.append("\r\n".data(using: .utf8)!)
        
        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw TranscriptionError.apiKeyInvalid
            }
            if let errorData = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(errorData.error.message)
            }
            throw TranscriptionError.serverError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let transcription = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TranscriptionError.invalidResponse
        }
        
        return transcription
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case apiKeyMissing
    case apiKeyInvalid
    case invalidResponse
    case serverError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "OpenAI API Key fehlt. Bitte in den Einstellungen konfigurieren."
        case .apiKeyInvalid:
            return "OpenAI API Key ist ungültig."
        case .invalidResponse:
            return "Ungültige Antwort vom Server."
        case .serverError(let code):
            return "Server-Fehler: \(code)"
        case .apiError(let message):
            return "API-Fehler: \(message)"
        }
    }
}

// MARK: - Response Models

private struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
    
    struct OpenAIError: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}
