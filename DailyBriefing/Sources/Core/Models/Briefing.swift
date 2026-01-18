import Foundation

/// Represents a generated briefing
struct Briefing: Identifiable, Codable {
    let id: UUID
    let generatedAt: Date
    let summary: String
    let audioURL: URL?
    let sections: [BriefingSection]
    let detailLevel: DetailLevel

    enum DetailLevel: String, Codable, CaseIterable {
        case quick
        case detailed

        var displayName: String {
            switch self {
            case .quick: return "Quick (2-3 Min)"
            case .detailed: return "Detailed (5-10 Min)"
            }
        }
    }

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        summary: String,
        audioURL: URL? = nil,
        sections: [BriefingSection],
        detailLevel: DetailLevel
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.summary = summary
        self.audioURL = audioURL
        self.sections = sections
        self.detailLevel = detailLevel
    }
}

/// A section within a briefing, typically from one source
struct BriefingSection: Identifiable, Codable {
    let id: UUID
    let sourceId: String
    let sourceName: String
    let sourceIcon: String
    let summary: String
    let items: [BriefingItem]
    let priority: Priority

    enum Priority: Int, Codable, Comparable {
        case low = 0
        case medium = 1
        case high = 2
        case urgent = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        sourceId: String,
        sourceName: String,
        sourceIcon: String,
        summary: String,
        items: [BriefingItem],
        priority: Priority = .medium
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.sourceIcon = sourceIcon
        self.summary = summary
        self.items = items
        self.priority = priority
    }
}

/// An individual item from a source
struct BriefingItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let subtitle: String?
    let body: String?
    let timestamp: Date?
    let deepLink: URL?
    let priority: BriefingSection.Priority
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        timestamp: Date? = nil,
        deepLink: URL? = nil,
        priority: BriefingSection.Priority = .medium,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.timestamp = timestamp
        self.deepLink = deepLink
        self.priority = priority
        self.metadata = metadata
    }
}
