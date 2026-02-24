import Foundation

struct ClaudeTaskContext: Identifiable, Equatable, Codable {
    let id: UUID
    let source: String
    let title: String
    let summary: String
    let detail: String
    let referenceID: String?
    let referenceURL: String?
    let terminalStartupCommand: String?
    let terminalWorkingDirectory: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        source: String,
        title: String,
        summary: String,
        detail: String,
        referenceID: String?,
        referenceURL: String?,
        terminalStartupCommand: String?,
        terminalWorkingDirectory: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.summary = summary
        self.detail = detail
        self.referenceID = referenceID
        self.referenceURL = referenceURL
        self.terminalStartupCommand = terminalStartupCommand
        self.terminalWorkingDirectory = terminalWorkingDirectory
        self.createdAt = createdAt
    }

    var shortPreview: String {
        [summary, detail]
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol TaskContextProvider {
    var taskContext: ClaudeTaskContext { get }
}

protocol ClaudeContextProvider: TaskContextProvider {
    var claudeContext: ClaudeTaskContext { get }
}

extension ClaudeContextProvider {
    var taskContext: ClaudeTaskContext {
        claudeContext
    }
}

extension BriefingItem: ClaudeContextProvider {
    /// Source name for Claude context; from metadata or inferred from subtitle
    private var sourceName: String {
        metadata["sourceName"]
            ?? (metadata["issueKey"] != nil ? "Jira" : nil)
            ?? (metadata["conversationId"] != nil ? "Slack" : nil)
            ?? (metadata["messageId"] != nil ? "Mail" : nil)
            ?? subtitle
            ?? "Unbekannt"
    }

    var claudeContext: ClaudeTaskContext {
        let summary = subtitle ?? title

        var details: [String] = []
        if let timestamp = timestamp {
            details.append("Zeit: \(Self.claudeDateFormatter.string(from: timestamp))")
        }
        if let body = body, !body.isEmpty {
            details.append(body)
        }
        if let attendees = metadata["attendees"], !attendees.isEmpty {
            details.append("Teilnehmer: \(attendees)")
        }
        if let location = metadata["location"], !location.isEmpty {
            details.append("Ort: \(location)")
        }
        if let duration = metadata["duration"], !duration.isEmpty {
            details.append("Dauer: \(duration)")
        }
        let detailText = details.joined(separator: "\n")
        let startupCommand = buildTerminalStartupCommand(
            source: sourceName,
            title: title,
            summary: summary,
            detail: detailText
        )
        let workingDirectory = metadata["workingDirectory"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ClaudeTaskContext(
            id: id,
            source: sourceName,
            title: title,
            summary: summary,
            detail: detailText,
            referenceID: id.uuidString,
            referenceURL: deepLink?.absoluteString,
            terminalStartupCommand: startupCommand,
            terminalWorkingDirectory: workingDirectory
        )
    }

    private func buildTerminalStartupCommand(
        source: String,
        title: String,
        summary: String,
        detail: String
    ) -> String? {
        let lines = [
            "Task-Kontext aus DailyDigest",
            "Quelle: \(source)",
            "Titel: \(title)",
            "Zusammenfassung: \(summary)",
            detail
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { return nil }

        let payload = lines.joined(separator: "\n")
        return "printf \(Self.shellSingleQuoteEscaped(payload)) && printf '\\n'"
    }

    private static func shellSingleQuoteEscaped(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static var claudeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()
}
