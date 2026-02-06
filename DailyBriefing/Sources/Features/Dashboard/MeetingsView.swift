import SwiftUI

// MARK: - Meetings View

struct MeetingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    // State for calendar navigation and data
    @State private var selectedDate: Date = Date()
    @State private var fetchedMeetings: [BriefingItem] = []
    @State private var isLoading: Bool = false

    private let calendar = Calendar.current

    private var hasCalendarConnected: Bool {
        connectionManager.isConnected(.googleCalendar) ||
        connectionManager.isConnected(.appleCalendar)
    }
    
    var showHeader: Bool = true
    
    @State private var showConnectPopup: Bool = true
    @State private var showMeetingRecordingPopup: Bool = false
    @State private var selectedMeetingForRecording: BriefingItem? = nil
    @State private var showMeetingDetailPopup: Bool = false
    @State private var selectedMeetingForDetail: BriefingItem? = nil
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                if showHeader {
                    HStack {
                        Text("KALENDER")
                            .font(.tuiMonoTiny)
                            .fontWeight(.bold)
                            .foregroundStyle(.tertiary)
                        
                        Spacer()
                        
                        if hasCalendarConnected {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Text("\(fetchedMeetings.count) events this week")
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                            }
                        } else {
                            Text("nicht verbunden")
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.tuiBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                }
                
                // Always show calendar grid
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Week Calendar Grid
                        WeekCalendarView(
                            meetings: fetchedMeetings,
                            selectedDate: $selectedDate,
                            onRecordMeeting: { meeting in
                                selectedMeetingForRecording = meeting
                                showMeetingRecordingPopup = true
                            }
                        )
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                        
                        // Detailed List for the week
                        if !fetchedMeetings.isEmpty {
                            calendarMeetingsHeader

                            ForEach(fetchedMeetings) { item in
                                MeetingRow(item: item) { meeting in
                                    selectedMeetingForDetail = meeting
                                    showMeetingDetailPopup = true
                                }

                                Rectangle()
                                    .fill(Color.tuiBorder)
                                    .frame(height: 1)
                            }
                        } else if !isLoading {
                            VStack(spacing: Spacing.sm) {
                                Text(hasCalendarConnected ? "Keine Termine diese Woche" : "Keine Termine")
                                    .font(.tuiMonoSmall)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(Spacing.xl)
                        }

                        // Recording section
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)

                        AdHocRecordingSection()

                        // Ad-hoc recordings list
                        AdHocMeetingsSection()
                    }
                }
            }
            .background(Color.tuiBackground)
            
            // Floating popup when not connected
            if !hasCalendarConnected && showConnectPopup {
                CalendarConnectPopup(showPopup: $showConnectPopup)
            }
            
            // Keyboard shortcut hint
            if hasCalendarConnected && !fetchedMeetings.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        KeyBadge(key: "⇧⌘R")
                        Text("Meeting aufnehmen")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(Spacing.sm)
                    .background(Color.tuiHover)
                    .cornerRadius(4)
                    .padding(Spacing.md)
                }
            }
        }
        .task(id: hasCalendarConnected) {
            if hasCalendarConnected {
                await loadMeetings()
                showConnectPopup = false
            }
        }
        .task(id: selectedDate) {
            if hasCalendarConnected {
                await loadMeetings()
            }
        }
        .onKeyPress("r", modifiers: [.command, .shift]) {
            // Open recording popup for first meeting of the day
            if let firstMeeting = fetchedMeetings.first(where: { 
                calendar.isDate($0.timestamp ?? Date(), inSameDayAs: Date())
            }) {
                selectedMeetingForRecording = firstMeeting
                showMeetingRecordingPopup = true
                return .handled
            }
            return .ignored
        }
        .overlay {
            if showMeetingRecordingPopup, let meeting = selectedMeetingForRecording {
                MeetingRecordingPopup(
                    isPresented: $showMeetingRecordingPopup,
                    meeting: meeting
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }
        }
        .overlay {
            if showMeetingDetailPopup, let meeting = selectedMeetingForDetail {
                MeetingDetailPopup(
                    isPresented: $showMeetingDetailPopup,
                    meeting: meeting,
                    onStartRecording: {
                        showMeetingDetailPopup = false
                        selectedMeetingForRecording = meeting
                        showMeetingRecordingPopup = true
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }
        }
        .animation(.tuiSnappy, value: showMeetingDetailPopup)
    }
    
    private var calendarMeetingsHeader: some View {
        HStack {
            Text("TERMINE")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.quaternary)
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiHover.opacity(0.3))
    }
    
    private func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }
        
        // Calculate week range for selectedDate
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        var allMeetings: [BriefingItem] = []
        
        do {
            // Fetch from Google Calendar
            if let googleSource = connectionManager.googleCalendarSource, googleSource.isAuthenticated {
                let googleEvents = try await googleSource.fetchEvents(from: startOfWeek, to: endOfWeek)
                allMeetings.append(contentsOf: googleEvents)
            }
            
            // Fetch from Apple Calendar
            if let appleSource = connectionManager.appleCalendarSource, appleSource.isAuthenticated {
                let appleEvents = try await appleSource.fetchEvents(from: startOfWeek, to: endOfWeek)
                allMeetings.append(contentsOf: appleEvents)
            }
            
            // Sort by date
            fetchedMeetings = allMeetings.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        } catch {
            print("Failed to load meetings: \(error)")
        }
    }
}

