import SwiftUI

struct GoogleOAuthCredentialsSection: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anmeldung erfolgt im Browser bei Google.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if GoogleConfig.hasBundledConfig {
                    Text("OAuth ist in der App vorkonfiguriert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("OAuth-Konfiguration fehlt in der App. Bitte eine gültige Google Client ID hinterlegen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Redirect URL (in Google OAuth Client hinterlegen):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("http://127.0.0.1:0/oauth/google")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Link("Google Cloud Console öffnen", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
        } header: {
            Text("OAuth")
        } footer: {
            Text("Für den Login wird eine gültige Google Client ID benötigt.")
        }
    }
}
