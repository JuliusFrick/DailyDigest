import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared
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
            AddSourceSheet(connectionManager: connectionManager)
        }
    }

    // MARK: - Connected Sources

    private var connectedSourcesSection: some View {
        Section {
            if connectionManager.connectedSources.isEmpty {
                ContentUnavailableView {
                    Label("Keine Quellen verbunden", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("Verbinde Quellen um dein Briefing zu erstellen.")
                }
            } else {
                ForEach(connectionManager.connectedSources, id: \.id) { source in
                    ConnectedSourceRow(source: source, connectionManager: connectionManager)
                }
            }
        } header: {
            Text("Verbundene Quellen")
        }
    }

    // MARK: - Available Sources

    private var availableSourcesSection: some View {
        Section {
            ForEach(ServiceType.allCases.filter { !connectionManager.isConnected($0) }) { serviceType in
                AvailableSourceRowNew(
                    serviceType: serviceType,
                    connectionManager: connectionManager
                )
            }
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
    @ObservedObject var connectionManager: ServiceConnectionManager
    @State private var showingConfig = false

    private var serviceType: ServiceType? {
        ServiceType(rawValue: type(of: source).sourceId)
    }

    var body: some View {
        Button {
            showingConfig = true
        } label: {
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
                        .foregroundStyle(.primary)

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
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .sheet(isPresented: $showingConfig) {
            if let serviceType = serviceType {
                NavigationStack {
                    ServiceDetailView(serviceType: serviceType)
                        .navigationTitle(serviceType.displayName)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") {
                                    showingConfig = false
                                }
                            }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("Trennen", role: .destructive) {
                                    Task {
                                        await connectionManager.disconnect(serviceType)
                                        showingConfig = false
                                    }
                                }
                            }
                        }
                }
                .frame(minWidth: 450, minHeight: 400)
            }
        }
    }
}

// MARK: - Available Source Row

struct AvailableSourceRowNew: View {
    let serviceType: ServiceType
    @ObservedObject var connectionManager: ServiceConnectionManager
    @State private var isConnecting = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serviceType.iconName)
                .font(.title2)
                .foregroundStyle(serviceType.brandColor)
                .frame(width: 40, height: 40)
                .background(serviceType.brandColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(serviceType.displayName)
                    .font(.headline)
                Text(serviceType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                connect()
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

    private func connect() {
        isConnecting = true
        Task {
            do {
                try await connectionManager.connect(serviceType)
            } catch {
                print("Connection error: \(error)")
            }
            isConnecting = false
        }
    }
}

// MARK: - Add Source Sheet

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var connectionManager: ServiceConnectionManager

    var body: some View {
        NavigationStack {
            List {
                Section("Cloud-Dienste") {
                    ForEach([ServiceType.googleCalendar, .gmail, .slack, .jira]) { serviceType in
                        if !connectionManager.isConnected(serviceType) {
                            AvailableSourceRowNew(
                                serviceType: serviceType,
                                connectionManager: connectionManager
                            )
                        }
                    }
                }

                Section("Apple-Dienste") {
                    ForEach([ServiceType.appleMail, .appleReminders]) { serviceType in
                        if !connectionManager.isConnected(serviceType) {
                            AvailableSourceRowNew(
                                serviceType: serviceType,
                                connectionManager: connectionManager
                            )
                        }
                    }
                }

                Section("Bald verfügbar") {
                    ComingSoonRow(name: "WhatsApp", icon: "message.fill", color: .green)
                    ComingSoonRow(name: "iMessage", icon: "bubble.left.fill", color: .blue)
                    ComingSoonRow(name: "Notion", icon: "doc.text", color: .primary)
                    ComingSoonRow(name: "Linear", icon: "line.3.horizontal", color: .purple)
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
