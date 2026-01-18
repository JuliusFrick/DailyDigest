import SwiftUI

/// Slack integration for fetching messages and mentions
@MainActor
final class SlackSource: BriefingSource, ObservableObject {
    static let sourceId = "slack"
    static let displayName = "Slack"
    static let iconName = "bubble.left.and.bubble.right.fill"
    static let brandColor = Color(red: 0.32, green: 0.15, blue: 0.46)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties

    private lazy var oauthService: OAuthService = {
        let config = OAuthService.Configuration(
            clientId: SlackConfig.clientId,
            clientSecret: SlackConfig.clientSecret,
            authorizationURL: URL(string: "https://slack.com/oauth/v2/authorize")!,
            tokenURL: URL(string: "https://slack.com/api/oauth.v2.access")!,
            redirectURI: "dailybriefing://oauth/slack",
            scopes: [
                "channels:history",
                "channels:read",
                "groups:history",
                "groups:read",
                "im:history",
                "im:read",
                "mpim:history",
                "mpim:read",
                "users:read"
            ]
        )
        return OAuthService(configuration: config, sourceId: Self.sourceId)
    }()

    private let keychain = KeychainService.shared
    private let baseURL = "https://slack.com/api"

    // MARK: - Configuration

    @Published var selectedWorkspace: SlackWorkspace?
    @Published var availableWorkspaces: [SlackWorkspace] = []
    @Published var availableChannels: [SlackChannel] = []
    @Published var includeDMs: Bool = true
    @Published var includeChannels: Bool = true
    @Published var includeMentions: Bool = true

    /// IDs of channels that are selected for inclusion in the briefing
    @Published var selectedChannelIds: Set<String> {
        didSet {
            saveSelectedChannels()
        }
    }

    private static let selectedChannelsKey = "slack_selected_channel_ids"

    // MARK: - Initialization

    init() {
        // Load selected channels from UserDefaults before calling super
        if let savedIds = UserDefaults.standard.array(forKey: Self.selectedChannelsKey) as? [String] {
            selectedChannelIds = Set(savedIds)
        } else {
            selectedChannelIds = []
        }

        isAuthenticated = oauthService.isAuthenticated
        connectionStatus = isAuthenticated ? .connected : .disconnected
    }

    // MARK: - Channel Selection Persistence

    private func saveSelectedChannels() {
        UserDefaults.standard.set(Array(selectedChannelIds), forKey: Self.selectedChannelsKey)
    }

    /// Toggle whether a channel is selected
    func toggleChannel(_ channelId: String) {
        if selectedChannelIds.contains(channelId) {
            selectedChannelIds.remove(channelId)
        } else {
            selectedChannelIds.insert(channelId)
        }
    }

    /// Check if a channel is selected
    func isChannelSelected(_ channelId: String) -> Bool {
        selectedChannelIds.contains(channelId)
    }

    /// Select all available channels
    func selectAllChannels() {
        selectedChannelIds = Set(availableChannels.map(\.id))
    }

