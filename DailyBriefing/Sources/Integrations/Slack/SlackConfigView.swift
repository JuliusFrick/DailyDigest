import SwiftUI

/// Configuration view for Slack integration
struct SlackConfigView: View {
    @ObservedObject var source: SlackSource
    @AppStorage("slack_auth_method") private var slackAuthMethodRaw: String = ""
    @State private var channelSearchText = ""
    @State private var slackUserToken: String = ""
    @State private var didLoadUserToken = false

    private var authMethod: SlackAuthMethod {
        if let method = SlackAuthMethod(rawValue: slackAuthMethodRaw), !slackAuthMethodRaw.isEmpty {
            return method
        }
        return SlackConfig.authMethod
    }

    private var canConnect: Bool {
        switch authMethod {
        case .userToken:
            return !slackUserToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .oauth:
            return !SlackConfig.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Form {
            authMethodSection
            if authMethod == .userToken {
                userTokenSection
            } else {
                oauthCredentialsSection
            }
            connectionSection
            if source.isAuthenticated {
                workspaceSection
                channelSelectionSection
                contentTypesSection
                filterSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !didLoadUserToken else { return }
            slackUserToken = (try? KeychainService.shared.loadString(for: "slack_user_token")) ?? ""
            didLoadUserToken = true
        }
        .onChange(of: slackUserToken) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if trimmed.isEmpty {
                    try? KeychainService.shared.delete(for: "slack_user_token")
                } else {
                    try KeychainService.shared.save(trimmed, for: "slack_user_token")
                }
            } catch {
                // Ignore UI persistence errors
            }
        }
    }

    /// Channels filtered by search text
    private var filteredChannels: [SlackChannel] {
        if channelSearchText.isEmpty {
            return source.availableChannels
        }
        return source.availableChannels.filter {
            $0.name.localizedCaseInsensitiveContains(channelSearchText)
        }
    }

    /// Number of selected channels
    private var selectedChannelCount: Int {
        source.selectedChannelIds.count
    }

    private var authMethodBinding: Binding<String> {
        Binding(
            get: { authMethod.rawValue },
            set: { slackAuthMethodRaw = $0 }
        )
    }

    // MARK: - Auth Method Section

