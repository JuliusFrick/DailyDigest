import SwiftUI

/// Jira panel: list of issues with detail and filter
struct JiraPanelView: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var items: [BriefingItem] = []
    @State private var isLoading = false
    @State private var lastError: Error?
    @State private var selectedItemId: BriefingItem.ID?
    @State private var lastRefresh = Date()
    @State private var showFilter = false

    private var selectedItem: BriefingItem? {
        guard let id = selectedItemId else { return nil }
        return items.first { $0.id == id }
    }

    private var jiraSource: JiraSource? {
        connectionManager.jiraSource
    }

    var body: some View {
        NavigationSplitView {
            listContent
        } detail: {
            if let item = selectedItem {
                JiraDetailView(item: item)
            } else {
                emptyDetailView
            }
        }
        .background(Color.tuiBackground)
        .task(id: lastRefresh) {
            await loadItems()
        }
        .refreshable {
            lastRefresh = Date()
            await loadItems()
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            headerView

            if jiraSource == nil || !(jiraSource?.isAuthenticated ?? false) {
                notConnectedView
            } else if isLoading && items.isEmpty {
                loadingView
            } else if let error = lastError {
                errorView(error)
            } else if items.isEmpty {
                emptyStateView
            } else {
                itemsList
            }
        }
        .frame(minWidth: 260)
    }

    private var headerView: some View {
        HStack {
            Text("JIRA")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                showFilter = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.tuiMonoTiny)
            }
            .buttonStyle(.plain)

            Button {
                Task { await loadItems() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.tuiMonoTiny)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiPanel.opacity(0.5))
        .sheet(isPresented: $showFilter) {
            if let source = jiraSource {
                JiraFilterView(source: source)
            }
        }
    }

    private var itemsList: some View {
        List(selection: $selectedItemId) {
            ForEach(items) { item in
                JiraPanelItemRow(item: item)
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItemId = item.id
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var notConnectedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(JiraSource.brandColor.opacity(0.6))

            Text("Jira nicht verbunden")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)

            Text("Verbinde Jira in den Einstellungen unter Integrationen.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Lade…")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Text("Keine Issues")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailView: some View {
        VStack(spacing: Spacing.md) {
            Text("Wähle ein Issue")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadItems() async {
        guard let source = jiraSource, source.isAuthenticated else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        do {
            items = try await source.fetchItems(since: since)
            if selectedItemId == nil, let first = items.first {
                selectedItemId = first.id
            }
        } catch {
            lastError = error
        }
    }
}

// MARK: - Item Row

private struct JiraPanelItemRow: View {
    let item: BriefingItem
    @State private var isHovered = false

    private var priorityChar: String {
        switch item.priority {
        case .urgent: return "!"
        case .high: return "•"
        case .medium: return "·"
        case .low: return "·"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .primary
        case .low: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(priorityChar)
                .font(.tuiMonoTiny)
                .foregroundStyle(priorityColor)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.tuiMonoSmall)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .background(isHovered ? Color.tuiHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("An Claude senden") {
                _ = ClaudeChatService.shared.openThread(for: item)
            }
            Button("Im Terminal öffnen") {
                _ = TerminalSessionManager.shared.openSession(for: item)
            }
            if let url = item.deepLink {
                Button("In Jira öffnen") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Detail View

struct JiraDetailView: View {
    let item: BriefingItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(item.title)
                    .font(.tuiMonoSmall)
                    .fontWeight(.medium)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }

                if let assignee = item.metadata["assignee"], !assignee.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Text("Zugewiesen:")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                        Text(assignee)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                }

                if let reporter = item.metadata["reporter"], !reporter.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Text("Reporter:")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                        Text(reporter)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                }

                if let timestamp = item.timestamp {
                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }

                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.lg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
        .background(Color.tuiBackground)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("An Claude senden") {
                    _ = ClaudeChatService.shared.openThread(for: item)
                }
                Button("Im Terminal öffnen") {
                    _ = TerminalSessionManager.shared.openSession(for: item)
                }
                if let url = item.deepLink {
                    Button("In Jira öffnen") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Filter View

struct JiraFilterView: View {
    @ObservedObject var source: JiraSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Inhalt") {
                    Toggle("Mir zugewiesen", isOn: $source.includeAssignedToMe)
                    Toggle("Beobachtet", isOn: $source.includeWatching)
                    Toggle("Erwähnungen", isOn: $source.includeMentions)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Jira Filter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}
