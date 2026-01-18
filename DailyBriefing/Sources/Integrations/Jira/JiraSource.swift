import SwiftUI

/// Jira integration for fetching issues and comments
@MainActor
final class JiraSource: BriefingSource, ObservableObject {
    static let sourceId = "jira"
    static let displayName = "Jira"
    static let iconName = "checkmark.square.fill"
    static let brandColor = Color(red: 0.03, green: 0.47, blue: 0.95)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties

    private lazy var oauthService: OAuthService = {
        let config = OAuthService.Configuration(
            clientId: JiraConfig.clientId,
            clientSecret: JiraConfig.clientSecret,
            authorizationURL: URL(string: "https://auth.atlassian.com/authorize")!,
            tokenURL: URL(string: "https://auth.atlassian.com/oauth/token")!,
            redirectURI: "dailybriefing://oauth/jira",
            scopes: [
                "read:jira-user",
                "read:jira-work",
                "offline_access"
            ]
        )
        return OAuthService(configuration: config, sourceId: Self.sourceId)
    }()

    private let keychain = KeychainService.shared

    // MARK: - Configuration

    @Published var selectedCloud: JiraCloud?
    @Published var availableClouds: [JiraCloud] = []
    @Published var includeAssignedToMe: Bool = true
    @Published var includeWatching: Bool = true
    @Published var includeMentions: Bool = true

    private var cloudId: String? {
        selectedCloud?.id
    }

    private var baseURL: String? {
        guard let cloudId = cloudId else { return nil }
        return "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3"
    }

    // MARK: - Initialization

    init() {
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
            _ = try await oauthService.authorize()
            isAuthenticated = true
            connectionStatus = .connected

            // Fetch accessible resources (cloud instances)
            try await fetchAccessibleResources()
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
            print("Jira logout error: \(error)")
        }
        isAuthenticated = false
        connectionStatus = .disconnected
        selectedCloud = nil
        availableClouds = []
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Jira verbunden")
        }

        guard let baseURL = baseURL else {
            throw SourceError.configurationMissing("Kein Jira Cloud ausgewählt")
        }

        let tokens = try await oauthService.getValidTokens()
        var items: [BriefingItem] = []

        // Fetch assigned issues
        if includeAssignedToMe {
            let assignedIssues = try await fetchIssues(
                jql: "assignee = currentUser() AND updated >= -1d ORDER BY updated DESC",
                accessToken: tokens.accessToken,
                baseURL: baseURL
            )
            items.append(contentsOf: assignedIssues)
        }

        // Fetch watched issues
        if includeWatching {
            let watchedIssues = try await fetchIssues(
                jql: "watcher = currentUser() AND updated >= -1d ORDER BY updated DESC",
                accessToken: tokens.accessToken,
                baseURL: baseURL
            )
            items.append(contentsOf: watchedIssues)
        }

        // Fetch mentioned issues
        if includeMentions {
            let mentionedIssues = try await fetchIssues(
                jql: "text ~ currentUser() AND updated >= -1d ORDER BY updated DESC",
                accessToken: tokens.accessToken,
                baseURL: baseURL
            )
            items.append(contentsOf: mentionedIssues)
        }

        // Remove duplicates and sort
        let uniqueItems = Array(Set(items.map { $0.id })).compactMap { id in
            items.first { $0.id == id }
        }

        return uniqueItems.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    func configurationView() -> AnyView {
        AnyView(JiraConfigView(source: self))
    }

    // MARK: - API Calls

    func fetchAccessibleResources() async throws {
        let tokens = try await oauthService.getValidTokens()

        var request = URLRequest(url: URL(string: "https://api.atlassian.com/oauth/token/accessible-resources")!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("Jira-Ressourcen konnten nicht geladen werden")
        }

        availableClouds = try JSONDecoder().decode([JiraCloud].self, from: data)

        // Auto-select first cloud if none selected
        if selectedCloud == nil, let firstCloud = availableClouds.first {
            selectedCloud = firstCloud
        }
    }

    private func fetchIssues(jql: String, accessToken: String, baseURL: String) async throws -> [BriefingItem] {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "fields", value: "summary,description,status,priority,updated,assignee,reporter,issuetype")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        let searchResponse = try JSONDecoder().decode(JiraSearchResponse.self, from: data)

        return (searchResponse.issues ?? []).map { issue in
            let priority = mapJiraPriority(issue.fields.priority?.name)
            let statusName = issue.fields.status?.name ?? "Unbekannt"
            let issueType = issue.fields.issuetype?.name ?? "Issue"

            return BriefingItem(
                title: "[\(issue.key)] \(issue.fields.summary ?? "Kein Titel")",
                subtitle: "\(issueType) · \(statusName)",
                body: issue.fields.description?.content?.first?.content?.first?.text,
                timestamp: parseJiraDate(issue.fields.updated),
                deepLink: buildJiraDeepLink(issueKey: issue.key),
                priority: priority,
                metadata: [
                    "issueKey": issue.key,
                    "status": statusName,
                    "assignee": issue.fields.assignee?.displayName ?? "",
                    "reporter": issue.fields.reporter?.displayName ?? ""
                ]
            )
        }
    }

    // MARK: - Helpers

    private func mapJiraPriority(_ priorityName: String?) -> BriefingSection.Priority {
        guard let name = priorityName?.lowercased() else { return .medium }

        switch name {
        case "highest", "blocker":
            return .urgent
        case "high":
            return .high
        case "medium", "normal":
            return .medium
        case "low", "lowest":
            return .low
        default:
            return .medium
        }
    }

    private func parseJiraDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private func buildJiraDeepLink(issueKey: String) -> URL? {
        guard let cloud = selectedCloud else { return nil }
        return URL(string: "\(cloud.url)/browse/\(issueKey)")
    }
}

