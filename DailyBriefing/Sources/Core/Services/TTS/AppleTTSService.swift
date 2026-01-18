import AVFoundation
import Foundation

/// Apple native TTS implementation using AVSpeechSynthesizer
final class AppleTTSService: NSObject, TTSProvider {
    private let synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?

    private(set) var playbackState: TTSPlaybackState = .idle
    private(set) var rate: Float = 1.0
    private(set) var selectedVoice: TTSVoice?

    var onSpeechFinished: (() -> Void)?
    var onSpeechPaused: (() -> Void)?
    var onSpeechResumed: (() -> Void)?

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self

        // Set default voice (system default)
        let voices = availableVoices()
        selectedVoice = voices.first { $0.isDefault } ?? voices.first
    }

    func speak(text: String) {
        stop()

        let utterance = AVSpeechUtterance(string: text)

        // Set rate: AVSpeechUtterance rate ranges from 0.0 to 1.0
        // Map our 0.5-2.0 range to AVSpeechUtterance range
        // Default rate is AVSpeechUtteranceDefaultSpeechRate (around 0.5)
        let mappedRate = mapRateToAVSpeech(rate)
        utterance.rate = mappedRate

        // Set voice if selected
        if let voice = selectedVoice,
           let avVoice = AVSpeechSynthesisVoice(identifier: voice.id) {
            utterance.voice = avVoice
        }

        currentUtterance = utterance
        playbackState = .speaking
        synthesizer.speak(utterance)
    }

    func pause() {
        guard playbackState == .speaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        playbackState = .paused
        onSpeechPaused?()
    }

    func resume() {
        guard playbackState == .paused else { return }
        synthesizer.continueSpeaking()
        playbackState = .speaking
        onSpeechResumed?()
    }

    func stop() {
        guard playbackState == .speaking || playbackState == .paused else { return }
        synthesizer.stopSpeaking(at: .immediate)
        playbackState = .stopped
        currentUtterance = nil
    }

    func setRate(_ rate: Float) {
        // Clamp rate to valid range (0.5 to 2.0)
        let clampedRate = max(0.5, min(2.0, rate))
        self.rate = clampedRate
    }

    func setVoice(_ voice: TTSVoice) {
        selectedVoice = voice
    }

    func availableVoices() -> [TTSVoice] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let currentLanguage = Locale.current.language.languageCode?.identifier

        return allVoices.map { avVoice in
            let isDefault = avVoice.language == currentLanguage && avVoice.quality == .enhanced

            return TTSVoice(
                id: avVoice.identifier,
                name: avVoice.name,
                language: avVoice.language,
                isDefault: isDefault
            )
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Private Helpers

    /// Maps our rate (0.5-2.0) to AVSpeechUtterance rate (0.0-1.0)
    private func mapRateToAVSpeech(_ rate: Float) -> Float {
        // AVSpeechUtteranceDefaultSpeechRate is around 0.5
        // AVSpeechUtteranceMinimumSpeechRate is 0.0
        // AVSpeechUtteranceMaximumSpeechRate is 1.0
        //
        // Our range: 0.5x to 2.0x (where 1.0x is normal)
        // Map: 0.5 -> 0.25, 1.0 -> 0.5, 2.0 -> 1.0

        let normalizedRate = (rate - 0.5) / 1.5 // Normalize to 0.0-1.0
        let avRate = AVSpeechUtteranceMinimumSpeechRate +
            normalizedRate * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        return avRate
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AppleTTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        if playbackState == .speaking {
            playbackState = .idle
            currentUtterance = nil
            onSpeechFinished?()
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        playbackState = .idle
        currentUtterance = nil
    }
}
