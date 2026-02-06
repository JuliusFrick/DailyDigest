import Foundation
import UserNotifications
import Combine

/// Service for scheduling post-meeting notifications to capture notes
@MainActor
final class PostMeetingNotificationService: ObservableObject {
    static let shared = PostMeetingNotificationService()
    
    // MARK: - Published Properties
    
    @Published private(set) var pendingMeetingIds: Set<String> = []
    
    // MARK: - Private Properties
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private enum NotificationIdentifier {
        static let prefix = "post-meeting-notes-"
    }
    
    private enum NotificationCategory {
        static let postMeeting = "POST_MEETING_NOTES"
    }
    
    private enum NotificationAction {
        static let addNotes = "ADD_NOTES"
        static let skip = "SKIP"
    }
    
    // MARK: - Callbacks
    
    /// Called when user wants to add notes for a meeting
    var onAddNotesRequested: ((String, String) -> Void)? // (meetingId, meetingTitle)
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Public API
    
    /// Schedule a post-meeting notification
    /// - Parameters:
    ///   - meeting: The meeting that ended
    ///   - delayMinutes: Minutes after meeting end to show notification (default: 5)
    func schedulePostMeetingNotification(
        for meeting: BriefingItem,
        delayMinutes: Int = 5
    ) async throws {
        // Check permission
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        
        // Get meeting end time
        guard let startTime = meeting.timestamp else { return }
        let durationString = meeting.metadata["duration"] ?? "30"
        let durationMinutes = parseDuration(durationString)
        let endTime = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        
        // Calculate notification time (after meeting ends + delay)
        let notificationTime = endTime.addingTimeInterval(TimeInterval(delayMinutes * 60))
        
        // Don't schedule if notification time is in the past
        guard notificationTime > Date() else { return }
        
        let meetingId = meetingId(for: meeting)
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Meeting beendet"
        content.body = "Möchtest du Notizen zu \"\(meeting.title)\" hinzufügen?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.postMeeting
        content.userInfo = [
            "meetingId": meetingId,
            "meetingTitle": meeting.title
        ]
        
        // Add attendees info if available
        if !meeting.attendees.others.isEmpty {
            content.subtitle = "Mit \(meeting.attendees.formattedNames(limit: 2))"
        }
        
        // Create trigger
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create request
        let identifier = NotificationIdentifier.prefix + meetingId
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule
        try await notificationCenter.add(request)
        pendingMeetingIds.insert(meetingId)
    }
    
    /// Schedule notifications for all meetings ending today
    func scheduleNotificationsForTodaysMeetings(_ meetings: [BriefingItem]) async {
        for meeting in meetings where meeting.isMeeting {
            do {
                try await schedulePostMeetingNotification(for: meeting)
            } catch {
                print("Failed to schedule post-meeting notification: \(error)")
            }
        }
    }
    
    /// Cancel a pending post-meeting notification
    func cancelNotification(for meetingId: String) {
        let identifier = NotificationIdentifier.prefix + meetingId
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        pendingMeetingIds.remove(meetingId)
    }
    
    /// Cancel all pending post-meeting notifications
    func cancelAllNotifications() {
        Task {
            let requests = await notificationCenter.pendingNotificationRequests()
            let identifiers = requests
                .filter { $0.identifier.hasPrefix(NotificationIdentifier.prefix) }
                .map { $0.identifier }
            
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            pendingMeetingIds.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationCategories() {
        let addNotesAction = UNNotificationAction(
            identifier: NotificationAction.addNotes,
            title: "Notizen hinzufügen",
            options: [.foreground]
        )
        
        let skipAction = UNNotificationAction(
            identifier: NotificationAction.skip,
            title: "Überspringen",
            options: [.destructive]
        )
        
        let category = UNNotificationCategory(
            identifier: NotificationCategory.postMeeting,
            actions: [addNotesAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
    }
    
    private func parseDuration(_ duration: String) -> Int {
        // Parse duration string like "30 min" or "1h 30m"
        let components = duration.lowercased()
        
        var totalMinutes = 0
        
        // Extract hours
        if let hourRange = components.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let hourStr = String(components[hourRange]).filter { $0.isNumber }
            totalMinutes += (Int(hourStr) ?? 0) * 60
        }
        
        // Extract minutes
        if let minRange = components.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let minStr = String(components[minRange]).filter { $0.isNumber }
            totalMinutes += Int(minStr) ?? 0
        }
        
        // If no pattern matched, try parsing as plain number (minutes)
        if totalMinutes == 0 {
            totalMinutes = Int(components.filter { $0.isNumber }) ?? 30
        }
        
        return max(totalMinutes, 15) // Minimum 15 minutes
    }
    
    private func meetingId(for item: BriefingItem) -> String {
        if let eventId = item.metadata["eventId"], !eventId.isEmpty {
            return "google_calendar_\(eventId)"
        }
        let timestamp = item.timestamp?.timeIntervalSince1970 ?? 0
        let titleHash = item.title.hash
        return "\(timestamp)_\(titleHash)"
    }
}

// MARK: - Notification Delegate Extension

extension PostMeetingNotificationService {
    /// Handle notification response - call from app delegate
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        guard let meetingId = userInfo["meetingId"] as? String,
              let meetingTitle = userInfo["meetingTitle"] as? String else { return }
        
        switch response.actionIdentifier {
        case NotificationAction.addNotes,
             UNNotificationDefaultActionIdentifier:
            // User wants to add notes
            onAddNotesRequested?(meetingId, meetingTitle)
            
        case NotificationAction.skip,
             UNNotificationDismissActionIdentifier:
            // User skipped
            pendingMeetingIds.remove(meetingId)
            
        default:
            break
        }
    }
}
