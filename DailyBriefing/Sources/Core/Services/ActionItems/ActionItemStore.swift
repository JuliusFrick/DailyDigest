import Foundation
import SwiftUI
import EventKit

// MARK: - Action Item Store

/// Centralized store for managing action items
@MainActor
final class ActionItemStore: ObservableObject {
    static let shared = ActionItemStore()
    
    @Published private(set) var items: [ActionItem] = []
    
    private let userDefaultsKey = "com.dailydigest.actionItems"
    
    private init() {
        load()
    }
    
    // MARK: - CRUD Operations
    
    func add(_ item: ActionItem) {
        items.append(item)
        save()
    }
    
    func add(_ newItems: [ActionItem]) {
        items.append(contentsOf: newItems)
        save()
    }
    
    func update(_ item: ActionItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            save()
        }
    }
    
    func delete(_ item: ActionItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func complete(_ item: ActionItem) {
        var updated = item
        updated.status = .completed
        updated.completedAt = Date()
        update(updated)
    }
    
    func toggleCompletion(_ item: ActionItem) {
        var updated = item
        if updated.status == .completed {
            updated.status = .todo
            updated.completedAt = nil
        } else {
            updated.status = .completed
            updated.completedAt = Date()
        }
        update(updated)
    }
    
    // MARK: - Queries
    
    func items(for meetingId: String) -> [ActionItem] {
        items.filter { $0.meetingId == meetingId }
    }
    
    func openItems() -> [ActionItem] {
        items.filter { $0.isOpen }
            .sorted { item1, item2 in
                // Sort by due date, then by creation date
                if let date1 = item1.dueDate, let date2 = item2.dueDate {
                    return date1 < date2
                }
                if item1.dueDate != nil {
                    return true
                }
                if item2.dueDate != nil {
                    return false
                }
                return item1.createdAt > item2.createdAt
            }
    }
    
    func overdueItems() -> [ActionItem] {
        items.filter { $0.isOverdue }
            .sorted { $0.dueDate! < $1.dueDate! }
    }
    
    func completedItems() -> [ActionItem] {
        items.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
    }
    
    func itemsByStatus(_ status: ActionItem.Status) -> [ActionItem] {
        items.filter { $0.status == status }
    }
    
    // MARK: - Statistics
    
    var totalItems: Int { items.count }
    var openItemsCount: Int { openItems().count }
    var completedItemsCount: Int { completedItems().count }
    var overdueItemsCount: Int { overdueItems().count }
    
    func completionRate(for meetingId: String? = nil) -> Double {
        let relevantItems = meetingId != nil ? items(for: meetingId!) : items
        guard !relevantItems.isEmpty else { return 0 }
        
        let completed = relevantItems.filter { $0.status == .completed }.count
        return Double(completed) / Double(relevantItems.count)
    }
    
    // MARK: - Persistence
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to save action items: \(error)")
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ActionItem].self, from: data)
        } catch {
            print("Failed to load action items: \(error)")
            items = []
        }
    }
    
    // MARK: - Export to Apple Reminders
    
    func exportToReminders(_ items: [ActionItem]) async throws {
        let store = EKEventStore()
        
        // Request access
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
        
        guard granted else {
            throw ExportError.permissionDenied
        }
        
        // Get default calendar
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ExportError.noDefaultCalendar
        }
        
        // Create reminders
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.title
            reminder.notes = buildReminderNotes(for: item)
            reminder.calendar = calendar
            
            // Set due date
            if let dueDate = item.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }
            
            // Set priority
            switch item.status {
            case .todo:
                reminder.priority = 5 // Medium
            case .inProgress:
                reminder.priority = 1 // High
            case .completed:
                reminder.isCompleted = true
                if let completedAt = item.completedAt {
                    reminder.completionDate = completedAt
                }
            case .cancelled:
                continue // Skip cancelled items
            }
            
            try store.save(reminder, commit: false)
        }
        
        // Commit all changes
        try store.commit()
    }
    
    private func buildReminderNotes(for item: ActionItem) -> String {
        var notes = ""
        
        if let description = item.description {
            notes += description + "\n\n"
        }
        
        if let assignee = item.assignee {
            notes += "👤 Assignee: \(assignee)\n"
        }
        
        notes += "📅 Created: \(item.createdAt.formatted())\n"
        notes += "🔗 From: DailyDigest Meeting \(item.meetingId)"
        
        return notes
    }
    
    // MARK: - Export to Jira (Placeholder)
    
    func exportToJira(_ items: [ActionItem]) async throws {
        // TODO: Implement Jira API integration
        // Required setup:
        // 1. Jira API token credentials in Keychain
        // 2. Project/Board selection UI
        // 3. Issue creation via Jira REST API
        //
        // Example API endpoint: https://api.atlassian.com/ex/jira/{cloudid}/rest/api/3/issue
        throw ExportError.jiraNotConfigured
    }
    
    // MARK: - Export to Linear (Placeholder)
    
    func exportToLinear(_ items: [ActionItem]) async throws {
        // TODO: Implement Linear API integration
        // Required setup:
        // 1. Linear API key in Keychain
        // 2. Team/Project selection UI
        // 3. Issue creation via Linear GraphQL API
        //
        // Example: POST https://api.linear.app/graphql with createIssue mutation
        throw ExportError.linearNotConfigured
    }
    
    // MARK: - Bulk Operations
    
    func deleteAll() {
        items.removeAll()
        save()
    }
    
    func deleteCompleted() {
        items.removeAll { $0.status == .completed }
        save()
    }
    
    func archiveOldItems(olderThan days: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        items.removeAll { item in
            item.status == .completed &&
            (item.completedAt ?? item.createdAt) < cutoffDate
        }
        save()
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case permissionDenied
    case noDefaultCalendar
    case notImplemented
    case jiraNotConfigured
    case linearNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission to access Reminders was denied. Please grant access in System Settings."
        case .noDefaultCalendar:
            return "No default reminders calendar found."
        case .notImplemented:
            return "This export feature is not yet implemented."
        case .jiraNotConfigured:
            return "Jira integration is not configured. Please set up Jira credentials in Settings > Integrations."
        case .linearNotConfigured:
            return "Linear integration is not configured. Please set up your Linear API key in Settings > Integrations."
        }
    }
}
