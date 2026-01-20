import SwiftUI

/// Configuration view for Apple Reminders integration
struct AppleRemindersConfigView: View {
    @ObservedObject var source: AppleRemindersSource

    var body: some View {
        Form {
            connectionSection
            if source.isAuthenticated {
                listSelectionSection
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
                    Text("Apple Reminders")
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
            Text("Greife auf deine Apple Reminders zu, um anstehende Aufgaben in deinem Briefing anzuzeigen.")
        }
    }

    // MARK: - List Selection Section

    private var listSelectionSection: some View {
        Section {
            if source.availableLists.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Listen werden geladen...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    Task {
                        await source.fetchAvailableLists()
                    }
                }
            } else {
                ForEach(source.availableLists) { list in
                    ReminderListToggleRow(
                        list: list,
                        isSelected: source.selectedLists.contains(list.id)
                    ) { isSelected in
                        if isSelected {
                            source.selectedLists.insert(list.id)
                        } else {
                            source.selectedLists.remove(list.id)
                        }
                    }
                }
            }
        } header: {
            Text("Listen")
        } footer: {
            Text("Wähle die Listen aus, deren Erinnerungen in deinem Briefing erscheinen sollen.")
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Toggle("Bald fällige Erinnerungen", isOn: $source.includeDueSoon)
            Toggle("Erledigte Erinnerungen anzeigen", isOn: $source.includeCompleted)
        } header: {
            Text("Filter")
        } footer: {
            Text("Konfiguriere, welche Erinnerungen in deinem Briefing erscheinen sollen.")
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
                    Text("Diese App benötigt Zugriff auf deine Erinnerungen. Du kannst dies in den Systemeinstellungen ändern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            }
            .buttonStyle(.tui)
        } header: {
            Text("Berechtigungen")
        }
    }
}

// MARK: - Reminder List Toggle Row

struct ReminderListToggleRow: View {
    let list: ReminderList
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { onToggle($0) }
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(list.color)
                    .frame(width: 12, height: 12)
                Text(list.title)
                    .font(.body)
            }
        }
    }
}
