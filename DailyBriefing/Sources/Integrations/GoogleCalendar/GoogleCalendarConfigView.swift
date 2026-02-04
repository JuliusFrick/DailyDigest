import SwiftUI

/// Configuration view for Google Calendar integration
struct GoogleCalendarConfigView: View {
    @ObservedObject var source: GoogleCalendarSource
    @State private var isLoadingCalendars = false
    
    private var isConfigured: Bool {
        if !Secrets.googleClientId.isEmpty { return true }
        let clientId = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        return !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canConnect: Bool {
        !GoogleCalendarConfig.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            GoogleOAuthCredentialsSection()
            connectionSection
            if source.isAuthenticated {
                calendarSelectionSection
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
                            .fill(source.isAuthenticated ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(source.isAuthenticated ? "Verbunden" : "Nicht verbunden")
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
                Text("Verbinde dein Google-Konto um Kalendertermine in deinem Briefing zu sehen.")
            }
        }
    }

    // MARK: - Calendar Selection Section

    private var calendarSelectionSection: some View {
        Section {
            if source.availableCalendars.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Kalender werden geladen...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    Task {
                        try? await source.fetchCalendarList()
                    }
                }
            } else {
                ForEach(source.availableCalendars) { calendar in
                    CalendarToggleRow(
                        calendar: calendar,
                        isSelected: source.selectedCalendars.contains(calendar.id)
                    ) { isSelected in
                        if isSelected {
                            source.selectedCalendars.insert(calendar.id)
                        } else {
                            source.selectedCalendars.remove(calendar.id)
                        }
                    }
                }
            }
        } header: {
            Text("Kalender")
        } footer: {
            Text("Wähle die Kalender aus, die in deinem Briefing berücksichtigt werden sollen.")
        }
    }
}

// MARK: - Calendar Toggle Row

struct CalendarToggleRow: View {
    let calendar: GoogleCalendar
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { onToggle($0) }
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: calendar.backgroundColor ?? "#4285F4") ?? .blue)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.summary)
                        .font(.body)
                    if calendar.primary == true {
                        Text("Hauptkalender")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
