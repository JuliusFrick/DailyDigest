import SwiftUI
import WebKit
import AppKit

struct CockpitView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared

    let workspaceSetupID: UUID?
    let workspaceName: String?
    let workspaceTerminalSessionIDs: [UUID]
    let onCreateWorkspaceTerminalSession: (() -> Void)?

    @State private var meetings: [BriefingItem] = []
    @State private var isLoadingMeetings = false
    @State private var selectedMeeting: BriefingItem?
    @State private var activeMode: CockpitMode = .work

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    enum CockpitMode: String, CaseIterable, Identifiable {
        case work = "Work"
        case meeting = "Meeting"

        var id: String { rawValue }
    }

    init(
        workspaceSetupID: UUID? = nil,
        workspaceName: String? = nil,
        workspaceTerminalSessionIDs: [UUID] = [],
        onCreateWorkspaceTerminalSession: (() -> Void)? = nil
    ) {
        self.workspaceSetupID = workspaceSetupID
        self.workspaceName = workspaceName
        self.workspaceTerminalSessionIDs = workspaceTerminalSessionIDs
        self.onCreateWorkspaceTerminalSession = onCreateWorkspaceTerminalSession
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            meetingBar

            if selectedMeeting != nil {
                modeTabs
            }

            Group {
                if activeMode == .meeting, let meeting = selectedMeeting {
                    meetingMode(meeting)
                } else {
                    workMode
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tuiBackground)
        .task(id: hasConnectedCalendar) {
            await refreshMeetings()
        }
        .onReceive(refreshTimer) { _ in
            Task { await refreshMeetings() }
        }
        .onChange(of: selectedMeeting?.id) { _, newID in
            if newID == nil {
                activeMode = .work
            }
        }
    }

    private var hasConnectedCalendar: Bool {
        connectionManager.isConnected(.googleCalendar) ||
        connectionManager.googleCalendarSource?.isAuthenticated == true
    }

    private var meetingBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("MEETINGS")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            if !hasConnectedCalendar {
                Button {
                    appState.selectedPanel = .settings
                } label: {
                    Label("Google Calendar verbinden", systemImage: "link.badge.plus")
                        .font(.tuiMonoTiny)
                }
                .buttonStyle(.tuiPrimary)
            } else if isLoadingMeetings && meetings.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.65)
                    Text("lade Termine…")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
            } else if meetings.isEmpty {
                Text("heute keine Meetings")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Array(meetings.prefix(6))) { meeting in
                            meetingChip(meeting)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer()

            Button {
                Task { await refreshMeetings() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingMeetings)
            .help("Meetings aktualisieren")

            Button {
                appState.selectedPanel = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.tuiHover.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .help("Settings öffnen")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }

    private func meetingChip(_ meeting: BriefingItem) -> some View {
        let urgency = meetingUrgency(for: meeting)
        let tint = urgency.tint
        let url = meetingURL(for: meeting)

        return HStack(spacing: 6) {
            Text(meetingTimeText(for: meeting))
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)

            Text(meeting.title)
                .font(.tuiMonoTiny)
                .lineLimit(1)

            Text(meetingTimeLabel(for: meeting))
                .font(.tuiMonoTiny)
                .foregroundStyle(tint.opacity(0.9))

            if url != nil {
                Button("Join") {
                    selectedMeeting = meeting
                    activeMode = .meeting
                }
                .font(.tuiMonoTiny)
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(selectedMeeting?.id == meeting.id ? 0.18 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMeeting = meeting
            if activeMode == .meeting {
                activeMode = .meeting
            }
        }
    }

    private var modeTabs: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(CockpitMode.allCases) { mode in
                Button {
                    withAnimation(.tuiSnappy) {
                        activeMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(activeMode == mode ? Color.tuiButtonText : .secondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(activeMode == mode ? Color.tuiButtonBackground : Color.tuiHover.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if selectedMeeting != nil {
                Button("Leave") {
                    selectedMeeting = nil
                    activeMode = .work
                }
                .font(.tuiMonoTiny)
                .buttonStyle(.tui)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }

    private var workMode: some View {
        HStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.md) {
                CockpitCard(title: "Terminal Grid", icon: "rectangle.grid.2x2.fill") {
                    CockpitTerminalGrid(
                        workspaceName: workspaceName,
                        workspaceSessionIDs: workspaceTerminalSessionIDs,
                        onAddWorkspaceSession: onCreateWorkspaceTerminalSession
                    )
                }
                .frame(height: 170)

                CockpitCard(title: "Terminal Workspace", icon: "terminal.fill") {
                    TerminalsPanelView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    CockpitTaskFeedCard(limit: 6, scopeID: workspaceTaskScopeID)
                    CockpitJiraSnapshotCard()
                    CockpitSlackSnapshotCard()
                    CockpitQuickCaptureCard(
                        title: "Quick Capture",
                        placeholder: "Task notieren …",
                        meetingID: workspaceTaskScopeID
                    )
                }
                .padding(2)
            }
            .frame(width: 360)
        }
    }

    private func meetingMode(_ meeting: BriefingItem) -> some View {
        HStack(spacing: Spacing.md) {
            CockpitCard(title: meeting.title, icon: "video.fill") {
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text(meetingTimeText(for: meeting))
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let url = meetingURL(for: meeting) {
                            Button("Extern öffnen") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(.tuiMonoTiny)
                            .buttonStyle(.tui)
                        }
                    }

                    if let url = meetingURL(for: meeting) {
                        CockpitMeetingWebView(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.tuiBorder.opacity(0.7), lineWidth: 1)
                            )
                    } else {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 26))
                                .foregroundStyle(.secondary)
                            Text("Kein Meeting-Link gefunden")
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.tuiHover.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    CockpitMeetingDetailCard(meeting: meeting)
                    CockpitQuickCaptureCard(
                        title: "Meeting Note",
                        placeholder: "Action Item aus dem Meeting …",
                        meetingID: meeting.id.uuidString
                    )
                    CockpitTaskFeedCard(limit: 8, scopeID: workspaceTaskScopeID)
                }
                .padding(2)
            }
            .frame(width: 360)
        }
    }

    private var workspaceTaskScopeID: String? {
        guard let workspaceSetupID else { return nil }
        return "workspace.\(workspaceSetupID.uuidString)"
    }

    private func refreshMeetings() async {
        guard hasConnectedCalendar,
              let calendarSource = connectionManager.googleCalendarSource,
              calendarSource.isAuthenticated else {
            meetings = []
            selectedMeeting = nil
            return
        }

        if isLoadingMeetings {
            return
        }

        isLoadingMeetings = true
        defer { isLoadingMeetings = false }

        let now = Date()
        let from = Calendar.current.date(byAdding: .minute, value: -30, to: now) ?? now
        let to = Calendar.current.date(byAdding: .hour, value: 12, to: now) ?? now

        do {
            let fetched = try await calendarSource.fetchEvents(from: from, to: to)
            let sorted = fetched
                .filter { $0.timestamp != nil }
                .sorted { ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture) }
            let next = Array(sorted.prefix(8))
            meetings = next
            syncSelectedMeeting(with: next)
            if selectedMeeting == nil {
                selectedMeeting = next.first(where: { meetingURL(for: $0) != nil }) ?? next.first
            }
        } catch {
            meetings = []
        }
    }

    private func syncSelectedMeeting(with refreshed: [BriefingItem]) {
        guard let selectedMeeting else { return }
        if let match = refreshed.first(where: { isSameMeeting($0, selectedMeeting) }) {
            self.selectedMeeting = match
            return
        }

        if activeMode == .meeting {
            self.selectedMeeting = refreshed.first
        }
    }

    private func isSameMeeting(_ lhs: BriefingItem, _ rhs: BriefingItem) -> Bool {
        if let lhsID = lhs.metadata["eventId"], let rhsID = rhs.metadata["eventId"] {
            return lhsID == rhsID
        }

        guard lhs.title == rhs.title,
              let lhsTime = lhs.timestamp,
              let rhsTime = rhs.timestamp else {
            return false
        }

        return abs(lhsTime.timeIntervalSince(rhsTime)) < 120
    }

    private func meetingURL(for meeting: BriefingItem) -> URL? {
        if let value = meeting.metadata["meetingLink"], let url = URL(string: value) {
            return url
        }
        return meeting.deepLink
    }

    private func meetingTimeText(for meeting: BriefingItem) -> String {
        guard let timestamp = meeting.timestamp else { return "--:--" }
        return Self.timeFormatter.string(from: timestamp)
    }

    private func meetingTimeLabel(for meeting: BriefingItem) -> String {
        guard let timestamp = meeting.timestamp else { return "" }

        let minutes = Int(timestamp.timeIntervalSince(Date()) / 60)
        if minutes <= 0 && minutes >= -45 {
            return "NOW"
        }
        if minutes < 60 {
            return "in \(max(minutes, 0))m"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest > 0 ? "in \(hours)h \(rest)m" : "in \(hours)h"
    }

    private func meetingUrgency(for meeting: BriefingItem) -> MeetingUrgency {
        guard let timestamp = meeting.timestamp else { return .normal }
        let minutes = Int(timestamp.timeIntervalSince(Date()) / 60)
        if minutes <= 0 && minutes >= -45 { return .now }
        if minutes <= 5 { return .imminent }
        if minutes <= 15 { return .soon }
        return .normal
    }

    private enum MeetingUrgency {
        case now
        case imminent
        case soon
        case normal

        var tint: Color {
            switch self {
            case .now: return .red
            case .imminent: return .orange
            case .soon: return .yellow
            case .normal: return .tuiAccent
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct CockpitCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tuiAccent)

                Text(title.uppercased())
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))

            Divider()
                .background(Color.tuiBorder)

            content
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
    }
}

