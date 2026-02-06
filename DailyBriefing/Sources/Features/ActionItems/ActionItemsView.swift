import SwiftUI

// MARK: - Action Items View

/// Main view for displaying and managing action items
struct ActionItemsView: View {
    @StateObject var store = ActionItemStore.shared
    @StateObject var notificationService = ActionItemNotificationService.shared
    @State private var filter: Filter = .all
    @State private var showExportMenu = false
    @State private var showError: String?
    @State private var selectedItem: ActionItem?
    @State private var showingDetail = false
    
    enum Filter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case completed = "Completed"
        case overdue = "Overdue"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .open: return "circle"
            case .completed: return "checkmark.circle.fill"
            case .overdue: return "exclamationmark.circle.fill"
            }
        }
    }
    
    var filteredItems: [ActionItem] {
        switch filter {
        case .all:
            return store.items.sorted { $0.createdAt > $1.createdAt }
        case .open:
            return store.openItems()
        case .completed:
            return store.completedItems()
        case .overdue:
            return store.overdueItems()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            statsBar
            
            Divider()
            
            // Filter picker
            filterPicker
            
            Divider()
            
            // Items list
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            ActionItemRow(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                    showingDetail = true
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Action Items")
        .toolbar {
            ToolbarItemGroup {
                // Export button
                Menu {
                    Button {
                        Task { await exportToReminders() }
                    } label: {
                        Label("Export to Reminders", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        store.deleteCompleted()
                    } label: {
                        Label("Delete Completed", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ActionItemDetailView(item: binding(for: item))
            }
        }
        .alert("Error", isPresented: Binding(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }
    
    // MARK: - Stats Bar
    
    private var statsBar: some View {
        HStack(spacing: 16) {
            StatBadge(
                label: "Total",
                count: store.totalItems,
                color: .primary
            )
            
            StatBadge(
                label: "Open",
                count: store.openItemsCount,
                color: .blue
            )
            
            StatBadge(
                label: "Completed",
                count: store.completedItemsCount,
                color: .green
            )
            
            if store.overdueItemsCount > 0 {
                StatBadge(
                    label: "Overdue",
                    count: store.overdueItemsCount,
                    color: .red
                )
            }
            
            Spacer()
            
            // Completion rate
            if store.totalItems > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Completion")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(store.completionRate() * 100))%")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Filter Picker
    
    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(Filter.allCases, id: \.self) { filter in
                Label(filter.rawValue, systemImage: filter.icon)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: filter == .completed ? "checkmark.circle" : "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(emptyStateMessage)
                .font(.headline)
                .foregroundColor(.secondary)
            
            if filter != .all {
                Button("Show All") {
                    filter = .all
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateMessage: String {
        switch filter {
        case .all:
            return "No action items yet"
        case .open:
            return "No open action items"
        case .completed:
            return "No completed items"
        case .overdue:
            return "No overdue items"
        }
    }
    
    // MARK: - Helpers
    
    private func binding(for item: ActionItem) -> Binding<ActionItem> {
        Binding(
            get: { store.items.first { $0.id == item.id } ?? item },
            set: { store.update($0) }
        )
    }
    
    private func exportToReminders() async {
        do {
            let itemsToExport = filter == .all ? store.openItems() : filteredItems
            try await store.exportToReminders(itemsToExport)
            showError = nil
        } catch {
            showError = error.localizedDescription
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Preview

struct ActionItemsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ActionItemsView()
        }
    }
}
