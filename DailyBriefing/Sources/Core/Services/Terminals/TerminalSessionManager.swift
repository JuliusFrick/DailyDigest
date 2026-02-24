import Foundation

@MainActor
final class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    struct Session: Identifiable, Equatable {
        let id: UUID
        var title: String
        let createdAt: Date
        var initialCommand: String?
        var workingDirectory: String?
    }

    @Published private(set) var sessions: [Session] = []
    @Published var selectedSessionID: UUID?

    private init() {
        _ = openSession(title: "Terminal 1")
    }

    var activeSession: Session? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    @discardableResult
    func openSession(
        title: String = "Terminal",
        initialCommand: String? = nil,
        workingDirectory: String? = nil
    ) -> UUID {
        let sessionTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Terminal"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedWorkingDirectory = workingDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let newSession = Session(
            id: UUID(),
            title: sessionTitle,
            createdAt: Date(),
            initialCommand: initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectory: normalizedWorkingDirectory
        )

        sessions.append(newSession)
        selectedSessionID = newSession.id
        return newSession.id
    }

    @discardableResult
    func openSession(for contextProvider: TaskContextProvider) -> UUID {
        let context = contextProvider.taskContext
        let sessionID = openSession(
            title: buildSessionTitle(from: context),
            initialCommand: context.terminalStartupCommand,
            workingDirectory: context.terminalWorkingDirectory
        )
        AppState.shared.selectedPanel = .terminals
        return sessionID
    }

    func selectSession(_ id: UUID) {
        selectedSessionID = sessions.contains { $0.id == id } ? id : sessions.first?.id
    }

    func closeSession(_ id: UUID) {
        guard sessions.count > 1 else { return }

        guard let removeIndex = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: removeIndex)

        if selectedSessionID == id {
            selectedSessionID = sessions.indices.contains(removeIndex)
                ? sessions[removeIndex].id
                : sessions.first?.id
        }
    }

    func renameSession(_ id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sessions[index].title = trimmed
    }

    private func buildSessionTitle(from context: ClaudeTaskContext) -> String {
        let baseTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.source.isEmpty {
            return baseTitle.isEmpty ? "Task Terminal" : baseTitle
        }

        let prefix = "\(context.source): "
        return "\(prefix)\(baseTitle)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

