import Foundation
import Combine

/// Service for storing and retrieving meeting notes
@MainActor
final class MeetingNotesService: ObservableObject {
    static let shared = MeetingNotesService()
    
    private let userDefaults = UserDefaults.standard
    private let notesKeyPrefix = "meeting_notes_"
    
    private init() {}
    
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
        let titleHash = item.title.hash
        return "\(timestamp)_\(titleHash)"
    }
}