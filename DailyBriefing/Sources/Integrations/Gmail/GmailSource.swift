import SwiftUI

/// Gmail integration for fetching unread emails
@MainActor
final class GmailSource: BriefingSource, ObservableObject {
    static let sourceId = "gmail"
    static let displayName = "Gmail"
    static let iconName = "envelope.fill"
    static let brandColor = Color(red: 0.91, green: 0.26, blue: 0.21)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties
    private var oauthService: OAuthService

    private let keychain = KeychainService.shared
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"

    // MARK: - Configuration

    @Published var maxEmailsToFetch: Int = 20
    @Published var fetchUnreadOnly: Bool = true
    @Published var selectedLabels: Set<String> = ["INBOX"]

    // MARK: - Initialization

    init() {
        oauthService = Self.makeOAuthService()
        isAuthenticated = oauthService.isAuthenticated
        connectionStatus = isAuthenticated ? .connected : .disconnected
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }

        do {
            // Rebuild to pick up latest credentials from UserDefaults
            oauthService = Self.makeOAuthService()
            _ = try await oauthService.authorize()
            isAuthenticated = true
            connectionStatus = .connected
        } catch {
            lastError = error
            connectionStatus = .error
            throw error
        }
    }

    func disconnect() async {
        do {
            try await oauthService.logout()
        } catch {
            print("Gmail logout error: \(error)")
        }
        isAuthenticated = false
        connectionStatus = .disconnected
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Gmail verbunden")
        }

        let tokens = try await oauthService.getValidTokens()

        // Fetch message list
        let messages = try await fetchMessageList(accessToken: tokens.accessToken, since: since)

        // Fetch full message details
        var items: [BriefingItem] = []
        for message in messages.prefix(maxEmailsToFetch) {
            if let item = try? await fetchMessageDetails(messageId: message.id, accessToken: tokens.accessToken) {
                items.append(item)
            }
        }

        return items
    }

    func configurationView() -> AnyView {
        AnyView(GmailConfigView(source: self))
    }

    // MARK: - API Calls

    private func fetchMessageList(accessToken: String, since: Date) async throws -> [GmailMessageRef] {
        var components = URLComponents(string: "\(baseURL)/users/me/messages")!

        var queryParts: [String] = []
        if fetchUnreadOnly {
            queryParts.append("is:unread")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        queryParts.append("after:\(dateFormatter.string(from: since))")

        if !selectedLabels.isEmpty {
            let labelQuery = selectedLabels.map { "label:\($0.lowercased())" }.joined(separator: " OR ")
            queryParts.append("(\(labelQuery))")
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: queryParts.joined(separator: " ")),
            URLQueryItem(name: "maxResults", value: String(maxEmailsToFetch))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError("Ungültige Server-Antwort")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                connectionStatus = .tokenExpired
                throw SourceError.tokenExpired
            }
            throw SourceError.networkError("Fehler \(httpResponse.statusCode)")
        }

        let listResponse = try JSONDecoder().decode(GmailMessageListResponse.self, from: data)
        return listResponse.messages ?? []
    }

    private func fetchMessageDetails(messageId: String, accessToken: String) async throws -> BriefingItem {
        var components = URLComponents(string: "\(baseURL)/users/me/messages/\(messageId)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("E-Mail konnte nicht geladen werden")
        }

        let message = try JSONDecoder().decode(GmailMessage.self, from: data)

        let subject = message.payload?.headers?.first { $0.name == "Subject" }?.value ?? "Kein Betreff"
        let from = message.payload?.headers?.first { $0.name == "From" }?.value ?? "Unbekannt"
        let dateString = message.payload?.headers?.first { $0.name == "Date" }?.value
        let timestamp = parseEmailDate(dateString)

        let priority = determinePriority(labels: message.labelIds ?? [], from: from)

        return BriefingItem(
            title: subject,
            subtitle: formatSender(from),
            body: message.snippet,
            timestamp: timestamp,
            deepLink: URL(string: "https://mail.google.com/mail/u/0/#inbox/\(messageId)"),
            priority: priority,
            metadata: [
                "messageId": messageId,
                "from": from,
                "labels": (message.labelIds ?? []).joined(separator: ",")
            ]
        )
    }

    // MARK: - Helpers

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

    private func formatSender(_ from: String) -> String {
        if let nameEnd = from.firstIndex(of: "<") {
            return String(from[..<nameEnd]).trimmingCharacters(in: .whitespaces)
        }
        return from
    }

    private func determinePriority(labels: [String], from: String) -> BriefingSection.Priority {
        if labels.contains("IMPORTANT") || labels.contains("STARRED") {
            return .high
        }

        if labels.contains("CATEGORY_UPDATES") || labels.contains("CATEGORY_PROMOTIONS") {
            return .low
        }

        return .medium
    }
}

// MARK: - API Response Models

struct GmailMessageListResponse: Codable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailPayload?
    let internalDate: String?
}

struct GmailPayload: Codable {
    let headers: [GmailHeader]?
    let mimeType: String?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

// MARK: - Shared Google Configuration

enum GoogleConfig {
    static var clientId: String {
        UserDefaults.standard.string(forKey: "google_client_id") ?? ""
    }

    static var clientSecret: String? {
        UserDefaults.standard.string(forKey: "google_client_secret")
    }
}

private extension GmailSource {
    static func makeOAuthService() -> OAuthService {
        let config = OAuthService.Configuration(
            clientId: GoogleConfig.clientId,
            clientSecret: GoogleConfig.clientSecret,
            authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            // Google native/desktop OAuth requires a loopback redirect (custom schemes like dailybriefing://... are rejected).
            // ":0" is a placeholder that gets replaced per-session with a random high port.
            redirectURI: "http://127.0.0.1:0/oauth/google",
            scopes: [
                "https://www.googleapis.com/auth/gmail.readonly",
                "https://www.googleapis.com/auth/gmail.labels"
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
