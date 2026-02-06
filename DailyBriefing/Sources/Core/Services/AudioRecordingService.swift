import AVFoundation
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for recording audio from microphone
@MainActor
final class AudioRecordingService: NSObject, ObservableObject {
    static let shared = AudioRecordingService()
    
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var hasPermission = false
    @Published private(set) var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var meteringTimer: Timer?
    private var recordingURL: URL?
    
    private override init() {
        super.init()
        checkPermission()
    }
    
    // MARK: - Permission
    
    func checkPermission() {
        #if os(macOS)
        // On macOS, check microphone permission using AVCaptureDevice
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasPermission = status == .authorized
        #else
        // iOS/tvOS - AVAudioSession is available
        let status = AVAudioSession.sharedInstance().recordPermission
        hasPermission = status == .granted
        #endif
    }

    func isPermissionUndetermined() -> Bool {
        #if os(macOS)
        return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        #else
        return AVAudioSession.sharedInstance().recordPermission == .undetermined
        #endif
    }
    
    func requestPermission() async -> Bool {
        #if os(macOS)
        // On macOS, request microphone permission using AVCaptureDevice
        let status = await AVCaptureDevice.requestAccess(for: .audio)
        hasPermission = status
        return status
        #else
        // iOS/tvOS - AVAudioSession is available
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
        #endif
    }
    
    func openMicrophoneSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
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
        
        #if !os(macOS)
        // Configure audio session (iOS/tvOS only)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        #endif
        
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
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        isRecording = true
        recordingDuration = 0
        audioLevel = 0.0
        
        // Start duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recordingDuration += 0.1
            }
        }
        
        // Start metering timer for audio level updates
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                // Convert decibels (-160 to 0) to normalized level (0 to 1)
                let db = recorder.averagePower(forChannel: 0)
                let minDb: Float = -60.0
                let level = max(0, (db - minDb) / (-minDb))
                self.audioLevel = level
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
        
        meteringTimer?.invalidate()
        meteringTimer = nil
        
        isRecording = false
        audioLevel = 0.0
        
        #if !os(macOS)
        // Deactivate audio session (iOS/tvOS only)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        
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
        
        meteringTimer?.invalidate()
        meteringTimer = nil
        
        isRecording = false
        recordingDuration = 0
        audioLevel = 0.0
        
        // Delete file if exists
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        
        #if !os(macOS)
        // Deactivate audio session (iOS/tvOS only)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
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
