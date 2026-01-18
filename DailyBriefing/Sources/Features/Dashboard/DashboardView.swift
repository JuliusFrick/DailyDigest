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
        .alert("Fehler", isPresented: $appState.showError) {
            Button("OK") {
                appState.dismissError()
            }
            if case .noSourcesConnected = appState.lastError {
                Button("Quellen verbinden") {
                    appState.dismissError()
                    appState.selectedTab = .sources
                }
            }
            if case .llmNotConfigured = appState.lastError {
                Button("KI konfigurieren") {
                    appState.dismissError()
                    appState.selectedTab = .settings
                }
            }
        } message: {
            if let error = appState.lastError {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText)
                .font(.largeTitle)
                .fontWeight(.bold)

            HStack {
                Text(dateText)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let nextTime = appState.nextScheduledBriefingTime {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Label(nextTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
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
            onPlayToggle: { appState.toggleAudioPlayback() },
            onGenerateBriefing: {
                Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
            },
            isLoading: appState.isLoadingBriefing,
            hasBriefing: appState.currentBriefing != nil
        )
    }

    // MARK: - Summary

    private var summarySection: some View {
        Group {
            if let briefing = appState.currentBriefing {
                SummaryCard(summary: briefing.summary)
            } else if appState.isLoadingBriefing {
                GenerationProgressCard(progress: appState.generationProgress)
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
            Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
        } label: {
            if appState.isLoadingBriefing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(appState.isLoadingBriefing)
        .help("Briefing aktualisieren (\(appState.currentShortcut.displayString))")
        .keyboardShortcut("r", modifiers: .command)
    }
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    @Binding var isPlaying: Bool
    @Binding var detailLevel: Briefing.DetailLevel

    var onPlayToggle: () -> Void
    var onGenerateBriefing: () -> Void
    var isLoading: Bool
    var hasBriefing: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Play Button
            Button(action: hasBriefing ? onPlayToggle : onGenerateBriefing) {
                ZStack {
                    Circle()
                        .fill(.tint.gradient)
                        .frame(width: 56, height: 56)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: hasBriefing ? (isPlaying ? "pause.fill" : "play.fill") : "sparkles")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .offset(x: (hasBriefing && !isPlaying) ? 2 : 0)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            VStack(alignment: .leading, spacing: 4) {
                Text(hasBriefing ? "Audio Briefing" : "Briefing erstellen")
                    .font(.headline)

                Text(statusText)
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
            .disabled(isLoading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var statusText: String {
        if isLoading {
            return "Wird generiert..."
        } else if hasBriefing {
            return isPlaying ? "Wird abgespielt..." : "Tippe zum Abspielen"
        } else {
            return "Tippe zum Generieren"
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

// MARK: - Generation Progress Card

struct GenerationProgressCard: View {
    let progress: GenerationProgress

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                // Outer rotating ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.accentColor.opacity(0.1), .accentColor.opacity(0.8), .accentColor.opacity(0.1)],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(animationPhase * 360))

                // Inner pulsing circle
                Circle()
                    .fill(.tint.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .scaleEffect(1 + sin(animationPhase * .pi * 2) * 0.1)

                // Center icon
                Image(systemName: progressIcon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: true)
            }

            VStack(spacing: 8) {
                Text(progress.displayText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Progress steps indicator
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index <= progressStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progressStep)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }

    private var progressIcon: String {
        switch progress {
        case .idle, .starting:
            return "sparkles"
        case .fetchingSources:
            return "arrow.down.circle"
        case .processingSources:
            return "gearshape.2"
        case .generatingSummary:
            return "brain.head.profile"
        case .finalizing:
            return "checkmark.circle"
        case .completed:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var progressStep: Int {
        switch progress {
        case .idle, .starting: return 0
        case .fetchingSources: return 1
        case .processingSources: return 2
        case .generatingSummary: return 3
        case .finalizing, .completed: return 4
        case .failed: return 0
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
