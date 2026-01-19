import Foundation
import Sparkle

/// Service for handling app updates via Sparkle
@MainActor
final class UpdateService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = UpdateService()

    // MARK: - Constants

    /// Default appcast URL used when Info.plist doesn't provide one
    private static let defaultFeedURL = "https://juliusfrick.github.io/DailyBriefing/appcast.xml"

    // MARK: - Published Properties

    @Published private(set) var canCheckForUpdates = false

    // MARK: - Private Properties

    private var updaterController: SPUStandardUpdaterController?

    /// The resolved feed URL (from Info.plist or fallback)
    private let feedURL: URL?

    // MARK: - Initialization

    private override init() {
        // Resolve feed URL: prefer Info.plist, fall back to default
        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: plistURL) {
            self.feedURL = url
        } else if let url = URL(string: Self.defaultFeedURL) {
            self.feedURL = url
        } else {
            self.feedURL = nil
        }

        super.init()

        // Only set up Sparkle if we have a valid feed URL
        canCheckForUpdates = feedURL != nil
        if canCheckForUpdates {
            setupSparkle()
        }
    }

    // MARK: - Setup

    private func setupSparkle() {
        // Initialize Sparkle updater controller with self as delegate to provide feed URL
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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
        guard canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
    }

    /// Check for updates in background
    func checkForUpdatesInBackground() {
        guard canCheckForUpdates else { return }
        updaterController?.updater.checkForUpdatesInBackground()
    }

    /// Enable or disable automatic update checks
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateService: SPUUpdaterDelegate {
    /// Provide the feed URL to Sparkle (called by the updater)
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // Access the pre-resolved URL; this is safe because feedURL is set once in init
        // and never mutated afterwards.
        MainActor.assumeIsolated {
            feedURL?.absoluteString
        }
    }
}