// MARK: - Calendar Config Banner

struct CalendarConfigBanner: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)
            
            Text("KALENDER NICHT KONFIGURIERT")
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Text("Verbinde deinen Kalender, um deine\nTermine hier zu sehen.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            
            Button {
                Task {
                    try? await connectionManager.connect(.googleCalendar)
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("+")
                    Text("Kalender verbinden")
                        .font(.tuiMonoSmall)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            Text("────────────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Calendar Connect Popup

struct CalendarConnectPopup: View {
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    @Binding var showPopup: Bool
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: Spacing.md) {
                // Header with close button
                HStack {
                    Text("KALENDER VERBINDEN")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            showPopup = false
                        }
                    } label: {
                        Text("✕")
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Verbinde deinen Kalender, um Termine zu sehen und Meeting-Zusammenfassungen zu erstellen.")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                
                HStack(spacing: Spacing.sm) {
                    Button {
                        Task {
                            try? await connectionManager.connect(.googleCalendar)
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("+")
                            Text("Verbinden")
                                .font(.tuiMonoSmall)
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            showPopup = false
                        }
                    } label: {
                        Text("Später")
                            .font(.tuiMonoSmall)
                    }
                    .buttonStyle(.tui)
                }
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .padding(Spacing.lg)
        }
        .frame(maxWidth: 320)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.95))
        ))
    }
}

// MARK: - Week Calendar View

struct WeekCalendarView: View {
    let meetings: [BriefingItem]
    @Binding var selectedDate: Date
    var onRecordMeeting: ((BriefingItem) -> Void)? = nil

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 40
    private let startHour = 7  // 07:00
    private let endHour = 20   // 20:00
    
    private var weekDays: [Date] {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
    
    private var weekRange: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with navigation
            HStack {
                Text("ÜBERSICHT")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.quaternary)
                
                Spacer()
                
                HStack(spacing: Spacing.sm) {
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                        }
                    } label: {
                        Text("◀")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.plain)
                    
                    Text(weekRange)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 120)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                        }
                    } label: {
                        Text("▶")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.tuiSnappy) {
                            selectedDate = Date()
                        }
                    } label: {
                        Text("Heute")
                            .font(.tuiMonoTiny)
                    }
                    .buttonStyle(.tui)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            // Day headers
            HStack(spacing: 0) {
                // Time column spacer
                Text("")
                    .frame(width: 40)
                
                ForEach(weekDays, id: \.self) { day in
                    DayHeaderCell(date: day, isToday: calendar.isDateInToday(day))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.tuiBackground)
            
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
            
            // Calendar grid
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour lines and labels
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            HStack(spacing: 0) {
                                Text(String(format: "%02d", hour))
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                                    .frame(width: 40)
                                
                                Rectangle()
                                    .fill(Color.tuiBorder.opacity(0.5))
                                    .frame(height: 1)
                            }
                            .frame(height: hourHeight)
                        }
                    }
                    
                    // Events overlay
                    HStack(spacing: 0) {
                        // Time column spacer
                        Color.clear
                            .frame(width: 40)
                        
                        ForEach(weekDays, id: \.self) { day in
                            DayEventsColumn(
                                date: day,
                                meetings: meetingsForDay(day),
                                hourHeight: hourHeight,
                                startHour: startHour,
                                endHour: endHour,
                                onRecordMeeting: onRecordMeeting
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight + 20)
        }
    }
    
    private func meetingsForDay(_ day: Date) -> [BriefingItem] {
        meetings.filter { item in
            guard let timestamp = item.timestamp else { return false }
            return calendar.isDate(timestamp, inSameDayAs: day)
        }
    }
}

