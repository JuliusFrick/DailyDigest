import SwiftUI

/// Settings view for managing the transcription dictionary
struct DictionarySettingsView: View {
    @StateObject private var dictionary = TranscriptionDictionaryService.shared
    @State private var selectedCategory: DictionaryEntry.Category?
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var editingEntry: DictionaryEntry?
    
    var filteredEntries: [DictionaryEntry] {
        var result = dictionary.entries
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            result = result.filter { 
                $0.word.localizedCaseInsensitiveContains(searchText) ||
                ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return result.sorted { $0.word < $1.word }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            HStack(spacing: 0) {
                // Sidebar with categories
                sidebar
                    .frame(width: 180)
                
                Divider()
                
                // Main list
                mainList
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            AddDictionaryEntrySheet(dictionary: dictionary)
        }
        .sheet(item: $editingEntry) { entry in
            EditDictionaryEntrySheet(entry: entry, dictionary: dictionary)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "character.book.closed")
            Text("Wörterbuch")
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Suchen...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.tuiHover.opacity(0.5))
            .cornerRadius(6)
            
            // Add button
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.tui)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // All entries
            sidebarItem(title: "Alle", icon: "list.bullet", category: nil)
            
            Divider()
                .padding(.vertical, Spacing.sm)
            
            // Categories
            ForEach(DictionaryEntry.Category.allCases, id: \.self) { category in
                sidebarItem(
                    title: category.displayName,
                    icon: category.icon,
                    category: category
                )
            }
            
            Spacer()
            
            // Stats
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dictionary.entries.count) Einträge")
                    .font(.tuiCaption)
                    .foregroundStyle(.secondary)
                
                Text("Max. 100 für Voxtral")
                    .font(.tuiCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiBackground)
    }
    
    private func sidebarItem(title: String, icon: String, category: DictionaryEntry.Category?) -> some View {
        let isSelected = selectedCategory == category
        let count = category == nil 
            ? dictionary.entries.count 
            : dictionary.entries(for: category!).count
        
        return Button {
            selectedCategory = category
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.tuiCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? Color.tuiAccent.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.xs)
    }
    
    // MARK: - Main List
    
    private var mainList: some View {
        Group {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        DictionaryEntryRow(entry: entry)
                            .contextMenu {
                                Button("Bearbeiten") {
                                    editingEntry = entry
                                }
                                Divider()
                                Button("Löschen", role: .destructive) {
                                    dictionary.deleteEntry(entry)
                                }
                            }
                    }
                    .onDelete { offsets in
                        let entriesToDelete = offsets.map { filteredEntries[$0] }
                        for entry in entriesToDelete {
                            dictionary.deleteEntry(entry)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("Noch keine Einträge")
                .font(.tuiBody)
                .foregroundStyle(.secondary)
            
            Text("Füge Namen, Firmen oder Fachbegriffe hinzu,\ndie korrekt transkribiert werden sollen.")
                .font(.tuiCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Button {
                showAddSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Eintrag hinzufügen")
                }
            }
            .buttonStyle(.tuiPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dictionary Entry Row

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Category icon
            Image(systemName: entry.category.icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            // Word
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.word)
                    .font(.tuiBody)
                    .fontWeight(.medium)
                
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.tuiCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Usage count
            if entry.usageCount > 0 {
                Text("\(entry.usageCount)×")
                    .font(.tuiCaption)
                    .foregroundStyle(.tertiary)
            }
            
            // Category badge
            Text(entry.category.displayName)
                .font(.tuiCaption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tuiHover)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Entry Sheet

struct AddDictionaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let dictionary: TranscriptionDictionaryService
    
    @State private var word = ""
    @State private var category: DictionaryEntry.Category = .other
    @State private var phonetic = ""
    @State private var notes = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Neuer Eintrag")
                    .font(.tuiMonoSmall)
                    .fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                TextField("Wort / Name", text: $word)
                
                Picker("Kategorie", selection: $category) {
                    ForEach(DictionaryEntry.Category.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.icon)
                            .tag(cat)
                    }
                }
                
                TextField("Aussprache (optional)", text: $phonetic)
                
                TextField("Notizen (optional)", text: $notes)
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.tui)
                
                Spacer()
                
                Button("Hinzufügen") {
                    let entry = DictionaryEntry(
                        word: word,
                        category: category,
                        phonetic: phonetic.isEmpty ? nil : phonetic,
                        notes: notes.isEmpty ? nil : notes
                    )
                    dictionary.addEntry(entry)
                    dismiss()
                }
                .buttonStyle(.tuiPrimary)
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Edit Entry Sheet

struct EditDictionaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DictionaryEntry
    let dictionary: TranscriptionDictionaryService
    
    @State private var word: String
    @State private var category: DictionaryEntry.Category
    @State private var phonetic: String
    @State private var notes: String
    
    init(entry: DictionaryEntry, dictionary: TranscriptionDictionaryService) {
        self.entry = entry
        self.dictionary = dictionary
        _word = State(initialValue: entry.word)
        _category = State(initialValue: entry.category)
        _phonetic = State(initialValue: entry.phonetic ?? "")
        _notes = State(initialValue: entry.notes ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Eintrag bearbeiten")
                    .font(.tuiMonoSmall)
                    .fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                TextField("Wort / Name", text: $word)
                
                Picker("Kategorie", selection: $category) {
                    ForEach(DictionaryEntry.Category.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.icon)
                            .tag(cat)
                    }
                }
                
                TextField("Aussprache (optional)", text: $phonetic)
                
                TextField("Notizen (optional)", text: $notes)
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.tui)
                
                Spacer()
                
                Button("Speichern") {
                    var updated = entry
                    updated.word = word
                    updated.category = category
                    updated.phonetic = phonetic.isEmpty ? nil : phonetic
                    updated.notes = notes.isEmpty ? nil : notes
                    dictionary.updateEntry(updated)
                    dismiss()
                }
                .buttonStyle(.tuiPrimary)
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Preview

#Preview {
    DictionarySettingsView()
}
