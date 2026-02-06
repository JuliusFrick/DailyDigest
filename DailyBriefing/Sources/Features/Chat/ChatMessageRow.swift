import SwiftUI

/// Row view for a single chat message with optional transcript citations
struct ChatMessageRow: View {
    let message: TranscriptChatMessage
    let onJumpToTimestamp: ((TimeInterval) -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Role icon
            roleIcon
            
            // Message content
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Message text
                Text(message.content)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(message.role == .user ? .primary : .secondary)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                
                // Citations with timestamps (only for assistant messages)
                if message.role == .assistant, let chunks = message.relatedChunks, !chunks.isEmpty {
                    citationsView(chunks: chunks)
                }
                
                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.sm)
        .background(messageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Role Icon
    
    @ViewBuilder
    private var roleIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18))
                .foregroundStyle(.purple)
        case .system:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - Background
    
    private var messageBackground: Color {
        switch message.role {
        case .user:
            return Color.primary.opacity(0.1)
        case .assistant:
            return Color.tuiHover
        case .system:
            return Color.tuiBackground
        }
    }
    
    // MARK: - Citations
    
    private func citationsView(chunks: [TranscriptChunk]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("QUELLEN")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)
                .padding(.top, Spacing.xs)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(chunks.prefix(5).enumerated()), id: \.element.id) { index, chunk in
                        TimestampButton(
                            label: "[\(index + 1)]",
                            time: chunk.startTime,
                            text: chunk.text,
                            onTap: onJumpToTimestamp
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Timestamp Button

/// Button that shows a timestamp and optional preview text
struct TimestampButton: View {
    let label: String
    let time: TimeInterval
    let text: String?
    let onTap: ((TimeInterval) -> Void)?
    
    @State private var isHovering = false
    
    init(
        label: String? = nil,
        time: TimeInterval,
        text: String? = nil,
        onTap: ((TimeInterval) -> Void)? = nil
    ) {
        self.label = label ?? Self.formatTime(time)
        self.time = time
        self.text = text
        self.onTap = onTap
    }
    
    var body: some View {
        Button {
            onTap?(time)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text("\(label) \(formatTime(time))")
                    .font(.tuiMonoTiny)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovering ? 0.2 : 0.1))
            )
        }
        .buttonStyle(.plain)
        .help(text ?? "Springe zu \(formatTime(time))")
        .onHover { hovering in
            isHovering = hovering
        }
        .disabled(onTap == nil)
    }
    
    private static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        Self.formatTime(time)
    }
}

// MARK: - Preview

#Preview("User Message") {
    ChatMessageRow(
        message: TranscriptChatMessage(
            role: .user,
            content: "Was waren die wichtigsten Entscheidungen?"
        ),
        onJumpToTimestamp: nil
    )
    .padding()
    .background(Color.tuiBackground)
}

#Preview("Assistant Message with Citations") {
    ChatMessageRow(
        message: TranscriptChatMessage(
            role: .assistant,
            content: "Die wichtigsten Entscheidungen waren: 1) Wir implementieren das neue Feature bis Ende des Monats. 2) Das Team wird um zwei Entwickler erweitert.",
            relatedChunks: [
                TranscriptChunk(
                    text: "Okay, ich denke wir sollten das Feature bis Ende des Monats fertig haben...",
                    startTime: 125.0,
                    endTime: 140.0
                ),
                TranscriptChunk(
                    text: "Wir brauchen definitiv mehr Leute im Team. Ich schlage vor, zwei weitere Entwickler einzustellen.",
                    startTime: 245.0,
                    endTime: 260.0
                )
            ]
        ),
        onJumpToTimestamp: { time in
            print("Jump to \(time)")
        }
    )
    .padding()
    .background(Color.tuiBackground)
}
