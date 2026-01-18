import SwiftUI

/// Google Calendar integration for fetching calendar events
@MainActor
final class GoogleCalendarSource: BriefingSource, ObservableObject {
    static let sourceId = "google_calendar"
    static let displayName = "Google Calendar"
    static let iconName = "calendar"
    static let brandColor = Color(red: 0.26, green: 0.52, blue: 0.96) // Google Blue

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?

    // MARK: - Private Properties
    private var oauthService: OAuthService

    private let keychain = KeychainService.shared
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    // MARK: - Configuration

    @Published var selectedCalendars: Set<String> = []
    @Published var availableCalendars: [GoogleCalendar] = []

    // MARK: - Initialization

    init() {
        oauthService = Self.makeOAuthService()
        isAuthenticated = oauthService.isAuthenticated
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            // Rebuild to pick up latest credentials from UserDefaults
            oauthService = Self.makeOAuthService()
            _ = try await oauthService.authorize()
            isAuthenticated = true

            // Fetch available calendars
            try await fetchCalendarList()
        } catch {
            lastError = error
            throw error
        }
    }

    func disconnect() async {
        do {
            try await oauthService.logout()
        } catch {
            print("Logout error: \(error)")
        }
        isAuthenticated = false
        selectedCalendars = []
        availableCalendars = []
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Google verbunden")
        }

        let tokens = try await oauthService.getValidTokens()

        // Get events for today and tomorrow
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)!

        var allEvents: [GoogleCalendarEvent] = []

        // Fetch from selected calendars (or primary if none selected)
        let calendarsToFetch = selectedCalendars.isEmpty ? ["primary"] : Array(selectedCalendars)

        for calendarId in calendarsToFetch {
            let events = try await fetchEvents(
                calendarId: calendarId,
                timeMin: startOfToday,
                timeMax: endOfTomorrow,
                accessToken: tokens.accessToken
            )
            allEvents.append(contentsOf: events)
        }

        // Sort by start time
        allEvents.sort { ($0.start.dateTime ?? $0.start.date ?? Date()) < ($1.start.dateTime ?? $1.start.date ?? Date()) }

        // Convert to BriefingItems
        return allEvents.map { event in
            BriefingItem(
                title: event.summary ?? "Unbenannter Termin",
                subtitle: formatEventTime(event),
                body: event.description,
                timestamp: event.start.dateTime ?? event.start.date,
                deepLink: event.htmlLink.flatMap { URL(string: $0) },
                priority: determinePriority(for: event),
                metadata: [
                    "location": event.location ?? "",
                    "organizer": event.organizer?.displayName ?? event.organizer?.email ?? ""
                ]
            )
        }
    }

    func configurationView() -> AnyView {
        AnyView(GoogleCalendarConfigView(source: self))
    }

    // MARK: - API Calls

    func fetchCalendarList() async throws {
        let tokens = try await oauthService.getValidTokens()

        var request = URLRequest(url: URL(string: "\(baseURL)/users/me/calendarList")!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("Kalender-Liste konnte nicht geladen werden")
        }

        let listResponse = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        availableCalendars = listResponse.items

        // Auto-select primary calendar
        if selectedCalendars.isEmpty, let primary = availableCalendars.first(where: { $0.primary == true }) {
            selectedCalendars.insert(primary.id)
        }
    }

    private func fetchEvents(calendarId: String, timeMin: Date, timeMax: Date, accessToken: String) async throws -> [GoogleCalendarEvent] {
        let formatter = ISO8601DateFormatter()

        var components = URLComponents(string: "\(baseURL)/calendars/\(calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError("Ungültige Server-Antwort")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw SourceError.tokenExpired
            }
            throw SourceError.networkError("Fehler \(httpResponse.statusCode)")
        }

        let eventsResponse = try JSONDecoder().decode(EventsResponse.self, from: data)
        return eventsResponse.items ?? []
    }

    // MARK: - Helpers

    private func formatEventTime(_ event: GoogleCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")

        if let dateTime = event.start.dateTime {
            formatter.dateFormat = "HH:mm"
            let startTime = formatter.string(from: dateTime)

            if let endDateTime = event.end.dateTime {
                let endTime = formatter.string(from: endDateTime)
                return "\(startTime) - \(endTime)"
            }
            return startTime
        } else if let date = event.start.date {
            formatter.dateFormat = "EEEE, d. MMM"
            return "Ganztägig · \(formatter.string(from: date))"
        }

        return ""
    }

    private func determinePriority(for event: GoogleCalendarEvent) -> BriefingSection.Priority {
        // High priority if it starts within the next 2 hours
        if let startTime = event.start.dateTime {
            let hoursUntilStart = startTime.timeIntervalSinceNow / 3600
            if hoursUntilStart <= 2 && hoursUntilStart > 0 {
                return .high
            }
        }

        // Check for keywords that suggest importance
        let title = (event.summary ?? "").lowercased()
        if title.contains("important") || title.contains("urgent") || title.contains("wichtig") || title.contains("dringend") {
            return .urgent
        }

        if title.contains("1:1") || title.contains("interview") || title.contains("review") {
            return .high
        }

        return .medium
    }
}

