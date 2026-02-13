import SwiftUI

// MARK: - TUI History View

struct TUIHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var cacheService = BriefingCacheService.shared
    @StateObject private var errorService = ErrorDisplayService.shared

    @State private var cachedBriefings: [Briefing] = []
    @State private var selectedBriefing: Briefing?
    @State private var selectedIndex: Int = 0
    @State private var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: List
            listPanel
                .frame(width: 200)

            Rectangle()
                .fill(Color.tuiBorder)
                .frame(width: 1)

            // Right: Detail
            detailPanel
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            loadBriefings()
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
                selectedBriefing = cachedBriefings[safe: selectedIndex]
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < cachedBriefings.count - 1 {
                selectedIndex += 1
                selectedBriefing = cachedBriefings[safe: selectedIndex]
            }
            return .handled
        }
        .onKeyPress(.delete) {
            if let briefing = selectedBriefing {
                deleteBriefing(briefing)
            }
            return .handled
        }
    }

    // MARK: - List Panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("BRIEFINGS")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Text("[\(cachedBriefings.count)]")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)

                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)
            }

            // List
            if cachedBriefings.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Text("no history")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(cachedBriefings.enumerated()), id: \.element.id) { index, briefing in
                            TUIHistoryRow(
                                briefing: briefing,
                                isSelected: selectedBriefing?.id == briefing.id,
                                onSelect: {
                                    withAnimation(.tuiFast) {
                                        selectedBriefing = briefing
                                        selectedIndex = index
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // Footer with hints
            HStack {
                Text("↑↓ navigate")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)

                Spacer()

                Text("⌫ delete")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }
            .padding(Spacing.sm)
            .background(Color.tuiBackground)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        VStack(spacing: 0) {
            if let briefing = selectedBriefing {
                // Header
                HStack {
                    Text(briefing.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.tuiMonoSmall)
                        .fontWeight(.medium)

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text(briefing.detailLevel.displayName.lowercased())
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        deleteBriefing(briefing)
                    } label: {
                        Text("delete")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.tuiGhost)
                }
                .padding(Spacing.md)
                .background(Color.tuiBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 1)
                }

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Summary
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SUMMARY")
                                .font(.tuiMonoTiny)
                                .fontWeight(.bold)
                                .foregroundStyle(.tertiary)

                            Text(briefing.summary)
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }

                        // Sections
                        ForEach(briefing.sections) { section in
                            TUIHistorySectionView(section: section)
                        }
                    }
                    .padding(Spacing.md)
                }
            } else {
                VStack(spacing: Spacing.md) {
                    Text("─────────────────")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.quaternary)

                    Text("select a briefing")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func loadBriefings() {
        cachedBriefings = cacheService.loadAll()
        if let first = cachedBriefings.first {
            selectedBriefing = first
            selectedIndex = 0
        }
    }

    private func deleteBriefing(_ briefing: Briefing) {
        withAnimation(.tuiFast) {
            try? cacheService.delete(id: briefing.id)
            cachedBriefings.removeAll { $0.id == briefing.id }

            if selectedBriefing?.id == briefing.id {
                selectedBriefing = cachedBriefings[safe: selectedIndex] ?? cachedBriefings.first
            }
        }
    }
}

// MARK: - TUI History Row

struct TUIHistoryRow: View {
    let briefing: Briefing
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Text(isSelected ? "▶" : " ")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(briefing.generatedAt.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.tuiMonoSmall)
                        .fontWeight(isSelected ? .medium : .regular)

                    Text(briefing.generatedAt.formatted(.dateTime.hour().minute()))
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("[\(briefing.sections.count)]")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.tuiHighlight : (isHovered ? Color.tuiHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.tuiFast, value: isHovered)
        .animation(.tuiFast, value: isSelected)
    }
}

// MARK: - TUI History Section View

struct TUIHistorySectionView: View {
    let section: BriefingSection
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(.tuiSnappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(isExpanded ? "▼" : "▶")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)

                    Text(section.sourceName.uppercased())
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)

                    Text("[\(section.items.count)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(section.items) { item in
                        HStack(spacing: Spacing.sm) {
                            Text("·")
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.tertiary)

                            Text(item.title)
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, Spacing.md)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Legacy View (for compatibility)

struct BriefingHistoryView: View {
    var body: some View {
        TUIHistoryView()
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
