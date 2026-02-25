import SwiftUI

/// Configuration view for Granola integration (API Key)
struct GranolaConfigView: View {
    @ObservedObject var source: GranolaSource
    @State private var apiKey: String = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let apiKeyHelpURL = URL(string: "https://docs.granola.ai/help-center/sharing/integrations/enterprise-api")!

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API-Key (Enterprise Plan)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("Granola API-Key eingeben", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Link("API-Key erstellen", destination: apiKeyHelpURL)
                        .font(.caption)
                }
            } header: {
                Text("Zugangsdaten")
            } footer: {
                Text("Der API-Key wird unter Settings → Workspaces in deinem Granola Enterprise Workspace erstellt.")
            }

            Section {
                if source.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Verbunden mit Granola")
                    }

                    Button("Trennen") {
                        Task {
                            await source.disconnect()
                            apiKey = ""
                            errorMessage = nil
                        }
                    }
                    .foregroundStyle(.red)
                } else {
                    Button {
                        connect()
                    } label: {
                        if isConnecting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Verbinde...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Verbinden")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GranolaSource.brandColor)
                    .disabled(isConnecting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if source.hasAPIKey() {
                if let tokens = try? KeychainService.shared.loadTokens(for: GranolaSource.sourceId) {
                    apiKey = tokens.accessToken
                }
            }
        }
    }

    private func connect() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Bitte API-Key eingeben"
            return
        }

        errorMessage = nil
        isConnecting = true

        Task {
            do {
                try source.saveAPIKey(trimmed)
                try await source.authenticate()
            } catch {
                errorMessage = error.localizedDescription
                await source.disconnect()
            }
            isConnecting = false
        }
    }
}