// MARK: - API Response Models

struct CalendarListResponse: Codable {
    let items: [GoogleCalendar]
}

struct GoogleCalendar: Codable, Identifiable, Hashable {
    let id: String
    let summary: String
    let description: String?
    let primary: Bool?
    let backgroundColor: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GoogleCalendar, rhs: GoogleCalendar) -> Bool {
        lhs.id == rhs.id
    }
}

struct EventsResponse: Codable {
    let items: [GoogleCalendarEvent]?
}

struct GoogleCalendarEvent: Codable, Identifiable {
    let id: String
    let summary: String?
    let description: String?
    let location: String?
    let start: EventDateTime
    let end: EventDateTime
    let htmlLink: String?
    let organizer: EventOrganizer?
    let attendees: [EventAttendee]?
}

struct EventDateTime: Codable {
    let date: Date?
    let dateTime: Date?
    let timeZone: String?

    enum CodingKeys: String, CodingKey {
        case date, dateTime, timeZone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)

        // Handle date-only (all-day events)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: dateString)
        } else {
            date = nil
        }

        // Handle dateTime
        if let dateTimeString = try container.decodeIfPresent(String.self, forKey: .dateTime) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsedDateTime = formatter.date(from: dateTimeString)

            if parsedDateTime == nil {
                formatter.formatOptions = [.withInternetDateTime]
                parsedDateTime = formatter.date(from: dateTimeString)
            }
            dateTime = parsedDateTime
        } else {
            dateTime = nil
        }
    }
}

struct EventOrganizer: Codable {
    let email: String?
    let displayName: String?
}

struct EventAttendee: Codable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
}

// MARK: - Configuration

enum GoogleCalendarConfig {
    // These should be loaded from environment or config file
    static var clientId: String {
        // TODO: Load from secure configuration
        UserDefaults.standard.string(forKey: "google_client_id") ?? ""
    }

    static var clientSecret: String? {
        // For desktop apps, client secret is optional with PKCE
        UserDefaults.standard.string(forKey: "google_client_secret")
    }
}

private extension GoogleCalendarSource {
    static func makeOAuthService() -> OAuthService {
        let config = OAuthService.Configuration(
            clientId: GoogleCalendarConfig.clientId,
            clientSecret: GoogleCalendarConfig.clientSecret,
            authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            // Google native/desktop OAuth requires a loopback redirect (custom schemes like dailybriefing://... are rejected).
            // ":0" is a placeholder that gets replaced per-session with a random high port.
            redirectURI: "http://127.0.0.1:0/oauth/google",
            scopes: [
                "https://www.googleapis.com/auth/calendar.readonly",
                "https://www.googleapis.com/auth/calendar.events.readonly"
            ],
            scopeSeparator: " ",
            additionalAuthorizationQueryItems: [
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ],
            usePKCE: true,
            callbackURLScheme: "http"
        )
        return OAuthService(configuration: config, sourceId: Self.sourceId)
    }
}
