import SwiftUI

/// Jira integration for fetching issues and comments
@MainActor
final class JiraSource: BriefingSource, ObservableObject {
    nonisolated static let sourceId = "jira"
    static let displayName = "Jira"
    static let iconName = "checkmark.square.fill"
    static let brandColor = Color(red: 0.03, green: 0.47, blue: 0.95)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties
    private var oauthService: OAuthService

    private let keychain = KeychainService.shared
    
    private var authMethod: JiraAuthMethod {
        JiraConfig.authMethod
    }

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
        switch authMethod {
        case .oauth3LO:
            guard let cloudId = cloudId else { return nil }
            return "https://api.atlassian.com/ex/jira/\(cloudId)/rest/api/3"
        case .apiToken:
            let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !site.isEmpty else { return nil }
            return "\(site.trimmedTrailingSlash)/rest/api/3"
        }
    }

    // MARK: - Initialization

    init() {
        oauthService = Self.makeOAuthService()
        isAuthenticated = Self.computeIsAuthenticated(oauthService: oauthService)
        connectionStatus = isAuthenticated ? .connected : .disconnected
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }

        do {
            switch authMethod {
            case .oauth3LO:
                // Rebuild to pick up latest credentials from UserDefaults
                oauthService = Self.makeOAuthService()
                if oauthService.isAuthenticated {
                    do {
                        _ = try await oauthService.getValidTokens()
                        isAuthenticated = true
                        connectionStatus = .connected
                        try await fetchAccessibleResources()
                        return
                    } catch OAuthError.notAuthenticated {
                        // Fall through to interactive login
                    } catch OAuthError.tokenRefreshFailed {
                        // Fall through to interactive login
                    } catch SourceError.tokenExpired {
                        // Fall through to interactive login
                    } catch {
                        throw error
                    }
                }

                _ = try await oauthService.authorize()
                isAuthenticated = true
                connectionStatus = .connected

                // Fetch accessible resources (cloud instances)
                try await fetchAccessibleResources()
            case .apiToken:
                try await authenticateWithAPIToken()
                isAuthenticated = true
                connectionStatus = .connected
                selectedCloud = nil
                availableClouds = []
            }
        } catch {
            lastError = error
            connectionStatus = .error
            throw error
        }
    }

    func disconnect() async {
        do {
            switch authMethod {
            case .oauth3LO:
                try await oauthService.logout()
            case .apiToken:
                try keychain.delete(for: Self.jiraApiTokenKey)
            }
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
            switch authMethod {
            case .oauth3LO:
                throw SourceError.configurationMissing("Kein Jira Cloud ausgewählt")
            case .apiToken:
                throw SourceError.configurationMissing("Jira Site URL fehlt")
            }
        }

        let authHeader = try await makeAuthorizationHeader()
        var items: [BriefingItem] = []

        // Fetch assigned issues
        if includeAssignedToMe {
            let assignedIssues = try await fetchIssues(
                jql: "assignee = currentUser() AND updated >= -1d ORDER BY updated DESC",
                authorizationHeader: authHeader,
                baseURL: baseURL
            )
            items.append(contentsOf: assignedIssues)
        }

        // Fetch watched issues
        if includeWatching {
            let watchedIssues = try await fetchIssues(
                jql: "watcher = currentUser() AND updated >= -1d ORDER BY updated DESC",
                authorizationHeader: authHeader,
                baseURL: baseURL
            )
            items.append(contentsOf: watchedIssues)
        }

        // Fetch mentioned issues
        if includeMentions {
            let mentionedIssues = try await fetchIssues(
                jql: "text ~ currentUser() AND updated >= -1d ORDER BY updated DESC",
                authorizationHeader: authHeader,
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
        guard authMethod == .oauth3LO else { return }
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

    private func fetchIssues(jql: String, authorizationHeader: String, baseURL: String) async throws -> [BriefingItem] {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "fields", value: "summary,description,status,priority,updated,assignee,reporter,issuetype")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
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
        switch authMethod {
        case .oauth3LO:
            guard let cloud = selectedCloud else { return nil }
            return URL(string: "\(cloud.url)/browse/\(issueKey)")
        case .apiToken:
            let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !site.isEmpty else { return nil }
            return URL(string: "\(site.trimmedTrailingSlash)/browse/\(issueKey)")
        }
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
    static var authMethod: JiraAuthMethod {
        JiraAuthMethod(rawValue: UserDefaults.standard.string(forKey: "jira_auth_method") ?? JiraAuthMethod.oauth3LO.rawValue)
            ?? .oauth3LO
    }

    static var clientId: String {
        let bundled = OAuthClientConfigStore.normalized(OAuthClientConfigStore.shared?.jira?.clientId)
        if !bundled.isEmpty {
            return bundled
        }
        return UserDefaults.standard.string(forKey: "jira_client_id") ?? ""
    }

    static var clientSecret: String? {
        let bundled = OAuthClientConfigStore.normalized(OAuthClientConfigStore.shared?.jira?.clientSecret)
        if !bundled.isEmpty {
            return bundled
        }
        return UserDefaults.standard.string(forKey: "jira_client_secret")
    }

    static var siteURL: String {
        UserDefaults.standard.string(forKey: "jira_site_url") ?? ""
    }

    static var email: String {
        UserDefaults.standard.string(forKey: "jira_email") ?? ""
    }

    static var hasBundledOAuthConfig: Bool {
        !OAuthClientConfigStore.normalized(OAuthClientConfigStore.shared?.jira?.clientId).isEmpty
    }
}

private extension JiraSource {
    static let jiraApiTokenKey = "jira_api_token"

    static func makeOAuthService() -> OAuthService {
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
            ],
            scopeSeparator: " ",
            additionalAuthorizationQueryItems: [
                // Atlassian requires the audience parameter for 3LO.
                URLQueryItem(name: "audience", value: "api.atlassian.com"),
                URLQueryItem(name: "prompt", value: "consent")
            ],
            useExternalBrowser: true
        )
        return OAuthService(configuration: config, sourceId: Self.sourceId)
    }

    static func computeIsAuthenticated(oauthService: OAuthService) -> Bool {
        switch JiraConfig.authMethod {
        case .oauth3LO:
            return oauthService.isAuthenticated
        case .apiToken:
            let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = JiraConfig.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !site.isEmpty, !email.isEmpty else { return false }
            return KeychainService.shared.exists(for: jiraApiTokenKey)
        }
    }

    func makeAuthorizationHeader() async throws -> String {
        switch authMethod {
        case .oauth3LO:
            let tokens = try await oauthService.getValidTokens()
            return "Bearer \(tokens.accessToken)"
        case .apiToken:
            let email = JiraConfig.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, !site.isEmpty else {
                throw SourceError.configurationMissing("Jira Site URL / E-Mail fehlt")
            }
            let token = try keychain.loadString(for: Self.jiraApiTokenKey)
            let raw = "\(email):\(token)"
            guard let data = raw.data(using: .utf8) else {
                throw SourceError.networkError("Konnte Jira Credentials nicht kodieren")
            }
            return "Basic \(data.base64EncodedString())"
        }
    }

    func authenticateWithAPIToken() async throws {
        let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = JiraConfig.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { throw SourceError.configurationMissing("Jira Site URL") }
        guard !email.isEmpty else { throw SourceError.configurationMissing("Jira E-Mail") }

        _ = try keychain.loadString(for: Self.jiraApiTokenKey)

        guard let url = URL(string: "\(site.trimmedTrailingSlash)/rest/api/3/myself") else {
            throw SourceError.configurationMissing("Ungültige Jira Site URL")
        }

        var request = URLRequest(url: url)
        request.setValue(try await makeAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.networkError("Ungültige Server-Antwort")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SourceError.authenticationFailed("Jira API Token ungültig oder keine Berechtigung")
            }
            throw SourceError.networkError("Fehler \(http.statusCode)")
        }
    }
}

enum JiraAuthMethod: String, CaseIterable, Identifiable {
    case oauth3LO = "oauth_3lo"
    case apiToken = "api_token"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oauth3LO: return "OAuth"
        case .apiToken: return "API Token"
        }
    }
}

private extension String {
    var trimmedTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
