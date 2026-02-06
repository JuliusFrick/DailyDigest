import Foundation

// MARK: - Action Item

/// Represents an action item extracted from a meeting transcript
struct ActionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var assignee: String? // Name aus Meeting attendees
    var dueDate: Date?
    let meetingId: String
    var timestamp: TimeInterval? // Wann im Meeting erwähnt
    var status: Status
    let createdAt: Date
    var completedAt: Date?
    
    enum Status: String, Codable, CaseIterable {
        case todo
        case inProgress
        case completed
        case cancelled
        
        var displayName: String {
            switch self {
            case .todo: return "To Do"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
        
        var iconName: String {
            switch self {
            case .todo: return "circle"
            case .inProgress: return "arrow.clockwise.circle"
            case .completed: return "checkmark.circle.fill"
            case .cancelled: return "xmark.circle"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        assignee: String? = nil,
        dueDate: Date? = nil,
        meetingId: String,
        timestamp: TimeInterval? = nil,
        status: Status = .todo,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.assignee = assignee
        self.dueDate = dueDate
        self.meetingId = meetingId
        self.timestamp = timestamp
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
    
    // Helper computed properties
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed && status != .cancelled
    }
    
    var isOpen: Bool {
        status != .completed && status != .cancelled
    }
}

// MARK: - Action Item Response

/// Response structure for LLM extraction
struct ActionItemExtractionResponse: Codable {
    let actionItems: [ExtractedActionItem]
    
    struct ExtractedActionItem: Codable {
        let title: String
        let description: String?
        let assignee: String?
        let dueDateString: String? // e.g., "tomorrow", "next week", "2024-12-25"
        let timestamp: TimeInterval?
    }
}
