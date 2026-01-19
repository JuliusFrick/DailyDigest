import SwiftUI

// MARK: - Meetings View

struct MeetingsView: View {
    @EnvironmentObject private var appState: AppState
    
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
                    Text("\(meetingsCount) meetings")
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
            
            // Meetings list
            if let briefing = appState.currentBriefing {
                let meetings = allMeetings(from: briefing)
                
                if meetings.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(meetings) { item in
                                MeetingRow(item: item)
                                
                                Rectangle()
                                    .fill(Color.tuiBorder)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color.tuiBackground)
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Text("─────────────────")
                .font(.tuiMonoSmall)
                .foregroundStyle(.quaternary)
            
            Text("no meetings")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)
            
            Text("generate a briefing to see meetings")
                .font(.tuiMonoTiny)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        
                        if item.metadata["meetingNotes"]?.isEmpty == false {
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
        let meetingId = notesService.meetingId(for: item)
        meetingNotes = notesService.getNotes(meetingId: meetingId) ?? item.metadata["meetingNotes"]
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
