import SwiftUI

// MARK: - Recordings View (Meeting Notes Overview)

/// Shows all recorded meetings - both calendar-based and ad-hoc recordings
struct RecordingsView: View {
    @StateObject private var notesService = MeetingNotesService.shared
    @StateObject private var recorder = AudioRecordingService.shared
    @StateObject private var connectionManager = ServiceConnectionManager.shared
    
    @State private var selectedRecording: RecordingItem?
    @State private var showRecordingPopup = false
    @State private var showQuickRecord = false
    @State private var quickRecordTitle = ""
    @State private var isLoadingCalendarMeetings = false
    @State private var calendarMeetingsWithNotes: [BriefingItem] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
            
            // Content
            if notesService.adHocMeetings.isEmpty && calendarMeetingsWithNotes.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
        .background(Color.tuiBackground)
        .task {
            await loadCalendarMeetingsWithNotes()
        }
        .sheet(isPresented: $showQuickRecord) {
            QuickRecordSheet(isPresented: $showQuickRecord)
        }
        .sheet(item: $selectedRecording) { item in
            if case .adHoc(let meeting) = item {
                AdHocMeetingDetailPopup(meeting: meeting, isPresented: .init(
                    get: { selectedRecording != nil },
                    set: { if !$0 { selectedRecording = nil } }
                ))
            } else if case .calendar(let briefingItem) = item {
                MeetingDetailPopup(meeting: briefingItem, isPresented: .init(
                    get: { selectedRecording != nil },
                    set: { if !$0 { selectedRecording = nil } }
                ))
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("AUFNAHMEN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)
            
            Spacer()
            
            // Quick Record Button
            Button {
                showQuickRecord = true
            } label: {
                HStack(spacing: 4) {
                    Text("●")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                    Text("Neue Aufnahme")
                        .font(.tuiMonoTiny)
                }
            }
            .buttonStyle(.tui)
        }
        .padding(Spacing.md)
        .background(Color.tuiBackground)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            
            Text("🎙")
                .font(.system(size: 48))
            
            Text("Keine Aufnahmen")
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            Text("Starte eine Aufnahme um Meeting-Notizen,\nTranskriptionen und Action Items zu erstellen.")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            
            Button {
                showQuickRecord = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("●")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                    Text("Aufnahme starten")
                        .font(.tuiMonoSmall)
                }
            }
            .buttonStyle(.tuiPrimary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
    
    // MARK: - Recordings List
    
    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Ad-hoc Recordings Section
                if !notesService.adHocMeetings.isEmpty {
                    sectionHeader("SPONTANE AUFNAHMEN", count: notesService.adHocMeetings.count)
                    
                    ForEach(notesService.adHocMeetings) { meeting in
                        AdHocRecordingRow(meeting: meeting) {
                            selectedRecording = .adHoc(meeting)
                        }
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                }
                
                // Calendar Meetings with Notes
                if !calendarMeetingsWithNotes.isEmpty {
                    sectionHeader("KALENDER-MEETINGS", count: calendarMeetingsWithNotes.count)
                    
                    ForEach(calendarMeetingsWithNotes) { item in
                        CalendarRecordingRow(item: item) {
                            selectedRecording = .calendar(item)
                        }
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.quaternary)
            
            Spacer()
            
            Text("\(count)")
                .font(.tuiMonoTiny)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiHover.opacity(0.3))
    }
    
    // MARK: - Load Calendar Meetings
    
    private func loadCalendarMeetingsWithNotes() async {
        // Get all meeting IDs that have notes stored
        let meetingIdsWithNotes = notesService.allMeetingIdsWithNotes()
        
        // If no notes exist, return early
        guard !meetingIdsWithNotes.isEmpty else {
            calendarMeetingsWithNotes = []
            return
        }
        
        // Fetch recent calendar events (last 30 days)
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        // Get events from all connected calendar sources
        var allEvents: [BriefingItem] = []
        
        // Apple Calendar
        if let appleSource = connectionManager.appleCalendarSource {
            do {
                let events = try await appleSource.fetchEvents(from: startDate, to: Date())
                allEvents.append(contentsOf: events)
            } catch {
                print("Failed to fetch Apple Calendar events: \(error)")
            }
        }
        
        // Google Calendar
        if let googleSource = connectionManager.googleCalendarSource {
            do {
                let events = try await googleSource.fetchEvents(from: startDate, to: Date())
                allEvents.append(contentsOf: events)
            } catch {
                print("Failed to fetch Google Calendar events: \(error)")
            }
        }
        
        // Match events with notes and update UI
        await MainActor.run {
            calendarMeetingsWithNotes = allEvents.filter { item in
                let meetingId = notesService.meetingId(for: item)
                return meetingIdsWithNotes.contains(meetingId)
            }
        }
    }
}

// MARK: - Recording Item Enum

enum RecordingItem: Identifiable {
    case adHoc(AdHocMeeting)
    case calendar(BriefingItem)
    
    var id: String {
        switch self {
        case .adHoc(let meeting): return "adhoc_\(meeting.id)"
        case .calendar(let item): return "cal_\(item.id)"
        }
    }
}

// MARK: - Ad-Hoc Recording Row

struct AdHocRecordingRow: View {
    let meeting: AdHocMeeting
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM, HH:mm"
        return formatter.string(from: meeting.createdAt)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Text("🎙")
                    .font(.tuiMonoSmall)
                    .frame(width: 24)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(formattedDate)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Indicators
                HStack(spacing: Spacing.xs) {
                    if !meeting.notes.isEmpty {
                        Text("📝")
                            .font(.tuiMonoTiny)
                            .help("Hat Notizen")
                    }
                    
                    if meeting.summary != nil {
                        Text("✨")
                            .font(.tuiMonoTiny)
                            .help("Hat Zusammenfassung")
                    }
                }
                
                // Arrow
                Text("→")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0.4)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Color.tuiHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Calendar Recording Row

struct CalendarRecordingRow: View {
    let item: BriefingItem
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    private var formattedDate: String {
        guard let timestamp = item.timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM, HH:mm"
        return formatter.string(from: timestamp)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Text("📅")
                    .font(.tuiMonoSmall)
                    .frame(width: 24)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(formattedDate)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Duration
                if let duration = item.metadata["duration"] {
                    Text("[\(duration)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }
                
                // Arrow
                Text("→")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
                    .opacity(isHovered ? 1 : 0.4)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Color.tuiHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Quick Record Sheet

struct QuickRecordSheet: View {
    @Binding var isPresented: Bool
    
    @StateObject private var recorder = AudioRecordingService.shared
    @StateObject private var transcriber = TranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared
    
    @State private var title = ""
    @State private var recordingURL: URL?
    @State private var transcriptionResult: String?
    @State private var isTranscribing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SCHNELLE AUFNAHME")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button { close() } label: {
                    Text("[ESC]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
            .background(Color.tuiBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.tuiBorder).frame(height: 1)
            }
            
            // Content
            VStack(spacing: Spacing.lg) {
                // Title input
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("TITEL (OPTIONAL)")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)
                    
                    TextField("z.B. Brainstorming Session", text: $title)
                        .textFieldStyle(.plain)
                        .font(.tuiMonoSmall)
                        .padding(Spacing.sm)
                        .background(Color.tuiHover.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                // Recording UI
                VStack(spacing: Spacing.md) {
                    // Recording indicator
                    if recorder.isRecording {
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(.red)
                                .frame(width: 12, height: 12)
                                .scaleEffect(1.0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recorder.isRecording)
                            
                            Text(recorder.formattedDuration())
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, Spacing.lg)
                    }
                    
                    // Record button
                    if recorder.isRecording {
                        Button {
                            Task { await toggleRecording() }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text("⏹")
                                    .font(.tuiMonoSmall)
                                Text("Aufnahme stoppen")
                                    .font(.tuiMonoSmall)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tuiPrimary)
                    } else {
                        Button {
                            Task { await toggleRecording() }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text("●")
                                    .font(.tuiMonoSmall)
                                    .foregroundStyle(Color.red)
                                Text("Aufnahme starten")
                                    .font(.tuiMonoSmall)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tui)
                    }
                }
                
                // Transcription status
                if isTranscribing {
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Transkribiert...")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Transcription result preview
                if let result = transcriptionResult, !result.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("TRANSKRIPTION")
                            .font(.tuiMonoTiny)
                            .fontWeight(.bold)
                            .foregroundStyle(.tertiary)
                        
                        Text(result)
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .padding(Spacing.sm)
                            .background(Color.tuiHover.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                Spacer()
                
                // Save button (after recording stopped)
                if recordingURL != nil && !recorder.isRecording {
                    Button {
                        saveRecording()
                    } label: {
                        HStack {
                            Text("✓")
                            Text("Speichern")
                                .font(.tuiMonoSmall)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tuiPrimary)
                }
            }
            .padding(Spacing.md)
        }
        .frame(width: 400, height: 450)
        .background(Color.tuiBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func toggleRecording() async {
        if recorder.isRecording {
            recordingURL = recorder.stopRecording()
            
            // Auto-transcribe after stopping
            if let url = recordingURL {
                await transcribe(url: url)
            }
        } else {
            do {
                recordingURL = try await recorder.startRecording()
            } catch {
                errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func transcribe(url: URL) async {
        isTranscribing = true
        defer { isTranscribing = false }
        
        do {
            transcriptionResult = try await transcriber.transcribe(audioURL: url)
        } catch {
            print("Transcription error: \(error)")
            // Don't show error - transcription is optional
        }
    }
    
    private func saveRecording() {
        let finalTitle = title.isEmpty ? AdHocMeeting.defaultTitle(for: Date()) : title
        notesService.createAdHocMeeting(
            title: finalTitle,
            notes: transcriptionResult ?? "",
            summary: nil
        )
        close()
    }
    
    private func close() {
        isPresented = false
    }
}

// MARK: - Ad-Hoc Meeting Detail Popup

struct AdHocMeetingDetailPopup: View {
    let meeting: AdHocMeeting
    @Binding var isPresented: Bool
    
    @StateObject private var notesService = MeetingNotesService.shared
    @State private var notes: String
    @State private var title: String
    @State private var isEditingTitle = false
    @State private var isEditingNotes = false
    
    init(meeting: AdHocMeeting, isPresented: Binding<Bool>) {
        self.meeting = meeting
        self._isPresented = isPresented
        self._notes = State(initialValue: meeting.notes)
        self._title = State(initialValue: meeting.title)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy, HH:mm 'Uhr'"
        return formatter.string(from: meeting.createdAt)
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    if isEditingTitle {
                        TextField("Titel", text: $title)
                            .textFieldStyle(.plain)
                            .font(.tuiMonoSmall)
                            .fontWeight(.bold)
                            .onSubmit {
                                notesService.updateAdHocMeeting(id: meeting.id, title: title)
                                isEditingTitle = false
                            }
                    } else {
                        Text(title.uppercased())
                            .font(.tuiMonoSmall)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .onTapGesture {
                                isEditingTitle = true
                            }
                    }
                    
                    Spacer()
                    
                    Button { close() } label: {
                        Text("[ESC]")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.md)
                .background(Color.tuiBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.tuiBorder).frame(height: 1)
                }
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Date
                        HStack(spacing: Spacing.sm) {
                            Text("📅")
                            Text(formattedDate)
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.secondary)
                        }
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                        
                        // Notes section
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                Text("TRANSKRIPTION / NOTIZEN")
                                    .font(.tuiMonoTiny)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)
                                
                                Spacer()
                                
                                Button {
                                    if isEditingNotes {
                                        notesService.updateAdHocMeeting(id: meeting.id, notes: notes)
                                    }
                                    isEditingNotes.toggle()
                                } label: {
                                    Text(isEditingNotes ? "fertig" : "bearbeiten")
                                        .font(.tuiMonoTiny)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if notes.isEmpty && !isEditingNotes {
                                Text("Keine Notizen vorhanden")
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.quaternary)
                                    .italic()
                            } else {
                                TextEditor(text: $notes)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.tuiHover.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .frame(minHeight: 200)
                                    .disabled(!isEditingNotes)
                            }
                        }
                        
                        // Summary section (if available)
                        if let summary = meeting.summary {
                            Rectangle()
                                .fill(Color.tuiBorder)
                                .frame(height: 1)
                            
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("ZUSAMMENFASSUNG")
                                    .font(.tuiMonoTiny)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)
                                
                                Text(summary)
                                    .font(.tuiMonoTiny)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                        }
                        
                        Rectangle()
                            .fill(Color.tuiBorder)
                            .frame(height: 1)
                        
                        // Delete button
                        HStack {
                            Spacer()
                            
                            Button {
                                notesService.deleteAdHocMeeting(id: meeting.id)
                                close()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("🗑")
                                    Text("Löschen")
                                        .font(.tuiMonoTiny)
                                }
                                .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .frame(width: 480)
            .frame(maxHeight: 500)
            .background(Color.tuiBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }
    
    private func close() {
        // Save any pending edits
        if isEditingNotes {
            notesService.updateAdHocMeeting(id: meeting.id, notes: notes)
        }
        if isEditingTitle {
            notesService.updateAdHocMeeting(id: meeting.id, title: title)
        }
        withAnimation(.tuiSnappy) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#Preview {
    RecordingsView()
        .frame(width: 600, height: 500)
}
