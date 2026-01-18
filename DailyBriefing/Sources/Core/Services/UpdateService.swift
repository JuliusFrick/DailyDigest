import Foundation
import Sparkle

/// Service for handling app updates via Sparkle
@MainActor
final class UpdateService: ObservableObject {

    // MARK: - Singleton

    static let shared = UpdateService()

    // MARK: - Published Properties

    @Published private(set) var canCheckForUpdates = true

    // MARK: - Private Properties

    private var updaterController: SPUStandardUpdaterController?

    // MARK: - Initialization

    private init() {
        setupSparkle()
    }

    // MARK: - Setup

    private func setupSparkle() {
        // Initialize Sparkle updater controller
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: - Computed Properties

    /// Whether the app automatically checks for updates
    var automaticallyChecksForUpdates: Bool {
        updaterController?.updater.automaticallyChecksForUpdates ?? true
    }

    // MARK: - Public API

    /// Check for updates manually
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Check for updates in background
    func checkForUpdatesInBackground() {
        updaterController?.updater.checkForUpdatesInBackground()
    }

    /// Enable or disable automatic update checks
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }
}