// MARK: - API Response Models

struct JiraCloud: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let url: String
    let scopes: [String]?
    let avatarUrl: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JiraCloud, rhs: JiraCloud) -> Bool {
        lhs.id == rhs.id
    }
}

struct JiraSearchResponse: Codable {
    let total: Int?
    let maxResults: Int?
    let issues: [JiraIssue]?
}

struct JiraIssue: Codable {
    let id: String
    let key: String
    let fields: JiraIssueFields
}

struct JiraIssueFields: Codable {
    let summary: String?
    let description: JiraDescription?
    let status: JiraStatus?
    let priority: JiraPriority?
    let issuetype: JiraIssueType?
    let assignee: JiraUser?
    let reporter: JiraUser?
    let updated: String?
}

struct JiraDescription: Codable {
    let content: [JiraContent]?
}

struct JiraContent: Codable {
    let content: [JiraTextContent]?
}

struct JiraTextContent: Codable {
    let text: String?
}

struct JiraStatus: Codable {
    let name: String
    let statusCategory: JiraStatusCategory?
}

struct JiraStatusCategory: Codable {
    let key: String
    let name: String
}

struct JiraPriority: Codable {
    let name: String
    let iconUrl: String?
}

struct JiraIssueType: Codable {
    let name: String
    let iconUrl: String?
}

struct JiraUser: Codable {
    let accountId: String
    let displayName: String?
    let avatarUrls: JiraAvatarUrls?
}

struct JiraAvatarUrls: Codable {
    let url48x48: String?
    let url24x24: String?
    let url16x16: String?

    enum CodingKeys: String, CodingKey {
        case url48x48 = "48x48"
        case url24x24 = "24x24"
        case url16x16 = "16x16"
    }
}

// MARK: - Configuration

enum JiraConfig {
    static var clientId: String {
        UserDefaults.standard.string(forKey: "jira_client_id") ?? ""
    }

    static var clientSecret: String? {
        UserDefaults.standard.string(forKey: "jira_client_secret")
    }
}
