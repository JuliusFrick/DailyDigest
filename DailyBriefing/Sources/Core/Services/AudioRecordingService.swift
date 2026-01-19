import AVFoundation
import Foundation

/// Service for recording audio from microphone
@MainActor
final class AudioRecordingService: NSObject, ObservableObject {
    static let shared = AudioRecordingService()
    
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var hasPermission = false
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
    private override init() {
        super.init()
        checkPermission()
    }
    
    // MARK: - Permission
    
    func checkPermission() {
        let status = AVAudioSession.sharedInstance().recordPermission
        hasPermission = status == .granted
    }
    
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    // MARK: - Recording
    
    func startRecording() async throws -> URL {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }
        
        // Request permission if needed
        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw RecordingError.permissionDenied
            }
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingFilename = "meeting_recording_\(Date().timeIntervalSince1970).m4a"
        recordingURL = documentsPath.appendingPathComponent(recordingFilename)
        
        guard let recordingURL = recordingURL else {
            throw RecordingError.couldNotCreateFile
        }
        
        // Configure recorder
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        
        isRecording = true
        recordingDuration = 0
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recordingDuration += 0.1
            }
        }
        
        return recordingURL
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        isRecording = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        let url = recordingURL
        recordingURL = nil
        
        return url
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        isRecording = false
        recordingDuration = 0
        
        // Delete file if exists
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    // MARK: - Formatting
    
    func formattedDuration() -> String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                // Recording failed
                cancelRecording()
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            cancelRecording()
        }
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case alreadyRecording
    case permissionDenied
    case couldNotCreateFile
    case recordingFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Es wird bereits aufgenommen"
        case .permissionDenied:
            return "Mikrofon-Berechtigung wurde verweigert"
        case .couldNotCreateFile:
            return "Aufnahmedatei konnte nicht erstellt werden"
        case .recordingFailed:
            return "Aufnahme fehlgeschlagen"
        }
    }
}
