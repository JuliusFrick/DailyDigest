import SwiftUI

/// Granola integration for fetching meeting notes and transcripts
/// Uses the Granola Enterprise API (https://public-api.granola.ai)
@MainActor
final class GranolaSource: BriefingSource, ObservableObject {
    nonisolated static let sourceId = "granola"
    static let displayName = "Granola"
    static let iconName = "doc.text.magnifyingglass"
    static let brandColor = Color(red: 0.4, green: 0.65, blue: 0.35) // Granola green

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties

    private let keychain = KeychainService.shared
    private let baseURL = "https://public-api.granola.ai"

    // MARK: - Initialization

    init() {
        isAuthenticated = keychain.hasTokens(for: Self.sourceId)
        connectionStatus = isAuthenticated ? .connected : .disconnected
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        lastError = nil
        connectionStatus = .connecting
        defer { isLoading = false }

        guard keychain.hasTokens(for: Self.sourceId) else {
            throw SourceError.configurationMissing("Bitte API-Key in den Einstellungen eingeben")
        }

        // Validate API key with a simple list request
        do {
            _ = try await fetchNotesSummary(createdAfter: Date().addingTimeInterval(-86400), pageSize: 1)
            isAuthenticated = true
            connectionStatus = .connected
        } catch {
            if (error as NSError).userInfo["statusCode"] as? Int == 401 {
                throw SourceError.authenticationFailed("Ungültiger Granola API-Key")
            }
            throw error
        }
    }

    func disconnect() async {
        do {
            try keychain.deleteTokens(for: Self.sourceId)
        } catch {
            print("Granola disconnect warning: \(error.localizedDescription)")
        }
        isAuthenticated = false
        connectionStatus = .disconnected
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Granola verbunden")
        }

