import AppKit
import Foundation

/// Service for managing the app icon in the dock
@MainActor
final class AppIconService {

    // MARK: - Singleton

    static let shared = AppIconService()

    // MARK: - Private Properties

    private var timer: Timer?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start the service (updates dock icon based on time of day)
    func start() {
        // Update immediately
        updateDockIcon()

        // Schedule periodic updates (every hour)
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIcon()
            }
        }
    }

    /// Stop the service
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private Methods

    private func updateDockIcon() {
        // The dock icon could be updated based on time of day
        // For now, we just use the default icon
        // This is a placeholder for future enhancements
    }
}
