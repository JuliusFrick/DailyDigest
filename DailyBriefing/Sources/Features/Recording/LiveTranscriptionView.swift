import SwiftUI

/// Real-time transcription view during meeting recording
struct LiveTranscriptionView: View {
    @StateObject private var viewModel = LiveTranscriptionViewModel()
    @StateObject private var recorder = AudioRecordingService.shared
    
    let meetingTitle: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Transcription panel
                transcriptionPanel
                    .frame(minWidth: 400)
                
                Divider()
                
                // Action items panel
                actionItemsPanel
                    .frame(width: 280)
            }
            
            Divider()
            
            // Footer with controls
            footer
        }
        .frame(width: 720, height: 500)
        .background(Color.tuiBackground)
        .onAppear {
            viewModel.startSession(meetingTitle: meetingTitle)
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if recorder.isRecording {
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(viewModel.pulseAnimation ? 1.5 : 1.0)
                                .opacity(viewModel.pulseAnimation ? 0 : 1)
                                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: viewModel.pulseAnimation)
                        }
                    }
                
                Text(recorder.isRecording ? "LIVE" : "PAUSED")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(recorder.isRecording ? .red : .secondary)
            }
            
            Spacer()
            
            // Meeting title
            Text(meetingTitle.uppercased())
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
            
            Spacer()
            
            // Duration
            Text(viewModel.formattedDuration)
                .font(.tuiMono)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            
            // Close button
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(.leading, Spacing.md)
        }
        .padding(Spacing.md)
        .background(Color.tuiBackground)
    }
    
    // MARK: - Transcription Panel
    
    private var transcriptionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Image(systemName: "text.alignleft")
                Text("Live Transkription")
                    .font(.tuiMonoSmall)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Status indicator
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            // Transcription content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(viewModel.transcriptionSegments) { segment in
                            TranscriptionSegmentRow(segment: segment)
                                .id(segment.id)
                        }
                        
                        // Current partial transcription
                        if !viewModel.currentPartial.isEmpty {
                            Text(viewModel.currentPartial)
                                .font(.tuiBody)
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.horizontal, Spacing.sm)
                        }
                        
                        // Anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(Spacing.sm)
                }
                .onChange(of: viewModel.transcriptionSegments.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Action Items Panel
    
    private var actionItemsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Image(systemName: "checklist")
                Text("Action Items")
                    .font(.tuiMonoSmall)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(viewModel.actionItems.count)")
                    .font(.tuiMonoTiny)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.tuiAccent.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(Spacing.sm)
            .background(Color.tuiHover.opacity(0.3))
            
            // Action items list
            if viewModel.actionItems.isEmpty {
                VStack {
                    Spacer()
                    Text("Action Items werden automatisch erkannt...")
                        .font(.tuiCaption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(viewModel.actionItems) { item in
                            LiveActionItemRow(item: item)
                        }
                    }
                    .padding(Spacing.sm)
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            // Voxtral status
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.voxtralStatus == .running ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(viewModel.voxtralStatus == .running ? "Voxtral On-Device" : "Cloud Fallback")
                    .font(.tuiCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Recording controls
            HStack(spacing: Spacing.sm) {
                Button {
                    if recorder.isRecording {
                        recorder.pauseRecording()
                    } else {
                        recorder.resumeRecording()
                    }
                } label: {
                    Image(systemName: recorder.isRecording ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.tui)
                
                Button {
                    viewModel.stopSession()
                    isPresented = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Beenden")
                    }
                }
                .buttonStyle(.tuiPrimary)
            }
        }
        .padding(Spacing.md)
        .background(Color.tuiBackground)
    }
}

// MARK: - Transcription Segment Row

struct TranscriptionSegmentRow: View {
    let segment: TranscriptionSegment
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Timestamp
            Text(segment.formattedTimestamp)
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .leading)
            
            // Speaker (if available)
            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.tuiMonoTiny)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
            }
            
            // Text
            Text(segment.text)
                .font(.tuiBody)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(segment.hasActionItem ? Color.tuiAccent.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Live Action Item Row

struct LiveActionItemRow: View {
    let item: LiveActionItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.tuiSmall)
                .fontWeight(.medium)
            
            if let assignee = item.assignee {
                HStack(spacing: 4) {
                    Image(systemName: "person")
                        .font(.system(size: 10))
                    Text(assignee)
                        .font(.tuiCaption)
                }
                .foregroundStyle(.secondary)
            }
            
            Text(item.formattedTimestamp)
                .font(.tuiCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tuiHover.opacity(0.5))
        .cornerRadius(4)
    }
}

