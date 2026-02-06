import Foundation
import Combine

// MARK: - Transcript Chunk

/// A chunk of transcript text with timing information and embedding
struct TranscriptChunk: Identifiable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    var embedding: [Float]?
    
    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval, embedding: [Float]? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.embedding = embedding
    }
    
    /// Format time for display (MM:SS)
    func formattedStartTime() -> String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Transcript Embedding Service

/// Service for chunking transcripts and generating embeddings for semantic search
@MainActor
final class TranscriptEmbeddingService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = TranscriptEmbeddingService()
    
    // MARK: - Published Properties
    
    @Published private(set) var isProcessing = false
    @Published private(set) var processingProgress: Double = 0
    
    // MARK: - Private Properties
    
    private let modelService = ModelSelectionService.shared
    private let keychain = KeychainService.shared
    
    // Configuration
    private let chunkSize = 200 // ~200 tokens per chunk
    private let overlapSize = 50 // ~50 tokens overlap
    private let avgCharsPerToken = 4 // Approximation for German text
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Chunk a transcript into overlapping segments with timestamps
    /// - Parameters:
    ///   - transcript: Full transcript text
    ///   - timestamps: Array of (start, end, text) tuples for each segment
    /// - Returns: Array of transcript chunks without embeddings
    func chunkTranscript(
        _ transcript: String,
        timestamps: [(start: TimeInterval, end: TimeInterval, text: String)]
    ) -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        
        // If we have timestamped segments, chunk based on those
        if !timestamps.isEmpty {
            chunks = chunkByTimestamps(timestamps)
        } else {
            // Fallback: chunk by character count without timestamps
            chunks = chunkByCharCount(transcript)
        }
        
        return chunks
    }
    
    /// Generate embeddings for an array of chunks
    /// - Parameter chunks: Chunks to embed
    /// - Returns: Chunks with embeddings populated
    func generateEmbeddings(for chunks: [TranscriptChunk]) async throws -> [TranscriptChunk] {
        guard !chunks.isEmpty else { return [] }
        
        isProcessing = true
        processingProgress = 0
        
        defer {
            isProcessing = false
            processingProgress = 0
        }
        
        // Get selected embedding model
        let selectedModel = modelService.getModel(for: .embeddings)
        
        var embeddedChunks: [TranscriptChunk] = []
        let totalChunks = Double(chunks.count)
        
        for (index, chunk) in chunks.enumerated() {
            let embedding = try await generateEmbedding(for: chunk.text, using: selectedModel)
            
            var updatedChunk = chunk
            updatedChunk.embedding = embedding
            embeddedChunks.append(updatedChunk)
            
            processingProgress = Double(index + 1) / totalChunks
        }
        
        return embeddedChunks
    }
    
    /// Search for relevant chunks using vector similarity
    /// - Parameters:
    ///   - query: Search query
    ///   - chunks: Chunks to search through (must have embeddings)
    ///   - topK: Number of top results to return
    /// - Returns: Array of (chunk, similarity) tuples, sorted by similarity descending
    func search(
        query: String,
        in chunks: [TranscriptChunk],
        topK: Int = 5
    ) async throws -> [(chunk: TranscriptChunk, similarity: Float)] {
        // Get selected embedding model
        let selectedModel = modelService.getModel(for: .embeddings)
        
        // Generate embedding for query
        let queryEmbedding = try await generateEmbedding(for: query, using: selectedModel)
        
        // Filter chunks that have embeddings
        let embeddedChunks = chunks.filter { $0.embedding != nil }
        
        // Calculate cosine similarity for each chunk
        var results: [(chunk: TranscriptChunk, similarity: Float)] = []
        
        for chunk in embeddedChunks {
            guard let chunkEmbedding = chunk.embedding else { continue }
            
            let similarity = cosineSimilarity(queryEmbedding, chunkEmbedding)
            results.append((chunk: chunk, similarity: similarity))
        }
        
        // Sort by similarity descending and take top K
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK))
    }
    
    // MARK: - Private Methods
    
    /// Chunk based on timestamped segments
    private func chunkByTimestamps(
        _ timestamps: [(start: TimeInterval, end: TimeInterval, text: String)]
    ) -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0
        var segmentCount = 0
        
        let targetChars = chunkSize * avgCharsPerToken
        
        for (index, segment) in timestamps.enumerated() {
            // Start new chunk if this is the first segment
            if currentText.isEmpty {
                currentStart = segment.start
            }
            
            currentText += (currentText.isEmpty ? "" : " ") + segment.text
            currentEnd = segment.end
            segmentCount += 1
            
            // Check if we've reached target size or end of transcript
            if currentText.count >= targetChars || index == timestamps.count - 1 {
                let chunk = TranscriptChunk(
                    text: currentText,
                    startTime: currentStart,
                    endTime: currentEnd
                )
                chunks.append(chunk)
                
                // Prepare for next chunk with overlap
                if index < timestamps.count - 1 {
                    let overlapChars = overlapSize * avgCharsPerToken
                    let overlapStart = max(0, segmentCount - (overlapSize / 50)) // Rough estimate
                    
                    // Start next chunk from overlap position
                    if overlapStart < segmentCount {
                        let overlapSegments = timestamps[max(0, index - overlapStart + 1)...index]
                        currentText = overlapSegments.map { $0.text }.joined(separator: " ")
                        currentStart = overlapSegments.first?.start ?? segment.end
                        segmentCount = overlapSegments.count
                    } else {
                        currentText = ""
                        segmentCount = 0
                    }
                } else {
                    currentText = ""
                    segmentCount = 0
                }
            }
        }
        
        return chunks
    }
    
    /// Fallback chunking by character count
    private func chunkByCharCount(_ text: String) -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        
        let targetChars = chunkSize * avgCharsPerToken
        let overlapChars = overlapSize * avgCharsPerToken
        let stepSize = targetChars - overlapChars
        
        var startIndex = text.startIndex
        
        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: targetChars, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = String(text[startIndex..<endIndex])
            
            let chunk = TranscriptChunk(
                text: chunkText,
                startTime: 0,
                endTime: 0
            )
            chunks.append(chunk)
            
            // Move start index forward by step size
            guard let newStart = text.index(startIndex, offsetBy: stepSize, limitedBy: text.endIndex) else {
                break
            }
            startIndex = newStart
        }
        
        return chunks
    }
    
    /// Generate embedding for a single text using the specified model
    private func generateEmbedding(for text: String, using modelProvider: ModelProvider) async throws -> [Float] {
        switch modelProvider {
        case .ollama(let model):
            return try await generateOllamaEmbedding(text: text, model: model)
            
        case .openai(let model):
            return try await generateOpenAIEmbedding(text: text, model: model)
            
        default:
            throw EmbeddingError.unsupportedProvider
        }
    }
    
    /// Generate embedding using Ollama
    private func generateOllamaEmbedding(text: String, model: String) async throws -> [Float] {
        let url = URL(string: "http://localhost:11434/api/embeddings")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": text
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EmbeddingError.networkError
        }
        
        struct OllamaResponse: Codable {
            let embedding: [Float]
        }
        
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.embedding
    }
    
    /// Generate embedding using OpenAI
    private func generateOpenAIEmbedding(text: String, model: String) async throws -> [Float] {
        guard let apiKey = keychain.loadLLMAPIKey(for: "openai"), !apiKey.isEmpty else {
            throw EmbeddingError.missingAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": model,
            "input": text
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EmbeddingError.networkError
        }
        
        struct OpenAIResponse: Codable {
            struct EmbeddingData: Codable {
                let embedding: [Float]
            }
            let data: [EmbeddingData]
        }
        
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let embedding = decoded.data.first?.embedding else {
            throw EmbeddingError.invalidResponse
        }
        
        return embedding
    }
    
    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard magnitude > 0 else { return 0 }
        
        return dotProduct / magnitude
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case unsupportedProvider
    case networkError
    case missingAPIKey
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "Embedding-Provider wird nicht unterstützt"
        case .networkError:
            return "Netzwerkfehler beim Generieren der Embeddings"
        case .missingAPIKey:
            return "API-Key fehlt. Bitte in den Einstellungen konfigurieren."
        case .invalidResponse:
            return "Ungültige Antwort vom Embedding-Service"
        }
    }
}
