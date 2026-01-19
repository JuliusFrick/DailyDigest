import SwiftUI

struct GoogleOAuthCredentialsSection: View {
    @AppStorage("google_client_id") private var googleClientId: String = ""
    @AppStorage("google_client_secret") private var googleClientSecret: String = ""

    var body: some View {
        Section {
            TextField("Client ID", text: $googleClientId)
                .autocorrectionDisabled(true)
                .font(.system(.body, design: .monospaced))

            SecureField("Client Secret (optional)", text: $googleClientSecret)
                .autocorrectionDisabled(true)
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .leading, spacing: 6) {
                Text("Redirect URL (in Google OAuth Client hinterlegen):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("http://127.0.0.1:0/oauth/google")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Link("Google Cloud Console oeffnen", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
        } header: {
            Text("OAuth")
        } footer: {
            if googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Fuer den Login wird mindestens eine Google Client ID benoetigt.")
            } else {
                Text("Client-ID/Secret werden in UserDefaults gespeichert (fuer Development ok).")
            }
        }
    }
}
