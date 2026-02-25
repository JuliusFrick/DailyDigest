import SwiftUI

/// Configuration view for Jira integration
struct JiraConfigView: View {
    @ObservedObject var source: JiraSource
    @AppStorage("jira_site_url") private var jiraSiteURL: String = ""
    @AppStorage("jira_email") private var jiraEmail: String = ""
    
    @State private var jiraApiToken: String = ""
    @State private var didLoadApiToken = false
    
    // Help link for API token
    private let apiTokenHelpURL = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
    
    private var canConnect: Bool {
        !jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !jiraApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            credentialsSection
            connectionSection
            if source.isAuthenticated {
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

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        Section {
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
        } header: {
            Text("Zugangsdaten")
        } footer: {
            Text("Jira nutzt hier ausschließlich API-Token (kein OAuth).")
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
