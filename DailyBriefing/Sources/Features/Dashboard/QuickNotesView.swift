import SwiftUI

/// Quick notes input view for post-meeting note capture
struct QuickNotesView: View {
    let meetingId: String
    let meetingTitle: String
    let onDismiss: () -> Void
    
    @State private var notesText: String = ""
    @State private var isExtracting = false
    @State private var extractedItems: [ActionItem] = []
    @State private var showExtractedItems = false
    @State private var errorMessage: String?
    
    @ObservedObject var notesService = MeetingNotesService.shared
    @ObservedObject var extractionService = ActionItemExtractionService.shared
    @ObservedObject var actionItemStore = ActionItemStore.shared
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Notes input
                    notesInputSection
                    
                    // Error message
                    if let error = errorMessage {
                        errorView(error)
                    }
                    
                    // Extracted action items
                    if showExtractedItems && !extractedItems.isEmpty {
                        extractedItemsSection
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer with actions
            footer
        }
        .frame(width: 500, height: 450)
        .background(.regularMaterial)
        .onAppear {
            // Load existing notes if any
            if let existingNotes = notesService.getNotes(meetingId: meetingId) {
                notesText = existingNotes
            }
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting-Notizen")
                    .font(.headline)
                Text(meetingTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Notes Input
    
    private var notesInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notizen", systemImage: "note.text")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextEditor(text: $notesText)
                .font(.body)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .focused($isTextFieldFocused)
            
            Text("Schreibe Stichpunkte — Action Items werden automatisch erkannt")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Extracted Items
    
    private var extractedItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Erkannte Action Items", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                ForEach(extractedItems) { item in
                    extractedItemRow(item)
                }
            }
        }
    }
    
    private func extractedItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.top, 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                
                if let assignee = item.assignee {
                    Text("→ \(assignee)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let dueDate = item.dueDate {
                    Text("Fällig: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Spacer()
            
            // Extract action items
            Button {
                Task { await extractActionItems() }
            } label: {
                if isExtracting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Label("Action Items erkennen", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderless)
            .disabled(notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting)
            
            // Save button
            Button {
                Task { await saveNotes() }
            } label: {
                Text("Speichern")
            }
            .buttonStyle(.borderedProminent)
            .disabled(notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func extractActionItems() async {
        isExtracting = true
        errorMessage = nil
        
        do {
            let items = try await extractionService.extractActionItems(
                from: notesText,
                timestamps: nil,
                attendees: [], // Could pass meeting attendees here
                meetingId: meetingId
            )
            
            extractedItems = items
            showExtractedItems = true
        } catch {
            errorMessage = "Fehler beim Erkennen: \(error.localizedDescription)"
        }
        
        isExtracting = false
    }
    
    private func saveNotes() async {
        // Save notes
        notesService.saveNotes(meetingId: meetingId, notes: notesText)
        
        // Save extracted action items if any
        if !extractedItems.isEmpty {
            actionItemStore.add(extractedItems)
        }
        
        onDismiss()
    }
}

// MARK: - Preview

struct QuickNotesView_Previews: PreviewProvider {
    static var previews: some View {
        QuickNotesView(
            meetingId: "preview-123",
            meetingTitle: "Weekly Team Standup",
            onDismiss: {}
        )
    }
}