// MARK: - Day Header Cell

struct DayHeaderCell: View {
    let date: Date
    let isToday: Bool
    
    private let calendar = Calendar.current
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(dayName)
                .font(.tuiMonoTiny)
                .foregroundStyle(isToday ? .primary : .quaternary)
            
            Text(dayNumber)
                .font(.tuiMonoSmall)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .primary : .secondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(isToday ? Color.tuiAccent.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Day Events Column

struct DayEventsColumn: View {
    let date: Date
    let meetings: [BriefingItem]
    let hourHeight: CGFloat
    let startHour: Int
    let endHour: Int
    var onRecordMeeting: ((BriefingItem) -> Void)? = nil

    private let calendar = Calendar.current
    private let maxWidth: CGFloat = 120 // Max width for event blocks
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background for today
            if calendar.isDateInToday(date) {
                Rectangle()
                    .fill(Color.tuiAccent.opacity(0.05))
            }
            
            // Current time indicator
            if calendar.isDateInToday(date) {
                CurrentTimeIndicator(hourHeight: hourHeight, startHour: startHour)
            }
            
            // Events with overlap resolution
            let resolvedEvents = resolveEventOverlaps(meetings)
            
            // Group events by column
            let columns = groupEventsByColumn(resolvedEvents)
            
            HStack(spacing: 4) {
                ForEach(0..<columns.count, id: \.self) { columnIndex in
                    VStack(spacing: 0) {
                        ForEach(columns[columnIndex]) { eventLayout in
                            if let timestamp = eventLayout.meeting.timestamp {
                                EventBlock(
                                    meeting: eventLayout.meeting,
                                    hourHeight: hourHeight,
                                    startHour: startHour,
                                    topOffset: offsetForTime(timestamp),
                                    onRecordMeeting: onRecordMeeting
                                )
                                .frame(width: columnWidth(for: columns.count))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(endHour - startHour) * hourHeight)
    }
    
    private func offsetForTime(_ date: Date) -> CGFloat {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let hoursFromStart = CGFloat(hour - startHour) + CGFloat(minute) / 60.0
        return max(0, hoursFromStart * hourHeight)
    }

    // MARK: - Event Overlap Resolution

    struct EventLayout: Identifiable {
        let id = UUID()
        let meeting: BriefingItem
        let columnIndex: Int
        let columnCount: Int
    }

    private func resolveEventOverlaps(_ meetings: [BriefingItem]) -> [EventLayout] {
        // Convert meetings to time intervals
        let intervals: [(start: Date, end: Date, meeting: BriefingItem)] = meetings.compactMap { meeting in
            guard let timestamp = meeting.timestamp else { return nil }
            let duration = meeting.metadata["duration"] ?? "1h"
            let endTime = calculateEndTime(from: timestamp, duration: duration)
            return (timestamp, endTime, meeting)
        }

        // Sort by start time
        let sortedIntervals = intervals.sorted { $0.start < $1.start }

        // Assign columns to avoid overlaps
        var columns: [[(start: Date, end: Date, meeting: BriefingItem)]] = []

        for interval in sortedIntervals {
            // Find first available column
            var assignedToColumn = false
            for (index, column) in columns.enumerated() {
                if let lastEvent = column.last {
                    // Check if this event overlaps with the last event in this column
                    if interval.start >= lastEvent.end {
                        // No overlap, add to this column
                        columns[index].append(interval)
                        assignedToColumn = true
                        break
                    }
                } else {
                    // Empty column
                    columns[index].append(interval)
                    assignedToColumn = true
                    break
                }
            }

            // If no available column found, create a new one
            if !assignedToColumn {
                columns.append([interval])
            }
        }

        // Convert to EventLayout
        var layouts: [EventLayout] = []
        for (columnIndex, column) in columns.enumerated() {
            for event in column {
                layouts.append(EventLayout(
                    meeting: event.meeting,
                    columnIndex: columnIndex,
                    columnCount: columns.count
                ))
            }
        }

        return layouts
    }

    private func groupEventsByColumn(_ layouts: [EventLayout]) -> [[EventLayout]] {
        var columns: [[EventLayout]] = []
        
        // Find maximum column index
        let maxColumn = layouts.map { $0.columnIndex }.max() ?? 0
        
        // Initialize columns
        for _ in 0...maxColumn {
            columns.append([])
        }
        
        // Group events by column
        for layout in layouts {
            if layout.columnIndex < columns.count {
                columns[layout.columnIndex].append(layout)
            }
        }
        
        return columns
    }

    private func columnWidth(for columnCount: Int) -> CGFloat {
        if columnCount <= 1 {
            return maxWidth
        }
        return max(50, maxWidth / CGFloat(columnCount))
    }

    private func calculateEndTime(from start: Date, duration: String) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()

        // Parse duration string (e.g., "1h 30m" or "30m")
        let parts = duration.lowercased().components(separatedBy: " ")
        for part in parts {
            if part.contains("h") {
                if let hours = Int(part.replacingOccurrences(of: "h", with: "")) {
                    components.hour = hours
                }
            } else if part.contains("m") {
                if let minutes = Int(part.replacingOccurrences(of: "m", with: "")) {
                    components.minute = minutes
                }
            }
        }

        return calendar.date(byAdding: components, to: start) ?? start
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat
    let startHour: Int
    
    private let calendar = Calendar.current
    
    private var offset: CGFloat {
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let hoursFromStart = CGFloat(hour - startHour) + CGFloat(minute) / 60.0
        return max(0, hoursFromStart * hourHeight)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(y: offset - 3)
    }
}

// MARK: - Event Block

struct EventBlock: View {
    let meeting: BriefingItem
    let hourHeight: CGFloat
    let startHour: Int
    let topOffset: CGFloat
    var onRecordMeeting: ((BriefingItem) -> Void)? = nil

    @State private var isHovered = false
    
    private var duration: CGFloat {
        // Try to parse duration from metadata, default to 1 hour
        if let durationStr = meeting.metadata["duration"] {
            // Parse "1h 30m" or "30m" format
            var totalMinutes: CGFloat = 0
            let components = durationStr.lowercased().components(separatedBy: " ")
            for component in components {
                if component.contains("h") {
                    if let hours = Double(component.replacingOccurrences(of: "h", with: "")) {
                        totalMinutes += CGFloat(hours) * 60
                    }
                } else if component.contains("m") {
                    if let minutes = Double(component.replacingOccurrences(of: "m", with: "")) {
                        totalMinutes += CGFloat(minutes)
                    }
                }
            }
            return max(30, totalMinutes) // Minimum 30 minutes for visibility
        }
        return 60 // Default 1 hour
    }
    
    private var height: CGFloat {
        (duration / 60.0) * hourHeight
    }
    
    private var eventColor: Color {
        if meeting.metadata["meetingLink"] != nil {
            return Color.blue.opacity(0.6)
        }
        return Color.tuiAccent.opacity(0.6)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(meeting.title)
                .font(.tuiMonoTiny)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(height > 30 ? 2 : 1)
            
            if height > 40, let subtitle = meeting.subtitle {
                Text(subtitle)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(eventColor)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHovered ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .offset(y: topOffset)
        .onHover { isHovered = $0 }
        .help(meeting.title + (meeting.subtitle.map { " - \($0)" } ?? ""))
        .contextMenu {
            if let onRecordMeeting {
                Button {
                    onRecordMeeting(meeting)
                } label: {
                    Label("Meeting aufnehmen", systemImage: "mic.fill")
                }
            }
        }
    }
}

// MARK: - Meeting Detail Popup

struct MeetingDetailPopup: View {
    @Binding var isPresented: Bool
    let meeting: BriefingItem
    var onStartRecording: (() -> Void)? = nil

    @StateObject private var notesService = MeetingNotesService.shared

    private var meetingNotes: String? {
        notesService.getNotes(for: meeting)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.tuiOverlayBackdrop
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Popup
            VStack(spacing: 0) {
                // Header
                popupHeader

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Title
                        Text(meeting.title)
                            .font(.tuiMono)
                            .fontWeight(.medium)

                        // Meta info grid
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if let subtitle = meeting.subtitle {
                                metaRow(label: "Zeit", value: subtitle)
                            }

                            if let duration = meeting.metadata["duration"] {
                                metaRow(label: "Dauer", value: duration)
                            }

                            if let location = meeting.metadata["location"], !location.isEmpty {
                                metaRow(label: "Ort", value: location)
                            }

                            if let organizer = meeting.metadata["organizer"], !organizer.isEmpty {
                                metaRow(label: "Von", value: organizer)
                            }
                        }

                        // Attendees
                        if let attendees = meeting.metadata["attendees"], !attendees.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("TEILNEHMER")
                                    .font(.tuiMonoTiny)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)

                                Text(attendees)
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                        }

                        // Description
                        if let body = meeting.body, !body.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("BESCHREIBUNG")
                                    .font(.tuiMonoTiny)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)

                                Text(body)
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            }
                        }

                        // Notes section
                        if let notes = meetingNotes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("NOTIZEN")
                                    .font(.tuiMonoTiny)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)

                                Text(notes)
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.tuiHover)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.tuiBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(Spacing.md)
                }

                // Footer with actions
                popupFooter
            }
            .frame(maxWidth: 420, maxHeight: 480)
            .background(Color.tuiPanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private var popupHeader: some View {
        HStack {
            Text("TERMIN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

            KeyBadge(key: "ESC")
        }
        .padding(Spacing.md)
        .background(Color.tuiBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }

    private var popupFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)

            HStack(spacing: Spacing.sm) {
                // Meeting Link Button
                if let meetingLink = meeting.metadata["meetingLink"],
                   let url = URL(string: meetingLink) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Beitreten")
                    }
                    .buttonStyle(.tuiPrimary)
                }

                // Record Button
                if let onStartRecording {
                    Button {
                        onStartRecording()
                    } label: {
                        Text("Aufnehmen")
                    }
                    .buttonStyle(.tui)
                }

                // Open in Calendar
                if let deepLink = meeting.deepLink {
                    Button {
                        NSWorkspace.shared.open(deepLink)
                    } label: {
                        Text("Kalender")
                    }
                    .buttonStyle(.tui)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Schließen")
                }
                .buttonStyle(.tuiGhost)
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(label)
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .trailing)

            Text(value)
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Meeting Recording Popup

