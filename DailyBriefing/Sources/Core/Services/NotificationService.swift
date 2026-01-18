import Foundation
import UserNotifications
import AppKit

/// Service responsible for managing app notifications
/// Handles permission requests, scheduling morning reminders, and notification actions
@MainActor
final class NotificationService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Published Properties

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    /// `UNUserNotificationCenter.current()` can assert/crash if the process is not running from
    /// a proper app bundle (e.g. SwiftPM-built executable in a DerivedData/Debug folder).
    /// We therefore gate all notification functionality behind a runtime bundle check.
    private static var canUseUserNotifications: Bool {
        // `bundleURL.pathExtension == "app"` is not reliable for SwiftPM executables launched from Xcode
        // (Bundle.main can be a plain directory like ".../Build/Products/Debug/").
        //
        // A more robust indicator for a real app bundle is CFBundlePackageType == "APPL".
        let isAppPackageType = (Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String) == "APPL"
        let hasAppBundleURL = Bundle.main.bundleURL.pathExtension == "app"
        return isAppPackageType && hasAppBundleURL
    }

    private var notificationCenter: UNUserNotificationCenter? {
        guard Self.canUseUserNotifications else { return nil }
        return UNUserNotificationCenter.current()
    }

    // MARK: - Constants

    private enum NotificationIdentifier {
        static let morningReminder = "daily-briefing-morning-reminder"
        static let briefingReady = "daily-briefing-ready"
    }

    private enum NotificationCategory {
        static let briefing = "BRIEFING_CATEGORY"
    }

    private enum NotificationAction {
        static let openDashboard = "OPEN_DASHBOARD"
        static let dismiss = "DISMISS"
    }

    // MARK: - Callbacks

    /// Called when user taps on a notification to open the dashboard
    var onOpenDashboardRequested: (() -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
        guard let notificationCenter else {
            // Running without an app bundle: disable notifications instead of crashing.
            isAuthorized = false
            authorizationStatus = .notDetermined
            return
        }

        setupNotificationCategories(using: notificationCenter)
        notificationCenter.delegate = self
        Task { await checkAuthorizationStatus(using: notificationCenter) }
    }

    // MARK: - Public API

    /// Request notification permissions from the user
    /// Should be called on first app launch or when enabling notifications
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestPermission() async -> Bool {
        guard let notificationCenter else { return false }
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await checkAuthorizationStatus(using: notificationCenter)
            return granted
        } catch {
            return false
        }
    }

    /// Check if permissions have been requested before
    func hasRequestedPermission() async -> Bool {
        guard let notificationCenter else { return true }
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus != .notDetermined
    }

    /// Schedule a daily morning reminder notification
    /// - Parameter time: The time to show the reminder each day
    func scheduleMorningReminder(at time: Date) {
        guard let notificationCenter else { return }
        // Cancel any existing morning reminder
        cancelMorningReminder()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Daily Briefing"
        content.body = "Dein Daily Briefing ist bereit"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.briefing

        // Extract hour and minute from the provided time
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)

        // Create a daily repeating trigger
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        // Create the request
        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.morningReminder,
            content: content,
            trigger: trigger
        )

        // Schedule the notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule morning reminder: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel the morning reminder notification
    func cancelMorningReminder() {
        guard let notificationCenter else { return }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.morningReminder]
        )
    }

    /// Send an immediate notification that the briefing is ready
    func sendBriefingReadyNotification() async {
        guard let notificationCenter else { return }
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Briefing bereit"
        content.body = "Dein Daily Briefing ist bereit"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.briefing

        // Add a unique identifier with timestamp to allow multiple notifications
        let identifier = "\(NotificationIdentifier.briefingReady)-\(UUID().uuidString)"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Immediate delivery
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to send briefing ready notification: \(error.localizedDescription)")
        }
    }

    /// Remove all pending notifications
    func cancelAllNotifications() {
        guard let notificationCenter else { return }
        notificationCenter.removeAllPendingNotificationRequests()
    }

    /// Remove all delivered notifications from notification center
    func clearDeliveredNotifications() {
        guard let notificationCenter else { return }
        notificationCenter.removeAllDeliveredNotifications()
    }

    // MARK: - Private Methods

    private func setupNotificationCategories(using notificationCenter: UNUserNotificationCenter) {
        // Define actions
        let openAction = UNNotificationAction(
            identifier: NotificationAction.openDashboard,
            title: "Öffnen",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Schließen",
            options: [.destructive]
        )

        // Define category with actions
        let briefingCategory = UNNotificationCategory(
            identifier: NotificationCategory.briefing,
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Register the category
        notificationCenter.setNotificationCategories([briefingCategory])
    }

    private func checkAuthorizationStatus(using notificationCenter: UNUserNotificationCenter) async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Bring the app to the foreground and navigate to dashboard
    private func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Find and show the main window
        if let window = NSApplication.shared.windows.first(where: {
            $0.title == "Daily Briefing" || $0.title.isEmpty
        }) {
            window.makeKeyAndOrderFront(nil)
        }

        // Notify listeners to navigate to dashboard
        onOpenDashboardRequested?()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound]
    }

    /// Handle user interaction with notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier

        // Handle different actions
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier,
             NotificationAction.openDashboard:
            // User tapped on notification or "Open" action
            await MainActor.run {
                openDashboard()
            }

        case NotificationAction.dismiss,
             UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            break

        default:
            break
        }
    }
}
