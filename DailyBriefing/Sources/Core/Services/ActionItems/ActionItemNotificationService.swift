import Foundation
import UserNotifications
import Combine

// MARK: - Action Item Notification Service

/// Service for scheduling notifications for action item deadlines
final class ActionItemNotificationService: ObservableObject {
    static let shared = ActionItemNotificationService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {}
    
    // MARK: - Permission
    
    func requestPermission() async throws -> Bool {
        let settings = await notificationCenter.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized:
            return true
            
        case .notDetermined:
            return try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
        case .denied, .provisional, .ephemeral:
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Schedule Notifications
    
    func scheduleNotification(for item: ActionItem, minutesBefore: Int = 60) async throws {
        guard let dueDate = item.dueDate else { return }
        guard item.isOpen else { return }
        
        // Check permission
        let granted = try await requestPermission()
        guard granted else { return }
        
        // Calculate notification date (default: 1 hour before due)
        let notificationDate = dueDate.addingTimeInterval(-Double(minutesBefore * 60))
        
        // Don't schedule if notification date is in the past
        guard notificationDate > Date() else { return }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Action Item Due Soon"
        content.body = item.title
        content.sound = .default
        content.categoryIdentifier = "ACTION_ITEM"
        content.userInfo = [
            "actionItemId": item.id.uuidString,
            "meetingId": item.meetingId
        ]
        
        if let assignee = item.assignee {
            content.subtitle = "Assigned to: \(assignee)"
        }
        
        // Create trigger
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create request
        let identifier = "action-item-\(item.id.uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule
        try await notificationCenter.add(request)
    }
    
    func cancelNotification(for item: ActionItem) {
        let identifier = "action-item-\(item.id.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func rescheduleNotification(for item: ActionItem, minutesBefore: Int = 60) async throws {
        cancelNotification(for: item)
        try await scheduleNotification(for: item, minutesBefore: minutesBefore)
    }
    
    // MARK: - Bulk Operations
    
    func scheduleNotifications(for items: [ActionItem], minutesBefore: Int = 60) async throws {
        for item in items {
            try await scheduleNotification(for: item, minutesBefore: minutesBefore)
        }
    }
    
    func cancelAllNotifications() {
        // Get all pending notifications
        Task {
            let requests = await notificationCenter.pendingNotificationRequests()
            let actionItemIdentifiers = requests
                .filter { $0.identifier.hasPrefix("action-item-") }
                .map { $0.identifier }
            
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: actionItemIdentifiers
            )
        }
    }
    
    // MARK: - Daily Summary Notification
    
    func scheduleDailySummary(at hour: Int = 9) async throws {
        let granted = try await requestPermission()
        guard granted else { return }
        
        // Get overdue and due today items
        let store = await ActionItemStore.shared
        let overdueItems = await store.overdueItems()
        let dueTodayItems = await store.openItems().filter { item in
            guard let dueDate = item.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate)
        }
        
        guard !overdueItems.isEmpty || !dueTodayItems.isEmpty else { return }
        
        // Build summary
        let content = UNMutableNotificationContent()
        content.title = "Action Items Summary"
        content.sound = .default
        content.categoryIdentifier = "ACTION_ITEM_SUMMARY"
        
        var body = ""
        if !overdueItems.isEmpty {
            body += "\(overdueItems.count) overdue"
        }
        if !dueTodayItems.isEmpty {
            if !body.isEmpty { body += ", " }
            body += "\(dueTodayItems.count) due today"
        }
        content.body = body
        
        // Schedule for specified hour
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "action-item-daily-summary",
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
    }
    
    func cancelDailySummary() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["action-item-daily-summary"]
        )
    }
}

// MARK: - Notification Actions

extension ActionItemNotificationService {
    static func setupNotificationCategories() {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "Mark Complete",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 1h",
            options: []
        )
        
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View",
            options: .foreground
        )
        
        let category = UNNotificationCategory(
            identifier: "ACTION_ITEM",
            actions: [completeAction, snoozeAction, viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let summaryCategory = UNNotificationCategory(
            identifier: "ACTION_ITEM_SUMMARY",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            category,
            summaryCategory
        ])
    }
}
