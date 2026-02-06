import SwiftUI
import EventKit
import AppKit

/// Apple Calendar integration using native EventKit APIs
@MainActor
final class AppleCalendarSource: BriefingSource, ObservableObject {
    nonisolated static let sourceId = "apple_calendar"
    static let displayName = "Apple Calendar"
    static let iconName = "calendar.badge.clock"
    static let brandColor = Color(red: 0.9, green: 0.2, blue: 0.2)
    
    // MARK: - Published Properties
    
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // MARK: - Configuration
    
    @Published var selectedCalendars: Set<String> = []
    @Published var availableCalendars: [AppleCalendar] = []
    
    // MARK: - Private Properties
    
    private let eventStore = EKEventStore()
    
    // MARK: - Initialization
    
    init() {
        checkCalendarAccess()
    }
    
    // MARK: - BriefingSource Protocol
    
    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }
        
        do {
            let granted = try await requestCalendarAccess()
            
            if granted {
                isAuthenticated = true
                connectionStatus = .connected
                await fetchAvailableCalendars()
            } else {
                throw SourceError.authenticationFailed("Zugriff auf Kalender wurde verweigert")
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
        selectedCalendars = []
        availableCalendars = []
    }
    
    func fetchItems(since: Date) async throws -> [BriefingItem] {
        // For briefing, we want today and tomorrow
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)!
        
        return try await fetchEvents(from: startOfToday, to: endOfTomorrow)
    }
    
    func configurationView() -> AnyView {
        AnyView(AppleCalendarConfigView(source: self))
    }
    
    // MARK: - Private Methods
    
    private func checkCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized, .writeOnly:
            isAuthenticated = true
            connectionStatus = .connected
            Task {
                await fetchAvailableCalendars()
            }
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
    
    private func requestCalendarAccess() async throws -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await eventStore.requestAccess(to: .event)
        }
    }
    
    func fetchAvailableCalendars() async {
        let calendars = eventStore.calendars(for: .event)
        availableCalendars = calendars.map { calendar in
            AppleCalendar(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: Color(cgColor: calendar.cgColor)
            )
        }
        
        // Auto-select all calendars if none selected
        if selectedCalendars.isEmpty {
            selectedCalendars = Set(availableCalendars.map { $0.id })
        }
    }
    
    private func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }
        
        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Kein Zugriff auf Apple Calendar")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let calendars: [EKCalendar]
            if selectedCalendars.isEmpty {
                calendars = eventStore.calendars(for: .event)
            } else {
                calendars = eventStore.calendars(for: .event).filter { selectedCalendars.contains($0.calendarIdentifier) }
            }
            
            guard !calendars.isEmpty else {
                continuation.resume(returning: [])
                return
            }
            
            let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
            let events = eventStore.events(matching: predicate)
            
            let briefingItems = events.map { event -> BriefingItem in
                // Determine priority based on availability and attendees
                var priority: BriefingSection.Priority = .medium
                if event.availability == .busy {
                    priority = .high
                }
                if event.title.lowercased().contains("wichtig") || event.title.lowercased().contains("urgent") {
                    priority = .urgent
                }
                
                // Parse attendees from EventKit
                let attendees = self.parseAttendees(from: event)
                
                // Meetings with attendees get higher priority
                if attendees.others.count > 0 {
                    priority = max(priority, .high)
                }
                
                // Format time subtitle
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                
                var subtitle = event.calendar.title
                if event.isAllDay {
                     subtitle += " · Ganztägig"
                } else {
                    formatter.dateFormat = "HH:mm"
                    subtitle += " · \(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
                }
                
                // Add attendee count to subtitle if it's a meeting
                if !attendees.others.isEmpty {
                    subtitle += " · 👥 \(attendees.others.count)"
                }
                
                return BriefingItem(
                    title: event.title,
                    subtitle: subtitle,
                    body: event.notes,
                    timestamp: event.startDate,
                    deepLink: URL(string: "ical://"), // Opens Calendar app
                    priority: priority,
                    metadata: [
                        "calendarId": event.calendar.calendarIdentifier,
                        "location": event.location ?? "",
                        "organizer": event.organizer?.name ?? "",
                        "eventId": event.eventIdentifier
                    ],
                    attendees: attendees
                )
            }
            
            continuation.resume(returning: briefingItems)
        }
    }
}

struct AppleCalendar: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}

// MARK: - Attendee Parsing

extension AppleCalendarSource {
    /// Parse attendees from an EventKit event
    func parseAttendees(from event: EKEvent) -> [Attendee] {
        guard let ekAttendees = event.attendees else {
            return []
        }
        
        return ekAttendees.map { participant in
            Attendee(
                email: extractEmail(from: participant),
                name: participant.name,
                status: mapParticipantStatus(participant.participantStatus),
                isOrganizer: participant.participantRole == .chair,
                isCurrentUser: participant.isCurrentUser
            )
        }
    }
    
    /// Extract email from EKParticipant URL
    /// EKParticipant stores email as URL like "mailto:email@example.com"
    private func extractEmail(from participant: EKParticipant) -> String? {
        let urlString = participant.url.absoluteString
        if urlString.hasPrefix("mailto:") {
            return String(urlString.dropFirst(7))
        }
        return urlString
    }
    
    /// Map EventKit participant status to our Attendee.ResponseStatus
    private func mapParticipantStatus(_ status: EKParticipantStatus) -> Attendee.ResponseStatus {
        switch status {
        case .accepted:
            return .accepted
        case .declined:
            return .declined
        case .tentative:
            return .tentative
        case .pending:
            return .pending
        case .unknown, .completed, .delegated, .inProcess:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
