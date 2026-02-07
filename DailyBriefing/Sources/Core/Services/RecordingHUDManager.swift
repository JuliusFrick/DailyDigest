import AppKit
import SwiftUI
import Combine

/// Manager for the floating recording HUD window
@MainActor
final class RecordingHUDManager: NSObject, ObservableObject {
    static let shared = RecordingHUDManager()
    
    @Published var isReviewing = false
    private var tempRecordingURL: URL?
    
    private var hudWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        setupBindings()
    }
    
    private func setupBindings() {
        // Monitor recording state
        AudioRecordingService.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    self.showHUD()
                } else if !self.isReviewing {
                    // Only hide if not reviewing
                    self.hideHUD()
                }
            }
            .store(in: &cancellables)
            
        // Monitor review state to hide HUD when finished
        $isReviewing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReviewing in
                guard let self = self else { return }
                if !isReviewing && !AudioRecordingService.shared.isRecording {
                    self.hideHUD()
                }
            }
            .store(in: &cancellables)
    }
    
    func startReview(url: URL) {
        self.tempRecordingURL = url
        self.isReviewing = true
        // Ensure HUD stays visible
        showHUD()
    }
    
    func confirmReview() {
        guard let url = tempRecordingURL else {
            discardReview()
            return
        }
        
        NotificationCenter.default.post(
            name: .recordingConfirmed,
            object: nil,
            userInfo: ["url": url]
        )
        
        finishReview()
    }
    
    func discardReview() {
        if let url = tempRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        finishReview()
    }
    
    private func finishReview() {
        tempRecordingURL = nil
        isReviewing = false
    }
    
    func showHUD() {
        guard hudWindow == nil else { return }
        
        let contentView = RecordingHUDView()
            .environmentObject(AudioRecordingService.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 100, height: 150)
        
        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        panel.contentView = hostingView
        
        // Position at bottom right by default
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - hostingView.frame.width - 20
            let y = screenFrame.minY + 150
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.orderFront(nil)
        self.hudWindow = panel
    }
    
    func hideHUD() {
        hudWindow?.orderOut(nil)
        hudWindow = nil
    }
}

// Extension for stop notification
extension Notification.Name {
    static let stopRecordingFromHUD = Notification.Name("stopRecordingFromHUD")
    static let recordingConfirmed = Notification.Name("recordingConfirmed")
}
