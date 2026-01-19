import Foundation
import OSLog
import Sparkle

/// Service for handling app updates via Sparkle
@MainActor
final class UpdateService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = UpdateService()

    // MARK: - Constants

    /// Default appcast URL used when Info.plist doesn't provide one
    private static let defaultFeedURL = "https://juliusfrick.github.io/DailyDigest/DailyDigest/appcast.xml"
    private static let legacyFeedURLMappings: [String: String] = [
        "https://juliusfrick.github.io/DailyBriefing/appcast.xml": defaultFeedURL,
        "https://juliusfrick.github.io/DailyDigest/appcast.xml": defaultFeedURL
    ]

    // MARK: - Published Properties

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateError: String?
    @Published private(set) var lastUpdateErrorDetails: String?

    // MARK: - Private Properties

    private var updaterController: SPUStandardUpdaterController?

    /// The resolved feed URL (from Info.plist or fallback)
    private let feedURL: URL?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DailyBriefing",
        category: "UpdateService"
    )

    // MARK: - Initialization

    private override init() {
        // Resolve feed URL: prefer Info.plist, fall back to default
        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String {
            let normalized = Self.legacyFeedURLMappings[plistURL] ?? plistURL
            if let url = URL(string: normalized) {
                self.feedURL = url
            } else if let url = URL(string: Self.defaultFeedURL) {
                self.feedURL = url
            } else {
                self.feedURL = nil
            }
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
        lastUpdateError = nil
        lastUpdateErrorDetails = nil
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

    var resolvedFeedURLString: String? {
        feedURL?.absoluteString
    }

    private func formatErrorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var details = "\(nsError.domain) (\(nsError.code))"

        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            details += " · \(url.absoluteString)"
        } else if let urlString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            details += " · \(urlString)"
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " · underlying: \(underlying.domain) (\(underlying.code))"
        }

        return details
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

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let message = error.localizedDescription
        let details = formatErrorDetails(error)
        logger.error("Update check failed: \(message, privacy: .public) (\(details, privacy: .public))")
        lastUpdateError = message
        lastUpdateErrorDetails = details
    }
}
