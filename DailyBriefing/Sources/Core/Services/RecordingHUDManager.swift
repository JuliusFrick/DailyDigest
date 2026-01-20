import AppKit
import SwiftUI
import Combine

/// Manager for the floating recording HUD window
@MainActor
final class RecordingHUDManager: NSObject {
    static let shared = RecordingHUDManager()
    
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
                if isRecording {
                    self?.showHUD()
                } else {
                    self?.hideHUD()
                }
            }
            .store(in: &cancellables)
    }
    
    func showHUD() {
        guard hudWindow == nil else { return }
        
        let contentView = RecordingHUDView()
            .environmentObject(AudioRecordingService.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
        
        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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
            let y = screenFrame.minY + 20
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
}
