import SwiftUI

/// Configuration view for Gmail integration
struct GmailConfigView: View {
    @ObservedObject var source: GmailSource
    
    private var isConfigured: Bool {
        if !Secrets.googleClientId.isEmpty { return true }
        let clientId = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        return !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            GoogleOAuthCredentialsSection()
            connectionSection
            if source.isAuthenticated {
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
                    Text("Google Konto")
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
                    .buttonStyle(.tui)
                    .tint(.red)
                } else {
                    Button("Verbinden") {
                        Task {
                            try? await source.authenticate()
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                    .disabled(source.isLoading || !isConfigured)
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
            if !isConfigured {
                Text("Bitte richte zuerst die Google-Konfiguration ein (siehe oben).")
                    .foregroundStyle(.orange)
            } else {
                Text("Verbinde dein Gmail-Konto um ungelesene E-Mails in deinem Briefing zu sehen.")
            }
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
}
