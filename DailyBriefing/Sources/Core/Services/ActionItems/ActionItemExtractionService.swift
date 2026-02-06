import Foundation
import SwiftUI

// MARK: - Action Item Extraction Service

/// Service for extracting action items from meeting transcripts using LLM
@MainActor
final class ActionItemExtractionService: ObservableObject {
    static let shared = ActionItemExtractionService()
    
    @Published var isExtracting = false
    @Published var lastError: Error?
    
    private init() {}
    
    /// Extract action items from transcript using LLM
    func extractActionItems(
        from transcript: String,
        timestamps: [(start: TimeInterval, end: TimeInterval, text: String)]? = nil,
        attendees: [String],
        meetingId: String
    ) async throws -> [ActionItem] {
        isExtracting = true
        defer { isExtracting = false }
        
        do {
            // Get model from ModelSelectionService with fallback
            let modelProvider = await ModelSelectionService.shared.getModelWithFallback(for: .actionItems)
            
            // Build prompt
            let prompt = buildExtractionPrompt(
                transcript: transcript,
                attendees: attendees
            )
            
            // Call LLM based on provider
            let responseText: String
            
            switch modelProvider {
            case .openai(let model):
                responseText = try await callOpenAI(model: model, prompt: prompt)
                
            case .anthropic(let model):
                responseText = try await callAnthropic(model: model, prompt: prompt)
                
            case .ollama(let model):
                responseText = try await callOllama(model: model, prompt: prompt)
                
            default:
                throw ExtractionError.unsupportedModel
            }
            
            // Parse JSON response
            let extractedItems = try parseExtractionResponse(responseText)
            
            // Convert to ActionItem objects with timestamp matching
            let actionItems = try matchTimestampsAndCreateItems(
                extractedItems: extractedItems,
                timestamps: timestamps,
                meetingId: meetingId
            )
            
            return actionItems
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Prompt Building
    
    private func buildExtractionPrompt(transcript: String, attendees: [String]) -> String {
        """
        Analyze this meeting transcript and extract all action items.
        
        For each action item, provide:
        1. **title**: A clear, concise title (what needs to be done)
        2. **description**: Additional context or details (optional)
        3. **assignee**: Who should do it (if mentioned, must be from the attendees list)
        4. **dueDateString**: When it should be done (if mentioned, e.g., "tomorrow", "next week", "2024-12-25")
        5. **timestamp**: Approximate timestamp in the transcript where it was mentioned (in seconds, optional)
        
        **Attendees**: \(attendees.joined(separator: ", "))
        
        **Transcript**:
        \(transcript)
        
        Return your response as a JSON object with this structure:
        ```json
        {
          "actionItems": [
            {
              "title": "Clear title of the action",
              "description": "Optional context",
              "assignee": "Person Name",
              "dueDateString": "tomorrow",
              "timestamp": 120.5
            }
          ]
        }
        ```
        
        **Important**:
        - Only extract explicit action items (tasks that someone needs to complete)
        - If no assignee is mentioned, leave it null
        - If no due date is mentioned, leave it null
        - Be precise and avoid duplicates
        - Return valid JSON only, no additional text
        """
    }
    
    // MARK: - LLM API Calls
    
    private func callOpenAI(model: String, prompt: String) async throws -> String {
        guard let apiKey = KeychainService.shared.get(key: .openAIKey) else {
            throw ExtractionError.missingAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert at extracting action items from meeting transcripts. Return only valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExtractionError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ExtractionError.invalidResponse
        }
        
        return content
    }
    
    private func callAnthropic(model: String, prompt: String) async throws -> String {
        guard let apiKey = KeychainService.shared.get(key: .anthropicKey) else {
            throw ExtractionError.missingAPIKey
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
            "max_tokens": 4096,
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExtractionError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ExtractionError.invalidResponse
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
            "stream": false,
            "format": "json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExtractionError.apiError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String else {
            throw ExtractionError.invalidResponse
        }
        
        return responseText
    }
    
    // MARK: - Response Parsing
    
    private func parseExtractionResponse(_ jsonString: String) throws -> [ActionItemExtractionResponse.ExtractedActionItem] {
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        // Try to extract JSON if wrapped in markdown
        var cleanedJSON = jsonString
        if let range = jsonString.range(of: "```json\\s*\\n", options: .regularExpression) {
            cleanedJSON = String(jsonString[range.upperBound...])
            if let endRange = cleanedJSON.range(of: "```") {
                cleanedJSON = String(cleanedJSON[..<endRange.lowerBound])
            }
        }
        
        let cleanedData = cleanedJSON.data(using: .utf8)!
        let response = try decoder.decode(ActionItemExtractionResponse.self, from: cleanedData)
        
        return response.actionItems
    }
    
    private func matchTimestampsAndCreateItems(
        extractedItems: [ActionItemExtractionResponse.ExtractedActionItem],
        timestamps: [(start: TimeInterval, end: TimeInterval, text: String)]?,
        meetingId: String
    ) throws -> [ActionItem] {
        return extractedItems.map { extracted in
            // Try to parse due date
            let dueDate = parseDueDate(from: extracted.dueDateString)
            
            // Match timestamp in transcript if available
            var matchedTimestamp = extracted.timestamp
            if matchedTimestamp == nil, let timestamps = timestamps {
                matchedTimestamp = findBestTimestamp(
                    for: extracted.title,
                    in: timestamps
                )
            }
            
            return ActionItem(
                title: extracted.title,
                description: extracted.description,
                assignee: extracted.assignee,
                dueDate: dueDate,
                meetingId: meetingId,
                timestamp: matchedTimestamp,
                status: .todo,
                createdAt: Date()
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseDueDate(from string: String?) -> Date? {
        guard let string = string?.lowercased() else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Simple date parsing
        if string.contains("today") || string.contains("heute") {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        } else if string.contains("tomorrow") || string.contains("morgen") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        } else if string.contains("next week") || string.contains("nächste woche") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        } else if string.contains("next month") || string.contains("nächsten monat") {
            return calendar.date(byAdding: .month, value: 1, to: now)
        }
        
        // Try ISO date format
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try standard date formats
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: string) {
            return date
        }
        
        return nil
    }
    
    private func findBestTimestamp(
        for title: String,
        in timestamps: [(start: TimeInterval, end: TimeInterval, text: String)]
    ) -> TimeInterval? {
        let titleWords = Set(title.lowercased().split(separator: " ").map(String.init))
        
        var bestMatch: (timestamp: TimeInterval, score: Int)? = nil
        
        for segment in timestamps {
            let segmentWords = Set(segment.text.lowercased().split(separator: " ").map(String.init))
            let matchCount = titleWords.intersection(segmentWords).count
            
            if matchCount > 0 {
                if bestMatch == nil || matchCount > bestMatch!.score {
                    bestMatch = (segment.start, matchCount)
                }
            }
        }
        
        return bestMatch?.timestamp
    }
}

// MARK: - Errors

enum ExtractionError: LocalizedError {
    case missingAPIKey
    case unsupportedModel
    case apiError
    case invalidResponse
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing. Please configure it in Settings."
        case .unsupportedModel:
            return "The selected model is not supported for action item extraction."
        case .apiError:
            return "Failed to communicate with the API."
        case .invalidResponse:
            return "Received invalid response from the API."
        case .parsingError:
            return "Failed to parse action items from response."
        }
    }
}
