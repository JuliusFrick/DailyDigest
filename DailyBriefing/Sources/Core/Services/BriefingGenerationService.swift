import Foundation
import Combine

/// Service responsible for orchestrating briefing generation
/// Coordinates fetching data from sources and summarizing via LLM
@MainActor
final class BriefingGenerationService: ObservableObject {

    // MARK: - Singleton

    static let shared = BriefingGenerationService()

    // MARK: - Published Properties

    @Published private(set) var isGenerating = false
    @Published private(set) var generationProgress: GenerationProgress = .idle
    @Published private(set) var lastError: BriefingGenerationError?

    // MARK: - Dependencies

    private let connectionManager = ServiceConnectionManager.shared
    private let keychain = KeychainService.shared
    private let cacheService = BriefingCacheService.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Generate a new briefing from all connected sources
    func generateBriefing(detailLevel: Briefing.DetailLevel = .quick) async throws -> Briefing {
        guard !isGenerating else {
            throw BriefingGenerationError.alreadyGenerating
        }

        isGenerating = true
        generationProgress = .starting
        lastError = nil

        defer {
            isGenerating = false
        }

        do {
            // Step 1: Fetch data from all connected sources
            generationProgress = .fetchingSources
            let sourceItems = try await fetchFromAllSources()

            // Check if we have any items
            if sourceItems.isEmpty {
                throw BriefingGenerationError.noSourcesConnected
            }

            // Step 2: Build sections from source items
            generationProgress = .processingSources
            let sections = buildSections(from: sourceItems)

            // Step 3: Generate summary using LLM
            generationProgress = .generatingSummary
            let summary = try await generateSummary(sections: sections, detailLevel: detailLevel)

            // Step 4: Build final briefing
            generationProgress = .finalizing
            let briefing = Briefing(
                summary: summary,
                sections: sections,
                detailLevel: detailLevel
            )

            // Step 5: Cache the briefing for offline access
            try? cacheService.save(briefing: briefing)

            generationProgress = .completed
            return briefing

        } catch let error as BriefingGenerationError {
            lastError = error
            generationProgress = .failed(error)
            throw error
        } catch {
            let wrappedError = BriefingGenerationError.unknown(error)
            lastError = wrappedError
            generationProgress = .failed(wrappedError)
            throw wrappedError
        }
    }

    // MARK: - Private Methods

    /// Fetch items from all connected sources in parallel
    private func fetchFromAllSources() async throws -> [SourceFetchResult] {
        let sources = connectionManager.connectedSources

        guard !sources.isEmpty else {
            throw BriefingGenerationError.noSourcesConnected
        }

        // Calculate the time range - last 24 hours
        let since = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()

        var results: [SourceFetchResult] = []
        var errors: [SourceFetchError] = []

        // Fetch from all sources concurrently
        await withTaskGroup(of: (SourceFetchResult?, SourceFetchError?).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        let items = try await source.fetchItems(since: since)
                        return (SourceFetchResult(
                            sourceId: type(of: source).sourceId,
                            sourceName: type(of: source).displayName,
                            sourceIcon: type(of: source).iconName,
                            items: items
                        ), nil)
                    } catch {
                        // Capture error for potential reporting
                        return (nil, SourceFetchError(
                            sourceId: type(of: source).sourceId,
                            error: error
                        ))
                    }
                }
            }

            for await (result, error) in group {
                if let result = result {
                    results.append(result)
                }
                if let error = error {
                    errors.append(error)
                }
            }
        }

        // Check for critical errors that should be surfaced
        for fetchError in errors {
            if let sourceError = fetchError.error as? SourceError {
                switch sourceError {
                case .tokenExpired:
                    throw BriefingGenerationError.tokenExpired(sourceId: fetchError.sourceId)
                case .networkError:
                    throw BriefingGenerationError.networkError(fetchError.error)
                default:
                    break
                }
            }
        }

        // If all sources failed, throw an error
        if results.isEmpty && !sources.isEmpty {
            throw BriefingGenerationError.allSourcesFailed
        }

        return results
    }

    /// Build briefing sections from fetched items
    private func buildSections(from results: [SourceFetchResult]) -> [BriefingSection] {
        return results.compactMap { result in
            guard !result.items.isEmpty else { return nil }

            // Calculate section priority based on items
            let maxPriority = result.items.map { $0.priority }.max() ?? .medium

            return BriefingSection(
                sourceId: result.sourceId,
                sourceName: result.sourceName,
                sourceIcon: result.sourceIcon,
                summary: generateSectionSummary(items: result.items),
                items: result.items,
                priority: maxPriority
            )
        }
    }

    /// Generate a brief summary for a section
    private func generateSectionSummary(items: [BriefingItem]) -> String {
        let count = items.count
        let urgentCount = items.filter { $0.priority == .urgent }.count
        let highCount = items.filter { $0.priority == .high }.count

        if urgentCount > 0 {
            return "\(count) Einträge, davon \(urgentCount) dringend"
        } else if highCount > 0 {
            return "\(count) Einträge, davon \(highCount) wichtig"
        } else {
            return "\(count) Einträge"
        }
    }

    /// Generate the main summary using the configured LLM
    private func generateSummary(sections: [BriefingSection], detailLevel: Briefing.DetailLevel) async throws -> String {
        // Load LLM configuration
        guard let config = loadLLMConfiguration() else {
            throw BriefingGenerationError.llmNotConfigured
        }

        // Get API key if required
        let apiKey = keychain.loadLLMAPIKey(for: config.provider.rawValue)
        if config.provider.requiresAPIKey && (apiKey == nil || apiKey?.isEmpty == true) {
            throw BriefingGenerationError.llmNotConfigured
        }

        // Create LLM service
        let llmService = LLMServiceFactory.create(
            provider: config.provider,
            apiKey: apiKey,
            modelId: config.modelId,
            ollamaBaseURL: config.ollamaBaseURL
        )

        // Build the prompt
        let prompt = buildPrompt(sections: sections, detailLevel: detailLevel)
        let systemPrompt = buildSystemPrompt(detailLevel: detailLevel)

        // Generate the summary
        do {
            let summary = try await llmService.complete(prompt: prompt, systemPrompt: systemPrompt)
            return summary
        } catch {
            throw BriefingGenerationError.llmError(error)
        }
    }

    /// Load LLM configuration from UserDefaults
    private func loadLLMConfiguration() -> LLMConfiguration? {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        // Return default configuration
        return LLMConfiguration()
    }

    /// Build the prompt for the LLM
    private func buildPrompt(sections: [BriefingSection], detailLevel: Briefing.DetailLevel) -> String {
        var prompt = "Hier sind die Daten aus meinen verschiedenen Quellen für heute:\n\n"

        for section in sections.sorted(by: { $0.priority > $1.priority }) {
            prompt += "## \(section.sourceName)\n"
            for item in section.items.prefix(10) {  // Limit items per section
                prompt += "- \(item.title)"
                if let subtitle = item.subtitle {
                    prompt += " (\(subtitle))"
                }
                if item.priority == .urgent {
                    prompt += " [DRINGEND]"
                } else if item.priority == .high {
                    prompt += " [WICHTIG]"
                }
                prompt += "\n"
            }
            prompt += "\n"
        }

        return prompt
    }

    /// Build the system prompt for the LLM
    private func buildSystemPrompt(detailLevel: Briefing.DetailLevel) -> String {
        let lengthGuidance = detailLevel == .quick
            ? "Die Zusammenfassung sollte kurz und prägnant sein (2-3 Absätze)."
            : "Die Zusammenfassung sollte ausführlich sein und alle wichtigen Details enthalten (5-7 Absätze)."

        return """
        Du bist ein persönlicher Assistent, der ein tägliches Briefing erstellt. \
        Fasse die folgenden Informationen aus verschiedenen Quellen zu einer \
        natürlich klingenden Zusammenfassung zusammen.

        \(lengthGuidance)

        Beginne mit den wichtigsten und dringendsten Punkten. \
        Verwende einen freundlichen, aber professionellen Ton. \
        Antworte auf Deutsch.
        """
    }
}

