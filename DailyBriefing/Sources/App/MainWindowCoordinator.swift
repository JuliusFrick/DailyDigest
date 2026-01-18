import AppKit
import SwiftUI

@MainActor
final class MainWindowCoordinator {
    static let shared = MainWindowCoordinator()

    private var openWindow: OpenWindowAction?

    private init() {}

    func register(openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let candidates = NSApplication.shared.windows.filter { window in
            window.canBecomeKey && window.level == .normal
        }

        if let window = candidates.first(where: { $0.isVisible }) ?? candidates.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        openWindow?(id: "main")
    }
}
