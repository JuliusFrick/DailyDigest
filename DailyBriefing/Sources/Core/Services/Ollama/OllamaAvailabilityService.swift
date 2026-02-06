import Foundation

/// Service for checking Ollama availability and models
final class OllamaAvailabilityService {
    static let shared = OllamaAvailabilityService()
    
    private let baseURL = "http://localhost:11434"
    
    private init() {}
    
    /// Check if a specific model is available in Ollama
    func isModelAvailable(_ model: String) async -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/api/tags") else {
                return false
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check if response is successful
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            let decoder = JSONDecoder()
            let tagsResponse = try decoder.decode(OllamaTagsResponse.self, from: data)
            
            // Check if any model name contains the requested model
            return tagsResponse.models.contains { $0.name.contains(model) }
        } catch {
            // If Ollama is not running or any error occurs, return false
            return false
        }
    }
    
    /// Check if Ollama service is running
    func isRunning() async -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/api/tags") else {
                return false
            }
            
            let (_, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Response Models
    
    struct OllamaTagsResponse: Codable {
        let models: [OllamaModel]
    }
    
    struct OllamaModel: Codable {
        let name: String
        let modified_at: String?
        let size: Int?
        
        enum CodingKeys: String, CodingKey {
            case name
            case modified_at
            case size
        }
    }
}