struct MeetingRecordingPopup: View {
    @Binding var isPresented: Bool
    let meeting: BriefingItem
    @StateObject private var recordingService = AudioRecordingService.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var recordingNotes = ""

    var body: some View {
        ZStack {
            // Backdrop
            Color.tuiOverlayBackdrop
                .ignoresSafeArea()
                .onTapGesture {
                    if !isRecording && !isTranscribing {
                        isPresented = false
                    }
                }

            // Popup
            VStack(spacing: 0) {
                // Header
                popupHeader

                // Meeting Info
                meetingInfoSection

                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)

                // Recording Controls
                VStack(spacing: Spacing.md) {
                    if isRecording {
                        recordingInProgressView
                    } else if isTranscribing {
                        transcribingView
                    } else {
                        readyToRecordView
                    }

                    // Notes section
                    if isRecording || !recordingNotes.isEmpty {
                        notesSection
                    }
                }
                .padding(Spacing.md)

                // Footer
                if !isRecording && !isTranscribing {
                    popupFooter
                }
            }
            .frame(width: 380)
            .background(Color.tuiPanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .onKeyPress(.escape) {
            if !isRecording && !isTranscribing {
                isPresented = false
            }
            return .handled
        }
        .task {
            guard recordingService.isPermissionUndetermined() else { return }
            _ = await recordingService.requestPermission()
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var popupHeader: some View {
        HStack {
            Text("AUFNAHME")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

            if !isRecording && !isTranscribing {
                KeyBadge(key: "ESC")
            }
        }
        .padding(Spacing.md)
        .background(Color.tuiBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }

    private var meetingInfoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(meeting.title)
                .font(.tuiMonoSmall)
                .fontWeight(.medium)
                .lineLimit(2)

            if let subtitle = meeting.subtitle {
                Text(subtitle)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover)
    }

    private var popupFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)

            HStack {
                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Abbrechen")
                }
                .buttonStyle(.tuiGhost)
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
        }
    }

