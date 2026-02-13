import SwiftUI

// MARK: - Action Item Row

/// Row component for displaying a single action item
struct ActionItemRow: View {
    let item: ActionItem
    @ObservedObject var store = ActionItemStore.shared
    @State private var showExportMenu = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                store.toggleCompletion(item)
            } label: {
                Image(systemName: item.status.iconName)
                    .font(.title3)
                    .foregroundColor(statusColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.status == .completed ? "Mark as incomplete" : "Mark as complete")
            .accessibilityHint("Toggle the completion status of this action item")
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(item.status == .completed)
                    .foregroundColor(item.status == .completed ? .secondary : .primary)
                
                // Description
                if let description = item.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Metadata
                HStack(spacing: 12) {
                    // Assignee
                    if let assignee = item.assignee {
                        Label(assignee, systemImage: "person")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Due date
                    if let dueDate = item.dueDate {
                        Label(
                            formatDueDate(dueDate),
                            systemImage: "calendar"
                        )
                        .font(.caption2)
                        .foregroundColor(dueDateColor(dueDate))
                    }
                    
                    // Status badge
                    if item.status != .todo {
                        Text(item.status.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.1))
                            .foregroundColor(statusColor)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Timestamp badge
            if let timestamp = item.timestamp {
                Button {
                    // TODO: Jump to recording at timestamp
                    print("Jump to \(formatTimestamp(timestamp))")
                } label: {
                    Text(formatTimestamp(timestamp))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .contextMenu {
            contextMenuContent
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // Status actions
        Menu("Change Status") {
            ForEach(ActionItem.Status.allCases, id: \.self) { status in
                Button {
                    var updated = item
                    updated.status = status
                    if status == .completed {
                        updated.completedAt = Date()
                    } else {
                        updated.completedAt = nil
                    }
                    store.update(updated)
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
                .disabled(item.status == status)
            }
        }
        
        Divider()
        
        // Export
        Button {
            Task {
                try? await store.exportToReminders([item])
            }
        } label: {
            Label("Export to Reminders", systemImage: "arrow.down.doc")
        }
        
        Divider()
        
        // Delete
        Button(role: .destructive) {
            store.delete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch item.status {
        case .todo:
            return item.isOverdue ? .red : .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .gray
        }
    }
    
    private var backgroundColor: Color {
        if item.isOverdue && item.status != .completed {
            return Color.red.opacity(0.05)
        }
        return Color.secondary.opacity(0.05)
    }
    
    private func dueDateColor(_ date: Date) -> Color {
        if date < Date() && item.status != .completed {
            return .red
        }
        
        let hoursUntilDue = date.timeIntervalSinceNow / 3600
        if hoursUntilDue < 24 {
            return .orange
        }
        
        return .secondary
    }
    
    // MARK: - Formatters
    
    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today " + date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow " + date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return date.formatted(.dateTime.weekday().hour().minute())
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
    
    func formatTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Preview

struct ActionItemRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            ActionItemRow(item: ActionItem(
                title: "Review Q4 report",
                description: "Check all numbers and prepare presentation",
                assignee: "John Doe",
                dueDate: Date().addingTimeInterval(3600 * 24),
                meetingId: "test-meeting",
                timestamp: 125.5,
                status: .todo
            ))
            ActionItemRow(item: ActionItem(
                title: "Send follow-up email",
                assignee: "Jane Smith",
                dueDate: Date().addingTimeInterval(-3600),
                meetingId: "test-meeting",
                status: .inProgress
            ))
            ActionItemRow(item: ActionItem(
                title: "Update documentation",
                dueDate: Date().addingTimeInterval(3600 * 48),
                meetingId: "test-meeting",
                status: .completed,
                completedAt: Date()
            ))
        }
        .padding()
    }
}