    private var authMethodSection: some View {
        Section {
            Picker("Anmelde-Methode", selection: authMethodBinding) {
                Text("User Token (Empfohlen)").tag(SlackAuthMethod.userToken.rawValue)
                Text("OAuth").tag(SlackAuthMethod.oauth.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Login-Methode")
        } footer: {
            Text("User Token ist am einfachsten und erlaubt dir später auch Antworten auf Nachrichten.")
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slack Workspace")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(source.connectionStatus.color)
                            .frame(width: 8, height: 8)
                        Text(source.connectionStatus.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if source.isAuthenticated {
                    Button("Trennen") {
                        Task {
                            await source.disconnect()
                        }
                    }
                    .buttonStyle(.tui)
                    .tint(.red)
                } else {
                    Button("Verbinden") {
                        Task {
                            try? await source.authenticate()
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                    .disabled(source.isLoading || !canConnect)
                }
            }

            if let error = source.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Verbindung")
        } footer: {
            if authMethod == .userToken {
                Text("Verbinde deinen Slack-Workspace per User Token für Nachrichten, Mentions und Antworten.")
            } else {
                Text("Verbinde deinen Slack-Workspace per OAuth um Nachrichten und Mentions zu sehen.")
            }
        }
    }

    // MARK: - User Token Section

    private var userTokenSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Slack User Token")
                    .font(.caption)
                SecureField("xoxp-... oder xoxc-...", text: $slackUserToken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Empfohlene Scopes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("channels:history, channels:read, groups:history, groups:read, im:history, im:read, mpim:history, mpim:read, users:read, chat:write")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Link("Token-Typen & Scopes ansehen", destination: URL(string: "https://api.slack.com/authentication/token-types")!)
        } header: {
            Text("User Token")
        } footer: {
            Text("Nutze einen User Token für direkten Zugriff auf deine Nachrichten. Mit `chat:write` kannst du auch Antworten senden.")
        }
    }

    // MARK: - OAuth Credentials Section

    private var oauthCredentialsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anmeldung erfolgt im Browser bei Slack.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if SlackConfig.hasBundledConfig {
                    Text("OAuth ist in der App vorkonfiguriert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("OAuth-Konfiguration fehlt in der App. Bitte eine gültige Slack Client ID hinterlegen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Redirect URL (in Slack App hinterlegen):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("dailybriefing://oauth/slack")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Link("Slack Apps öffnen", destination: URL(string: "https://api.slack.com/apps")!)
        } header: {
            Text("OAuth (Optional)")
        } footer: {
            Text("Für OAuth wird eine gültige Slack Client ID benötigt.")
        }
    }

    // MARK: - Workspace Section

    private var workspaceSection: some View {
        Section {
            if let workspace = source.selectedWorkspace {
                HStack(spacing: 12) {
                    if let iconURL = workspace.icon, let url = URL(string: iconURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "building.2.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.headline)
                        Text("\(workspace.domain).slack.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Workspace")
        }
    }

    // MARK: - Channel Selection Section

    private var channelSelectionSection: some View {
        Section {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Channels suchen...", text: $channelSearchText)
                    .textFieldStyle(.plain)
                if !channelSearchText.isEmpty {
                    Button {
                        channelSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Select/Deselect all buttons
            if !source.availableChannels.isEmpty {
                HStack {
                    Button("Alle auswählen") {
                        source.selectAllChannels()
                    }
                    .font(.caption)
                    .buttonStyle(.tuiGhost)

                    Spacer()

                    Button("Alle abwählen") {
                        source.deselectAllChannels()
                    }
                    .font(.caption)
                    .buttonStyle(.tuiGhost)
                }
            }

            // Channel list
            if source.availableChannels.isEmpty {
                HStack {
                    Spacer()
                    if source.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Channels werden geladen...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Keine Channels verfügbar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                ForEach(filteredChannels) { channel in
                    ChannelToggleRow(
                        channel: channel,
                        isSelected: source.isChannelSelected(channel.id),
                        onToggle: { source.toggleChannel(channel.id) }
                    )
                }
            }
        } header: {
            HStack {
                Text("Channels")
                Spacer()
                Text("\(selectedChannelCount) ausgewählt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if selectedChannelCount == 0 && !source.availableChannels.isEmpty {
                Text("Wenn keine Channels ausgewählt sind, werden alle Channels einbezogen.")
            } else {
                Text("Wähle die Channels aus, die in deinem Briefing erscheinen sollen.")
            }
        }
    }

    // MARK: - Content Types Section

    private var contentTypesSection: some View {
        Section {
            Toggle("Ungelesene DMs einbeziehen", isOn: $source.includeUnreadDMs)
            Toggle("Mentions (@user) einbeziehen", isOn: $source.includeUserMentions)
            Toggle("Starred Messages einbeziehen", isOn: $source.includeStarredMessages)
            Toggle("Reactions auf eigene Nachrichten", isOn: $source.includeReactionsOnOwnMessages)
            Toggle("Slack Reminders einbeziehen", isOn: $source.includeSlackReminders)
        } header: {
            Text("Inhaltstypen")
        } footer: {
            Text("Wähle aus, welche Arten von Slack-Inhalten in deinem Briefing erfasst werden sollen.")
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Toggle("Channels einbeziehen", isOn: $source.includeChannels)
            Toggle("Direktnachrichten einbeziehen", isOn: $source.includeDMs)
            Toggle("Nur Mentions anzeigen", isOn: $source.includeMentions)
        } header: {
            Text("Filter")
        } footer: {
            Text("Konfiguriere, welche Nachrichten in deinem Briefing erscheinen sollen.")
        }
    }
}

// MARK: - Channel Toggle Row

private struct ChannelToggleRow: View {
    let channel: SlackChannel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.isPrivate ? "lock.fill" : "number")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                if channel.memberCount > 0 {
                    Text("\(channel.memberCount) Mitglieder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}
