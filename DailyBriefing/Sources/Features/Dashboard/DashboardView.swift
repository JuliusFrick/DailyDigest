import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDetailLevel: Briefing.DetailLevel = .quick

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                audioPlayerSection
                summarySection
                sourceSectionsView
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Dein Briefing")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(dateText)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter.string(from: Date())
    }

    // MARK: - Audio Player

    private var audioPlayerSection: some View {
        AudioPlayerCard(
            isPlaying: $appState.isPlayingAudio,
            detailLevel: $selectedDetailLevel,
            onPlayToggle: { appState.toggleAudioPlayback() }
        )
    }

    // MARK: - Summary

    private var summarySection: some View {
        Group {
            if let briefing = appState.currentBriefing {
                SummaryCard(summary: briefing.summary)
            } else if appState.isLoadingBriefing {
                LoadingCard()
            } else {
                EmptyStateCard(
                    title: "Noch kein Briefing",
                    message: "Verbinde deine Quellen und erstelle dein erstes Briefing.",
                    actionTitle: "Quellen verbinden",
                    action: { appState.selectedTab = .sources }
                )
            }
        }
    }

    // MARK: - Source Sections

    @ViewBuilder
    private var sourceSectionsView: some View {
        if let briefing = appState.currentBriefing {
            VStack(spacing: 16) {
                ForEach(briefing.sections.sorted { $0.priority > $1.priority }) { section in
                    SourceSectionCard(section: section)
                }
            }
        }
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            Task { await appState.refreshBriefing() }
        } label: {
            if appState.isLoadingBriefing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(appState.isLoadingBriefing)
        .help("Briefing aktualisieren")
    }
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    @Binding var isPlaying: Bool
    @Binding var detailLevel: Briefing.DetailLevel

    var onPlayToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Play Button
            Button(action: onPlayToggle) {
                ZStack {
                    Circle()
                        .fill(.tint.gradient)
                        .frame(width: 56, height: 56)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Briefing")
                    .font(.headline)

                Text(isPlaying ? "Wird abgespielt..." : "Tippe zum Abspielen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Detail Level Picker
            Picker("", selection: $detailLevel) {
                ForEach(Briefing.DetailLevel.allCases, id: \.self) { level in
                    Text(level == .quick ? "Quick" : "Detailed")
                        .tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Zusammenfassung", systemImage: "text.quote")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.body)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Loading Card

struct LoadingCard: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Briefing wird generiert...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Empty State Card

struct EmptyStateCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Source Section Card

struct SourceSectionCard: View {
    let section: BriefingSection
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: section.sourceIcon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 32)

                    Text(section.sourceName)
                        .font(.headline)

                    Spacer()

                    Text("\(section.items.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Items
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(section.items) { item in
                        BriefingItemRow(item: item)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Briefing Item Row

struct BriefingItemRow: View {
    let item: BriefingItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            priorityIndicator

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
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.deepLink {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var priorityIndicator: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
        .frame(width: 500, height: 800)
}
