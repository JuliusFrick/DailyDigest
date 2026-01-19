import SwiftUI

// MARK: - Meetings View

struct MeetingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var notesService = MeetingNotesService.shared
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    
    private var hasCalendarConnected: Bool {
        connectionManager.isConnected(.googleCalendar) ||
        connectionManager.googleCalendarSource?.isAuthenticated == true
        // Note: Apple Calendar doesn't have a dedicated source yet
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MEETINGS")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if let briefing = appState.currentBriefing {
                    let meetingsCount = allMeetings(from: briefing).count
                    let adHocCount = notesService.adHocMeetings.count
                    let total = meetingsCount + adHocCount
                    Text("\(total) meetings")
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
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Calendar view (if calendar is connected)
                    if hasCalendarConnected, let briefing = appState.currentBriefing {
                        let meetings = allMeetings(from: briefing)
                        WeekCalendarView(meetings: meetings)
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                    
                    // Ad-hoc recording section (always visible)
                    AdHocRecordingSection()
                    
                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(height: 1)
                    
                    // Ad-hoc meetings list
                    if !notesService.adHocMeetings.isEmpty {
                        AdHocMeetingsSection()
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                    
                    // Calendar meetings
                    if let briefing = appState.currentBriefing {
                        let meetings = allMeetings(from: briefing)
                        
                        if !meetings.isEmpty {
                            calendarMeetingsHeader
                            
                            ForEach(meetings) { item in
                                MeetingRow(item: item)
                                
                                Rectangle()
                                    .fill(Color.tuiBorder)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.tuiBackground)
    }
    
    private var calendarMeetingsHeader: some View {
        HStack {
            Text("KALENDER-TERMINE")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.quaternary)
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiHover.opacity(0.3))
    }
    
    private func allMeetings(from briefing: Briefing) -> [BriefingItem] {
        briefing.sections.flatMap { section in
            section.items.filter { item in
                // Filter items that have meeting links or are calendar events
                item.metadata["meetingLink"] != nil ||
                item.metadata["attendees"] != nil ||
                section.sourceId == "google_calendar" ||
                section.sourceId == "apple_calendar"
            }
        }
        .sorted { item1, item2 in
            // Sort by timestamp if available
            if let time1 = item1.timestamp, let time2 = item2.timestamp {
                return time1 < time2
            }
            return false
        }
    }
}

// MARK: - Week Calendar View

struct WeekCalendarView: View {
    let meetings: [BriefingItem]
    
    @State private var selectedDate: Date = Date()
    
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
                Text("KALENDER")
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
                                endHour: endHour
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
    
    private let calendar = Calendar.current
    
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
            
            // Events
            ForEach(meetings) { meeting in
                if let timestamp = meeting.timestamp {
                    EventBlock(
                        meeting: meeting,
                        hourHeight: hourHeight,
                        startHour: startHour,
                        topOffset: offsetForTime(timestamp)
                    )
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
    
    @State private var isHovered = false
    
    private var duration: CGFloat {
        // Try to parse duration from metadata, default to 1 hour
        if let durationStr = meeting.metadata["duration"] {
            // Parse "1h 30m" or "30m" format
            var totalMinutes: CGFloat = 0
            let components = durationStr.lowercased().components(separatedBy: " ")
            for component in components {
                if component.contains("h") {
                    if let hours = Double(component.replacingOccurrences(of: "h", of: "")) {
                        totalMinutes += CGFloat(hours) * 60
                    }
                } else if component.contains("m") {
                    if let minutes = Double(component.replacingOccurrences(of: "m", of: "")) {
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
        .padding(.horizontal, 1)
        .onHover { isHovered = $0 }
        .help(meeting.title + (meeting.subtitle.map { " - \($0)" } ?? ""))
    }
}

// MARK: - Ad-Hoc Recording Section

struct AdHocRecordingSection: View {
    @StateObject private var recordingService = AudioRecordingService.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("🎤")
                    .font(.tuiMonoSmall)
                Text("Neue Aufnahme")
                    .font(.tuiMonoSmall)
                    .fontWeight(.medium)
            }
            
            if isRecording {
                // Recording in progress
                HStack(spacing: Spacing.sm) {
                    // Recording indicator
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(recordingService.isRecording ? 1 : 0.5)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)
                        
                        Text(recordingService.formattedDuration())
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stop button
                    Button {
                        stopRecording()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("⏹")
                            Text("Aufnahme beenden")
                                .font(.tuiMonoTiny)
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                }
            } else if isTranscribing {
                // Transcribing
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Transkribiere...")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Start recording button
                HStack {
                    Button {
                        startRecording()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("🔴")
                            Text("Aufnahme starten")
                                .font(.tuiMonoTiny)
                        }
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
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.3))
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
                
                // Create ad-hoc meeting with the transcription
                notesService.createAdHocMeeting(notes: transcription)
                
                // Clean up audio file
                try? FileManager.default.removeItem(at: audioURL)
                
                isTranscribing = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isTranscribing = false
                
                // Clean up audio file on error
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }
}

// MARK: - Ad-Hoc Meetings Section

struct AdHocMeetingsSection: View {
    @StateObject private var notesService = MeetingNotesService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AUFNAHMEN")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.quaternary)
                
                Spacer()
                
                Text("\(notesService.adHocMeetings.count)")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            // Meetings list
            ForEach(notesService.adHocMeetings) { meeting in
                AdHocMeetingRow(meeting: meeting)
                
                Rectangle()
                    .fill(Color.tuiBorder.opacity(0.5))
                    .frame(height: 1)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeString(from: meeting.createdAt))
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                        
                        Text(dateString(from: meeting.createdAt))
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    }
                    .frame(width: 60)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text("\(meeting.notes.prefix(50))...")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Indicators
                    HStack(spacing: Spacing.xs) {
                        Text("📝")
                            .font(.tuiMonoTiny)
                        
                        Text(isExpanded ? "▼" : "▶")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    }
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title editing
            if isEditing {
                HStack {
                    TextField("Titel", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.tuiMonoSmall)
                        .padding(Spacing.xs)
                        .background(Color.tuiBackground)
                        .cornerRadius(4)
                    
                    Button("Speichern") {
                        notesService.updateAdHocMeeting(id: meeting.id, title: editedTitle)
                        isEditing = false
                    }
                    .buttonStyle(.tui)
                    
                    Button("Abbrechen") {
                        isEditing = false
                    }
                    .buttonStyle(.tui)
                }
            }
            
            // Notes
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text("📝")
                        .font(.tuiMonoTiny)
                    Text("Notizen")
                        .font(.tuiMonoTiny)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                Text(meeting.notes)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            
            Divider()
                .padding(.vertical, Spacing.xs)
            
            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    editedTitle = meeting.title
                    isEditing = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("✏️")
                        Text("Umbenennen")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meeting.notes, forType: .string)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("📋")
                        Text("Kopieren")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                
                Spacer()
                
                Button {
                    notesService.deleteAdHocMeeting(id: meeting.id)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("🗑")
                        Text("Löschen")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.5))
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
    @State private var isExpanded = false
    @State private var isHovered = false
    @StateObject private var recordingService = AudioRecordingService.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared
    @State private var meetingNotes: String?
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
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
                    if let timestamp = item.timestamp {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timeString(from: timestamp))
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.secondary)
                            
                            if let duration = item.metadata["duration"] {
                                Text(duration)
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .frame(width: 60)
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.tuiMonoSmall)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Indicators
                    HStack(spacing: Spacing.xs) {
                        if item.metadata["meetingLink"] != nil {
                            Text("📹")
                                .font(.tuiMonoTiny)
                        }
                        
                        if meetingNotes?.isEmpty == false || item.metadata["meetingNotes"]?.isEmpty == false {
                            Text("📝")
                                .font(.tuiMonoTiny)
                        }
                        
                        Text(isExpanded ? "▼" : "▶")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.quaternary)
                    }
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
        .onAppear {
            loadMeetingNotes()
        }
    }
    
    private func loadMeetingNotes() {
        meetingNotes = notesService.getNotes(for: item) ?? item.metadata["meetingNotes"]
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Attendees
            if let attendees = item.metadata["attendees"], !attendees.isEmpty {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("👥")
                        .font(.tuiMonoTiny)
                    Text(attendees)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
                        .lineLimit(2)
                }
            }
            
            // Description/Body
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .lineLimit(6)
                    .padding(.top, Spacing.xs)
            }
            
            // Meeting notes
            if let notes = meetingNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text("📝")
                            .font(.tuiMonoTiny)
                        Text("Meeting-Notizen")
                            .font(.tuiMonoTiny)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Text(notes)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xs)
            }
            
            // Recording controls
            recordingControls
            
            Divider()
                .padding(.vertical, Spacing.xs)
            
            // Action buttons
            HStack(spacing: Spacing.sm) {
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
                }
                
                // Deep link to calendar
                if let deepLink = item.deepLink {
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
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.5))
    }
    
    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("🎤")
                    .font(.tuiMonoTiny)
                Text("Meeting aufnehmen")
                    .font(.tuiMonoTiny)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            if isRecording {
                // Recording in progress
                HStack(spacing: Spacing.sm) {
                    // Recording indicator
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(recordingService.isRecording ? 1 : 0.5)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)
                        
                        Text(recordingService.formattedDuration())
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stop button
                    Button {
                        stopRecording()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("⏹")
                            Text("Stop")
                                .font(.tuiMonoTiny)
                        }
                    }
                    .buttonStyle(.tui)
                }
            } else if isTranscribing {
                // Transcribing
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Transkribiere...")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Start recording button
                Button {
                    startRecording()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("🔴")
                        Text("Aufnahme starten")
                            .font(.tuiMonoTiny)
                    }
                }
                .buttonStyle(.tui)
                .disabled(!recordingService.hasPermission)
            }
        }
        .padding(.top, Spacing.xs)
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
                
                // Save notes
                let meetingId = notesService.meetingId(for: item)
                notesService.saveNotes(meetingId: meetingId, notes: transcription)
                meetingNotes = transcription
                
                // Clean up audio file
                try? FileManager.default.removeItem(at: audioURL)
                
                isTranscribing = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isTranscribing = false
                
                // Clean up audio file on error
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - TUI Meetings View (for modal)

struct TUIMeetingsView: View {
    var body: some View {
        MeetingsView()
    }
}
