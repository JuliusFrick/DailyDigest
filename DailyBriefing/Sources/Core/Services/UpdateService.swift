import AppKit
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
    private static let defaultFeedURL = "https://juliusfrick.github.io/DailyBriefing/appcast.xml"
    private static let legacyFeedURLMappings: [String: String] = [
        "https://juliusfrick.github.io/DailyBriefing/appcast.xml": defaultFeedURL,
        "https://juliusfrick.github.io/DailyDigest/appcast.xml": defaultFeedURL,
        "https://juliusfrick.github.io/appcast.xml": defaultFeedURL,
        "https://juliusfrick.github.io/DailyDigest/DailyDigest/appcast.xml": defaultFeedURL
    ]

    // MARK: - Published Properties

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateError: String?
    @Published private(set) var lastUpdateErrorDetails: String?

    // MARK: - Private Properties

    private var updaterController: SPUStandardUpdaterController?

    /// The resolved feed URL (from Info.plist or fallback)
    private let feedURL: URL?
    /// Sparkle public key (needed to verify update signatures)
    private let sparklePublicKey: String?

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

        // Read Sparkle public key from Info.plist (required for signature verification)
        if let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.sparklePublicKey = publicKey
        } else {
            self.sparklePublicKey = nil
        }

        super.init()

        // Only set up Sparkle if we have a valid feed URL
        canCheckForUpdates = feedURL != nil && sparklePublicKey != nil
        if feedURL != nil && sparklePublicKey == nil {
            lastUpdateError = "Updates deaktiviert"
            lastUpdateErrorDetails = "SUPublicEDKey fehlt in der App. Die Update-Signatur kann nicht geprüft werden."
        }
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
            userDriverDelegate: self
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
        
        // Add human-readable error description for common Sparkle errors
        if nsError.domain == "SUSparkleErrorDomain" {
            switch nsError.code {
            case 1001:
                details += " (No update available)"
            case 1002:
                details += " (Appcast download failed)"
            case 1003:
                details += " (Appcast parsing failed)"
            case 3001:
                details += " (Signature verification failed)"
                // Add helpful message for signature failures
                if let feedURL = feedURL {
                    details += " · Check that appcast.xml contains sparkle:edSignature attribute"
                    details += " · Verify SUPublicEDKey is in Info.plist"
                    details += " · Ensure SPARKLE_PUBLIC_ED_KEY matches SPARKLE_PRIVATE_ED_KEY used to sign DMG"
                }
            case 3002:
                details += " (Validation failed)"
            default:
                break
            }
        }

        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            details += " · URL: \(url.absoluteString)"
        } else if let urlString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            details += " · URL: \(urlString)"
        }
        
        // Include localized failure reason if available
        if let failureReason = nsError.localizedFailureReason {
            details += " · Reason: \(failureReason)"
        }
        
        // Include recovery suggestion if available
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
            details += " · Suggestion: \(recoverySuggestion)"
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " · Underlying: \(underlying.domain) (\(underlying.code))"
        }
        
        // Log feed URL for debugging
        if let feedURL = feedURL {
            details += " · Feed: \(feedURL.absoluteString)"
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
        
        // Log with more context
        logger.error("Update check failed: \(message, privacy: .public)")
        logger.debug("Error details: \(details, privacy: .public)")
        
        // Store error information for UI display
        lastUpdateError = message
        lastUpdateErrorDetails = details
        
        // For error 1001 (no update available), provide a more user-friendly message
        let nsError = error as NSError
        if nsError.domain == "SUSparkleErrorDomain" && nsError.code == 1001 {
            lastUpdateError = "Keine Updates verfügbar"
            lastUpdateErrorDetails = "Die aktuelle Version ist bereits die neueste verfügbare Version."
        }
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdateService: SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        // Ensure Sparkle dialogs appear in front of other apps/windows.
        NSApp.activate(ignoringOtherApps: true)
    }
}