    private var recordingInProgressView: some View {
        VStack(spacing: Spacing.md) {
            // Recording indicator
            HStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Color.recordingActive)
                        .frame(width: 8, height: 8)
                        .opacity(recordingService.isRecording ? 1 : 0.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)

                    Text("REC")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.recordingActive)

                    Text(recordingService.formattedDuration())
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Button {
                    stopRecording()
                } label: {
                    Text("Beenden")
                }
                .buttonStyle(.tuiPrimary)
            }

            // Audio level indicator
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.tuiHover)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.recordingActive.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(recordingService.audioLevel))
                    }
            }
            .frame(height: 4)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.secondary)

                Text("Transkribiere...")
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text("Aufnahme wird verarbeitet")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readyToRecordView: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Button {
                    startRecording()
                } label: {
                    Text("Aufnahme starten")
                }
                .buttonStyle(.tuiPrimary)
                .disabled(!recordingService.hasPermission)

                Spacer()
            }

            if !recordingService.hasPermission {
                Text("Mikrofon-Berechtigung erforderlich")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Bereit")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("NOTIZEN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            TextField("Notizen hinzufügen...", text: $recordingNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.tuiMonoTiny)
                .padding(Spacing.sm)
                .background(Color.tuiHover)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.tuiBorder, lineWidth: 1)
                )
                .frame(minHeight: 60)
        }
    }

    private func startRecording() {
        Task {
            do {
                _ = try await recordingService.startRecording()
                isRecording = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopRecording() {
        guard let audioURL = recordingService.stopRecording() else {
            return
        }

        isRecording = false
        isTranscribing = true

        Task {
            do {
                let transcription = try await transcriptionService.transcribe(audioURL: audioURL)

                // Save meeting notes linked to this calendar event
                let meetingId = notesService.meetingId(for: meeting)
                let fullNotes = recordingNotes.isEmpty
                    ? transcription
                    : "\(recordingNotes)\n\n---\n\n\(transcription)"
                notesService.saveNotes(meetingId: meetingId, notes: fullNotes)

                // Clean up audio file
                try? FileManager.default.removeItem(at: audioURL)

                isTranscribing = false
                isPresented = false

            } catch {
                errorMessage = "Transkription fehlgeschlagen: \(error.localizedDescription)"
                showError = true
                isTranscribing = false

                // Clean up audio file on error
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }
}

// MARK: - Ad-Hoc Recording Section

struct AdHocRecordingSection: View {
    @StateObject private var recordingService = AudioRecordingService.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var didRequestPermission = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            Text("NEUE AUFNAHME")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            if isRecording {
                recordingView
            } else if isTranscribing {
                transcribingView
            } else {
                readyView
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover)
        .task {
            guard !didRequestPermission, recordingService.isPermissionUndetermined() else { return }
            didRequestPermission = true
            _ = await recordingService.requestPermission()
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var recordingView: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(Color.recordingActive)
                    .frame(width: 8, height: 8)
                    .opacity(recordingService.isRecording ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)

                Text("REC")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.recordingActive)

                Text(recordingService.formattedDuration())
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                stopRecording()
            } label: {
                Text("Beenden")
            }
            .buttonStyle(.tuiPrimary)
        }
    }

    private var transcribingView: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.secondary)
            Text("Transkribiere...")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
        }
    }

    private var readyView: some View {
        HStack {
            Button {
                startRecording()
            } label: {
                Text("Aufnahme starten")
            }
            .buttonStyle(.tuiPrimary)
            .disabled(!recordingService.hasPermission)

            if !recordingService.hasPermission {
                Text("Mikrofon-Berechtigung erforderlich")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func startRecording() {
        Task {
            do {
                _ = try await recordingService.startRecording()
                isRecording = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopRecording() {
        guard let audioURL = recordingService.stopRecording() else {
            return
        }

        isRecording = false
        isTranscribing = true

        Task {
            do {
                let transcription = try await transcriptionService.transcribe(audioURL: audioURL)
                notesService.createAdHocMeeting(notes: transcription)
                try? FileManager.default.removeItem(at: audioURL)
                isTranscribing = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isTranscribing = false
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }
}

// MARK: - Ad-Hoc Meetings Section

struct AdHocMeetingsSection: View {
    @StateObject private var notesService = MeetingNotesService.shared

    var body: some View {
        if !notesService.adHocMeetings.isEmpty {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("AUFNAHMEN")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text("\(notesService.adHocMeetings.count)")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.tuiHover)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.tuiBackground)

                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)

                // Meetings list
                ForEach(notesService.adHocMeetings) { meeting in
                    AdHocMeetingRow(meeting: meeting)

                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Ad-Hoc Meeting Row

struct AdHocMeetingRow: View {
    let meeting: AdHocMeeting
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @StateObject private var notesService = MeetingNotesService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button {
                withAnimation(.tuiSnappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Time indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timeString(from: meeting.createdAt))
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)

                        Text(dateString(from: meeting.createdAt))
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    }
                    .frame(width: 55)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !meeting.notes.isEmpty {
                            Text(String(meeting.notes.prefix(60)))
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Expand indicator
                    Text(isExpanded ? "−" : "+")
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isHovered ? Color.tuiHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

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

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title editing
            if isEditing {
                HStack(spacing: Spacing.sm) {
                    TextField("Titel", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.tuiMonoSmall)
                        .padding(Spacing.sm)
                        .background(Color.tuiBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.tuiBorder, lineWidth: 1)
                        )

                    Button("OK") {
                        notesService.updateAdHocMeeting(id: meeting.id, title: editedTitle)
                        isEditing = false
                    }
                    .buttonStyle(.tuiPrimary)

                    Button("Abbrechen") {
                        isEditing = false
                    }
                    .buttonStyle(.tuiGhost)
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("TRANSKRIPTION")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Text(meeting.notes)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    editedTitle = meeting.title
                    isEditing = true
                } label: {
                    Text("Umbenennen")
                }
                .buttonStyle(.tui)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meeting.notes, forType: .string)
                } label: {
                    Text("Kopieren")
                }
                .buttonStyle(.tui)

                Spacer()

                Button {
                    withAnimation(.tuiSnappy) {
                        notesService.deleteAdHocMeeting(id: meeting.id)
                    }
                } label: {
                    Text("Löschen")
                        .foregroundStyle(Color.recordingActive)
                }
                .buttonStyle(.tuiGhost)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover)
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: date)
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let item: BriefingItem
    var onTap: ((BriefingItem) -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Button {
            if let onTap {
                onTap(item)
            } else if let meetingLink = item.metadata["meetingLink"],
               let url = URL(string: meetingLink) {
                NSWorkspace.shared.open(url)
            } else if let deepLink = item.deepLink {
                NSWorkspace.shared.open(deepLink)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Time
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = item.subtitle {
                        Text(subtitle.components(separatedBy: " - ").first ?? subtitle)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 60, alignment: .leading)
                
                // Title
                Text(item.title)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Duration
                if let duration = item.metadata["duration"] {
                    Text("[\(duration)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }
                
                // Link indicator
                if item.metadata["meetingLink"] != nil {
                    Text("📹")
                        .font(.tuiMonoTiny)
                }
                
                // Arrow
                Text("→")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Color.tuiHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}


