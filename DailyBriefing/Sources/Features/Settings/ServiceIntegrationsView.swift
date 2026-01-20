import SwiftUI

/// Main view for managing all service integrations
struct ServiceIntegrationsView: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var selectedService: ServiceType?
    @State private var showingServiceDetail = false

    var body: some View {
        List {
            oauthServicesSection
            appleServicesSection
            syncSection
        }
        .listStyle(.inset)
        .navigationTitle("Integrationen")
        .sheet(item: $selectedService) { serviceType in
            NavigationStack {
                ServiceDetailView(serviceType: serviceType)
                    .navigationTitle(serviceType.displayName)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") {
                                selectedService = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 450, minHeight: 400)
        }
    }

    // MARK: - OAuth Services Section

    private var oauthServicesSection: some View {
        Section {
            ServiceRow(
                serviceType: .googleCalendar,
                connectionManager: connectionManager
            ) {
                openService(.googleCalendar)
            }

            ServiceRow(
                serviceType: .gmail,
                connectionManager: connectionManager
            ) {
                openService(.gmail)
            }

            ServiceRow(
                serviceType: .slack,
                connectionManager: connectionManager
            ) {
                openService(.slack)
            }

            ServiceRow(
                serviceType: .jira,
                connectionManager: connectionManager
            ) {
                openService(.jira)
            }
        } header: {
            Text("Cloud-Dienste")
        } footer: {
            Text("Diese Dienste benötigen OAuth-Anmeldung. Deine Zugangsdaten werden sicher in der macOS Keychain gespeichert.")
        }
    }

    // MARK: - Apple Services Section

    private var appleServicesSection: some View {
        Section {
            ServiceRow(
                serviceType: .appleMail,
                connectionManager: connectionManager
            ) {
                openService(.appleMail)
            }

            ServiceRow(
                serviceType: .appleReminders,
                connectionManager: connectionManager
            ) {
                openService(.appleReminders)
            }
            
            ServiceRow(
                serviceType: .appleCalendar,
                connectionManager: connectionManager
            ) {
                openService(.appleCalendar)
            }
        } header: {
            Text("Apple-Dienste")
        } footer: {
            Text("Diese Dienste nutzen native macOS APIs und benötigen keine Anmeldung, nur Systemberechtigungen.")
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            Toggle("iCloud-Sync für Verbindungen", isOn: Binding(
                get: { connectionManager.iCloudSyncEnabled },
                set: { connectionManager.iCloudSyncEnabled = $0 }
            ))
        } header: {
            Text("Synchronisation")
        } footer: {
            Text("Wenn aktiviert, werden deine Verbindungseinstellungen (nicht Zugangsdaten) mit iCloud synchronisiert.")
        }
    }

    private func openService(_ serviceType: ServiceType) {
        connectionManager.ensureSource(serviceType)
        selectedService = serviceType
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let serviceType: ServiceType
    @ObservedObject var connectionManager: ServiceConnectionManager
    let onTap: () -> Void

    @State private var isConnecting = false

    private var status: ConnectionStatus {
        connectionManager.connectionStatus(for: serviceType)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: serviceType.iconName)
                .font(.title2)
                .foregroundStyle(serviceType.brandColor)
                .frame(width: 40, height: 40)
                .background(serviceType.brandColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceType.displayName)
                    .font(.headline)

                Text(serviceType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status Indicator
            ConnectionStatusIndicator(status: status)

            // Action Button
            if status == .connected {
                Button {
                    onTap()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if serviceType.requiresOAuth {
                        onTap()
                    } else {
                        connect()
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Verbinden")
                    }
                }
                .buttonStyle(.tui)
                .disabled(isConnecting)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
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

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            if status == .connecting {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .help(status.displayName)
    }
}

// MARK: - Service Detail View

struct ServiceDetailView: View {
    let serviceType: ServiceType
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    var body: some View {
        Group {
            switch serviceType {
            case .googleCalendar:
                if let source = connectionManager.googleCalendarSource {
                    GoogleCalendarConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .gmail:
                if let source = connectionManager.gmailSource {
                    GmailConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .slack:
                if let source = connectionManager.slackSource {
                    SlackConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .jira:
                if let source = connectionManager.jiraSource {
                    JiraConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .appleMail:
                if let source = connectionManager.appleMailSource {
                    AppleMailConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .appleReminders:
                if let source = connectionManager.appleRemindersSource {
                    AppleRemindersConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }

            case .appleCalendar:
                if let source = connectionManager.appleCalendarSource {
                    AppleCalendarConfigView(source: source)
                } else {
                    ServiceNotConnectedView(serviceType: serviceType)
                }
            }
        }
    }
}

// MARK: - Service Not Connected View

struct ServiceNotConnectedView: View {
    let serviceType: ServiceType
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: serviceType.iconName)
                .font(.system(size: 48))
                .foregroundStyle(serviceType.brandColor)

            Text(serviceType.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text(serviceType.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isConnecting = true
                Task {
                    try? await connectionManager.connect(serviceType)
                    isConnecting = false
                }
            } label: {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Verbinden")
                }
            }
            .buttonStyle(.tuiPrimary)
            .disabled(isConnecting)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
