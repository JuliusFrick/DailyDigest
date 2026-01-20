import Foundation
import Combine

/// Service for transcribing audio using OpenAI or Groq Whisper API
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published var transcriptionProvider: LLMProvider = .openai
    
    private let keychain = KeychainService.shared
    
    private var baseURL: String {
        switch transcriptionProvider {
        case .openai:
            return "https://api.openai.com/v1/audio/transcriptions"
        case .groq:
            return "https://api.groq.com/openai/v1/audio/transcriptions"
        default:
            return "https://api.openai.com/v1/audio/transcriptions"
        }
    }
    
    private var modelName: String {
        switch transcriptionProvider {
        case .openai:
            return "whisper-1"
        case .groq:
            return "whisper-large-v3"
        default:
            return "whisper-1"
        }
    }
    
    private init() {
        // Load saved provider
        if let savedProvider = UserDefaults.standard.string(forKey: "transcriptionProvider"),
           let provider = LLMProvider(rawValue: savedProvider) {
            self.transcriptionProvider = provider
        }
    }
    
    func setProvider(_ provider: LLMProvider) {
        guard provider.supportsTranscription else { return }
        transcriptionProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "transcriptionProvider")
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio file using OpenAI Whisper API
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Transcribed text
    func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = keychain.loadLLMAPIKey(for: transcriptionProvider.rawValue),
              !apiKey.isEmpty else {
            throw TranscriptionError.apiKeyMissing(provider: transcriptionProvider.displayName)
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
        body.append(modelName.data(using: .utf8)!)
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
    case apiKeyMissing(provider: String)
    case apiKeyInvalid
    case invalidResponse
    case serverError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing(let provider):
            return "\(provider) API Key fehlt. Bitte in den Einstellungen konfigurieren."
        case .apiKeyInvalid:
            return "API Key ist ungültig."
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
