import AppKit
import SwiftUI

struct ExternalBridgeSettingsView: View {
    @StateObject private var bridgeService = ExternalBridgeService.shared
    
    @State private var isEnabled: Bool = false
    @State private var portText: String = ""
    @State private var allowlistText: String = ""
    @State private var testResult: String?
    @State private var isTestingBridge = false
    @State private var localHealthResponse: String = ""
    
    var body: some View {
        Form {
            Section {
                Toggle("Read-only Bridge aktivieren", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        Task {
                            await bridgeService.updateConfiguration(isEnabled: newValue)
                        }
                    }
                
                TextField("Listen-Port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyBridgeSettings() }
                    .disabled(!isEnabled)
                
                TextField("Erlaubte Clients (optional, z. B. 127.0.0.1, ::1)", text: $allowlistText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyBridgeSettings() }
                    .disabled(!isEnabled)
                
                Button("Konfiguration speichern") {
                    applyBridgeSettings()
                }
                .disabled(!isEnabled)
                
                if bridgeService.isRunning {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Status: Aktiv auf http://127.0.0.1:\(bridgeService.activePort)")
                    }
                } else if isEnabled {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text("Status: Konfiguration aktiv – Start im nächsten App-Start")
                    }
                } else {
                    Text("Status: Deaktiviert")
                }
                
                if let errorMessage = bridgeService.lastErrorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } header: {
                Text("OpenClaw Bridge")
            } footer: {
                Text("Die Bridge liefert nur Lesezugriff auf App-Daten für OpenClaw oder andere Agenten.")
            }
            
            Section {
                HStack {
                    Text("Geheimtoken")
                        .fontWeight(.medium)
                    Spacer()
                    Text(bridgeService.currentSecretMasked())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Button("Token kopieren") {
                        copyToken()
                    }
                    .disabled(bridgeService.currentSecret() == nil)
                    
                    Button("Token neu generieren") {
                        Task {
                            do {
                                _ = try await bridgeService.rotateSecret()
                                await MainActor.run {
                                    // Update UI state by reloading from service
                                    syncFromService()
                                }
                            } catch {
                                await MainActor.run {
                                    testResult = error.localizedDescription
                                }
                            }
                        }
                    }
                    .foregroundStyle(.red)
                }
            } footer: {
                Text("Sende OpenClaw-Anfragen mit `Authorization: Bearer <token>`.")
            }
            
            Section {
                Button(isTestingBridge ? "Teste Bridge..." : "Local Health prüfen") {
                    runLocalHealthCheck()
                }
                .disabled(isTestingBridge || !bridgeService.isRunning)
                
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(localHealthResponse.starts(with: "OK") ? .green : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verfügbare Endpunkte:")
                        .font(.caption)
                    Text("GET /health")
                    Text("GET /briefings/latest")
                    Text("GET /action-items/open")
                    Text("GET /services/connected")
                    Text("GET /context/overview")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Tipp: Für OpenClaw ist `GET /context/overview` der einfachste Startpunkt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Diagnose")
            }
        }
        .onAppear {
            syncFromService()
        }
    }
    
    private func applyBridgeSettings() {
        guard isEnabled else {
            Task {
                await bridgeService.updateConfiguration(isEnabled: false)
            }
            return
        }
        
        let resolvedPort = parsePort()
        let allowlist = parseAllowlist()
        Task {
            await bridgeService.updateConfiguration(
                isEnabled: isEnabled,
                port: resolvedPort,
                allowedClients: allowlist
            )
        }
    }
    
    private func runLocalHealthCheck() {
        guard let healthURL = bridgeService.healthURL else { return }
        isTestingBridge = true
        testResult = nil
        localHealthResponse = ""
        
        Task {
            guard let token = bridgeService.currentSecret() else {
                await MainActor.run {
                    isTestingBridge = false
                    testResult = "Kein Token gespeichert"
                    localHealthResponse = "FAIL"
                }
                return
            }
            
            var request = URLRequest(url: healthURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    localHealthResponse = status == 200 ? "OK" : "HTTP \(status)"
                    testResult = status == 200 ? "Bridge-Endpoint erreichbar." : "Antwortcode: \(status)"
                    isTestingBridge = false
                }
            } catch {
                await MainActor.run {
                    localHealthResponse = "FAIL"
                    testResult = "Fehler: \(error.localizedDescription)"
                    isTestingBridge = false
                }
            }
        }
    }
    
    private func parsePort() -> UInt16 {
        let trimmed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ExternalBridgeConfiguration.fallbackPort
        }
        return UInt16(trimmed) ?? ExternalBridgeConfiguration.fallbackPort
    }
    
    private func parseAllowlist() -> [String] {
        return allowlistText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func syncFromService() {
        isEnabled = bridgeService.configuration.isEnabled
        portText = String(bridgeService.configuration.port)
        allowlistText = bridgeService.configuration.allowedClients.joined(separator: ", ")
    }
    
    private func copyToken() {
        guard let token = bridgeService.currentSecret() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        testResult = "Token in Zwischenablage kopiert."
    }
}
