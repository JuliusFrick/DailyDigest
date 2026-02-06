import SwiftUI

// MARK: - Action Item Compact Row

/// Compact row for displaying action items in the dashboard widget
struct ActionItemCompactRow: View {
    let item: ActionItem
    @StateObject var store = ActionItemStore.shared
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Checkbox
            Button {
                store.toggleCompletion(item)
            } label: {
                Image(systemName: item.status.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(statusColor)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            
            // Title
            Text(item.title)
                .font(.tuiMonoTiny)
                .foregroundStyle(item.isOverdue ? .red : .secondary)
                .lineLimit(1)
                .strikethrough(item.status == .completed)
            
            Spacer()
            
            // Due date indicator
            if let dueDate = item.dueDate {
                Text(formatDueDate(dueDate))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(dueDateColor(dueDate))
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 3))
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
        return Color.tuiHover.opacity(0.3)
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
            return "today"
        } else if calendar.isDateInTomorrow(date) {
            return "tomorrow"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date).lowercased()
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date).lowercased()
        }
    }
}

// MARK: - Preview

struct ActionItemCompactRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            ActionItemCompactRow(item: ActionItem(
                title: "Review Q4 report",
                dueDate: Date().addingTimeInterval(3600 * 24),
                meetingId: "test",
                status: .todo
            ))
            ActionItemCompactRow(item: ActionItem(
                title: "Send follow-up email",
                dueDate: Date().addingTimeInterval(-3600),
                meetingId: "test",
                status: .inProgress
            ))
            ActionItemCompactRow(item: ActionItem(
                title: "Update documentation",
                dueDate: Date().addingTimeInterval(3600 * 2),
                meetingId: "test",
                status: .completed
            ))
        }
        .padding()
        .background(Color.tuiBackground)
    }
}
