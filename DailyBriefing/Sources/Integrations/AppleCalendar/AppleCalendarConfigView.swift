import SwiftUI

/// Configuration view for Apple Calendar integration
struct AppleCalendarConfigView: View {
    @ObservedObject var source: AppleCalendarSource
    
    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                calendarSelectionSection
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
                    Text("Apple Calendar")
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
            Text("Greife auf deinen lokalen Kalender zu, um Termine in deinem Briefing anzuzeigen.")
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
                        await source.fetchAvailableCalendars()
                    }
                }
            } else {
                ForEach(source.availableCalendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { source.selectedCalendars.contains(calendar.id) },
                        set: { isSelected in
                            if isSelected {
                                source.selectedCalendars.insert(calendar.id)
                            } else {
                                source.selectedCalendars.remove(calendar.id)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendar.color)
                                .frame(width: 12, height: 12)
                            Text(calendar.title)
                                .font(.body)
                        }
                    }
                }
            }
        } header: {
            Text("Kalender")
        } footer: {
            Text("Wähle die Kalender aus, deren Termine im Briefing erscheinen sollen.")
        }
    }
    
    // MARK: - Permissions Section
    
    private var permissionsSection: some View {
        Section {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Datenschutz")
                        .font(.subheadline)
                    Text("Diese App benötigt Zugriff auf deinen Kalender. Du kannst dies in den Systemeinstellungen ändern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .buttonStyle(.tui)
        } header: {
            Text("Berechtigungen")
        }
    }
}