// MARK: - View Model

@MainActor
class LiveTranscriptionViewModel: ObservableObject {
    @Published var transcriptionSegments: [TranscriptionSegment] = []
    @Published var actionItems: [LiveActionItem] = []
    @Published var currentPartial = ""
    @Published var isProcessing = false
    @Published var voxtralStatus: LocalTranscriptionService.ServerStatus = .unknown
    @Published var pulseAnimation = false
    
    private var sessionStartTime: Date?
    private var streamingSession: StreamingSession?
    private var timer: Timer?
    
    private let localTranscription = LocalTranscriptionService.shared
    private let actionItemExtractor = ActionItemExtractionService.shared
    
    var formattedDuration: String {
        guard let start = sessionStartTime else { return "00:00" }
        let duration = Date().timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func startSession(meetingTitle: String) {
        sessionStartTime = Date()
        pulseAnimation = true
        
        // Check Voxtral availability
        Task {
            await localTranscription.checkServerHealth()
            voxtralStatus = localTranscription.serverStatus
            
            // Start streaming if available
            if voxtralStatus == .running {
                startStreaming()
            }
        }
        
        // Update timer for duration display
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    
    func stopSession() {
        streamingSession?.stop()
        streamingSession = nil
        timer?.invalidate()
        timer = nil
        pulseAnimation = false
    }
    
    private func startStreaming() {
        streamingSession = localTranscription.startStreamingTranscription(
            language: "de"
        ) { [weak self] text in
            Task { @MainActor in
                self?.handleTranscriptionResult(text)
            }
        }
        streamingSession?.start()
    }
    
    private func handleTranscriptionResult(_ text: String) {
        guard !text.isEmpty else { return }
        
        let segment = TranscriptionSegment(
            timestamp: Date().timeIntervalSince(sessionStartTime ?? Date()),
            text: text,
            speaker: nil // Diarization would go here
        )
        
        transcriptionSegments.append(segment)
        
        // Extract action items from new text
        Task {
            await extractActionItems(from: text)
        }
    }
    
    private func extractActionItems(from text: String) async {
        // Simple pattern matching for now
        // TODO: Use Gemini for smarter extraction
        let patterns = [
            "(?:ich|wir|du|er|sie) (?:muss|müssen|sollte|sollten|werde|werden|kann|können) (.+)",
            "TODO:? (.+)",
            "Action Item:? (.+)",
            "(?:bitte|please) (.+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let taskRange = Range(match.range(at: 1), in: text) {
                        let task = String(text[taskRange])
                        let item = LiveActionItem(
                            title: task.trimmingCharacters(in: .whitespaces),
                            timestamp: Date().timeIntervalSince(sessionStartTime ?? Date()),
                            assignee: nil
                        )
                        
                        // Mark segment as having action item
                        if let lastIndex = transcriptionSegments.indices.last {
                            transcriptionSegments[lastIndex].hasActionItem = true
                        }
                        
                        actionItems.append(item)
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Models

struct TranscriptionSegment: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
    let speaker: String?
    var hasActionItem = false
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct LiveActionItem: Identifiable {
    let id = UUID()
    let title: String
    let timestamp: TimeInterval
    let assignee: String?
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    LiveTranscriptionView(
        meetingTitle: "Standup Meeting",
        isPresented: .constant(true)
    )
}
