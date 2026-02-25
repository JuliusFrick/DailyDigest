import Foundation
import SwiftUI

/// Represents the connection status of a service integration
enum ConnectionStatus: String, Codable, Equatable {
    case connected
    case disconnected
    case connecting
    case error
    case tokenExpired

    var displayName: String {
        switch self {
        case .connected: return "Verbunden"
        case .disconnected: return "Nicht verbunden"
        case .connecting: return "Verbindet..."
        case .error: return "Fehler"
        case .tokenExpired: return "Sitzung abgelaufen"
        }
    }

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .error: return .red
        case .tokenExpired: return .orange
        }
    }

    var iconName: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.circle.fill"
        case .tokenExpired: return "clock.badge.exclamationmark"
        }
    }
}

/// Represents a connected service integration
struct ServiceConnection: Identifiable, Codable, Equatable {
    let id: UUID
    let serviceId: String
    let serviceName: String
    let connectedAt: Date
    var lastSyncAt: Date?
    var status: ConnectionStatus
    var errorMessage: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        serviceId: String,
        serviceName: String,
        connectedAt: Date = Date(),
        lastSyncAt: Date? = nil,
        status: ConnectionStatus = .disconnected,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
        self.status = status
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

/// Enum representing all available service types
enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case googleCalendar = "google_calendar"
    case gmail = "gmail"
    case slack = "slack"
    case jira = "jira"
    case granola = "granola"
    case appleMail = "apple_mail"
    case appleReminders = "apple_reminders"
    case appleCalendar = "apple_calendar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleCalendar: return "Google Calendar"
        case .gmail: return "Gmail"
        case .slack: return "Slack"
        case .jira: return "Jira"
        case .granola: return "Granola"
        case .appleMail: return "Apple Mail"
        case .appleReminders: return "Apple Reminders"
        case .appleCalendar: return "Apple Calendar"
        }
    }

    var iconName: String {
        switch self {
        case .googleCalendar: return "calendar"
        case .gmail: return "envelope.fill"
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .jira: return "checkmark.square.fill"
        case .granola: return "doc.text.magnifyingglass"
        case .appleMail: return "envelope.fill"
        case .appleReminders: return "checklist"
        case .appleCalendar: return "calendar.badge.clock"
        }
    }

    var brandColor: Color {
        switch self {
        case .googleCalendar: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .gmail: return Color(red: 0.91, green: 0.26, blue: 0.21)
        case .slack: return Color(red: 0.32, green: 0.15, blue: 0.46)
        case .jira: return Color(red: 0.03, green: 0.47, blue: 0.95)
        case .granola: return Color(red: 0.4, green: 0.65, blue: 0.35)
        case .appleMail: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .appleReminders: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .appleCalendar: return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
    }

    var description: String {
        switch self {
        case .googleCalendar: return "Termine und Meetings synchronisieren"
        case .gmail: return "E-Mails und wichtige Nachrichten"
        case .slack: return "Nachrichten und Mentions aus deinem Workspace"
        case .jira: return "Issues, Kommentare und Updates"
        case .granola: return "Meeting-Notizen und Transkripte"
        case .appleMail: return "E-Mails von deinem Mac"
        case .appleReminders: return "Erinnerungen und Aufgaben"
        case .appleCalendar: return "Lokale Kalender Events"
        }
    }

    var requiresOAuth: Bool {
        switch self {
        case .googleCalendar, .gmail, .slack, .jira, .granola:
            return true
        case .appleMail, .appleReminders, .appleCalendar:
            return false
        }
    }

    var category: ServiceCategory {
        switch self {
        case .googleCalendar, .gmail, .appleMail, .appleCalendar:
            return .communication
        case .slack:
            return .messaging
        case .jira, .granola:
            return .productivity
        case .appleReminders:
            return .tasks
        }
    }
}

/// Category for grouping services
enum ServiceCategory: String, CaseIterable {
    case communication
    case messaging
    case productivity
    case tasks

    var displayName: String {
        switch self {
        case .communication: return "Kommunikation"
        case .messaging: return "Nachrichten"
        case .productivity: return "Produktivität"
        case .tasks: return "Aufgaben"
        }
    }
}
