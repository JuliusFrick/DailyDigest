import SwiftUI
import UniformTypeIdentifiers

/// Privacy settings view for managing user data
struct PrivacySettingsView: View {
    @StateObject private var cacheService = BriefingCacheService.shared
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    @State private var showClearCacheConfirmation = false
    @State private var showDeleteCredentialsConfirmation = false
    @State private var showExportPanel = false
    @State private var isExporting = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            cacheSection
            credentialsSection
            exportSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.tuiBackground)
        .font(.tuiMonoSmall)
        .controlSize(.small)
        .navigationTitle("Datenschutz")
        .alert("Cache leeren", isPresented: $showClearCacheConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Leeren", role: .destructive) {
                clearCache()
            }
        } message: {
            Text("Möchtest du alle gecachten Briefings wirklich löschen? Dies kann nicht rückgängig gemacht werden.")
        }
        .alert("Alle Credentials löschen", isPresented: $showDeleteCredentialsConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                deleteAllCredentials()
            }
        } message: {
            Text("Möchtest du wirklich alle gespeicherten Zugangsdaten löschen? Alle Dienste werden getrennt und du musst dich erneut anmelden.")
        }
        .alert("Erfolg", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert("Fehler", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fileExporter(
            isPresented: $showExportPanel,
            document: ExportDocument(data: exportData()),
            contentType: .json,
            defaultFilename: "DailyBriefing_Export_\(exportDateString()).json"
        ) { result in
            switch result {
            case .success(let url):
                successMessage = "Daten wurden erfolgreich exportiert nach:\n\(url.lastPathComponent)"
                showSuccessAlert = true
            case .failure(let error):
                errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    // MARK: - Cache Section

    private var cacheSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gecachte Briefings")
                    Text("\(cacheService.cachedBriefingCount) Briefings (\(formattedCacheSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cache leeren") {
                    showClearCacheConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(cacheService.cachedBriefingCount == 0)
            }
        } header: {
            Text("Cache")
        } footer: {
            Text("Löscht alle lokal gespeicherten Briefings. Neue Briefings werden weiterhin generiert.")
        }
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gespeicherte Zugangsdaten")
                    Text("\(connectionManager.connectedSources.count) verbundene Dienste")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Alle löschen", role: .destructive) {
                    showDeleteCredentialsConfirmation = true
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Zugangsdaten")
        } footer: {
            Text("Löscht alle OAuth-Tokens und API-Keys aus dem Schlüsselbund. Alle Dienste werden getrennt.")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alle Daten exportieren")
                    Text("Einstellungen, Briefings und Verbindungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Exportieren") {
                    showExportPanel = true
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Datenexport")
        } footer: {
            Text("Exportiert alle deine Daten als JSON-Datei. Zugangsdaten werden aus Sicherheitsgründen nicht exportiert.")
        }
    }

    // MARK: - Helpers

    private var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(cacheService.cacheSize))
    }

    private func clearCache() {
        do {
            try cacheService.clearAll()
            successMessage = "Cache wurde erfolgreich geleert."
            showSuccessAlert = true
        } catch {
            errorMessage = "Fehler beim Leeren des Caches: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func deleteAllCredentials() {
        Task {
            // First disconnect all sources
            await connectionManager.disconnectAllSources()

            // Then delete all keychain credentials
            do {
                try KeychainService.shared.deleteAllCredentials()
                await MainActor.run {
                    successMessage = "Alle Zugangsdaten wurden gelöscht. Alle Dienste wurden getrennt."
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Fehler beim Löschen der Zugangsdaten: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }

    private func exportDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }

    private func exportData() -> Data {
        let export = DataExport(
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            briefings: cacheService.loadAll(),
            connections: Array(connectionManager.connections.values).map { connection in
                ExportedConnection(
                    serviceId: connection.serviceId,
                    serviceName: connection.serviceName,
                    status: connection.status.rawValue,
                    connectedAt: connection.connectedAt,
                    lastSyncAt: connection.lastSyncAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return (try? encoder.encode(export)) ?? Data()
    }
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export Models

struct DataExport: Codable {
    let exportedAt: Date
    let appVersion: String
    let briefings: [Briefing]
    let connections: [ExportedConnection]
}

struct ExportedConnection: Codable {
    let serviceId: String
    let serviceName: String
    let status: String
    let connectedAt: Date
    let lastSyncAt: Date?
}
