import SwiftUI

// MARK: - Meeting Detail Popup

/// Popup das beim Klick auf ein Kalender-Event aufgeht:
/// Details anzeigen, Recording starten, Notizen bearbeiten, Meeting beitreten
struct MeetingDetailPopup: View {
    let meeting: BriefingItem
    @Binding var isPresented: Bool

    @StateObject private var recorder = AudioRecordingService.shared
    @StateObject private var transcriber = VoxtralTranscriptionService.shared
    @StateObject private var notesService = MeetingNotesService.shared

    @State private var notes: String
    @State private var isEditingNotes = false
    @State private var recordingURL: URL?
    @State private var transcriptionResult: VoxtralTranscriptionResponse?
    @State private var showTranscription = false

    init(meeting: BriefingItem, isPresented: Binding<Bool>) {
        self.meeting = meeting
        self._isPresented = isPresented
        self._notes = State(initialValue: MeetingNotesService.shared.getNotes(for: meeting) ?? meeting.metadata["meetingNotes"] ?? "")
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }

            // Popup
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        metaSection
                        divider
                        actionsSection
                        divider
                        notesSection
                        if showTranscription {
                            divider
                            transcriptionSection
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .frame(width: 480, maxHeight: 560)
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(meeting.title.uppercased())
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Recording indicator
            if recorder.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(recorder.isRecording ? 1.0 : 0.6)
                        .animation(.easeInOut(b: 1.2).repeatForever(autoreverses: true), value: recorder.isRecording)
                    Text(recorder.formattedDuration())
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.red)
                }
            }

            Button { close() } label: {
                Text("[ESC]")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tuiBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.tuiBorder).frame(height: 1)
        }
    }

    // MARK: - Meta (Zeit, Ort, Attendees)

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let subtitle = meeting.subtitle {
                metaRow(icon: "⏱", text: subtitle)
            }
            if let duration = meeting.metadata["duration"] {
                metaRow(icon: "📏", text: duration)
            }
            if let location = meeting.metadata["location"], !location.isEmpty {
                metaRow(icon: "📍", text: location)
            }
            if let attendees = meeting.metadata["attendees"], !attendees.isEmpty {
                metaRow(icon: "👥", text: attendees)
            }
            if let body = meeting.body, !body.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("BESCHREIBUNG")
                        .font(.tuiMonoTiny)
                        .fontWeight(.bold)
                        .foregroundStyle(.tertiary)
                    Text(body)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(icon)
                .font(.tuiMonoTiny)
                .frame(width: 18)
            Text(text)
                .font(.tuiMonoTiny)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Actions (Recording, Join)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("AKTIONEN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            HStack(spacing: Spacing.sm) {
                recordButton

                if recordingURL != nil && !recorder.isRecording {
                    transcribeButton
                }

                if let link = meeting.metadata["meetingLink"], let url = URL(string: link) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text("📹")
                            Text("beitreten")
                                .font(.tuiMonoTiny)
                        }
                    }
                    .buttonStyle(.tui)
                }
            }

            if transcriber.isTranscribing {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("transkribiert...")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            Task { await handleRecordToggle() }
        } label: {
            HStack(spacing: 4) {
                Text(recorder.isRecording ? "⏹" : "●")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(recorder.isRecording ? .red : .primary)
                Text(recorder.isRecording ? "stoppen" : "aufnehmen")
                    .font(.tuiMonoTiny)
            }
        }
        .buttonStyle(recorder.isRecording ? .tuiPrimary : .tui)
    }

    private var transcribeButton: some View {
        Button {
            Task { await handleTranscribe() }
        } label: {
            HStack(spacing: 4) {
                Text("📝")
                Text("transkribieren")
                    .font(.tuiMonoTiny)
            }
        }
        .buttonStyle(.tui)
        .disabled(transcriber.isTranscribing)
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("NOTIZEN")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Spacer()

                if !notes.isEmpty {
                    Button {
                        isEditingNotes.toggle()
                    } label: {
                        Text(isEditingNotes ? "fertig" : "bearbeiten")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if notes.isEmpty && !isEditingNotes {
                Button {
                    isEditingNotes = true
                } label: {
                    Text("+ Notiz hinzufügen")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                TextEditor(text: $notes)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .background(Color.tuiHover.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(minHeight: 60, maxHeight: 140)
                    .disabled(!isEditingNotes && !notes.isEmpty)
                    .onChange(of: notes) {
                        notesService.saveNotes(notes, for: meeting)
                    }
            }
        }
    }

    // MARK: - Transcription Result

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("TRANSKRIPTION")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let result = transcriptionResult {
                    Button {
                        let text = result.formattedWithSpeakers
                        notes += (notes.isEmpty ? "" : "\n\n") + text
                        notesService.saveNotes(notes, for: meeting)
                    } label: {
                        Text("→ in Notizen")
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let result = transcriptionResult {
                Text(result.formattedWithSpeakers)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(Spacing.sm)
                    .background(Color.tuiHover.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.tuiBorder)
            .frame(height: 1)
            .padding(.vertical, Spacing.sm)
    }

    private func close() {
        withAnimation(.tuiSnappy) {
            isPresented = false
        }
    }

    private func handleRecordToggle() async {
        if recorder.isRecording {
            recordingURL = recorder.stopRecording()
        } else {
            do {
                recordingURL = try await recorder.startRecording()
            } catch {
                print("Recording error: \(error)")
            }
        }
    }

    private func handleTranscribe() async {
        guard let url = recordingURL else { return }
        do {
            let result = try await transcriber.transcribe(
                audioURL: url,
                language: "de",
                enableDiarization: true
            )
            transcriptionResult = result
            showTranscription = true
        } catch {
            print("Transcription error: \(error)")
        }
    }
}
