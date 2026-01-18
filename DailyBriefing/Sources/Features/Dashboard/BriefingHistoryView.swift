import SwiftUI

/// View for displaying and managing briefing history
struct BriefingHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var cacheService = BriefingCacheService.shared

    @State private var cachedBriefings: [Briefing] = []
    @State private var selectedBriefing: Briefing?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        Group {
            if selectedBriefing != nil {
                briefingDetailView
            } else {
                historyListView
            }
        }
        .onAppear {
            loadBriefings()
        }
    }

    // MARK: - History List View

    @ViewBuilder
    private var historyListView: some View {
        VStack(spacing: 0) {
            headerSection

            if cachedBriefings.isEmpty {
                emptyStateView
            } else {
                briefingsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefingBackground)
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Briefing-Verlauf")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("\(cachedBriefings.count) Briefings gespeichert")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !cachedBriefings.isEmpty {
                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("Alle löschen", systemImage: "trash")
                }
                .buttonStyle(.subtle)
            }
        }
        .padding()
        .alert("Alle Briefings löschen?", isPresented: $showDeleteAllConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Alle löschen", role: .destructive) {
                deleteAllBriefings()
            }
        } message: {
            Text("Diese Aktion kann nicht rückgängig gemacht werden. Alle \(cachedBriefings.count) gespeicherten Briefings werden gelöscht.")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            Text("Keine Briefings vorhanden")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Generierte Briefings werden hier automatisch gespeichert.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                appState.selectedTab = .dashboard
            } label: {
                Text("Zum Dashboard")
            }
            .buttonStyle(.prominent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var briefingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(cachedBriefings) { briefing in
                    BriefingHistoryRow(briefing: briefing) {
                        selectedBriefing = briefing
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteBriefing(briefing)
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Briefing Detail View

    @ViewBuilder
    private var briefingDetailView: some View {
        VStack(spacing: 0) {
            detailHeaderSection

            if let briefing = selectedBriefing {
                BriefingDetailContent(briefing: briefing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefingBackground)
    }

    @ViewBuilder
    private var detailHeaderSection: some View {
        HStack {
            Button {
                withAnimation(.briefingEaseOut) {
                    selectedBriefing = nil
                }
            } label: {
                Label("Zurück", systemImage: "chevron.left")
            }
            .buttonStyle(.subtle)

            Spacer()

            if let briefing = selectedBriefing {
                Text(briefing.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadBriefings() {
        cachedBriefings = cacheService.loadAll()
    }

    private func deleteBriefing(_ briefing: Briefing) {
        withAnimation(.briefingEaseOut) {
            try? cacheService.delete(id: briefing.id)
            cachedBriefings.removeAll { $0.id == briefing.id }
        }
    }

    private func deleteAllBriefings() {
        withAnimation(.briefingEaseOut) {
            try? cacheService.clearAll()
            cachedBriefings.removeAll()
        }
    }
}

// MARK: - Briefing History Row

struct BriefingHistoryRow: View {
    let briefing: Briefing
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                dateColumn

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(briefing.detailLevel.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())

                        Spacer()

                        Text("\(briefing.sections.count) Quellen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(briefing.summary.prefix(150) + (briefing.summary.count > 150 ? "..." : ""))
                        .font(.body)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .cardStyle(padding: 0)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                try? BriefingCacheService.shared.delete(id: briefing.id)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var dateColumn: some View {
        VStack(spacing: 2) {
            Text(briefing.generatedAt.formatted(.dateTime.day()))
                .font(.title2)
                .fontWeight(.bold)

            Text(briefing.generatedAt.formatted(.dateTime.month(.abbreviated)))
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(briefing.generatedAt.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 50)
    }
}

// MARK: - Briefing Detail Content

struct BriefingDetailContent: View {
    let briefing: Briefing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summarySection
                sourceSectionsView
            }
            .padding()
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Zusammenfassung", systemImage: "text.quote")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(briefing.summary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var sourceSectionsView: some View {
        ForEach(briefing.sections) { section in
            HistorySectionCard(section: section)
        }
    }
}

// MARK: - History Section Card

struct HistorySectionCard: View {
    let section: BriefingSection
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: section.sourceIcon)
                        .font(.title3)
                        .foregroundStyle(.accent)
                        .frame(width: 28)

                    Text(section.sourceName)
                        .font(.headline)

                    Spacer()

                    Text("\(section.items.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    ForEach(section.items) { item in
                        HistoryItemRow(item: item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
}

// MARK: - History Item Row

struct HistoryItemRow: View {
    let item: BriefingItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if item.deepLink != nil {
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.deepLink {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

#Preview {
    BriefingHistoryView()
        .environmentObject(AppState())
        .frame(width: 600, height: 800)
}