private struct CockpitTerminalGrid: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var terminalSessionManager = TerminalSessionManager.shared

    let workspaceName: String?
    let workspaceSessionIDs: [UUID]
    let onAddWorkspaceSession: (() -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    private var scopedSessions: [TerminalSessionManager.Session] {
        guard !workspaceSessionIDs.isEmpty else { return terminalSessionManager.sessions }

        let lookup = Dictionary(uniqueKeysWithValues: terminalSessionManager.sessions.map { ($0.id, $0) })
        return workspaceSessionIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if let workspaceName, !workspaceName.isEmpty {
                HStack {
                    Text(workspaceName.uppercased())
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(Array(scopedSessions.prefix(4))) { session in
                    Button {
                        terminalSessionManager.selectSession(session.id)
                        appState.selectedPanel = .terminals
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title)
                                .font(.tuiMonoSmall)
                                .lineLimit(1)

                            Text(session.workingDirectory ?? "~")
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                        .background(Color.tuiHover.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(session.id == terminalSessionManager.selectedSessionID ? Color.tuiAccent.opacity(0.5) : Color.tuiBorder.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if scopedSessions.isEmpty && !workspaceSessionIDs.isEmpty {
                    Text("Keine Session für diesen Aufgaben-Tab")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .padding(.horizontal, Spacing.sm)
                        .background(Color.tuiHover.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    if let onAddWorkspaceSession {
                        onAddWorkspaceSession()
                    } else {
                        let title = "Terminal \(terminalSessionManager.sessions.count + 1)"
                        let id = terminalSessionManager.openSession(title: title)
                        terminalSessionManager.selectSession(id)
                    }
                    appState.selectedPanel = .terminals
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Neue Session")
                            .font(.tuiMonoTiny)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .foregroundStyle(.secondary)
                    .background(Color.tuiHover.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.tuiBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Terminal Hub öffnen") {
                    appState.selectedPanel = .terminals
                }
                .font(.tuiMonoTiny)
                .buttonStyle(.tui)
            }
        }
    }
}

private struct CockpitTaskFeedCard: View {
    @ObservedObject private var actionItemStore = ActionItemStore.shared
    let limit: Int
    var scopeID: String? = nil

    var body: some View {
        CockpitCard(title: "Tasks", icon: "checklist") {
            let scopedItems = openScopedItems()
            let items = Array(scopedItems.prefix(limit))

            if items.isEmpty {
                Text(scopeID == nil ? "Keine offenen Tasks" : "Keine offenen Tasks in diesem Tab")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(items) { item in
                        HStack(spacing: Spacing.sm) {
                            Button {
                                actionItemStore.toggleCompletion(item)
                            } label: {
                                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.status == .completed ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.tuiMonoTiny)
                                    .lineLimit(2)
                                if let dueDate = item.dueDate {
                                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.tuiMonoTiny)
                                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func openScopedItems() -> [ActionItem] {
        guard let scopeID else { return actionItemStore.openItems() }
        return actionItemStore.openItems().filter { $0.meetingId == scopeID }
    }
}

private struct CockpitQuickCaptureCard: View {
    @ObservedObject private var actionItemStore = ActionItemStore.shared
    let title: String
    let placeholder: String
    var meetingID: String?

    @State private var text = ""

    var body: some View {
        CockpitCard(title: title, icon: "square.and.pencil") {
            VStack(spacing: Spacing.sm) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.tuiMonoSmall)
                    .onSubmit(addTask)

                HStack {
                    Spacer()
                    Button("Hinzufügen") {
                        addTask()
                    }
                    .font(.tuiMonoTiny)
                    .buttonStyle(.tuiPrimary)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addTask() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = ActionItem(
            title: trimmed,
            meetingId: meetingID ?? "cockpit.manual"
        )
        actionItemStore.add(item)
        text = ""
    }
}

private struct CockpitJiraSnapshotCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    @State private var items: [BriefingItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshDate = Date()

    var body: some View {
        CockpitCard(title: "Jira", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !isConnected {
                    Text("Jira nicht verbunden")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)

                    Button("In Settings verbinden") {
                        appState.selectedPanel = .settings
                    }
                    .font(.tuiMonoTiny)
                    .buttonStyle(.tui)
                } else if isLoading && items.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("lade…")
                            .font(.tuiMonoTiny)
                    }
                } else if let lastError {
                    Text(lastError)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if items.isEmpty {
                    Text("Keine Tickets")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(items.prefix(4))) { item in
                        cockpitItemRow(item, fallbackOpen: { appState.selectedPanel = .jira })
                    }
                }

                HStack {
                    Spacer()
                    Button("Aktualisieren") {
                        refreshDate = Date()
                    }
                    .font(.tuiMonoTiny)
                    .buttonStyle(.tui)
                    .disabled(!isConnected || isLoading)
                }
            }
        }
        .task(id: refreshDate) {
            await loadItems()
        }
    }

    private var isConnected: Bool {
        connectionManager.isConnected(.jira) || connectionManager.jiraSource?.isAuthenticated == true
    }

    private func loadItems() async {
        guard let source = connectionManager.jiraSource, source.isAuthenticated else {
            items = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let fetched = try await source.fetchItems(since: since)
            items = fetched
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private struct CockpitSlackSnapshotCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var connectionManager = ServiceConnectionManager.shared
    @State private var items: [BriefingItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshDate = Date()

    var body: some View {
        CockpitCard(title: "Slack", icon: "bubble.left.and.bubble.right.fill") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !isConnected {
                    Text("Slack nicht verbunden")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)

                    Button("In Settings verbinden") {
                        appState.selectedPanel = .settings
                    }
                    .font(.tuiMonoTiny)
                    .buttonStyle(.tui)
                } else if isLoading && items.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("lade…")
                            .font(.tuiMonoTiny)
                    }
                } else if let lastError {
                    Text(lastError)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if items.isEmpty {
                    Text("Keine neuen Nachrichten")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(items.prefix(4))) { item in
                        cockpitItemRow(item, fallbackOpen: { appState.selectedPanel = .slack })
                    }
                }

                HStack {
                    Spacer()
                    Button("Aktualisieren") {
                        refreshDate = Date()
                    }
                    .font(.tuiMonoTiny)
                    .buttonStyle(.tui)
                    .disabled(!isConnected || isLoading)
                }
            }
        }
        .task(id: refreshDate) {
            await loadItems()
        }
    }

    private var isConnected: Bool {
        connectionManager.isConnected(.slack) || connectionManager.slackSource?.isAuthenticated == true
    }

    private func loadItems() async {
        guard let source = connectionManager.slackSource, source.isAuthenticated else {
            items = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let since = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let fetched = try await source.fetchItems(since: since)
            items = fetched
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private func cockpitItemRow(_ item: BriefingItem, fallbackOpen: @escaping () -> Void) -> some View {
    HStack(spacing: Spacing.sm) {
        Circle()
            .fill(priorityColor(item.priority))
            .frame(width: 6, height: 6)

        Text(item.title)
            .font(.tuiMonoTiny)
            .lineLimit(2)

        Spacer()

        Button("Open") {
            if let url = item.deepLink {
                NSWorkspace.shared.open(url)
            } else {
                fallbackOpen()
            }
        }
        .font(.tuiMonoTiny)
        .buttonStyle(.plain)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, 6)
    .background(Color.tuiHover.opacity(0.25))
    .clipShape(RoundedRectangle(cornerRadius: 6))
}

private func priorityColor(_ priority: BriefingSection.Priority) -> Color {
    switch priority {
    case .urgent: return .red
    case .high: return .orange
    case .medium: return .yellow
    case .low: return .secondary
    }
}

private struct CockpitMeetingDetailCard: View {
    let meeting: BriefingItem

    var body: some View {
        CockpitCard(title: "Meeting Details", icon: "person.3.fill") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                detailRow(label: "Titel", value: meeting.title)

                if let subtitle = meeting.subtitle, !subtitle.isEmpty {
                    detailRow(label: "Zeit", value: subtitle)
                }

                if let location = meeting.metadata["location"], !location.isEmpty {
                    detailRow(label: "Ort", value: location)
                }

                if let organizer = meeting.metadata["organizer"], !organizer.isEmpty {
                    detailRow(label: "Owner", value: organizer)
                }

                let attendees = meeting.attendeeCount
                if attendees > 0 {
                    detailRow(label: "Attendees", value: "\(attendees)")
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(label.uppercased())
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.tuiMonoTiny)
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer()
        }
    }
}

private struct CockpitMeetingWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
