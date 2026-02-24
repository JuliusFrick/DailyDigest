import SwiftUI

struct ErrorLoggingView: View {
    @StateObject private var errorDisplayService = ErrorDisplayService.shared

    private var allErrors: [DisplayableError] {
        var errors: [DisplayableError] = []
        if let currentError = errorDisplayService.currentError {
            errors.append(currentError)
        }
        errors.append(contentsOf: errorDisplayService.errorQueue)
        return errors
    }

    var body: some View {
        Form {
            Section("Fehler") {
                if allErrors.isEmpty {
                    Text("Zurzeit sind keine Fehlermeldungen vorhanden.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(allErrors) { error in
                        errorRow(error)
                    }
                }
            }

            if !allErrors.isEmpty {
                Section {
                    Button(role: .destructive) {
                        clearAllErrors()
                    } label: {
                        Text("Alle Meldungen löschen")
                    }
                }
            }
        }
    }

    private func clearAllErrors() {
        errorDisplayService.dismissCurrent()
        errorDisplayService.clearQueue()
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime
            .year()
            .month()
            .day()
            .hour()
            .minute()
            .second())
    }

    @ViewBuilder
    private func errorRow(_ error: DisplayableError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: error.severity.icon)
                    .foregroundStyle(error.severity.color)
                Text(error.title)
                    .font(.headline)
                Spacer()
                Text(formattedDate(error.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(error.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if error.retryAction != nil {
                Button("Erneut versuchen") {
                    error.retryAction?()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ErrorLoggingView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorLoggingView()
    }
}
