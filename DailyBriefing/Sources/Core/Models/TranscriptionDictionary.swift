import Foundation

/// Custom dictionary entry for transcription context biasing
struct DictionaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var word: String
    var category: Category
    var phonetic: String?  // Optional pronunciation hint
    var notes: String?
    var createdAt: Date
    var usageCount: Int
    
    enum Category: String, Codable, CaseIterable {
        case person = "person"
        case company = "company"
        case product = "product"
        case technical = "technical"
        case abbreviation = "abbreviation"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .person: return "Person"
            case .company: return "Firma"
            case .product: return "Produkt"
            case .technical: return "Fachbegriff"
            case .abbreviation: return "Abkürzung"
            case .other: return "Sonstiges"
            }
        }
        
        var icon: String {
            switch self {
            case .person: return "person"
            case .company: return "building.2"
            case .product: return "shippingbox"
            case .technical: return "wrench.and.screwdriver"
            case .abbreviation: return "textformat.abc"
            case .other: return "tag"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        word: String,
        category: Category = .other,
        phonetic: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        usageCount: Int = 0
    ) {
        self.id = id
        self.word = word
        self.category = category
        self.phonetic = phonetic
        self.notes = notes
        self.createdAt = createdAt
        self.usageCount = usageCount
    }
}

/// Service for managing the transcription dictionary
@MainActor
final class TranscriptionDictionaryService: ObservableObject {
    static let shared = TranscriptionDictionaryService()
    
    @Published private(set) var entries: [DictionaryEntry] = []
    
    private let fileURL: URL
    private let maxContextWords = 100  // Voxtral limit
    
    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to documents directory
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let appDir = documents?.appendingPathComponent("DailyBriefing", isDirectory: true) ?? URL(fileURLWithPath: "/tmp/DailyBriefing")
            fileURL = appDir.appendingPathComponent("transcription_dictionary.json")
            loadEntries()
            return
        }
        
        let appDir = appSupport.appendingPathComponent("DailyBriefing", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        fileURL = appDir.appendingPathComponent("transcription_dictionary.json")
        loadEntries()
    }
    
    // MARK: - CRUD Operations
    
    func addEntry(_ entry: DictionaryEntry) {
        // Avoid duplicates
        guard !entries.contains(where: { $0.word.lowercased() == entry.word.lowercased() }) else {
            return
        }
        
        entries.append(entry)
        saveEntries()
    }
    
    func addWord(_ word: String, category: DictionaryEntry.Category = .other) {
        let entry = DictionaryEntry(word: word, category: category)
        addEntry(entry)
    }
    
    func updateEntry(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        saveEntries()
    }
    
    func deleteEntry(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }
    
    func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        saveEntries()
    }
    
    // MARK: - Query
    
    func entries(for category: DictionaryEntry.Category) -> [DictionaryEntry] {
        entries.filter { $0.category == category }
    }
    
    /// Get context words for Voxtral (max 100, prioritized by usage)
    func contextWords(limit: Int? = nil) -> [String] {
        let maxWords = min(limit ?? maxContextWords, maxContextWords)
        
        return entries
            .sorted { $0.usageCount > $1.usageCount }
            .prefix(maxWords)
            .map { $0.word }
    }
    
    /// Increment usage count for words that appeared in transcription
    func recordUsage(of words: [String]) {
        var updated = false
        
        for word in words {
            if let index = entries.firstIndex(where: { 
                $0.word.lowercased() == word.lowercased() 
            }) {
                entries[index].usageCount += 1
                updated = true
            }
        }
        
        if updated {
            saveEntries()
        }
    }
    
    // MARK: - Import
    
    /// Import names from calendar attendees
    func importFromAttendees(_ attendees: [Attendee]) {
        for attendee in attendees {
            if let name = attendee.name, !name.isEmpty {
                // Skip if already exists
                guard !entries.contains(where: { $0.word.lowercased() == name.lowercased() }) else {
                    continue
                }
                
                let entry = DictionaryEntry(
                    word: name,
                    category: .person,
                    notes: attendee.email
                )
                entries.append(entry)
            }
        }
        saveEntries()
    }
    
    /// Import from a list of strings
    func importWords(_ words: [String], category: DictionaryEntry.Category) {
        for word in words {
            guard !word.isEmpty else { continue }
            guard !entries.contains(where: { $0.word.lowercased() == word.lowercased() }) else {
                continue
            }
            
            let entry = DictionaryEntry(word: word, category: category)
            entries.append(entry)
        }
        saveEntries()
    }
    
    // MARK: - Persistence
    
    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            print("Failed to load dictionary: \(error)")
        }
    }
    
    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save dictionary: \(error)")
        }
    }
}
