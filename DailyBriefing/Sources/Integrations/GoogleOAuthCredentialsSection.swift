import SwiftUI

struct GoogleOAuthCredentialsSection: View {
    @AppStorage("google_client_id") private var googleClientId: String = ""
    @AppStorage("google_client_secret") private var googleClientSecret: String = ""
    @State private var showWizard = false
    @State private var tempClientId = ""
    @State private var tempClientSecret = ""
    
    // Check if configuration is complete
    private var isConfigured: Bool {
        if !Secrets.googleClientId.isEmpty { return true }
        return !googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var isUsingSecrets: Bool {
        !Secrets.googleClientId.isEmpty
    }

    var body: some View {
        Section {
            if isConfigured {
                // Configured state - cleaner UI
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if isUsingSecrets {
                        Text("App ist vorkonfiguriert")
                    } else {
                        Text("App ist konfiguriert")
                    }
                    Spacer()
                    
                    if !isUsingSecrets {
                        Button("Einstellungen ändern") {
                            showWizard = true
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            } else {
                // Not configured - Call to action
                Button {
                    showWizard = true
                } label: {
                    HStack {
                        Image(systemName: "wrench.adjustable")
                        Text("Google-Zugriff einrichten")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.tuiPrimary)
            }
        } header: {
            Text("Konfiguration")
        } footer: {
            if !isConfigured {
                Text("Einmalige Einrichtung erforderlich, um Daily Briefing mit deinem Google-Konto zu verbinden.")
            }
        }
        .sheet(isPresented: $showWizard) {
            wizardView
        }
    }
    
    // MARK: - Wizard View
    

}

// Custom Wizard for Google to include TextFields
private struct GoogleSetupWizard: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("google_client_id") private var googleClientId: String = ""
    @AppStorage("google_client_secret") private var googleClientSecret: String = ""
    
    @State private var step = 0
    @State private var clientId = ""
    @State private var clientSecret = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Google-Einrichtung")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.tuiBackground)
            
            Divider()
            
            // Content
            VStack {
                if step == 0 {
                    introStep
                } else if step == 1 {
                    consoleStep
                } else if step == 2 {
                    redirectStep
                } else {
                    credentialsStep
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack {
                if step > 0 {
                    Button("Zurück") {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(.tui)
                }
                
                Spacer()
                
                if step < 3 {
                    Button("Weiter") {
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.tuiPrimary)
                } else {
                    Button("Speichern & Beenden") {
                        googleClientId = clientId
                        googleClientSecret = clientSecret
                        dismiss()
                    }
                    .buttonStyle(.tuiPrimary)
                    .disabled(clientId.isEmpty)
                }
            }
            .padding()
            .background(Color.tuiBackground)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            clientId = googleClientId
            clientSecret = googleClientSecret
        }
    }
    
    var introStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "g.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Verbindung zu Google herstellen")
                .font(.system(.headline, design: .monospaced))
                .bold()
            
            Text("Da dies eine private App ist, musst du einmalig eigene Zugangsdaten bei Google (kostenlos) erstellen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Text("Das dauert nur ca. 2 Minuten.")
                .font(.system(.caption, design: .monospaced))
                .italic()
                .foregroundStyle(.tertiary)
        }
    }
    
    var consoleStep: some View {
        VStack(spacing: 20) {
            Text("1. Projekt erstellen")
                .font(.system(.headline, design: .monospaced))
                .bold()
            
            Text("1. Öffne die **Google Cloud Console**\n2. Erstelle ein neues Projekt\n3. Gehe zu **APIs & Dienste > Zugangsdaten**\n4. Klicke auf **Anmeldedaten erstellen** > **OAuth-Client-ID**\n5. Wähle **Webanwendung**")
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
            
            Button {
                NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
            } label: {
                Text("Google Console öffnen")
            }
            .buttonStyle(.tui)
        }
    }
    
    var redirectStep: some View {
        VStack(spacing: 20) {
            Text("2. Redirect URI einstellen")
                .font(.system(.headline, design: .monospaced))
                .bold()
            
            Text("Füge unter **Autorisierte Weiterleitungs-URIs** genau diese Adresse hinzu:")
                .multilineTextAlignment(.center)
            
            HStack {
                Text("http://127.0.0.1:0/oauth/google")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.tuiBackground)
                    .cornerRadius(4)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("http://127.0.0.1:0/oauth/google", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
            
            Text("Wichtig: Der Port :0 ist ein Platzhalter, aber Google akzeptiert ihn für Loopback-Tests.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    var credentialsStep: some View {
        VStack(spacing: 20) {
            Text("3. Daten eingeben")
                .font(.system(.headline, design: .monospaced))
                .bold()
            
            VStack(alignment: .leading) {
                Text("Client ID")
                    .font(.caption)
                TextField("xxx.apps.googleusercontent.com", text: $clientId)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading) {
                Text("Client Secret")
                    .font(.caption)
                SecureField("Client Secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// Update the main view to use the custom wizard
extension GoogleOAuthCredentialsSection {
    private var wizardView: some View {
        GoogleSetupWizard()
    }
}
