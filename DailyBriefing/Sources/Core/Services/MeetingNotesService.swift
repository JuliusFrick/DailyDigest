import Foundation
import Combine
import CryptoKit

/// Represents an ad-hoc meeting recording (not from calendar)
struct AdHocMeeting: Codable, Identifiable {
    let id: String
    var title: String
    let createdAt: Date
    var notes: String
    var summary: String?
    
    init(title: String = "", notes: String = "", summary: String? = nil) {
        self.id = UUID().uuidString
        self.title = title.isEmpty ? Self.defaultTitle(for: Date()) : title
        self.createdAt = Date()
        self.notes = notes
        self.summary = summary
    }
    
    static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM, HH:mm"
        return "Aufnahme \(formatter.string(from: date))"
    }
}

/// Service for storing and retrieving meeting notes
@MainActor
final class MeetingNotesService: ObservableObject {
    static let shared = MeetingNotesService()
    
    private let userDefaults = UserDefaults.standard
    private let notesKeyPrefix = "meeting_notes_"
    private let adHocMeetingsKey = "adhoc_meetings"
    
    @Published private(set) var adHocMeetings: [AdHocMeeting] = []
    
    private init() {
        loadAdHocMeetings()
    }
    
    // MARK: - Calendar Meeting Notes
    
    /// Save meeting notes for a specific meeting
    /// - Parameters:
    ///   - meetingId: Unique identifier for the meeting (e.g., calendar event ID or item ID)
    ///   - notes: The transcribed notes
    func saveNotes(meetingId: String, notes: String) {
        let key = notesKeyPrefix + meetingId
        userDefaults.set(notes, forKey: key)
    }
    
    /// Get meeting notes for a specific meeting
    /// - Parameter meetingId: Unique identifier for the meeting
    /// - Returns: The stored notes, or nil if not found
    func getNotes(meetingId: String) -> String? {
        let key = notesKeyPrefix + meetingId
        return userDefaults.string(forKey: key)
    }

    /// Get meeting notes for a briefing item with fallback to legacy IDs
    func getNotes(for item: BriefingItem) -> String? {
        let preferredId = meetingId(for: item)
        if let notes = getNotes(meetingId: preferredId) {
            return notes
        }

        let legacyId = legacyMeetingId(for: item)
        if legacyId != preferredId {
            return getNotes(meetingId: legacyId)
        }

        return nil
    }
    
    /// Delete meeting notes for a specific meeting
    /// - Parameter meetingId: Unique identifier for the meeting
    func deleteNotes(meetingId: String) {
        let key = notesKeyPrefix + meetingId
        userDefaults.removeObject(forKey: key)
    }
    
    /// Generate a meeting ID from a BriefingItem
    /// Prefer stable event identifiers when available
    func meetingId(for item: BriefingItem) -> String {
        if let eventId = item.metadata["eventId"], !eventId.isEmpty {
            return "google_calendar_\(eventId)"
        }

        return legacyMeetingId(for: item)
    }

    private func legacyMeetingId(for item: BriefingItem) -> String {
        let timestamp = item.timestamp?.timeIntervalSince1970 ?? 0
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let raw = "\(timestamp)_\(normalizedTitle)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let stableHash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(timestamp)_\(stableHash)"
    }
    
    // MARK: - Ad-Hoc Meetings
    
    /// Create a new ad-hoc meeting with transcribed notes
    @discardableResult
    func createAdHocMeeting(title: String = "", notes: String, summary: String? = nil) -> AdHocMeeting {
        let meeting = AdHocMeeting(title: title, notes: notes, summary: summary)
        adHocMeetings.insert(meeting, at: 0)
        saveAdHocMeetings()
        return meeting
    }
    
    /// Update an existing ad-hoc meeting
    func updateAdHocMeeting(id: String, title: String? = nil, notes: String? = nil, summary: String? = nil) {
        guard let index = adHocMeetings.firstIndex(where: { $0.id == id }) else { return }
        
        if let title = title {
            adHocMeetings[index].title = title
        }
        if let notes = notes {
            adHocMeetings[index].notes = notes
        }
        if let summary = summary {
            adHocMeetings[index].summary = summary
        }
        saveAdHocMeetings()
    }
    
    /// Delete an ad-hoc meeting
    func deleteAdHocMeeting(id: String) {
        adHocMeetings.removeAll { $0.id == id }
        saveAdHocMeetings()
    }
    
    /// Get an ad-hoc meeting by ID
    func getAdHocMeeting(id: String) -> AdHocMeeting? {
        adHocMeetings.first { $0.id == id }
    }
    
    private func loadAdHocMeetings() {
        guard let data = userDefaults.data(forKey: adHocMeetingsKey),
              let meetings = try? JSONDecoder().decode([AdHocMeeting].self, from: data) else {
            adHocMeetings = []
            return
        }
        adHocMeetings = meetings
    }
    
    private func saveAdHocMeetings() {
        guard let data = try? JSONEncoder().encode(adHocMeetings) else { return }
        userDefaults.set(data, forKey: adHocMeetingsKey)
    }
    
    // MARK: - Query All Notes
    
    /// Get all meeting IDs that have notes stored
    /// Returns an array of meeting IDs with saved notes
    func allMeetingIdsWithNotes() -> [String] {
        let prefix = notesKeyPrefix
        return userDefaults.dictionaryRepresentation()
            .keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
    
    /// Check if a meeting has notes stored
    /// - Parameter meetingId: The meeting ID to check
    /// - Returns: true if notes exist for this meeting
    func hasNotes(for meetingId: String) -> Bool {
        let key = notesKeyPrefix + meetingId
        return userDefaults.string(forKey: key) != nil
    }
}