import SwiftUI

/// Chat view for asking questions about meeting transcripts
struct TranscriptChatView: View {
    let meetingId: String
    let onJumpToTimestamp: ((TimeInterval) -> Void)?
    
    @ObservedObject private var chatService = TranscriptChatService.shared
    @StateObject private var vectorStore = VectorStore.shared
    
    @State private var inputText = ""
    @State private var showingSuggestedQuestions = true
    @FocusState private var isInputFocused: Bool
    
    init(meetingId: String, onJumpToTimestamp: ((TimeInterval) -> Void)? = nil) {
        self.meetingId = meetingId
        self.onJumpToTimestamp = onJumpToTimestamp
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Check if transcript is available
            if !vectorStore.hasChunks(for: meetingId) {
                emptyState
            } else {
                // Messages list
                messagesList
                
                divider
                
                // Suggested questions (show when no messages)
                if messages.isEmpty && showingSuggestedQuestions {
                    suggestedQuestionsView
                }
                
                // Input field
                inputField
            }
        }
        .background(Color.tuiBackground)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("Kein Transkript verfügbar")
                .font(.tuiMonoSmall)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Text("Bitte zuerst eine Aufnahme transkribieren")
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
    
    // MARK: - Messages List
    
    private var messages: [TranscriptChatMessage] {
        chatService.getMessages(for: meetingId)
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if messages.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "message")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            
                            Text("Stelle eine Frage zum Meeting")
                                .font(.tuiMonoSmall)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                    } else {
                        ForEach(messages) { message in
                            ChatMessageRow(
                                message: message,
                                onJumpToTimestamp: onJumpToTimestamp
                            )
                            .id(message.id)
                        }
                    }
                    
                    // Loading indicator
                    if chatService.isGenerating {
                        TypingBubbleView()
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(Spacing.md)
            }
            .onChange(of: messages.count) { _ in
                // Scroll to bottom when new message arrives
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Suggested Questions
    
    private var suggestedQuestions: [String] {
        [
            "Was waren die wichtigsten Entscheidungen?",
            "Welche Action Items wurden besprochen?",
            "Fasse das Meeting zusammen",
            "Welche Themen wurden diskutiert?"
        ]
    }
    
    private var suggestedQuestionsView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("VORSCHLÄGE")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            inputText = question
                            showingSuggestedQuestions = false
                            sendMessage()
                        } label: {
                            Text(question)
                                .font(.tuiMonoTiny)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Input Field
    
    private var inputField: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Frage zum Meeting stellen...", text: $inputText)
                .font(.tuiMonoTiny)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(chatService.isGenerating)
            
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(inputText.isEmpty ? .tertiary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || chatService.isGenerating)
            
            if !messages.isEmpty {
                Button {
                    chatService.clearChat(for: meetingId)
                    showingSuggestedQuestions = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(Color.tuiHover)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(Spacing.md)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.tuiBorder)
            .frame(height: 1)
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let messageText = inputText
        inputText = ""
        showingSuggestedQuestions = false
        
        Task {
            do {
                try await chatService.sendMessage(messageText, meetingId: meetingId)
            } catch {
                // Show error (could add error banner here)
                print("❌ Chat error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview

struct TranscriptChatView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptChatView(meetingId: "preview-meeting-id")
            .frame(width: 400, height: 500)
    }
}
