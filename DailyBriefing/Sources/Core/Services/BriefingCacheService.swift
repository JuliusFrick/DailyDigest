import Foundation

/// Service responsible for caching briefings locally for offline access
/// Stores briefings as JSON files in the Application Support directory
@MainActor
final class BriefingCacheService: ObservableObject {

    // MARK: - Singleton

    static let shared = BriefingCacheService()

    // MARK: - Published Properties

    @Published private(set) var cachedBriefingCount: Int = 0
    @Published private(set) var cacheSize: UInt64 = 0

    // MARK: - Configuration

    /// Maximum number of briefings to keep in cache (default: 50)
    var maxCacheSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: maxCacheSizeKey)
            return stored > 0 ? stored : 50
        }
        set {
            UserDefaults.standard.set(newValue, forKey: maxCacheSizeKey)
        }
    }

    // MARK: - Private Properties

    private let maxCacheSizeKey = "briefing_cache_max_size"
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Directory where briefings are cached
    private var cacheDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDir = appSupport.appendingPathComponent("DailyBriefing/BriefingCache", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        return cacheDir
    }

    // MARK: - Initialization

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        updateCacheStats()
    }

    // MARK: - Public API

    /// Save a briefing to the cache
    /// - Parameter briefing: The briefing to cache
    func save(briefing: Briefing) throws {
        guard let cacheDir = cacheDirectory else {
            throw BriefingCacheError.cacheDirectoryUnavailable
        }

        let fileName = "\(briefing.id.uuidString).json"
        let fileURL = cacheDir.appendingPathComponent(fileName)

        let data = try encoder.encode(briefing)
        try data.write(to: fileURL, options: .atomic)

        // Enforce cache size limit after saving
        enforceMaxCacheSize()
        updateCacheStats()
    }

    /// Load the most recently generated briefing
    /// - Returns: The latest briefing or nil if cache is empty
    func loadLatest() -> Briefing? {
        let briefings = loadAllMetadata()
        return briefings.first.flatMap { load(id: $0.id) }
    }

    /// Load all cached briefings sorted by generation date (newest first)
    /// - Returns: Array of all cached briefings
    func loadAll() -> [Briefing] {
        guard let cacheDir = cacheDirectory else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }

            var briefings: [Briefing] = []
            for file in files {
                if let data = try? Data(contentsOf: file),
                   let briefing = try? decoder.decode(Briefing.self, from: data) {
                    briefings.append(briefing)
                }
            }

            // Sort by generation date, newest first
            return briefings.sorted { $0.generatedAt > $1.generatedAt }
        } catch {
            return []
        }
    }

    /// Delete a specific briefing from the cache
    /// - Parameter id: The UUID of the briefing to delete
    func delete(id: UUID) throws {
        guard let cacheDir = cacheDirectory else {
            throw BriefingCacheError.cacheDirectoryUnavailable
        }

        let fileName = "\(id.uuidString).json"
        let fileURL = cacheDir.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw BriefingCacheError.briefingNotFound(id)
        }

        try fileManager.removeItem(at: fileURL)
        updateCacheStats()
    }

    /// Clear all cached briefings
    func clearAll() throws {
        guard let cacheDir = cacheDirectory else {
            throw BriefingCacheError.cacheDirectoryUnavailable
        }

        let files = try fileManager.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        for file in files {
            try fileManager.removeItem(at: file)
        }

        updateCacheStats()
    }

    /// Load a specific briefing by ID
    /// - Parameter id: The UUID of the briefing to load
    /// - Returns: The briefing or nil if not found
    func load(id: UUID) -> Briefing? {
        guard let cacheDir = cacheDirectory else {
            return nil
        }

        let fileName = "\(id.uuidString).json"
        let fileURL = cacheDir.appendingPathComponent(fileName)

        guard let data = try? Data(contentsOf: fileURL),
              let briefing = try? decoder.decode(Briefing.self, from: data) else {
            return nil
        }

        return briefing
    }

    // MARK: - Private Methods

    /// Load metadata for all cached briefings (lightweight, for sorting/filtering)
    private func loadAllMetadata() -> [(id: UUID, generatedAt: Date)] {
        guard let cacheDir = cacheDirectory else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.creationDateKey]
            ).filter { $0.pathExtension == "json" }

            var metadata: [(id: UUID, generatedAt: Date)] = []

            for file in files {
                // Extract UUID from filename
                let fileName = file.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: fileName) else { continue }

                // Try to read just the generation date
                if let data = try? Data(contentsOf: file),
                   let briefing = try? decoder.decode(Briefing.self, from: data) {
                    metadata.append((id: id, generatedAt: briefing.generatedAt))
                }
            }

            // Sort by generation date, newest first
            return metadata.sorted { $0.generatedAt > $1.generatedAt }
        } catch {
            return []
        }
    }

    /// Enforce maximum cache size by deleting oldest briefings
    private func enforceMaxCacheSize() {
        let metadata = loadAllMetadata()

        guard metadata.count > maxCacheSize else { return }

        // Delete oldest briefings beyond the limit
        let toDelete = metadata.suffix(from: maxCacheSize)
        for item in toDelete {
            try? delete(id: item.id)
        }
    }

    /// Update cache statistics
    private func updateCacheStats() {
        guard let cacheDir = cacheDirectory else {
            cachedBriefingCount = 0
            cacheSize = 0
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.fileSizeKey]
            ).filter { $0.pathExtension == "json" }

            cachedBriefingCount = files.count

            var totalSize: UInt64 = 0
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let size = attributes[.size] as? UInt64 {
                    totalSize += size
                }
            }
            cacheSize = totalSize
        } catch {
            cachedBriefingCount = 0
            cacheSize = 0
        }
    }
}

// MARK: - Cache Errors

/// Errors that can occur during cache operations
enum BriefingCacheError: LocalizedError {
    case cacheDirectoryUnavailable
    case briefingNotFound(UUID)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .cacheDirectoryUnavailable:
            return "Cache-Verzeichnis nicht verfügbar"
        case .briefingNotFound(let id):
            return "Briefing nicht gefunden: \(id)"
        case .encodingFailed:
            return "Fehler beim Speichern des Briefings"
        case .decodingFailed:
            return "Fehler beim Laden des Briefings"
        }
    }
}
