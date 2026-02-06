import SwiftUI

/// Configuration view for Apple Mail integration
struct AppleMailConfigView: View {
    @ObservedObject var source: AppleMailSource
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                filterSection
            }
            permissionsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Mail")
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
                            await connectionManager.disconnect(.appleMail)
                        }
                    }
                    .buttonStyle(.tui)
                    .tint(.red)
                } else {
                    Button("Verbinden") {
                        Task {
                            try? await connectionManager.connect(.appleMail)
                        }
                    }
                    .buttonStyle(.tuiPrimary)
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
            Text("Greife auf deine Apple Mail E-Mails zu, um sie in deinem Briefing anzuzeigen.")
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Toggle("Nur ungelesene E-Mails", isOn: $source.fetchUnreadOnly)

            Stepper(
                "Maximale Anzahl: \(source.maxEmailsToFetch)",
                value: $source.maxEmailsToFetch,
                in: 5...50,
                step: 5
            )
        } header: {
            Text("Filter")
        } footer: {
            Text("Konfiguriere, welche E-Mails in deinem Briefing erscheinen sollen.")
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        Section {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Datenschutz")
                        .font(.subheadline)
                    Text("Diese App benötigt Automation-Zugriff auf Apple Mail. Du kannst dies in den Systemeinstellungen ändern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            .buttonStyle(.tui)
        } header: {
            Text("Berechtigungen")
        }
    }
}
