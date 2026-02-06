import Foundation
import Combine

/// Service for on-device transcription using Voxtral via MLX
/// Communicates with a local Python server for inference
@MainActor
final class LocalTranscriptionService: ObservableObject {
    static let shared = LocalTranscriptionService()
    
    // MARK: - Published State
    
    @Published private(set) var isAvailable = false
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var serverStatus: ServerStatus = .unknown
    @Published var lastError: String?
    
    // MARK: - Configuration
    
    private let serverPort = 8473
    private var serverURL: URL {
        URL(string: "http://127.0.0.1:\(serverPort)")!
    }
    
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    
    enum ServerStatus: String {
        case unknown = "Unbekannt"
        case starting = "Startet..."
        case running = "Läuft"
        case notInstalled = "Nicht installiert"
        case error = "Fehler"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Check server status on init
        Task {
            await checkServerHealth()
        }
    }
    
    deinit {
        stopServer()
    }
    
    // MARK: - Server Management
    
    /// Check if the Voxtral server is running and healthy
    func checkServerHealth() async {
        do {
            let url = serverURL.appendingPathComponent("health")
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                serverStatus = .error
                isAvailable = false
                return
            }
            
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            
            isAvailable = health.mlxAvailable
            isModelLoaded = health.modelLoaded
            serverStatus = .running
            
            if !health.mlxAvailable {
                serverStatus = .notInstalled
            }
        } catch {
            // Server not running
            serverStatus = .unknown
            isAvailable = false
            isModelLoaded = false
        }
    }
    
    /// Start the local Voxtral server
    func startServer() async throws {
        serverStatus = .starting
        
        // Find the Python script
        guard let scriptURL = Bundle.main.url(forResource: "voxtral_server", withExtension: "py") else {
            throw LocalTranscriptionError.serverScriptNotFound
        }
        
        // Check if Python is available
        let pythonPath = findPython()
        guard let python = pythonPath else {
            throw LocalTranscriptionError.pythonNotFound
        }
        
        // Start the server process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptURL.path, "--port", String(serverPort), "--preload"]
        
        // Capture output for debugging
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        do {
            try process.run()
            serverProcess = process
            
            // Wait for server to be ready
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                await checkServerHealth()
                
                if serverStatus == .running {
                    break
                }
            }
            
            if serverStatus != .running {
                throw LocalTranscriptionError.serverStartFailed
            }
            
            // Start health check timer
            startHealthCheckTimer()
            
        } catch {
            serverStatus = .error
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Stop the local server
    func stopServer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        serverProcess?.terminate()
        serverProcess = nil
        
        serverStatus = .unknown
        isModelLoaded = false
    }
    
    /// Pre-load the model without transcribing
    func preloadModel() async throws {
        let url = serverURL.appendingPathComponent("load")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LocalTranscriptionError.modelLoadFailed
        }
        
        isModelLoaded = true
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio file using local Voxtral model
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - language: Language code (default: "de" for German)
    ///   - useContextBiasing: Whether to use dictionary words for context biasing
    /// - Returns: Transcription result
    func transcribe(
        audioURL: URL,
        language: String = "de",
        useContextBiasing: Bool = true
    ) async throws -> TranscriptionResult {
        guard serverStatus == .running else {
            throw LocalTranscriptionError.serverNotRunning
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        // Read audio data
        let audioData = try Data(contentsOf: audioURL)
        
        // Get context words from dictionary
        var contextWords: [String] = []
        if useContextBiasing {
            contextWords = await TranscriptionDictionaryService.shared.contextWords()
        }
        
        // Build JSON request body
        let requestBody: [String: Any] = [
            "audio": audioData.base64EncodedString(),
            "language": language,
            "context_words": contextWords
        ]
        
        var request = URLRequest(url: serverURL.appendingPathComponent("transcribe"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 300 // 5 minutes for long audio
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalTranscriptionError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw LocalTranscriptionError.transcriptionFailed(errorResponse.error)
            }
            throw LocalTranscriptionError.serverError(httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        
        // Record usage of dictionary words that appeared in the transcription
        if useContextBiasing {
            let transcribedWords = Set(result.text.components(separatedBy: .whitespaces))
            let matchedWords = contextWords.filter { word in
                transcribedWords.contains { $0.localizedCaseInsensitiveContains(word) }
            }
            if !matchedWords.isEmpty {
                await TranscriptionDictionaryService.shared.recordUsage(of: matchedWords)
            }
        }
        
        return TranscriptionResult(
            text: result.text,
            language: result.language,
            processingTime: result.processingTime,
            isLocal: true
        )
    }
    
    // MARK: - Streaming Transcription (for live meetings)
    
    /// Start streaming transcription for live audio
    /// - Parameter onResult: Callback for each transcription chunk
    /// - Returns: StreamingSession to control the stream
    func startStreamingTranscription(
        language: String = "de",
        onResult: @escaping (String) -> Void
    ) -> StreamingSession {
        return StreamingSession(
            service: self,
            language: language,
            onResult: onResult
        )
    }
    
    // MARK: - Private Helpers
    
    private func findPython() -> String? {
        // Check common Python locations
        let paths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }
        
        return nil
    }
    
    private func startHealthCheckTimer() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkServerHealth()
            }
        }
    }
}

