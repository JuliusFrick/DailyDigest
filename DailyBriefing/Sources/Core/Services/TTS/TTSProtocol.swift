import Foundation

/// Represents a voice available for text-to-speech
struct TTSVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let isDefault: Bool

    init(id: String, name: String, language: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isDefault = isDefault
    }
}

/// Playback state for TTS
enum TTSPlaybackState: Equatable, Sendable {
    case idle
    case speaking
    case paused
    case stopped
}

/// Protocol defining the interface for Text-to-Speech services
protocol TTSProvider: AnyObject {
    /// Current playback state
    var playbackState: TTSPlaybackState { get }

    /// Current speech rate (0.5 to 2.0, where 1.0 is normal)
    var rate: Float { get }

    /// Currently selected voice
    var selectedVoice: TTSVoice? { get }

    /// Speak the given text
    /// - Parameter text: The text to speak
    func speak(text: String)

    /// Pause current speech
    func pause()

    /// Resume paused speech
    func resume()

    /// Stop current speech completely
    func stop()

    /// Set the speech rate
    /// - Parameter rate: Rate between 0.5 and 2.0 (1.0 is normal speed)
    func setRate(_ rate: Float)

    /// Set the voice to use for speech
    /// - Parameter voice: The voice to use
    func setVoice(_ voice: TTSVoice)

    /// Get all available voices
    /// - Returns: Array of available voices
    func availableVoices() -> [TTSVoice]

    /// Callback when speech finishes
    var onSpeechFinished: (() -> Void)? { get set }

    /// Callback when speech is paused
    var onSpeechPaused: (() -> Void)? { get set }

    /// Callback when speech is resumed
    var onSpeechResumed: (() -> Void)? { get set }
}
