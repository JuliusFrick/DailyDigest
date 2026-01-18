import SwiftUI

/// Configuration view for Jira integration
struct JiraConfigView: View {
    @ObservedObject var source: JiraSource
    @AppStorage("jira_client_id") private var jiraClientId: String = ""
    @AppStorage("jira_client_secret") private var jiraClientSecret: String = ""
    @AppStorage("jira_auth_method") private var jiraAuthMethodRaw: String = JiraAuthMethod.oauth3LO.rawValue
    @AppStorage("jira_site_url") private var jiraSiteURL: String = ""
    @AppStorage("jira_email") private var jiraEmail: String = ""

    @State private var jiraApiToken: String = ""
    @State private var didLoadApiToken = false
    
    private var canConnect: Bool {
        switch JiraAuthMethod(rawValue: jiraAuthMethodRaw) ?? .oauth3LO {
        case .oauth3LO:
            return !jiraClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .apiToken:
            return !jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var authMethod: JiraAuthMethod {
        JiraAuthMethod(rawValue: jiraAuthMethodRaw) ?? .oauth3LO
    }

    var body: some View {
        Form {
            authMethodSection
            credentialsSection
            connectionSection
            if source.isAuthenticated {
                if authMethod == .oauth3LO {
                    cloudSelectionSection
                }
                filterSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !didLoadApiToken else { return }
            jiraApiToken = (try? KeychainService.shared.loadString(for: "jira_api_token")) ?? ""
            didLoadApiToken = true
        }
        .onChange(of: jiraApiToken) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if trimmed.isEmpty {
                    try? KeychainService.shared.delete(for: "jira_api_token")
                } else {
                    try KeychainService.shared.save(trimmed, for: "jira_api_token")
                }
            } catch {
                // Ignore UI persistence errors; connection attempt will surface problems.
            }
        }
    }

    // MARK: - Auth Method Section

    private var authMethodSection: some View {
        Section {
            Picker("Anmeldung", selection: $jiraAuthMethodRaw) {
                Text(JiraAuthMethod.oauth3LO.displayName).tag(JiraAuthMethod.oauth3LO.rawValue)
                Text(JiraAuthMethod.apiToken.displayName).tag(JiraAuthMethod.apiToken.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Login")
        } footer: {
            Text("Für „API Token“ braucht jeder nur seine Jira Site URL, E-Mail und einen persönlichen Atlassian API Token (wie MCP-Config).")
        }
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        Section {
            switch authMethod {
            case .oauth3LO:
                TextField("Client ID", text: $jiraClientId)
                    .textFieldStyle(.roundedBorder)

                SecureField("Client Secret", text: $jiraClientSecret)
                    .textFieldStyle(.roundedBorder)

                if jiraClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Ohne Client ID kann Atlassian die App nicht identifizieren (Login schlägt dann sofort fehl).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case .apiToken:
                TextField("Jira Site URL (z.B. https://firma.atlassian.net)", text: $jiraSiteURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Atlassian E‑Mail", text: $jiraEmail)
                    .textFieldStyle(.roundedBorder)

                SecureField("Atlassian API Token", text: $jiraApiToken)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            Text(authMethod == .oauth3LO ? "Atlassian OAuth" : "API Token")
        } footer: {
            if authMethod == .oauth3LO {
                Text("Trage hier die OAuth Client ID und das Client Secret deiner Atlassian (3LO) App ein. Redirect URI muss exakt `dailybriefing://oauth/jira` sein.")
            } else {
                Text("Den API Token kannst du in deinem Atlassian Account erstellen. Er wird lokal im Keychain gespeichert.")
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Atlassian Konto")
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
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Verbinden") {
                        Task {
                            try? await source.authenticate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
            Text("Verbinde dein Atlassian-Konto um Jira-Issues in deinem Briefing zu sehen.")
        }
    }

    // MARK: - Cloud Selection Section

    private var cloudSelectionSection: some View {
        Section {
            if source.availableClouds.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Jira-Instanzen werden geladen...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    Task {
                        try? await source.fetchAccessibleResources()
                    }
                }
            } else if source.availableClouds.count == 1 {
                if let cloud = source.selectedCloud {
                    CloudRow(cloud: cloud)
                }
            } else {
                Picker("Jira-Instanz", selection: $source.selectedCloud) {
                    ForEach(source.availableClouds) { cloud in
                        Text(cloud.name).tag(Optional(cloud))
                    }
                }
            }
        } header: {
            Text("Jira Cloud")
        } footer: {
            if source.availableClouds.count > 1 {
                Text("Wähle die Jira-Instanz aus, von der du Issues abrufen möchtest.")
            }
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Toggle("Mir zugewiesene Issues", isOn: $source.includeAssignedToMe)
            Toggle("Beobachtete Issues", isOn: $source.includeWatching)
            Toggle("Issues mit Erwähnungen", isOn: $source.includeMentions)
        } header: {
            Text("Filter")
        } footer: {
            Text("Konfiguriere, welche Issues in deinem Briefing erscheinen sollen.")
        }
    }
}

// MARK: - Cloud Row

struct CloudRow: View {
    let cloud: JiraCloud

    var body: some View {
        HStack(spacing: 12) {
            if let avatarUrl = cloud.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cloud.name)
                    .font(.body)
                Text(cloud.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
