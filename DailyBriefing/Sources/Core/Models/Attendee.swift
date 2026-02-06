import Foundation

/// Represents a meeting attendee
struct Attendee: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let email: String?
    let name: String?
    let status: ResponseStatus
    let isOrganizer: Bool
    let isCurrentUser: Bool
    
    /// Response status for meeting invitations
    enum ResponseStatus: String, Codable {
        case accepted
        case declined
        case tentative
        case pending
        case unknown
        
        var displayName: String {
            switch self {
            case .accepted: return "Zugesagt"
            case .declined: return "Abgesagt"
            case .tentative: return "Vielleicht"
            case .pending: return "Ausstehend"
            case .unknown: return "Unbekannt"
            }
        }
        
        var icon: String {
            switch self {
            case .accepted: return "checkmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            case .tentative: return "questionmark.circle.fill"
            case .pending: return "clock.fill"
            case .unknown: return "circle"
            }
        }
        
        var color: String {
            switch self {
            case .accepted: return "green"
            case .declined: return "red"
            case .tentative: return "orange"
            case .pending: return "gray"
            case .unknown: return "gray"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        email: String? = nil,
        name: String? = nil,
        status: ResponseStatus = .unknown,
        isOrganizer: Bool = false,
        isCurrentUser: Bool = false
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.status = status
        self.isOrganizer = isOrganizer
        self.isCurrentUser = isCurrentUser
    }
    
    /// Display name for UI - prefers name, falls back to email
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        if let email = email {
            // Extract name part from email (before @)
            return email.components(separatedBy: "@").first ?? email
        }
        return "Unbekannt"
    }
    
    /// Short display (first name only)
    var shortName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }
}

// MARK: - Convenience Extensions

extension Array where Element == Attendee {
    /// All attendees except the current user
    var others: [Attendee] {
        filter { !$0.isCurrentUser }
    }
    
    /// Attendees who accepted
    var accepted: [Attendee] {
        filter { $0.status == .accepted }
    }
    
    /// The organizer, if any
    var organizer: Attendee? {
        first { $0.isOrganizer }
    }
    
    /// Formatted string for display: "Max, Lisa, +2"
    func formattedNames(limit: Int = 3) -> String {
        let names = others.prefix(limit).map { $0.shortName }
        let remaining = others.count - limit
        
        if remaining > 0 {
            return names.joined(separator: ", ") + ", +\(remaining)"
        }
        return names.joined(separator: ", ")
    }
}