// MARK: - Supporting Types

/// Result of fetching from a single source
private struct SourceFetchResult {
    let sourceId: String
    let sourceName: String
    let sourceIcon: String
    let items: [BriefingItem]
}

/// Error during source fetch
private struct SourceFetchError {
    let sourceId: String
    let error: Error
}

/// Progress states during briefing generation
enum GenerationProgress: Equatable {
    case idle
    case starting
    case fetchingSources
    case processingSources
    case generatingSummary
    case finalizing
    case completed
    case failed(BriefingGenerationError)

    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .starting:
            return "Starte Briefing-Generierung..."
        case .fetchingSources:
            return "Hole Daten von verbundenen Diensten..."
        case .processingSources:
            return "Verarbeite Daten..."
        case .generatingSummary:
            return "KI erstellt Zusammenfassung..."
        case .finalizing:
            return "Finalisiere Briefing..."
        case .completed:
            return "Briefing fertig!"
        case .failed(let error):
            return "Fehler: \(error.localizedDescription)"
        }
    }

    static func == (lhs: GenerationProgress, rhs: GenerationProgress) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.starting, .starting),
             (.fetchingSources, .fetchingSources),
             (.processingSources, .processingSources),
             (.generatingSummary, .generatingSummary),
             (.finalizing, .finalizing),
             (.completed, .completed):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Errors that can occur during briefing generation
enum BriefingGenerationError: LocalizedError {
    case alreadyGenerating
    case noSourcesConnected
    case allSourcesFailed
    case llmNotConfigured
    case llmError(Error)
    case tokenExpired(sourceId: String)
    case networkError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyGenerating:
            return "Ein Briefing wird bereits generiert"
        case .noSourcesConnected:
            return "Keine Quellen verbunden. Bitte verbinde mindestens eine Quelle in den Einstellungen."
        case .allSourcesFailed:
            return "Alle Quellen konnten nicht erreicht werden. Bitte überprüfe deine Internetverbindung."
        case .llmNotConfigured:
            return "KI-Provider nicht konfiguriert. Bitte richte einen Provider in den Einstellungen ein."
        case .llmError(let error):
            return "KI-Fehler: \(error.localizedDescription)"
        case .tokenExpired(let sourceId):
            return "Sitzung für '\(sourceId)' abgelaufen. Bitte erneut verbinden."
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unbekannter Fehler: \(error.localizedDescription)"
        }
    }

    /// The source ID for token-related errors
    var affectedSourceId: String? {
        if case .tokenExpired(let sourceId) = self {
            return sourceId
        }
        return nil
    }
}
