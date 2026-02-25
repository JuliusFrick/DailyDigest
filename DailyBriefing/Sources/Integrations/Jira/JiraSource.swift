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
    private let keychain = KeychainService.shared

    // MARK: - Configuration

    @Published var includeAssignedToMe: Bool = true
    @Published var includeWatching: Bool = true
    @Published var includeMentions: Bool = true

    private var baseURL: String? {
        let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { return nil }
        return "\(site.trimmedTrailingSlash)/rest/api/3"
    }

    // MARK: - Initialization

    init() {
        isAuthenticated = Self.computeIsAuthenticated()
        connectionStatus = isAuthenticated ? .connected : .disconnected
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }

        do {
            try await authenticateWithAPIToken()
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
            try keychain.delete(for: Self.jiraApiTokenKey)
        } catch {
            // Log to console - cleanup operation
            print("Jira logout warning: \(error.localizedDescription)")
        }
        isAuthenticated = false
        connectionStatus = .disconnected
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Jira verbunden")
        }

        guard let baseURL = baseURL else {
            throw SourceError.configurationMissing("Jira Site URL fehlt")
        }

        let authHeader = try makeAuthorizationHeader()
        var items: [BriefingItem] = []

        // Fetch assigned issues
        if includeAssignedToMe {
            let assignedIssues = try await fetchIssues(
                jql: buildJiraJQL(baseClause: "assignee = currentUser()"),
                authorizationHeader: authHeader,
                baseURL: baseURL
            )
            items.append(contentsOf: assignedIssues)
        }

        // Fetch watched issues
        if includeWatching {
            let watchedIssues = try await fetchIssues(
                jql: buildJiraJQL(baseClause: "watcher = currentUser()"),
                authorizationHeader: authHeader,
                baseURL: baseURL
            )
            items.append(contentsOf: watchedIssues)
        }

        // Fetch mentioned issues
        if includeMentions {
            let mentionedIssues = try await fetchIssues(
                jql: buildJiraJQL(baseClause: "text ~ currentUser()"),
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

        var items: [BriefingItem] = []

        for issue in searchResponse.issues ?? [] {
            let latestComment = await fetchLatestComment(
                issueKey: issue.key,
                authorizationHeader: authorizationHeader,
                baseURL: baseURL
            )
            let priority = mapJiraPriority(issue.fields.priority?.name)
            let statusName = issue.fields.status?.name ?? "Unbekannt"
            let issueType = issue.fields.issuetype?.name ?? "Issue"
            let body = buildJiraItemBody(issue: issue.fields, latestComment: latestComment)
            var metadata: [String: String] = [
                "issueKey": issue.key,
                "status": statusName,
                "assignee": issue.fields.assignee?.displayName ?? "",
                "reporter": issue.fields.reporter?.displayName ?? ""
            ]

            if let commentCount = latestComment.commentCount {
                metadata["commentCount"] = "\(commentCount)"
            }
            if let latestCommentAuthor = latestComment.authorName {
                metadata["latestCommentAuthor"] = latestCommentAuthor
            }

            items.append(BriefingItem(
                title: "[\(issue.key)] \(issue.fields.summary ?? "Kein Titel")",
                subtitle: "\(issueType) · \(statusName)",
                body: body,
                timestamp: parseJiraDate(issue.fields.updated),
                deepLink: buildJiraDeepLink(issueKey: issue.key),
                priority: priority,
                metadata: metadata
            ))
        }
        return items
    }

    // MARK: - Helpers

    private func buildJiraJQL(baseClause: String) -> String {
        "\(baseClause) AND status in (\"To Do\", \"In Progress\") AND updated >= -1d ORDER BY priority DESC"
    }

    private func buildJiraItemBody(issue: JiraIssueFields, latestComment: JiraIssueCommentInfo?) -> String? {
        var lines: [String] = []

        let descriptionText: String? = jiraPlainTextFromContent(issue.description?.content)
        if let descriptionText, !descriptionText.isEmpty {
            lines.append(descriptionText)
        }

        if let latestComment, let latestCommentText = latestComment.commentText, !latestCommentText.isEmpty {
            lines.append("💬 \(latestCommentText)")
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private func fetchLatestComment(
        issueKey: String,
        authorizationHeader: String,
        baseURL: String
    ) async -> JiraIssueCommentInfo {
        do {
            var components = URLComponents(string: "\(baseURL)/issue/\(issueKey)/comment")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "10"),
                URLQueryItem(name: "expand", value: "renderedBody")
            ]

            var request = URLRequest(url: components.url!)
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return JiraIssueCommentInfo(commentText: nil, authorName: nil, commentCount: nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return JiraIssueCommentInfo(commentText: nil, authorName: nil, commentCount: nil)
            }

            let commentsResponse = try JSONDecoder().decode(JiraCommentsResponse.self, from: data)
            let comments = commentsResponse.comments ?? []
            let latest = comments.max(by: {
                parseJiraDate($0.created) ?? .distantPast > parseJiraDate($1.created) ?? .distantPast
            })

            return JiraIssueCommentInfo(
                commentText: jiraCommentText(from: latest),
                authorName: latest?.author?.displayName,
                commentCount: commentsResponse.total ?? comments.count
            )
        } catch {
            return JiraIssueCommentInfo(commentText: nil, authorName: nil, commentCount: nil)
        }
    }

    private func jiraCommentText(from comment: JiraIssueComment?) -> String? {
        if let renderedBody = comment?.renderedBody?.trimmingCharacters(in: .whitespacesAndNewlines), !renderedBody.isEmpty {
            return stripHTML(renderedBody)
        }

        if let text = comment?.body?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        let content = jiraPlainText(from: comment?.body?.content)
        return content?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func jiraPlainText(from nodes: [JiraTextContent]?) -> String? {
        guard let nodes else { return nil }
        let text = nodes.compactMap { node in
            if let text = node.text, !text.isEmpty {
                return text
            }
            return jiraPlainText(from: node.content)
        }
        .joined(separator: " ")

        let normalized = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func jiraPlainTextFromContent(_ segments: [JiraContent]?) -> String? {
        guard let segments else { return nil }
        let texts = segments.compactMap { jiraPlainText(from: $0.content) }
        let joined = texts.joined(separator: " ")
        let normalized = joined.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { return nil }
        return URL(string: "\(site.trimmedTrailingSlash)/browse/\(issueKey)")
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

struct JiraIssueCommentInfo {
    let commentText: String?
    let authorName: String?
    let commentCount: Int?
}

struct JiraCommentsResponse: Decodable {
    let comments: [JiraIssueComment]?
    let total: Int?
}

struct JiraIssueComment: Decodable {
    let id: String
    let author: JiraUser?
    let body: JiraIssueCommentBody?
    let renderedBody: String?
    let created: String?
}

struct JiraIssueCommentBody: Decodable {
    let type: String?
    let text: String?
    let content: [JiraTextContent]?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case content
    }

    init(from decoder: Decoder) throws {
        let keyedContainer = try? decoder.container(keyedBy: CodingKeys.self)
        if let container = keyedContainer {
            type = try container.decodeIfPresent(String.self, forKey: .type)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            content = try container.decodeIfPresent([JiraTextContent].self, forKey: .content)
            return
        }

        let singleValueContainer = try decoder.singleValueContainer()
        text = try? singleValueContainer.decode(String.self)
        type = nil
        content = nil
    }
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
    let content: [JiraTextContent]?
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
    static var siteURL: String {
        UserDefaults.standard.string(forKey: "jira_site_url") ?? ""
    }

    static var email: String {
        UserDefaults.standard.string(forKey: "jira_email") ?? ""
    }
}

private extension JiraSource {
    static let jiraApiTokenKey = "jira_api_token"

    static func computeIsAuthenticated() -> Bool {
        let site = JiraConfig.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = JiraConfig.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty, !email.isEmpty else { return false }
        return KeychainService.shared.exists(for: jiraApiTokenKey)
    }

    func makeAuthorizationHeader() throws -> String {
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
        request.setValue(try makeAuthorizationHeader(), forHTTPHeaderField: "Authorization")
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

private extension String {
    var trimmedTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
