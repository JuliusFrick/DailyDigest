import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = NSApplication.shared.windows.first(where: { $0.canBecomeKey && $0.level == .normal }) {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        if window == nil {
            let contentView = ContentView()
                .environmentObject(AppState.shared)
                .environmentObject(UserSettingsStore.shared)

            let hostingController = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Daily Briefing"
            window.setContentSize(NSSize(width: 900, height: 620))
            window.minSize = NSSize(width: 360, height: 280)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
