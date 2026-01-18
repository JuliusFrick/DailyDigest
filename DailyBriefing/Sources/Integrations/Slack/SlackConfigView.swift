import SwiftUI

/// Configuration view for Slack integration
struct SlackConfigView: View {
    @ObservedObject var source: SlackSource

    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                workspaceSection
                filterSection
            }
        }
        .formStyle(.grouped)
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
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Verbinden") {
                        Task {
                            try? await source.authenticate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(source.isLoading)
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
            Text("Verbinde deinen Slack-Workspace um Nachrichten und Mentions in deinem Briefing zu sehen.")
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
