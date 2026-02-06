import Foundation

/// Email context for a meeting
struct MeetingEmailContext {
    let meeting: BriefingItem
    let emailsByAttendee: [String: [EmailSummary]] // email address -> emails
    let totalEmailCount: Int
    let unreadCount: Int
    
    /// Summary of emails for context
    var contextSummary: String {
        if totalEmailCount == 0 {
            return "Keine kürzlichen Emails mit Teilnehmern"
        }
        
        var parts: [String] = []
        for (email, emails) in emailsByAttendee {
            let name = email.components(separatedBy: "@").first ?? email
            let unread = emails.filter { $0.isUnread }.count
            if unread > 0 {
                parts.append("\(name): \(emails.count) Emails (\(unread) ungelesen)")
            } else {
                parts.append("\(name): \(emails.count) Emails")
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// Lightweight email summary for meeting context
struct EmailSummary: Identifiable, Codable {
    let id: String
    let subject: String
    let from: String
    let to: String
    let snippet: String?
    let timestamp: Date?
    let isUnread: Bool
    let threadId: String
    
    var displayDate: String {
        guard let timestamp = timestamp else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

/// Service for fetching email context for meeting attendees
@MainActor
final class MeetingContextService: ObservableObject {
    static let shared = MeetingContextService()
    
    // MARK: - Published Properties
    
    @Published var isLoading = false
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    
    private let keychain = KeychainService.shared
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private var oauthService: OAuthService?
    
    // MARK: - Cache
    
    private var contextCache: [String: (context: MeetingEmailContext, fetchedAt: Date)] = [:]
    private let cacheValiditySeconds: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        // OAuth service is lazily created when needed
    }
    
    // MARK: - Public API
    
    /// Fetch email context for a meeting's attendees
    /// - Parameters:
    ///   - meeting: The meeting to get context for
    ///   - days: Number of days to look back for emails
    /// - Returns: Email context with recent emails grouped by attendee
    func fetchEmailContext(for meeting: BriefingItem, days: Int = 7) async throws -> MeetingEmailContext {
        let cacheKey = cacheKey(for: meeting)
        
        // Check cache
        if let cached = contextCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < cacheValiditySeconds {
            return cached.context
        }
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        // Get attendee emails (excluding current user)
        let attendeeEmails = meeting.attendees.others.compactMap { $0.email }
        
        guard !attendeeEmails.isEmpty else {
            let emptyContext = MeetingEmailContext(
                meeting: meeting,
                emailsByAttendee: [:],
                totalEmailCount: 0,
                unreadCount: 0
            )
            return emptyContext
        }
        
        // Ensure OAuth service exists and is authenticated
        let tokens = try await getValidTokens()
        
        // Calculate date range
        let calendar = Calendar.current
        let sinceDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        
        // Fetch emails for each attendee
        var emailsByAttendee: [String: [EmailSummary]] = [:]
        var totalCount = 0
        var unreadCount = 0
        
        for email in attendeeEmails {
            do {
                let emails = try await fetchEmails(
                    for: email,
                    since: sinceDate,
                    accessToken: tokens.accessToken
                )
                
                if !emails.isEmpty {
                    emailsByAttendee[email] = emails
                    totalCount += emails.count
                    unreadCount += emails.filter { $0.isUnread }.count
                }
            } catch {
                // Log but continue with other attendees
                print("Failed to fetch emails for \(email): \(error)")
            }
        }
        
        let context = MeetingEmailContext(
            meeting: meeting,
            emailsByAttendee: emailsByAttendee,
            totalEmailCount: totalCount,
            unreadCount: unreadCount
        )
        
        // Cache the result
        contextCache[cacheKey] = (context, Date())
        
        return context
    }
    
    /// Clear the context cache
    func clearCache() {
        contextCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func getValidTokens() async throws -> KeychainService.OAuthTokens {
        // Try to load existing tokens for Gmail
        if keychain.hasTokens(for: GmailSource.sourceId) {
            if oauthService == nil {
                oauthService = makeOAuthService()
            }
            return try await oauthService!.getValidTokens()
        }
        
        throw MeetingContextError.notAuthenticated
    }
    
    private func fetchEmails(for email: String, since: Date, accessToken: String) async throws -> [EmailSummary] {
        // Build Gmail search query
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let dateStr = dateFormatter.string(from: since)
        
        // Search for emails from OR to this person
        let query = "(from:\(email) OR to:\(email)) after:\(dateStr)"
        
        var components = URLComponents(string: "\(baseURL)/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "10")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingContextError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw MeetingContextError.tokenExpired
            }
            throw MeetingContextError.apiError(httpResponse.statusCode)
        }
        
        let listResponse = try JSONDecoder().decode(GmailMessageListResponse.self, from: data)
        guard let messages = listResponse.messages else {
            return []
        }
        
        // Fetch details for each message
        var emailSummaries: [EmailSummary] = []
        for messageRef in messages.prefix(10) {
            if let summary = try? await fetchEmailSummary(
                messageId: messageRef.id,
                threadId: messageRef.threadId,
                accessToken: accessToken
            ) {
                emailSummaries.append(summary)
            }
        }
        
        return emailSummaries.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }
    
    private func fetchEmailSummary(messageId: String, threadId: String, accessToken: String) async throws -> EmailSummary {
        var components = URLComponents(string: "\(baseURL)/users/me/messages/\(messageId)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "To"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let message = try JSONDecoder().decode(GmailMessage.self, from: data)
        
        let subject = message.payload?.headers?.first { $0.name == "Subject" }?.value ?? "Kein Betreff"
        let from = message.payload?.headers?.first { $0.name == "From" }?.value ?? ""
        let to = message.payload?.headers?.first { $0.name == "To" }?.value ?? ""
        let dateString = message.payload?.headers?.first { $0.name == "Date" }?.value
        
        let isUnread = message.labelIds?.contains("UNREAD") ?? false
        
        return EmailSummary(
            id: messageId,
            subject: subject,
            from: from,
            to: to,
            snippet: message.snippet,
            timestamp: parseEmailDate(dateString),
            isUnread: isUnread,
            threadId: threadId
        )
    }
    
    private func parseEmailDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatters = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss z"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    private func cacheKey(for meeting: BriefingItem) -> String {
        let attendeeKey = meeting.attendees.others
            .compactMap { $0.email }
            .sorted()
            .joined(separator: ",")
        return "\(meeting.id)_\(attendeeKey)"
    }
    
    private func makeOAuthService() -> OAuthService {
        let config = OAuthService.Configuration(
            clientId: GoogleConfig.clientId,
            clientSecret: GoogleConfig.clientSecret,
            authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            redirectURI: "http://127.0.0.1:0/oauth/google",
            scopes: [
                "https://www.googleapis.com/auth/gmail.readonly"
            ],
            scopeSeparator: " ",
            additionalAuthorizationQueryItems: [
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ],
            usePKCE: true,
            useExternalBrowser: true,
            callbackURLScheme: "http"
        )
        return OAuthService(configuration: config, sourceId: GmailSource.sourceId)
    }
}

// MARK: - Errors

enum MeetingContextError: LocalizedError {
    case notAuthenticated
    case networkError
    case tokenExpired
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Gmail ist nicht verbunden. Bitte verbinde Gmail in den Einstellungen."
        case .networkError:
            return "Netzwerkfehler beim Laden der Emails."
        case .tokenExpired:
            return "Gmail-Sitzung abgelaufen. Bitte erneut anmelden."
        case .apiError(let code):
            return "Gmail API Fehler: \(code)"
        }
    }
}
