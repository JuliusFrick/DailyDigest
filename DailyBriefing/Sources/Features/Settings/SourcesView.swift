import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var sourceRegistry = SourceRegistry.shared
    @State private var showingAddSource = false

    var body: some View {
        List {
            connectedSourcesSection
            availableSourcesSection
        }
        .listStyle(.inset)
        .navigationTitle("Quellen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSource = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceSheet()
        }
    }

    // MARK: - Connected Sources

    private var connectedSourcesSection: some View {
        Section {
            if sourceRegistry.activeSources.isEmpty {
                ContentUnavailableView {
                    Label("Keine Quellen verbunden", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("Verbinde Quellen um dein Briefing zu erstellen.")
                }
            } else {
                ForEach(sourceRegistry.activeSources, id: \.id) { source in
                    ConnectedSourceRow(source: source)
                }
                .onMove { from, to in
                    // TODO: Implement reordering
                }
            }
        } header: {
            Text("Verbundene Quellen")
        }
    }

    // MARK: - Available Sources

    private var availableSourcesSection: some View {
        Section {
            // Work Sources
            AvailableSourceRow(
                name: "Google Calendar",
                icon: "calendar",
                color: .blue,
                description: "Termine und Meetings"
            )

            AvailableSourceRow(
                name: "Jira",
                icon: "checkmark.square",
                color: .blue,
                description: "Issues und Kommentare"
            )

            AvailableSourceRow(
                name: "Slack",
                icon: "bubble.left.and.bubble.right",
                color: .purple,
                description: "Nachrichten und Mentions"
            )

            AvailableSourceRow(
                name: "Email",
                icon: "envelope",
                color: .red,
                description: "Gmail & Apple Mail"
            )
        } header: {
            Text("Verfügbare Quellen")
        } footer: {
            Text("Weitere Quellen werden in zukünftigen Updates hinzugefügt.")
        }
    }
}

// MARK: - Connected Source Row

struct ConnectedSourceRow: View {
    let source: any BriefingSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type(of: source).iconName)
                .font(.title2)
                .foregroundStyle(type(of: source).brandColor)
                .frame(width: 40, height: 40)
                .background(type(of: source).brandColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(type(of: source).displayName)
                    .font(.headline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(source.isAuthenticated ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(source.isAuthenticated ? "Verbunden" : "Nicht verbunden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Available Source Row

struct AvailableSourceRow: View {
    let name: String
    let icon: String
    let color: Color
    let description: String

    @State private var isConnecting = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isConnecting = true
                // TODO: Implement connection flow
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isConnecting = false
                }
            } label: {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("Verbinden")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isConnecting)
        }
    }
}

// MARK: - Add Source Sheet

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Work") {
                    AvailableSourceRow(
                        name: "Google Calendar",
                        icon: "calendar",
                        color: .blue,
                        description: "Termine und Meetings"
                    )
                    AvailableSourceRow(
                        name: "Jira",
                        icon: "checkmark.square",
                        color: .blue,
                        description: "Issues und Kommentare"
                    )
                    AvailableSourceRow(
                        name: "Slack",
                        icon: "bubble.left.and.bubble.right",
                        color: .purple,
                        description: "Nachrichten und Mentions"
                    )
                    AvailableSourceRow(
                        name: "Email",
                        icon: "envelope",
                        color: .red,
                        description: "Gmail & Apple Mail"
                    )
                }

                Section("Bald verfügbar") {
                    ComingSoonRow(name: "WhatsApp", icon: "message.fill", color: .green)
                    ComingSoonRow(name: "iMessage", icon: "bubble.left.fill", color: .blue)
                    ComingSoonRow(name: "Apple Reminders", icon: "checklist", color: .orange)
                }
            }
            .navigationTitle("Quelle hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

struct ComingSoonRow: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color.opacity(0.5))
                .frame(width: 40, height: 40)
                .background(color.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(name)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Bald")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }
}

#Preview {
    SourcesView()
        .environmentObject(AppState())
}
