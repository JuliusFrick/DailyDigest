import SwiftUI

// MARK: - Action Item Detail View

/// Detail view for viewing and editing an action item
struct ActionItemDetailView: View {
    @Binding var item: ActionItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = ActionItemStore.shared
    
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedAssignee: String = ""
    @State private var editedDueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var editedStatus: ActionItem.Status = .todo
    
    var body: some View {
        Form {
            // Title Section
            Section("Title") {
                TextField("Title", text: $editedTitle)
                    .textFieldStyle(.plain)
            }
            
            // Description Section
            Section("Description") {
                TextEditor(text: $editedDescription)
                    .frame(minHeight: 80)
            }
            
            // Assignee Section
            Section("Assignee") {
                TextField("Assignee (optional)", text: $editedAssignee)
                    .textFieldStyle(.plain)
            }
            
            // Due Date Section
            Section("Due Date") {
                Toggle("Has Due Date", isOn: $hasDueDate)
                
                if hasDueDate {
                    DatePicker(
                        "Due Date",
                        selection: $editedDueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            
            // Status Section
            Section("Status") {
                Picker("Status", selection: $editedStatus) {
                    ForEach(ActionItem.Status.allCases, id: \.self) { status in
                        Label(status.displayName, systemImage: status.iconName)
                            .tag(status)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Metadata Section
            Section("Info") {
                LabeledContent("Created") {
                    Text(item.createdAt, style: .date)
                }
                
                if let completedAt = item.completedAt {
                    LabeledContent("Completed") {
                        Text(completedAt, style: .date)
                    }
                }
                
                if let timestamp = item.timestamp {
                    LabeledContent("Meeting Timestamp") {
                        Text(formatTimestamp(timestamp))
                    }
                }
                
                LabeledContent("Meeting ID") {
                    Text(item.meetingId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Delete Section
            Section {
                Button(role: .destructive) {
                    Task {
                        await store.delete(item)
                        dismiss()
                    }
                } label: {
                    Label("Delete Action Item", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Action Item")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .disabled(editedTitle.isEmpty)
            }
        }
        .onAppear {
            loadItemData()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadItemData() {
        editedTitle = item.title
        editedDescription = item.description ?? ""
        editedAssignee = item.assignee ?? ""
        editedStatus = item.status
        
        if let dueDate = item.dueDate {
            hasDueDate = true
            editedDueDate = dueDate
        } else {
            hasDueDate = false
            editedDueDate = Date().addingTimeInterval(86400) // Default: tomorrow
        }
    }
    
    private func saveChanges() {
        item.title = editedTitle
        item.description = editedDescription.isEmpty ? nil : editedDescription
        item.assignee = editedAssignee.isEmpty ? nil : editedAssignee
        item.dueDate = hasDueDate ? editedDueDate : nil
        
        // Handle status change
        if editedStatus != item.status {
            if editedStatus == .completed && item.completedAt == nil {
                item.completedAt = Date()
            } else if editedStatus != .completed {
                item.completedAt = nil
            }
            item.status = editedStatus
        }
        
        Task {
            await store.update(item)
        }
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

struct ActionItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ActionItemDetailView(item: .constant(ActionItem(
                title: "Review quarterly report",
                description: "Go through the Q4 numbers and prepare summary",
                assignee: "John",
                dueDate: Date().addingTimeInterval(86400 * 3),
                meetingId: "meeting-123",
                timestamp: 125.5,
                status: .inProgress
            )))
        }
    }
}
