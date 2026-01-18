import SwiftUI

// MARK: - TUI Dashboard View

struct TUIDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @State private var selectedDetailLevel: Briefing.DetailLevel = .quick
    @State private var selectedSection: Int = 0
    @State private var showChat: Bool = false

    var body: some View {
        mainContent
            .background(Color.tuiBackground)
            .modifier(KeyboardHandlersModifier(
                appState: appState,
                selectedDetailLevel: $selectedDetailLevel,
                selectedSection: $selectedSection
            ))
            .onKeyPress("c", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    showChat.toggle()
                }
                return .handled
            }
    }

    private var mainContent: some View {
        HStack(spacing: 1) {
            // Left panel - Controls & Summary
            leftPanel
                .frame(width: 280)

            // Divider
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(width: 1)

            // Center panel - Sections
            rightPanel
                .frame(maxWidth: .infinity)

            // Chat panel (conditional)
            if showChat {
                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(width: 1)

                chatPanel
                    .frame(width: 320)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        BriefingChatView()
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Date header
            dateHeader
                .padding(Spacing.md)

            Divider()
                .background(Color.tuiBorder)

            // Controls
            controlsSection
                .padding(Spacing.md)

            Divider()
                .background(Color.tuiBorder)

            // Summary
            summarySection
                .frame(maxHeight: .infinity)
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(dateText.uppercased())
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            if let nextTime = appState.nextScheduledBriefingTime {
                Text("next: \(nextTime)")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, d. MMM"
        return formatter.string(from: Date())
    }

    private var controlsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Generate/Play button
            Button {
                if appState.currentBriefing != nil {
                    appState.toggleAudioPlayback()
                } else {
                    Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                }
            } label: {
                HStack {
                    if appState.isLoadingBriefing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Text(appState.currentBriefing != nil ? (appState.isPlayingAudio ? "⏸" : "▶") : "+")
                            .font(.tuiMonoSmall)
                    }

                    Text(buttonLabel)
                        .font(.tuiMonoSmall)

                    Spacer()

                    KeyBadge(key: appState.currentBriefing != nil ? "SPC" : "⌘R")
                }
            }
            .buttonStyle(.tuiPrimary)
            .disabled(appState.isLoadingBriefing)

            // Detail level picker
            HStack(spacing: 2) {
                ForEach(Briefing.DetailLevel.allCases, id: \.self) { level in
                    DetailLevelButton(
                        level: level,
                        isSelected: selectedDetailLevel == level
                    ) {
                        withAnimation(.tuiSnappy) {
                            selectedDetailLevel = level
                        }
                    }
                }
            }

            // Progress indicator
            if appState.isLoadingBriefing {
                progressIndicator
            }

            // Chat toggle button
            if appState.currentBriefing != nil {
                ChatToggleButton(showChat: $showChat)
            }
        }
    }

    private var buttonLabel: String {
        if appState.isLoadingBriefing {
            return "generating..."
        } else if appState.currentBriefing != nil {
            return appState.isPlayingAudio ? "pause" : "play"
        } else {
            return "generate"
        }
    }

    private var progressIndicator: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(appState.generationProgress.displayText.lowercased())
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 2)

                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * progressValue, height: 2)
                        .animation(.tuiSmooth, value: progressValue)
                }
            }
            .frame(height: 2)
        }
        .padding(.top, Spacing.xs)
    }

    private var progressValue: Double {
        switch appState.generationProgress {
        case .idle, .starting: return 0.1
        case .fetchingSources: return 0.3
        case .processingSources: return 0.5
        case .generatingSummary: return 0.7
        case .finalizing: return 0.9
        case .completed: return 1.0
        case .failed: return 0
        }
    }

    private var summarySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("SUMMARY")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                if let briefing = appState.currentBriefing {
                    Text(briefing.summary)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                } else {
                    Text("no briefing yet. press ⌘R to generate.")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("SECTIONS")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let briefing = appState.currentBriefing {
                    Text("\(briefing.sections.count) sources")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)
            }

            // Sections list
            if let briefing = appState.currentBriefing {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(briefing.sections.sorted { $0.priority > $1.priority }.enumerated()), id: \.element.id) { index, section in
                            TUISectionRow(section: section, index: index)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Text("─────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)

            Text("no data")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            Text("connect sources and generate a briefing")
                .font(.tuiMonoTiny)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TUI Section Row

struct TUISectionRow: View {
    let section: BriefingSection
    let index: Int
    @State private var isExpanded = true
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.tuiSnappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(isExpanded ? "▼" : "▶")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(section.sourceName.uppercased())
                        .font(.tuiMonoSmall)
                        .fontWeight(.medium)

                    Spacer()

                    Text("[\(section.items.count)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isHovered ? Color.tuiHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Items
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(section.items) { item in
                        TUIItemRow(item: item)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }

            // Divider
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - TUI Item Row

struct TUIItemRow: View {
    let item: BriefingItem
    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row (clickable)
            Button {
                if hasDetails {
                    withAnimation(.tuiSnappy) {
                        isExpanded.toggle()
                    }
                } else if let url = item.deepLink {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Priority indicator
                    Text(priorityChar)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(priorityColor)
                        .frame(width: 12)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text(item.title)
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            // Duration badge
                            if let duration = item.metadata["duration"] {
                                Text("[\(duration)]")
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                            }
                        }

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Meeting link indicator
                    if item.metadata["meetingLink"] != nil {
                        Text("📹")
                            .font(.tuiMonoTiny)
                    }

                    // Expand/Link indicator
                    if hasDetails {
                        Text(isExpanded ? "▼" : "▶")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    } else if item.deepLink != nil {
                        Text("→")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                            .opacity(isHovered ? 1 : 0)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.leading, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                .background(isHovered ? Color.tuiHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.tuiFast, value: isHovered)

            // Expanded details
            if isExpanded {
                expandedDetails
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
    }

    private var hasDetails: Bool {
        item.body != nil ||
        item.metadata["attendees"] != nil ||
        item.metadata["location"]?.isEmpty == false
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Attendees
            if let attendees = item.metadata["attendees"], !attendees.isEmpty {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("👥")
                        .font(.tuiMonoTiny)
                    Text(attendees)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Location
            if let location = item.metadata["location"], !location.isEmpty {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("📍")
                        .font(.tuiMonoTiny)
                    Text(location)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Description/Body
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
                    .padding(.top, Spacing.xs)
            }

            // Meeting link button
            if let meetingLink = item.metadata["meetingLink"],
               let url = URL(string: meetingLink) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("📹")
                        Text("Meeting beitreten")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                .padding(.top, Spacing.xs)
            }

            // Deep link to calendar
            if let deepLink = item.deepLink,
               item.metadata["meetingLink"] != nil {
                Button {
                    NSWorkspace.shared.open(deepLink)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("📅")
                        Text("Im Kalender öffnen")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.leading, Spacing.lg + 12 + Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.5))
    }

    private var priorityChar: String {
        switch item.priority {
        case .urgent: return "!"
        case .high: return "●"
        case .medium: return "○"
        case .low: return "·"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .primary.opacity(0.6)
        case .low: return .primary.opacity(0.3)
        }
    }
}

// MARK: - Keyboard Handlers Extension

struct KeyboardHandlersModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedDetailLevel: Briefing.DetailLevel
    @Binding var selectedSection: Int

    func body(content: Content) -> some View {
        content
            .modifier(RefreshKeysModifier(appState: appState, selectedDetailLevel: $selectedDetailLevel))
            .modifier(AudioKeysModifier(appState: appState))
            .modifier(DetailLevelKeysModifier(selectedDetailLevel: $selectedDetailLevel))
            .modifier(SectionKeysModifier(appState: appState, selectedSection: $selectedSection))
    }
}

struct RefreshKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedDetailLevel: Briefing.DetailLevel

    func body(content: Content) -> some View {
        content
            .onKeyPress("r", modifiers: .command) {
                Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                return .handled
            }
            .onKeyPress("n", modifiers: .command) {
                Task { await appState.refreshBriefing(detailLevel: selectedDetailLevel) }
                return .handled
            }
    }
}

struct AudioKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                if appState.currentBriefing != nil {
                    appState.toggleAudioPlayback()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(".", modifiers: .command) {
                if appState.isPlayingAudio {
                    appState.stopAudioPlayback()
                    return .handled
                }
                return .ignored
            }
    }
}

struct DetailLevelKeysModifier: ViewModifier {
    @Binding var selectedDetailLevel: Briefing.DetailLevel

    func body(content: Content) -> some View {
        content
            .onKeyPress("q", modifiers: [.command, .shift]) {
                withAnimation(.tuiSnappy) {
                    selectedDetailLevel = .quick
                }
                return .handled
            }
            .onKeyPress("d", modifiers: [.command, .shift]) {
                withAnimation(.tuiSnappy) {
                    selectedDetailLevel = .detailed
                }
                return .handled
            }
    }
}

struct SectionKeysModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var selectedSection: Int

    func body(content: Content) -> some View {
        content
            .onKeyPress("[", modifiers: .command) {
                if selectedSection > 0 {
                    withAnimation(.tuiSnappy) {
                        selectedSection -= 1
                    }
                }
                return .handled
            }
            .onKeyPress("]", modifiers: .command) {
                if let briefing = appState.currentBriefing, selectedSection < briefing.sections.count - 1 {
                    withAnimation(.tuiSnappy) {
                        selectedSection += 1
                    }
                }
                return .handled
            }
    }
}

// MARK: - Detail Level Button

struct DetailLevelButton: View {
    let level: Briefing.DetailLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) {
                    Text(level == .quick ? "quick" : "detailed")
                        .font(.tuiMonoTiny)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tuiPrimary)
            } else {
                Button(action: action) {
                    Text(level == .quick ? "quick" : "detailed")
                        .font(.tuiMonoTiny)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tui)
            }
        }
    }
}

// MARK: - Chat Toggle Button

struct ChatToggleButton: View {
    @Binding var showChat: Bool

    var body: some View {
        Group {
            if showChat {
                Button {
                    withAnimation(.tuiSnappy) {
                        showChat.toggle()
                    }
                } label: {
                    buttonLabel
                }
                .buttonStyle(.tuiPrimary)
            } else {
                Button {
                    withAnimation(.tuiSnappy) {
                        showChat.toggle()
                    }
                } label: {
                    buttonLabel
                }
                .buttonStyle(.tui)
            }
        }
    }

    private var buttonLabel: some View {
        HStack {
            Text(showChat ? ">" : "<")
                .font(.tuiMonoSmall)

            Text("chat")
                .font(.tuiMonoSmall)

            Spacer()

            KeyBadge(key: "\u{2318}C")
        }
    }
}

// MARK: - Legacy Dashboard View (for compatibility)

struct DashboardView: View {
    var body: some View {
        TUIDashboardView()
    }
}
