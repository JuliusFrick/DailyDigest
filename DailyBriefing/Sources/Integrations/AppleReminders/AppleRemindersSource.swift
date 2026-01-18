import SwiftUI
import EventKit
import AppKit

/// Apple Reminders integration using native EventKit APIs
@MainActor
final class AppleRemindersSource: BriefingSource, ObservableObject {
    nonisolated static let sourceId = "apple_reminders"
    static let displayName = "Apple Reminders"
    static let iconName = "checklist"
    static let brandColor = Color(red: 1.0, green: 0.58, blue: 0.0)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Configuration

    @Published var selectedLists: Set<String> = []
    @Published var availableLists: [ReminderList] = []
    @Published var includeCompleted: Bool = false
    @Published var includeDueSoon: Bool = true

    // MARK: - Private Properties

    private let eventStore = EKEventStore()

    // MARK: - Initialization

    init() {
        checkRemindersAccess()
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }

        do {
            let granted = try await requestRemindersAccess()

            if granted {
                isAuthenticated = true
                connectionStatus = .connected
                await fetchAvailableLists()
            } else {
                throw SourceError.authenticationFailed("Zugriff auf Erinnerungen wurde verweigert")
            }
        } catch {
            lastError = error
            connectionStatus = .error
            throw error
        }
    }

    func disconnect() async {
        isAuthenticated = false
        connectionStatus = .disconnected
        selectedLists = []
        availableLists = []
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Kein Zugriff auf Apple Reminders")
        }

        let reminders = try await fetchReminders(since: since)

        return reminders.compactMap { reminder -> BriefingItem? in
            guard let title = reminder.title, !title.isEmpty else { return nil }

            let priority = mapReminderPriority(reminder.priority)
            let dueDate = reminder.dueDateComponents?.date

            var subtitle = reminder.calendar.title

            if let dueDate = dueDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                subtitle += " · Fällig: \(formatter.string(from: dueDate))"
            }

            return BriefingItem(
                title: title,
                subtitle: subtitle,
                body: reminder.notes,
                timestamp: dueDate ?? reminder.creationDate,
                deepLink: URL(string: "x-apple-reminderkit://reminder/\(reminder.calendarItemIdentifier)"),
                priority: priority,
                metadata: [
                    "calendarId": reminder.calendar.calendarIdentifier,
                    "listName": reminder.calendar.title,
                    "isCompleted": String(reminder.isCompleted),
                    "priority": String(reminder.priority)
                ]
            )
        }
    }

    func configurationView() -> AnyView {
        AnyView(AppleRemindersConfigView(source: self))
    }

    // MARK: - Private Methods

    private func checkRemindersAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            isAuthenticated = true
            connectionStatus = .connected
            Task {
                await fetchAvailableLists()
            }
        case .writeOnly:
            isAuthenticated = true
            connectionStatus = .connected
        case .denied, .restricted:
            isAuthenticated = false
            connectionStatus = .disconnected
        case .notDetermined:
            isAuthenticated = false
            connectionStatus = .disconnected
        @unknown default:
            isAuthenticated = false
            connectionStatus = .disconnected
        }
    }

    private func requestRemindersAccess() async throws -> Bool {
        // Ensure the app is foregrounded so macOS can show the permission prompt.
        NSApplication.shared.activate(ignoringOtherApps: true)

        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await eventStore.requestAccess(to: .reminder)
        }
    }

    func fetchAvailableLists() async {
        let calendars = eventStore.calendars(for: .reminder)
        availableLists = calendars.map { calendar in
            ReminderList(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: Color(cgColor: calendar.cgColor)
            )
        }

        // Auto-select all lists if none selected
        if selectedLists.isEmpty {
            selectedLists = Set(availableLists.map { $0.id })
        }
    }

    private func fetchReminders(since: Date) async throws -> [EKReminder] {
        return try await withCheckedThrowingContinuation { continuation in
            let calendars: [EKCalendar]
            if selectedLists.isEmpty {
                calendars = eventStore.calendars(for: .reminder)
            } else {
                calendars = eventStore.calendars(for: .reminder).filter { selectedLists.contains($0.calendarIdentifier) }
            }

            guard !calendars.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            // Create predicate for incomplete reminders
            let predicate: NSPredicate
            if includeDueSoon {
                // Fetch reminders due in the next 7 days
                let endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                predicate = eventStore.predicateForIncompleteReminders(
                    withDueDateStarting: since,
                    ending: endDate,
                    calendars: calendars
                )
            } else {
                predicate = eventStore.predicateForReminders(in: calendars)
            }

            eventStore.fetchReminders(matching: predicate) { reminders in
                var filtered = reminders ?? []

                // Filter out completed if not included
                if !self.includeCompleted {
                    filtered = filtered.filter { !$0.isCompleted }
                }

                // Sort by priority and due date
                filtered.sort { first, second in
                    // Higher priority first (EKReminder uses 0 = none, 1 = high, 5 = medium, 9 = low)
                    if first.priority != second.priority {
                        return first.priority < second.priority
                    }

                    // Then by due date
                    let firstDate = first.dueDateComponents?.date ?? Date.distantFuture
                    let secondDate = second.dueDateComponents?.date ?? Date.distantFuture
                    return firstDate < secondDate
                }

                continuation.resume(returning: Array(filtered.prefix(30)))
            }
        }
    }

    private func mapReminderPriority(_ priority: Int) -> BriefingSection.Priority {
        switch priority {
        case 1...4:
            return .high
        case 5:
            return .medium
        case 6...9:
            return .low
        default:
            return .medium
        }
    }
}

// MARK: - Data Models

struct ReminderList: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}
