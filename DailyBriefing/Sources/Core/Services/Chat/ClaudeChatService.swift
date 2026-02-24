import Foundation

/// Threaded chat session for the dedicated Claude panel.
@MainActor
final class ClaudeChatService: ObservableObject {
    static let shared = ClaudeChatService()

    @Published private(set) var threads: [ClaudeChatThread] = []
    @Published private(set) var activeThreadID: UUID?
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: Error?

    private let keychain = KeychainService.shared
    private let maxRecentMessages = 12

    private init() {
        resetToDefaultState()
    }

    /// Build a single-thread fallback for first-run and recovery.
    private func resetToDefaultState() {
        if threads.isEmpty {
            let threadID = createThread(title: "Neuer Chat")
            activeThreadID = threadID
        } else if activeThreadID == nil {
            activeThreadID = threads.first?.id
        }
    }

    /// Return the currently active thread.
    var activeThread: ClaudeChatThread? {
        guard let activeID = activeThreadID else { return threads.first }
        return threads.first(where: { $0.id == activeID }) ?? threads.first
    }

    /// Return the active thread's messages.
    var activeMessages: [ChatMessage] {
        activeThread?.messages ?? []
    }

    /// Open a new chat thread.
    @discardableResult
    func createThread(
        title: String? = nil,
        context: ClaudeTaskContext? = nil
    ) -> UUID {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let threadTitle = trimmedTitle.isEmpty
            ? (context?.title.isEmpty == false ? context?.title ?? "Neuer Chat" : "Neuer Chat")
            : trimmedTitle

        let newThread = ClaudeChatThread(
            id: UUID(),
            title: threadTitle,
            createdAt: Date(),
            updatedAt: Date(),
            context: context,
            messages: []
        )
        threads.append(newThread)
        activeThreadID = newThread.id
        return newThread.id
    }

    /// Open a fresh thread using context from a provider (e.g. Slack, Jira, Mail item).
    @discardableResult
    func openThread(for contextProvider: ClaudeContextProvider) -> UUID {
        openThread(for: contextProvider as TaskContextProvider)
    }

    @discardableResult
    func openThread(for contextProvider: TaskContextProvider) -> UUID {
        createThread(
            title: contextProvider.taskContext.title,
            context: contextProvider.taskContext
        )
    }

    /// Activate an existing thread.
    func selectThread(_ threadID: UUID) {
        activeThreadID = threadID
    }

    /// Remove a thread. Keeps at least one thread.
    func closeThread(_ threadID: UUID) {
        guard threads.count > 1 else { return }
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }

        let removedActive = threadID == activeThreadID
        threads.remove(at: index)

        if removedActive {
            let fallbackIndex = max(0, min(index, threads.count - 1))
            activeThreadID = threads[fallbackIndex].id
        }
    }

    /// Clear messages for the current or specified thread.
    func clearMessages(for threadID: UUID? = nil) {
        guard let resolvedThreadID = threadID ?? activeThreadID,
              let index = threads.firstIndex(where: { $0.id == resolvedThreadID }) else { return }
        threads[index].messages.removeAll()
        threads[index].updatedAt = Date()
    }

    /// Rename a thread title.
    func renameThread(_ threadID: UUID, to title: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        threads[index].title = trimmed.isEmpty ? "Chat" : trimmed
        threads[index].updatedAt = Date()
    }

    /// Send a user message into the selected thread and append assistant answer.
    func sendMessage(_ content: String, threadID: UUID? = nil) async throws {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let targetID: UUID
        if let threadID {
            targetID = threadID
        } else if let activeID = activeThreadID {
            targetID = activeID
        } else {
            targetID = createThread(title: "Neuer Chat")
            activeThreadID = targetID
        }

        guard let threadIndex = threads.firstIndex(where: { $0.id == targetID }) else {
            throw ClaudeChatError.threadNotFound
        }

        threads[threadIndex].messages.append(ChatMessage(role: .user, content: normalized))
        threads[threadIndex].updatedAt = Date()
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            let response = try await generateResponse(for: threads[threadIndex])
            threads[threadIndex].messages.append(ChatMessage(role: .assistant, content: response))
            threads[threadIndex].updatedAt = Date()
        } catch {
            lastError = error
            throw error
        }
    }

    private func generateResponse(for thread: ClaudeChatThread) async throws -> String {
        let config = loadLLMConfiguration()
        let provider = config.provider
        let modelId = resolvedModelId(for: provider, from: config)
        let apiKey = keychain.loadLLMAPIKey(for: provider.rawValue)

        if provider.requiresAPIKey && (apiKey?.isEmpty ?? true) {
            throw ClaudeChatError.providerNotConfigured
        }

        let service = LLMServiceFactory.create(
            provider: provider,
            apiKey: apiKey,
            modelId: modelId,
            ollamaBaseURL: config.ollamaBaseURL,
            openClawBaseURL: config.openClawBaseURL,
            openClawAgentId: config.openClawAgentId
        )

        let systemPrompt = buildSystemPrompt(from: thread.context)
        let prompt = buildPrompt(from: thread.messages)
        return try await service.complete(prompt: prompt, systemPrompt: systemPrompt)
    }

    private func resolvedModelId(for provider: LLMProvider, from config: LLMConfiguration) -> String {
        if provider == .openClaw {
            let normalizedAgent = config.openClawAgentId
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedAgent.isEmpty ? "default" : normalizedAgent
        }

        let trimmedModel = config.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? provider.defaultModel.id : trimmedModel
    }

    private func buildSystemPrompt(from context: ClaudeTaskContext?) -> String {
        var systemPrompt = """
        Du bist der dedizierte Claude-Assistent des Produktivitäts-Hubs.
        Antworte auf Deutsch, kurz und handlungsorientiert.
        Nutze keine unnötigen Floskeln.
        """

        if let context {
            systemPrompt += """

            Aktueller Task-Kontext:
            Quelle: \(context.source)
            Titel: \(context.title)
            Zusammenfassung: \(context.summary)
            Details: \(context.detail.isEmpty ? "Keine zusätzlichen Details." : context.detail)
            Referenz: \(context.referenceURL ?? "nicht gesetzt")

            Konzentriere dich beim Antworten auf diesen Kontext.
            """
        } else {
            systemPrompt += "\nKein spezifischer Task-Kontext gesetzt."
        }

        return systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildPrompt(from messages: [ChatMessage]) -> String {
        let recent = messages.suffix(maxRecentMessages)
        var lines: [String] = []

        for message in recent {
            switch message.role {
            case .user:
                lines.append("Benutzer: \(message.content)")
            case .assistant:
                lines.append("Claude: \(message.content)")
            case .system:
                lines.append("System: \(message.content)")
            }
        }

        lines.append("Claude:")
        return lines.joined(separator: "\n")
    }

    private func loadLLMConfiguration() -> LLMConfiguration {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }

        if let data = UserDefaults.standard.data(forKey: "llmConfiguration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }

        return LLMConfiguration()
    }
}

struct ClaudeChatThread: Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var context: ClaudeTaskContext?
    var messages: [ChatMessage]
}

enum ClaudeChatError: LocalizedError {
    case threadNotFound
    case providerNotConfigured

    var errorDescription: String? {
        switch self {
        case .threadNotFound:
            return "Kein Chat-Thread gefunden."
        case .providerNotConfigured:
            return "LLM-Provider fehlt die Konfiguration."
        }
    }
}