        let tokens = try keychain.loadTokens(for: Self.sourceId)
        let apiKey = tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SourceError.configurationMissing("Granola API-Key fehlt")
        }

        var allItems: [BriefingItem] = []
        var cursor: String? = nil

        repeat {
            let (notes, nextCursor) = try await fetchNotesSummary(
                createdAfter: since,
                pageSize: 30,
                cursor: cursor
            )

            for note in notes {
                let item = try await noteToBriefingItem(note: note, apiKey: apiKey)
                allItems.append(item)
            }

            cursor = nextCursor
        } while cursor != nil

        // Sort by timestamp descending (newest first)
        allItems.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }

        return allItems
    }

    func configurationView() -> AnyView {
        AnyView(GranolaConfigView(source: self))
    }

    // MARK: - API Helpers

    func saveAPIKey(_ key: String) throws {
        let tokens = KeychainService.OAuthTokens(
            accessToken: key,
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer"
        )
        try keychain.saveTokens(tokens, for: Self.sourceId)
        isAuthenticated = true
        connectionStatus = .connected
    }

    func hasAPIKey() -> Bool {
        keychain.hasTokens(for: Self.sourceId)
    }

    private func fetchNotesSummary(
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        updatedAfter: Date? = nil,
        pageSize: Int = 10,
        cursor: String? = nil
    ) async throws -> ([GranolaNoteSummary], String?) {
        let tokens = try keychain.loadTokens(for: Self.sourceId)
        let apiKey = tokens.accessToken

        var components = URLComponents(string: "\(baseURL)/v1/notes")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page_size", value: "\(min(30, max(1, pageSize)))")
        ]
        if let after = createdAfter {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "created_after", value: formatter.string(from: after)))
        }
        if let before = createdBefore {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "created_before", value: formatter.string(from: before)))
        }
        if let updated = updatedAfter {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "updated_after", value: formatter.string(from: updated)))
        }
        if let c = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: c))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError("Ungültige Server-Antwort")
        }

        if httpResponse.statusCode == 401 {
            throw SourceError.tokenExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("Granola API Fehler \(httpResponse.statusCode)")
        }

        let decoded = try granolaJSONDecoder.decode(GranolaListNotesResponse.self, from: data)
        return (decoded.notes, decoded.hasMore ? decoded.cursor : nil)
    }

    private func fetchNoteDetail(noteId: String, includeTranscript: Bool, apiKey: String) async throws -> GranolaNote {
        var components = URLComponents(string: "\(baseURL)/v1/notes/\(noteId)")!
        if includeTranscript {
            components.queryItems = [URLQueryItem(name: "include", value: "transcript")]
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError("Ungültige Server-Antwort")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("Granola API Fehler \(httpResponse.statusCode)")
        }

        return try granolaJSONDecoder.decode(GranolaNote.self, from: data)
    }

    private func noteToBriefingItem(note: GranolaNoteSummary, apiKey: String) async throws -> BriefingItem {
        // Fetch full note for summary and calendar info
        let fullNote = try await fetchNoteDetail(noteId: note.id, includeTranscript: false, apiKey: apiKey)

        let title = fullNote.title ?? note.title ?? "Meeting ohne Titel"
        let summaryText = fullNote.summaryText ?? ""
        let timestamp = fullNote.calendarEvent?.scheduledStartTime ?? note.createdAt

        var metadata: [String: String] = [
            "noteId": note.id,
            "organizer": fullNote.calendarEvent?.organiser ?? ""
        ]
        if let eventId = fullNote.calendarEvent?.calendarEventId {
            metadata["calendarEventId"] = eventId
        }

        let attendees = (fullNote.attendees ?? []).map { user in
            Attendee(email: user.email, name: user.name, status: .unknown, isOrganizer: false, isCurrentUser: false)
        }

        let subtitle = formatNoteSubtitle(note: fullNote)

        // Deep link to Granola web app (note URLs typically use app.granola.ai)
        let deepLink = URL(string: "https://app.granola.ai/notes/\(note.id)")

        return BriefingItem(
            title: title,
            subtitle: subtitle,
            body: summaryText.isEmpty ? nil : summaryText,
            timestamp: timestamp,
            deepLink: deepLink,
            priority: .high,
            metadata: metadata,
            attendees: attendees
        )
    }

    private func formatNoteSubtitle(note: GranolaNote) -> String {
        var parts: [String] = []

        if let start = note.calendarEvent?.scheduledStartTime {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "HH:mm"
            parts.append(formatter.string(from: start))
        }

        if let attendees = note.attendees, !attendees.isEmpty {
            parts.append("👥 \(attendees.count)")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - API Models

private struct GranolaListNotesResponse: Codable {
    let notes: [GranolaNoteSummary]
    let hasMore: Bool
    let cursor: String?

    enum CodingKeys: String, CodingKey {
        case notes, hasMore = "has_more", cursor
    }
}

struct GranolaNoteSummary: Codable {
    let id: String
    let title: String?
    let owner: GranolaUser?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, owner
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GranolaNote: Codable {
    let id: String
    let title: String?
    let calendarEvent: GranolaCalendarEvent?
    let attendees: [GranolaUser]?
    let summaryText: String?
    let summaryMarkdown: String?

    enum CodingKeys: String, CodingKey {
        case id, title, attendees
        case calendarEvent = "calendar_event"
        case summaryText = "summary_text"
        case summaryMarkdown = "summary_markdown"
    }
}

struct GranolaCalendarEvent: Codable {
    let eventTitle: String?
    let organiser: String?
    let calendarEventId: String?
    let scheduledStartTime: Date?
    let scheduledEndTime: Date?

    enum CodingKeys: String, CodingKey {
        case eventTitle = "event_title"
        case organiser
        case calendarEventId = "calendar_event_id"
        case scheduledStartTime = "scheduled_start_time"
        case scheduledEndTime = "scheduled_end_time"
    }
}

struct GranolaUser: Codable {
    let name: String?
    let email: String
}

// MARK: - JSON Decoder

private let granolaJSONDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
    }
    return d
}()
