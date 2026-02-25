import SwiftUI

/// Mail panel: aggregates Gmail and Apple Mail items
struct MailPanelView: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var items: [BriefingItem] = []
    @State private var isLoading = false
    @State private var lastError: Error?
    @State private var selectedItemId: BriefingItem.ID?
    @State private var lastRefresh = Date()
    @State private var showSetupWizard = false

    private var selectedItem: BriefingItem? {
        guard let id = selectedItemId else { return nil }
        return items.first { $0.id == id }
    }

    private var hasMailSource: Bool {
        (connectionManager.gmailSource?.isAuthenticated ?? false) ||
        (connectionManager.appleMailSource?.isAuthenticated ?? false)
    }

    var body: some View {
        NavigationSplitView {
            listContent
        } detail: {
            if let item = selectedItem {
                MailDetailView(item: item)
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
        .sheet(isPresented: $showSetupWizard) {
            IntegrationSetupWizardView()
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            headerView

            if !hasMailSource {
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
            Text("MAIL")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

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
    }

    private var itemsList: some View {
        List(selection: $selectedItemId) {
            ForEach(items) { item in
                MailPanelItemRow(item: item)
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
            Image(systemName: "envelope.fill")
                .font(.system(size: 40))
                .foregroundStyle(GmailSource.brandColor.opacity(0.6))

            Text("Kein Mail-Konto verbunden")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)

            Text("Verbinde Gmail oder Apple Mail in den Einstellungen unter Integrationen.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Setup-Wizard öffnen") {
                showSetupWizard = true
            }
            .buttonStyle(.tuiPrimary)
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
            Text("Keine E-Mails")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailView: some View {
        VStack(spacing: Spacing.md) {
            Text("Wähle eine E-Mail")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadItems() async {
        guard hasMailSource else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        var allItems: [BriefingItem] = []

        if let gmail = connectionManager.gmailSource, gmail.isAuthenticated {
            do {
                let gmailItems = try await gmail.fetchItems(since: since)
                allItems.append(contentsOf: gmailItems)
            } catch {
                lastError = error
                return
            }
        }

        if let appleMail = connectionManager.appleMailSource, appleMail.isAuthenticated {
            do {
                let appleItems = try await appleMail.fetchItems(since: since)
                allItems.append(contentsOf: appleItems)
            } catch {
                if lastError == nil { lastError = error }
            }
        }

        items = allItems.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        if selectedItemId == nil, let first = items.first {
            selectedItemId = first.id
        }
    }
}

// MARK: - Item Row

private struct MailPanelItemRow: View {
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
            Button("An OpenClaw senden") {
                _ = OpenClawChatService.shared.openThread(for: item)
            }
            Button("Im Terminal öffnen") {
                _ = TerminalSessionManager.shared.openSession(for: item)
            }
            if let url = item.deepLink {
                Button("E-Mail öffnen") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Detail View

struct MailDetailView: View {
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
                Button("An OpenClaw senden") {
                    _ = OpenClawChatService.shared.openThread(for: item)
                }
                Button("Im Terminal öffnen") {
                    _ = TerminalSessionManager.shared.openSession(for: item)
                }
                if let url = item.deepLink {
                    Button("E-Mail öffnen") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
