import AVFoundation
import Foundation

/// OpenAI TTS service implementation using the OpenAI Audio API
final class OpenAITTSService: NSObject, TTSProvider {
    // MARK: - OpenAI Voice Definitions

    /// Available OpenAI TTS voices
    enum OpenAIVoice: String, CaseIterable {
        case alloy
        case echo
        case fable
        case onyx
        case nova
        case shimmer

        var displayName: String {
            switch self {
            case .alloy: return "Alloy"
            case .echo: return "Echo"
            case .fable: return "Fable"
            case .onyx: return "Onyx"
            case .nova: return "Nova"
            case .shimmer: return "Shimmer"
            }
        }

        var description: String {
            switch self {
            case .alloy: return "Neutral und ausgewogen"
            case .echo: return "Warm und klar"
            case .fable: return "Ausdrucksstark und dynamisch"
            case .onyx: return "Tief und autoritär"
            case .nova: return "Freundlich und natürlich"
            case .shimmer: return "Hell und optimistisch"
            }
        }
    }

    // MARK: - Properties

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/speech"
    private let model = "tts-1"

    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

    private(set) var playbackState: TTSPlaybackState = .idle
    private(set) var rate: Float = 1.0
    private(set) var selectedVoice: TTSVoice?

    var onSpeechFinished: (() -> Void)?
    var onSpeechPaused: (() -> Void)?
    var onSpeechResumed: (() -> Void)?

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()

        // Set default voice
        let voices = availableVoices()
        selectedVoice = voices.first { $0.isDefault } ?? voices.first
    }

    /// Factory method that creates an instance with API key loaded from Keychain
    /// Uses the same OpenAI API key as the LLM service
    static func fromKeychain() -> OpenAITTSService? {
        guard let apiKey = KeychainService.shared.loadLLMAPIKey(for: "openai"),
              !apiKey.isEmpty else {
            return nil
        }
        return OpenAITTSService(apiKey: apiKey)
    }

    // MARK: - TTSProvider Implementation

    func speak(text: String) {
        stop()

        guard !apiKey.isEmpty else {
            playbackState = .idle
            onSpeechFinished?()
            return
        }

        playbackState = .speaking

        currentTask = Task { @MainActor in
            do {
                let audioData = try await fetchAudio(for: text)
                try playAudio(data: audioData)
            } catch {
                print("OpenAI TTS Error: \(error.localizedDescription)")
                playbackState = .idle
                onSpeechFinished?()
            }
        }
    }

    func pause() {
        guard playbackState == .speaking, let player = audioPlayer else { return }
        player.pause()
        playbackState = .paused
        onSpeechPaused?()
    }

    func resume() {
        guard playbackState == .paused, let player = audioPlayer else { return }
        player.play()
        playbackState = .speaking
        onSpeechResumed?()
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil

        audioPlayer?.stop()
        audioPlayer = nil

        if playbackState == .speaking || playbackState == .paused {
            playbackState = .stopped
        }
    }

    func setRate(_ rate: Float) {
        // OpenAI TTS supports speed from 0.25 to 4.0
        // We map our 0.5-2.0 range to OpenAI's supported range
        let clampedRate = max(0.5, min(2.0, rate))
        self.rate = clampedRate
    }

    func setVoice(_ voice: TTSVoice) {
        selectedVoice = voice
    }

    func availableVoices() -> [TTSVoice] {
        return OpenAIVoice.allCases.map { voice in
            TTSVoice(
                id: voice.rawValue,
                name: "\(voice.displayName) - \(voice.description)",
                language: "multilingual",
                isDefault: voice == .nova
            )
        }
    }

    // MARK: - Private Methods

    private func fetchAudio(for text: String) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw OpenAITTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let voiceId = selectedVoice?.id ?? OpenAIVoice.nova.rawValue

        // OpenAI TTS speed range is 0.25 to 4.0
        // Map our 0.5-2.0 range directly (it's within OpenAI's supported range)
        let speed = rate

        let body: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voiceId,
            "response_format": "mp3",
            "speed": speed
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITTSError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return data

        case 401:
            throw OpenAITTSError.invalidAPIKey

        case 429:
            throw OpenAITTSError.rateLimited

        default:
            let errorMessage = parseErrorMessage(from: data)
            throw OpenAITTSError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    private func playAudio(data: Data) throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()

        guard audioPlayer?.play() == true else {
            throw OpenAITTSError.playbackFailed
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

// MARK: - AVAudioPlayerDelegate

extension OpenAITTSService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if playbackState == .speaking {
            playbackState = .idle
            audioPlayer = nil
            onSpeechFinished?()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        playbackState = .idle
        audioPlayer = nil
        onSpeechFinished?()
    }
}

// MARK: - Errors

enum OpenAITTSError: LocalizedError {
    case invalidURL
    case invalidAPIKey
    case invalidResponse
    case rateLimited
    case serverError(Int, String?)
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige URL"
        case .invalidAPIKey:
            return "Ungültiger API-Schlüssel"
        case .invalidResponse:
            return "Ungültige Antwort vom Server"
        case .rateLimited:
            return "Rate-Limit erreicht"
        case .serverError(let code, let message):
            return "Serverfehler \(code): \(message ?? "Unbekannt")"
        case .playbackFailed:
            return "Audio-Wiedergabe fehlgeschlagen"
        }
    }
}
