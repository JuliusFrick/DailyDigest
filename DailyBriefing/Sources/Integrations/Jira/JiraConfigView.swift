import SwiftUI

/// Configuration view for Jira integration
struct JiraConfigView: View {
    @ObservedObject var source: JiraSource

    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                cloudSelectionSection
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
