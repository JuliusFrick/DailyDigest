import SwiftUI

/// Configuration view for Slack integration
struct SlackConfigView: View {
    @ObservedObject var source: SlackSource
    @State private var channelSearchText = ""

    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                workspaceSection
                channelSelectionSection
                filterSection
            }
        }
        .formStyle(.grouped)
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
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("Alle abwählen") {
                        source.deselectAllChannels()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
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