// MARK: - Streaming Session

/// Manages a streaming transcription session for live audio
class StreamingSession {
    private let service: LocalTranscriptionService
    private let language: String
    private let onResult: (String) -> Void
    
    private var audioBuffer = Data()
    private var isActive = false
    private let chunkDuration: TimeInterval = 5.0 // Process every 5 seconds
    private var lastProcessTime = Date()
    
    init(service: LocalTranscriptionService, language: String, onResult: @escaping (String) -> Void) {
        self.service = service
        self.language = language
        self.onResult = onResult
    }
    
    /// Add audio data to the buffer
    func addAudio(_ data: Data) {
        guard isActive else { return }
        audioBuffer.append(data)
        
        // Check if we should process a chunk
        if Date().timeIntervalSince(lastProcessTime) >= chunkDuration {
            processCurrentBuffer()
        }
    }
    
    /// Start the streaming session
    func start() {
        isActive = true
        lastProcessTime = Date()
    }
    
    /// Stop the streaming session and process remaining audio
    func stop() {
        isActive = false
        processCurrentBuffer()
    }
    
    private func processCurrentBuffer() {
        guard !audioBuffer.isEmpty else { return }
        
        let dataToProcess = audioBuffer
        audioBuffer = Data()
        lastProcessTime = Date()
        
        Task { @MainActor in
            // Save to temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")
            
            do {
                try dataToProcess.write(to: tempURL)
                let result = try await service.transcribe(audioURL: tempURL, language: language)
                onResult(result.text)
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                print("Streaming transcription error: \(error)")
            }
        }
    }
}

// MARK: - Models

struct TranscriptionResult {
    let text: String
    let language: String
    let processingTime: Double
    let isLocal: Bool
}

private struct HealthResponse: Codable {
    let status: String
    let mlxAvailable: Bool
    let modelLoaded: Bool
    let modelId: String
    
    enum CodingKeys: String, CodingKey {
        case status
        case mlxAvailable = "mlx_available"
        case modelLoaded = "model_loaded"
        case modelId = "model_id"
    }
}

private struct TranscriptionResponse: Codable {
    let text: String
    let language: String
    let processingTime: Double
    let model: String
    
    enum CodingKeys: String, CodingKey {
        case text, language, model
        case processingTime = "processing_time"
    }
}

private struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Errors

enum LocalTranscriptionError: LocalizedError {
    case serverScriptNotFound
    case pythonNotFound
    case serverStartFailed
    case serverNotRunning
    case modelLoadFailed
    case transcriptionFailed(String)
    case invalidResponse
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .serverScriptNotFound:
            return "Voxtral Server-Script nicht gefunden."
        case .pythonNotFound:
            return "Python 3 nicht gefunden. Bitte installieren."
        case .serverStartFailed:
            return "Voxtral Server konnte nicht gestartet werden."
        case .serverNotRunning:
            return "Voxtral Server läuft nicht."
        case .modelLoadFailed:
            return "Voxtral Model konnte nicht geladen werden."
        case .transcriptionFailed(let message):
            return "Transkription fehlgeschlagen: \(message)"
        case .invalidResponse:
            return "Ungültige Server-Antwort."
        case .serverError(let code):
            return "Server-Fehler: \(code)"
        }
    }
}