    /// Deselect all channels
    func deselectAllChannels() {
        selectedChannelIds = []
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

            // Fetch workspace info and channels
            try await fetchWorkspaceInfo()
            availableChannels = try await fetchChannels()
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
            print("Slack logout error: \(error)")
        }
        isAuthenticated = false
        connectionStatus = .disconnected
        selectedWorkspace = nil
        availableWorkspaces = []
        availableChannels = []
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Slack verbunden")
        }

        let tokens = try await oauthService.getValidTokens()
        var items: [BriefingItem] = []

        // Fetch conversations (channels and DMs)
        let conversations = try await fetchConversations(accessToken: tokens.accessToken)

        // Fetch recent messages from each conversation
        for conversation in conversations {
            let shouldFetch: Bool
            if conversation.isIm {
                // DMs: check includeDMs setting
                shouldFetch = includeDMs
            } else {
                // Channels: check includeChannels AND if channel is selected
                // If no channels are selected, include all channels (default behavior)
                let isChannelSelected = selectedChannelIds.isEmpty || selectedChannelIds.contains(conversation.id)
                shouldFetch = includeChannels && isChannelSelected
            }

            if shouldFetch {
                let messages = try await fetchMessages(
                    conversationId: conversation.id,
                    since: since,
                    accessToken: tokens.accessToken
                )
                items.append(contentsOf: messages)
            }
        }

        // Sort by timestamp (most recent first)
        items.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }

        return Array(items.prefix(30))
    }

    func configurationView() -> AnyView {
        AnyView(SlackConfigView(source: self))
    }

    // MARK: - API Calls

    private func fetchWorkspaceInfo() async throws {
        let tokens = try await oauthService.getValidTokens()

        var request = URLRequest(url: URL(string: "\(baseURL)/team.info")!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SourceError.networkError("Workspace-Info konnte nicht geladen werden")
        }

        let teamResponse = try JSONDecoder().decode(SlackTeamResponse.self, from: data)

        if teamResponse.ok, let team = teamResponse.team {
            selectedWorkspace = SlackWorkspace(
                id: team.id,
                name: team.name,
                domain: team.domain,
                icon: team.icon?.image68
            )
        }
    }

    /// Fetches available Slack channels (public and private)
    func fetchChannels() async throws -> [SlackChannel] {
        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Nicht mit Slack verbunden")
        }

        let tokens = try await oauthService.getValidTokens()

        var components = URLComponents(string: "\(baseURL)/conversations.list")!
        components.queryItems = [
            URLQueryItem(name: "types", value: "public_channel,private_channel"),
            URLQueryItem(name: "exclude_archived", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

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

        let channelsResponse = try JSONDecoder().decode(SlackChannelsResponse.self, from: data)

        guard channelsResponse.ok else {
            throw SourceError.networkError(channelsResponse.error ?? "Unbekannter Fehler")
        }

        return (channelsResponse.channels ?? []).map { channel in
            SlackChannel(
                id: channel.id,
                name: channel.name ?? "Unbekannt",
                isPrivate: channel.isPrivate ?? false,
                memberCount: channel.numMembers ?? 0
            )
        }
    }

    private func fetchConversations(accessToken: String) async throws -> [SlackConversation] {
        var components = URLComponents(string: "\(baseURL)/conversations.list")!
        components.queryItems = [
            URLQueryItem(name: "types", value: "public_channel,private_channel,im,mpim"),
            URLQueryItem(name: "exclude_archived", value: "true"),
            URLQueryItem(name: "limit", value: "100")
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

        let conversationsResponse = try JSONDecoder().decode(SlackConversationsResponse.self, from: data)

        guard conversationsResponse.ok else {
            throw SourceError.networkError(conversationsResponse.error ?? "Unbekannter Fehler")
        }

        return conversationsResponse.channels ?? []
    }

    private func fetchMessages(conversationId: String, since: Date, accessToken: String) async throws -> [BriefingItem] {
        var components = URLComponents(string: "\(baseURL)/conversations.history")!
        components.queryItems = [
            URLQueryItem(name: "channel", value: conversationId),
            URLQueryItem(name: "oldest", value: String(since.timeIntervalSince1970)),
            URLQueryItem(name: "limit", value: "20")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }

        let historyResponse = try JSONDecoder().decode(SlackHistoryResponse.self, from: data)

        guard historyResponse.ok else {
            return []
        }

        return (historyResponse.messages ?? []).compactMap { message in
            guard let text = message.text, !text.isEmpty else { return nil }

            let timestamp = message.ts.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }

            return BriefingItem(
                title: formatMessagePreview(text),
                subtitle: "Slack",
                body: text,
                timestamp: timestamp,
                deepLink: buildSlackDeepLink(conversationId: conversationId, messageTs: message.ts),
                priority: determinePriority(text: text),
                metadata: [
                    "conversationId": conversationId,
                    "userId": message.user ?? "",
                    "ts": message.ts ?? ""
                ]
            )
        }
    }

    // MARK: - Helpers

    private func formatMessagePreview(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 80 {
            return String(cleaned.prefix(80)) + "..."
        }
        return cleaned
    }

    private func determinePriority(text: String) -> BriefingSection.Priority {
        let lowercased = text.lowercased()

        if lowercased.contains("@here") || lowercased.contains("@channel") {
            return .high
        }

        if lowercased.contains("urgent") || lowercased.contains("dringend") || lowercased.contains("asap") {
            return .urgent
        }

        return .medium
    }

    private func buildSlackDeepLink(conversationId: String, messageTs: String?) -> URL? {
        guard let workspace = selectedWorkspace else { return nil }

        if let ts = messageTs {
            let tsFormatted = ts.replacingOccurrences(of: ".", with: "")
            return URL(string: "slack://channel?team=\(workspace.id)&id=\(conversationId)&message=\(tsFormatted)")
        }

        return URL(string: "slack://channel?team=\(workspace.id)&id=\(conversationId)")
    }
}

// MARK: - API Response Models

struct SlackTeamResponse: Codable {
    let ok: Bool
    let team: SlackTeam?
    let error: String?
}

struct SlackTeam: Codable {
    let id: String
    let name: String
    let domain: String
    let icon: SlackIcon?
}

struct SlackIcon: Codable {
    let image34: String?
    let image44: String?
    let image68: String?

    enum CodingKeys: String, CodingKey {
        case image34 = "image_34"
        case image44 = "image_44"
        case image68 = "image_68"
    }
}

struct SlackConversationsResponse: Codable {
    let ok: Bool
    let channels: [SlackConversation]?
    let error: String?
}

struct SlackConversation: Codable, Identifiable {
    let id: String
    let name: String?
    let isIm: Bool
    let isPrivate: Bool?
    let isMpim: Bool?
    let numMembers: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case isIm = "is_im"
        case isPrivate = "is_private"
        case isMpim = "is_mpim"
        case numMembers = "num_members"
    }
}

struct SlackHistoryResponse: Codable {
    let ok: Bool
    let messages: [SlackMessage]?
    let error: String?
}

struct SlackMessage: Codable {
    let type: String?
    let user: String?
    let text: String?
    let ts: String?
    let threadTs: String?

    enum CodingKeys: String, CodingKey {
        case type, user, text, ts
        case threadTs = "thread_ts"
    }
}

struct SlackWorkspace: Identifiable, Equatable {
    let id: String
    let name: String
    let domain: String
    let icon: String?
}

/// Model representing a Slack channel
struct SlackChannel: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let isPrivate: Bool
    let memberCount: Int
}

/// API response for channels list
struct SlackChannelsResponse: Codable {
    let ok: Bool
    let channels: [SlackConversation]?
    let error: String?
}

// MARK: - Configuration

enum SlackConfig {
    static var clientId: String {
        UserDefaults.standard.string(forKey: "slack_client_id") ?? ""
    }

    static var clientSecret: String? {
        UserDefaults.standard.string(forKey: "slack_client_secret")
    }
}
