import Foundation

/// AI-generated meeting brief
struct MeetingBrief: Identifiable, Codable {
    let id: UUID
    let meetingId: String
    let summary: String           // 2-3 sentences
    let keyPoints: [String]       // Bullet points
    let suggestedTopics: [String] // What to bring up
    let openActionItems: [ActionItem]
    let generatedAt: Date
    
    init(
        id: UUID = UUID(),
        meetingId: String,
        summary: String,
        keyPoints: [String],
        suggestedTopics: [String],
        openActionItems: [ActionItem] = [],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.meetingId = meetingId
        self.summary = summary
        self.keyPoints = keyPoints
        self.suggestedTopics = suggestedTopics
        self.openActionItems = openActionItems
        self.generatedAt = generatedAt
    }
}

/// Service for generating AI meeting briefs
@MainActor
final class MeetingBriefService: ObservableObject {
    static let shared = MeetingBriefService()
    
    // MARK: - Published Properties
    
    @Published var isGenerating = false
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    
    private let contextService = MeetingContextService.shared
    private let actionItemStore = ActionItemStore.shared
    
    // MARK: - Cache
    
    private var briefCache: [String: MeetingBrief] = [:]
    private let cacheValiditySeconds: TimeInterval = 1800 // 30 minutes
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Generate a meeting brief with context from emails and action items
    /// - Parameters:
    ///   - meeting: The meeting to generate a brief for
    ///   - forceRefresh: If true, bypass cache and regenerate
    /// - Returns: Generated meeting brief
    func generateBrief(for meeting: BriefingItem, forceRefresh: Bool = false) async throws -> MeetingBrief {
        let meetingId = meetingId(for: meeting)
        
        // Check cache
        if !forceRefresh, let cached = briefCache[meetingId] {
            let age = Date().timeIntervalSince(cached.generatedAt)
            if age < cacheValiditySeconds {
                return cached
            }
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        // Fetch email context
        let emailContext: MeetingEmailContext?
        do {
            emailContext = try await contextService.fetchEmailContext(for: meeting)
        } catch {
            print("Failed to fetch email context: \(error)")
            emailContext = nil
        }
        
        // Get open action items with these attendees
        let attendeeEmails = Set(meeting.attendees.others.compactMap { $0.email })
        let openItems = actionItemStore.openItems().filter { item in
            guard let assignee = item.assignee else { return false }
            return attendeeEmails.contains(where: { email in
                email.lowercased().contains(assignee.lowercased()) ||
                assignee.lowercased().contains(email.components(separatedBy: "@").first?.lowercased() ?? "")
            })
        }
        
        // Build and send prompt
        let prompt = buildPrompt(
            meeting: meeting,
            emailContext: emailContext,
            openActionItems: openItems
        )
        
        let response = try await callLLM(prompt: prompt)
        
        // Parse response
        let brief = try parseBriefResponse(
            response,
            meetingId: meetingId,
            openActionItems: openItems
        )
        
        // Cache the result
        briefCache[meetingId] = brief
        
        return brief
    }
    
    /// Clear the brief cache
    func clearCache() {
        briefCache.removeAll()
    }
    
    /// Get cached brief if available
    func getCachedBrief(for meeting: BriefingItem) -> MeetingBrief? {
        let meetingId = meetingId(for: meeting)
        return briefCache[meetingId]
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(
        meeting: BriefingItem,
        emailContext: MeetingEmailContext?,
        openActionItems: [ActionItem]
    ) -> String {
        let attendeeNames = meeting.attendees.others.map { $0.displayName }.joined(separator: ", ")
        
        var prompt = """
        Du bist ein Meeting-Vorbereiter. Erstelle ein kurzes Meeting-Brief auf Deutsch.
        
        **Meeting:** \(meeting.title)
        **Zeit:** \(formatMeetingTime(meeting))
        **Teilnehmer:** \(attendeeNames.isEmpty ? "Keine" : attendeeNames)
        
        """
        
        // Add email context
        if let context = emailContext, context.totalEmailCount > 0 {
            prompt += "\n**Letzte Emails mit Teilnehmern:**\n"
            for (email, emails) in context.emailsByAttendee.prefix(3) {
                let name = email.components(separatedBy: "@").first ?? email
                prompt += "- \(name):\n"
                for emailSummary in emails.prefix(3) {
                    prompt += "  • \(emailSummary.subject)"
                    if emailSummary.isUnread {
                        prompt += " (ungelesen)"
                    }
                    prompt += "\n"
                    if let snippet = emailSummary.snippet, !snippet.isEmpty {
                        prompt += "    \(snippet.prefix(100))...\n"
                    }
                }
            }
        }
        
        // Add open action items
        if !openActionItems.isEmpty {
            prompt += "\n**Offene Action Items:**\n"
            for item in openActionItems.prefix(5) {
                prompt += "- \(item.title)"
                if let assignee = item.assignee {
                    prompt += " (→ \(assignee))"
                }
                if let dueDate = item.dueDate {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "de_DE")
                    formatter.dateStyle = .short
                    prompt += " [Fällig: \(formatter.string(from: dueDate))]"
                }
                prompt += "\n"
            }
        }
        
        prompt += """
        
        Erstelle ein Meeting-Brief im folgenden JSON-Format:
        ```json
        {
          "summary": "2-3 Sätze: Was ist der Kontext dieses Meetings?",
          "keyPoints": [
            "Wichtiger Punkt 1 aus den Emails/Kontext",
            "Wichtiger Punkt 2"
          ],
          "suggestedTopics": [
            "Thema, das du ansprechen solltest",
            "Weiteres Thema"
          ]
        }
        ```
        
        **Wichtig:**
        - Halte es kurz und prägnant
        - Konzentriere dich auf actionable Insights
        - Wenn keine Emails vorhanden sind, basiere das Brief auf dem Meeting-Titel
        - Antworte nur mit validem JSON, kein zusätzlicher Text
        """
        
        return prompt
    }
    
    private func formatMeetingTime(_ meeting: BriefingItem) -> String {
        guard let timestamp = meeting.timestamp else {
            return "Unbekannt"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMM 'um' HH:mm"
        return formatter.string(from: timestamp)
    }
    
    private func callLLM(prompt: String) async throws -> String {
        // Get the configured model for summaries (reuse existing feature type)
        let modelProvider = await ModelSelectionService.shared.getModelWithFallback(for: .summaries)
        
        switch modelProvider {
        case .openai(let model):
            return try await callOpenAICompatible(
                model: model,
                prompt: prompt,
                baseURL: "https://api.openai.com/v1",
                getApiKey: { KeychainService.shared.getOpenAIKey() }
            )
            
        case .anthropic(let model):
            return try await callAnthropic(model: model, prompt: prompt)
            
        case .mistral(let model):
            return try await callOpenAICompatible(
                model: model,
                prompt: prompt,
                baseURL: "https://api.mistral.ai/v1",
                getApiKey: { KeychainService.shared.getMistralKey() }
            )
            
        case .ollama(let model):
            return try await callOllama(model: model, prompt: prompt)
            
        case .deepgram, .voxtral:
            // These are transcription-only providers, can't use for briefs
            throw MeetingBriefError.noModelConfigured
        }
    }
    
    private func callOpenAICompatible(
        model: String,
        prompt: String,
        baseURL: String,
        getApiKey: () -> String?
    ) async throws -> String {
        guard let apiKey = getApiKey() else {
            throw MeetingBriefError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeetingBriefError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw MeetingBriefError.invalidResponse
        }
        
        return content
    }
    
    private func callAnthropic(model: String, prompt: String) async throws -> String {
        guard let apiKey = KeychainService.shared.getAnthropicKey() else {
            throw MeetingBriefError.missingAPIKey
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2048,
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeetingBriefError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw MeetingBriefError.invalidResponse
        }
        
        return text
    }
    
    private func callOllama(model: String, prompt: String) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeetingBriefError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String else {
            throw MeetingBriefError.invalidResponse
        }
        
        return responseText
    }
    
    private func parseBriefResponse(
        _ response: String,
        meetingId: String,
        openActionItems: [ActionItem]
    ) throws -> MeetingBrief {
        // Extract JSON from response (might be wrapped in markdown)
        var jsonString = response
        
        if let range = response.range(of: "```json\\s*\\n", options: .regularExpression) {
            jsonString = String(response[range.upperBound...])
            if let endRange = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<endRange.lowerBound])
            }
        } else if let range = response.range(of: "```\\s*\\n", options: .regularExpression) {
            jsonString = String(response[range.upperBound...])
            if let endRange = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<endRange.lowerBound])
            }
        }
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw MeetingBriefError.invalidResponse
        }
        
        struct BriefResponse: Decodable {
            let summary: String
            let keyPoints: [String]?
            let suggestedTopics: [String]?
        }
        
        let parsed = try JSONDecoder().decode(BriefResponse.self, from: data)
        
        return MeetingBrief(
            meetingId: meetingId,
            summary: parsed.summary,
            keyPoints: parsed.keyPoints ?? [],
            suggestedTopics: parsed.suggestedTopics ?? [],
            openActionItems: openActionItems
        )
    }
    
    private func meetingId(for item: BriefingItem) -> String {
        if let eventId = item.metadata["eventId"], !eventId.isEmpty {
            return "google_calendar_\(eventId)"
        }
        let timestamp = item.timestamp?.timeIntervalSince1970 ?? 0
        let titleHash = item.title.hash
        return "\(timestamp)_\(titleHash)"
    }
}

// MARK: - Errors

enum MeetingBriefError: LocalizedError {
    case noModelConfigured
    case missingAPIKey
    case apiError
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noModelConfigured:
            return "Kein LLM-Modell konfiguriert. Bitte in den Einstellungen konfigurieren."
        case .missingAPIKey:
            return "API-Schlüssel fehlt. Bitte in den Einstellungen hinterlegen."
        case .apiError:
            return "Fehler bei der API-Anfrage."
        case .invalidResponse:
            return "Ungültige Antwort vom LLM."
        }
    }
}

// Note: Uses .summaries feature type from ModelSelectionService for LLM selection
