import Foundation
import Combine

/// Simple in-memory vector store for transcript chunks
/// Future: Migrate to CoreData or SQLite for persistence
final class VectorStore: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = VectorStore()
    
    // MARK: - Private Properties
    
    private var storage: [String: [TranscriptChunk]] = [:]
    private let queue = DispatchQueue(label: "com.dailydigest.vectorstore", attributes: .concurrent)
    
    // Persistent storage
    private let userDefaults = UserDefaults.standard
    private let storageKeyPrefix = "vectorstore_"
    
    // MARK: - Initialization
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Store chunks for a meeting
    /// - Parameters:
    ///   - chunks: Chunks to store (with embeddings)
    ///   - meetingId: Unique meeting identifier
    func store(chunks: [TranscriptChunk], for meetingId: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.storage[meetingId] = chunks
            self?.saveToDisk(meetingId: meetingId, chunks: chunks)
        }
    }
    
    /// Load chunks for a meeting
    /// - Parameter meetingId: Unique meeting identifier
    /// - Returns: Stored chunks, or nil if not found
    func load(for meetingId: String) -> [TranscriptChunk]? {
        return queue.sync {
            // Check in-memory first
            if let chunks = storage[meetingId] {
                return chunks
            }
            
            // Try to load from disk
            if let chunks = loadFromDisk(meetingId: meetingId) {
                storage[meetingId] = chunks
                return chunks
            }
            
            return nil
        }
    }
    
    /// Search for relevant chunks in a meeting's transcript
    /// - Parameters:
    ///   - query: Search query
    ///   - meetingId: Unique meeting identifier
    ///   - topK: Number of top results to return
    /// - Returns: Array of (chunk, similarity) tuples
    func search(
        query: String,
        meetingId: String,
        topK: Int
    ) async throws -> [(chunk: TranscriptChunk, similarity: Float)] {
        guard let chunks = load(for: meetingId) else {
            throw VectorStoreError.meetingNotFound
        }
        
        let embeddingService = await TranscriptEmbeddingService.shared
        return try await embeddingService.search(query: query, in: chunks, topK: topK)
    }
    
    /// Delete stored chunks for a meeting
    /// - Parameter meetingId: Unique meeting identifier
    func delete(for meetingId: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.storage.removeValue(forKey: meetingId)
            self?.deleteFromDisk(meetingId: meetingId)
        }
    }
    
    /// Clear all stored chunks (use with caution)
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let keys = self.storage.keys
            self.storage.removeAll()
            
            // Remove from disk
            for key in keys {
                self.deleteFromDisk(meetingId: key)
            }
        }
    }
    
    /// Get all stored meeting IDs
    func storedMeetingIds() -> [String] {
        return queue.sync {
            Array(storage.keys)
        }
    }
    
    /// Check if chunks exist for a meeting
    func hasChunks(for meetingId: String) -> Bool {
        return queue.sync {
            storage[meetingId] != nil || userDefaults.data(forKey: storageKeyPrefix + meetingId) != nil
        }
    }
    
    // MARK: - Persistence
    
    private func saveToDisk(meetingId: String, chunks: [TranscriptChunk]) {
        do {
            let data = try JSONEncoder().encode(chunks)
            let key = storageKeyPrefix + meetingId
            userDefaults.set(data, forKey: key)
        } catch {
            print("❌ Failed to save chunks to disk for \(meetingId): \(error)")
        }
    }
    
    private func loadFromDisk(meetingId: String) -> [TranscriptChunk]? {
        let key = storageKeyPrefix + meetingId
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode([TranscriptChunk].self, from: data)
        } catch {
            print("❌ Failed to load chunks from disk for \(meetingId): \(error)")
            return nil
        }
    }
    
    private func deleteFromDisk(meetingId: String) {
        let key = storageKeyPrefix + meetingId
        userDefaults.removeObject(forKey: key)
    }
    
    private func loadFromDisk() {
        // Load all stored chunks on initialization
        let keys = userDefaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(storageKeyPrefix) }
        
        for key in keys {
            let meetingId = String(key.dropFirst(storageKeyPrefix.count))
            if let chunks = loadFromDisk(meetingId: meetingId) {
                storage[meetingId] = chunks
            }
        }
    }
}

// MARK: - Errors

enum VectorStoreError: LocalizedError {
    case meetingNotFound
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .meetingNotFound:
            return "Keine Chunks für dieses Meeting gefunden"
        case .storageError:
            return "Fehler beim Speichern der Chunks"
        }
    }
}
