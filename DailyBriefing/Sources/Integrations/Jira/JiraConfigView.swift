import SwiftUI

/// Configuration view for Jira integration
struct JiraConfigView: View {
    @ObservedObject var source: JiraSource
    @AppStorage("jira_client_id") private var jiraClientId: String = ""
    @AppStorage("jira_client_secret") private var jiraClientSecret: String = ""
    @AppStorage("jira_auth_method") private var jiraAuthMethodRaw: String = JiraAuthMethod.apiToken.rawValue // Changed default to apiToken
    @AppStorage("jira_site_url") private var jiraSiteURL: String = ""
    @AppStorage("jira_email") private var jiraEmail: String = ""
    
    @State private var jiraApiToken: String = ""
    @State private var didLoadApiToken = false
    
    // Help link for API token
    private let apiTokenHelpURL = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
    
    private var canConnect: Bool {
        switch authMethod {
        case .oauth3LO:
            return !jiraClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .apiToken:
            return !jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var authMethod: JiraAuthMethod {
        JiraAuthMethod(rawValue: jiraAuthMethodRaw) ?? .apiToken
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
                // Ignore UI persistence errors
            }
        }
    }

    // MARK: - Auth Method Section

    private var authMethodSection: some View {
        Section {
            Picker("Anmelde-Methode", selection: $jiraAuthMethodRaw) {
                Text("API Token (Empfohlen)").tag(JiraAuthMethod.apiToken.rawValue)
                Text("OAuth (Komplex)").tag(JiraAuthMethod.oauth3LO.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Login-Methode")
        } footer: {
            if authMethod == .apiToken {
                Text("API Token ist die einfachste Methode für persönliche Nutzung.")
            }
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

                Text("Redirect URI muss sein: `dailybriefing://oauth/jira`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

            case .apiToken:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dein Jira Link")
                        .font(.caption)
                    TextField("https://deine-firma.atlassian.net", text: $jiraSiteURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("E-Mail Adresse")
                        .font(.caption)
                    TextField("name@firma.com", text: $jiraEmail)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("API Token")
                            .font(.caption)
                        Spacer()
                        Button("Token erstellen") {
                            NSWorkspace.shared.open(apiTokenHelpURL)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    SecureField("Einfügen...", text: $jiraApiToken)
                        .textFieldStyle(.roundedBorder)
                }
            }
        } header: {
            Text("Zugangsdaten")
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.isAuthenticated ? "Verbunden" : "Nicht verbunden")
                        .font(.headline)
                    
                    if source.isAuthenticated {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Jira ist bereit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        }
    }

    // MARK: - Cloud Selection Section

    private var cloudSelectionSection: some View {
        Section {
            if source.availableClouds.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Lade Instanzen...")
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
            Text("Instanz")
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Toggle("Mir zugewiesen", isOn: $source.includeAssignedToMe)
            Toggle("Ich beobachte", isOn: $source.includeWatching)
            Toggle("Erwähnungen", isOn: $source.includeMentions)
        } header: {
            Text("Filter")
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
