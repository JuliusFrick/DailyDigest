import AVFoundation
import Foundation

/// Service for playing back meeting recordings
@MainActor
final class RecordingPlaybackService: NSObject, ObservableObject {
    static let shared = RecordingPlaybackService()
    
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentURL: URL?
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Playback Control
    
    /// Play a recording from a URL
    /// - Parameter url: The local file URL of the recording
    func play(url: URL) {
        stop()
        
        do {
            #if !os(macOS)
            // Configure audio session for playback (iOS/tvOS only - AVAudioSession unavailable on macOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            currentURL = url
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            isPlaying = true
            startPlaybackTimer()
        } catch {
            print("Failed to play recording: \(error)")
            isPlaying = false
        }
    }
    
    /// Stop playback
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        stopPlaybackTimer()
    }
    
    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopPlaybackTimer()
    }
    
    /// Resume playback
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startPlaybackTimer()
    }
    
    /// Seek to a specific time
    /// - Parameter time: The time in seconds to seek to
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        
        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
    }
    
    /// Jump to a specific timestamp in the recording
    /// - Parameter timestamp: The timestamp in seconds from the start
    func jumpToTimestamp(_ timestamp: TimeInterval) {
        seek(to: timestamp)
    }
    
    /// Check if currently playing
    var isCurrentlyPlaying: Bool {
        isPlaying
    }
    
    // MARK: - Private Methods
    
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor in
                service.currentTime = service.audioPlayer?.currentTime ?? 0
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension RecordingPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopPlaybackTimer()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("Audio playback decode error: \(error)")
        }
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}

// MARK: - Convenience Extension for MeetingDetailPopup

extension RecordingPlaybackService {
    /// Jump to timestamp from an action item
    /// - Parameter timestamp: The timestamp in seconds (from ActionItem.timestamp)
    func jumpToActionItemTimestamp(_ timestamp: TimeInterval?) {
        guard let ts = timestamp else { return }
        guard currentURL != nil else {
            // If no recording is loaded, we need to find the recording URL for this meeting
            // This should be handled by the calling view
            print("No recording loaded - cannot jump to timestamp")
            return
        }
        jumpToTimestamp(ts)
    }
}
