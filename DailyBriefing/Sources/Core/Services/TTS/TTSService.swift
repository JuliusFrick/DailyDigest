import Combine
import Foundation

/// Main TTS service manager following the app's service patterns
@MainActor
final class TTSService: ObservableObject {
    static let shared = TTSService()

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var currentRate: Float = 1.0
    @Published private(set) var selectedVoice: TTSVoice?
    @Published private(set) var availableVoices: [TTSVoice] = []
    @Published private(set) var currentProvider: String = "apple"

    private var provider: TTSProvider

    private init() {
        provider = AppleTTSService()
        setupProvider()
        loadAvailableVoices()
    }

    /// Switch to a different TTS provider
    /// - Parameter providerName: The provider identifier ("apple" or "openai")
    func switchProvider(to providerName: String) {
        // Stop any current playback
        stop()

        // Create new provider
        let newProvider: TTSProvider
        switch providerName {
        case "openai":
            if let openAIService = OpenAITTSService.fromKeychain() {
                newProvider = openAIService
            } else {
                // Fall back to Apple if no API key
                newProvider = AppleTTSService()
            }
        default:
            newProvider = AppleTTSService()
        }

        // Update provider
        provider = newProvider
        currentProvider = providerName
        setupProvider()
        loadAvailableVoices()

        // Restore rate
        provider.setRate(currentRate)
    }

    private func setupProvider() {
        provider.onSpeechFinished = { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.isPaused = false
            }
        }

        provider.onSpeechPaused = { [weak self] in
            Task { @MainActor in
                self?.isPaused = true
            }
        }

        provider.onSpeechResumed = { [weak self] in
            Task { @MainActor in
                self?.isPaused = false
            }
        }

        selectedVoice = provider.selectedVoice
        currentRate = provider.rate
    }

    private func loadAvailableVoices() {
        availableVoices = provider.availableVoices()
    }

    // MARK: - Public API

    /// Speak the given text
    /// - Parameter text: The text to speak
    func speak(text: String) {
        provider.speak(text: text)
        isPlaying = true
        isPaused = false
    }

    /// Pause current speech
    func pause() {
        provider.pause()
    }

    /// Resume paused speech
    func resume() {
        provider.resume()
    }

    /// Stop current speech completely
    func stop() {
        provider.stop()
        isPlaying = false
        isPaused = false
    }

    /// Toggle between play/pause states
    /// If not playing, this does nothing (need to call speak with text)
    func togglePlayPause() {
        if isPaused {
            resume()
        } else if isPlaying {
            pause()
        }
    }

    /// Set the speech rate
    /// - Parameter rate: Rate between 0.5 and 2.0 (1.0 is normal speed)
    func setRate(_ rate: Float) {
        let clampedRate = max(0.5, min(2.0, rate))
        provider.setRate(clampedRate)
        currentRate = clampedRate
    }

    /// Set the voice to use for speech
    /// - Parameter voice: The voice to use
    func setVoice(_ voice: TTSVoice) {
        provider.setVoice(voice)
        selectedVoice = voice
    }

    /// Get voices filtered by language
    /// - Parameter languageCode: Language code (e.g., "en", "de")
    /// - Returns: Array of voices matching the language
    func voices(forLanguage languageCode: String) -> [TTSVoice] {
        availableVoices.filter { $0.language.hasPrefix(languageCode) }
    }

    /// Get the default voice for the system
    /// - Returns: The default voice if available
    func defaultVoice() -> TTSVoice? {
        availableVoices.first { $0.isDefault }
    }
}
