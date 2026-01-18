import SwiftUI

/// Chat view for interacting with the briefing
struct BriefingChatView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var chatService = BriefingChatService.shared
    @State private var inputText = ""
    @State private var isInputFocused = false
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()
                .background(Color.tuiBorder)

            // Messages
            if chatService.messages.isEmpty {
                emptyState
            } else {
                messagesList
            }

            Divider()
                .background(Color.tuiBorder)

            // Input
            inputArea
        }
        .background(Color.tuiBackground)
        .onChange(of: appState.currentBriefing?.id) { _, _ in
            chatService.setBriefingContext(appState.currentBriefing)
        }
        .onAppear {
            chatService.setBriefingContext(appState.currentBriefing)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Text("CHAT")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

            if !chatService.messages.isEmpty {
                Button {
                    chatService.clearChat()
                } label: {
                    Text("clear")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(Spacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Text("Frag mich etwas zum Briefing")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                suggestionButton("Was steht heute an?")
                suggestionButton("Welche Meetings habe ich?")
                suggestionButton("Was ist am wichtigsten?")
                suggestionButton("Fasse die E-Mails zusammen")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            Task {
                await sendMessage()
            }
        } label: {
            HStack {
                Text(">")
                    .foregroundStyle(.quaternary)
                Text(text)
                    .foregroundStyle(.secondary)
            }
            .font(.tuiMonoTiny)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
        .background(Color.tuiHover.opacity(0.5))
        .cornerRadius(4)
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(chatService.messages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if chatService.isLoading {
                        loadingIndicator
                    }
                }
                .padding(Spacing.md)
            }
            .onChange(of: chatService.messages.count) { _, _ in
                if let lastMessage = chatService.messages.last {
                    withAnimation(.tuiSmooth) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        HStack(spacing: Spacing.xs) {
            Text("...")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            ProgressView()
                .scaleEffect(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Nachricht eingeben...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.tuiMonoSmall)
                .focused($textFieldFocused)
                .onSubmit {
                    Task {
                        await sendMessage()
                    }
                }
                .disabled(appState.currentBriefing == nil || chatService.isLoading)

            Button {
                Task {
                    await sendMessage()
                }
            } label: {
                Text(">")
                    .font(.tuiMonoSmall)
                    .fontWeight(.bold)
            }
            .buttonStyle(.tuiPrimary)
            .disabled(inputText.isEmpty || chatService.isLoading || appState.currentBriefing == nil)
        }
        .padding(Spacing.md)
    }

    // MARK: - Actions

    private func sendMessage() async {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        do {
            try await chatService.sendMessage(message)
        } catch {
            // Error is handled by the service
        }
    }
}

// MARK: - Chat Message Row

struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Role indicator
            HStack(spacing: Spacing.xs) {
                Text(rolePrefix)
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(roleColor)

                Text(formatTime(message.timestamp))
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }

            // Content
            Text(message.content)
                .font(.tuiMonoSmall)
                .foregroundStyle(message.role == .user ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.sm)
        .background(message.role == .user ? Color.tuiHover : Color.clear)
        .cornerRadius(4)
    }

    private var rolePrefix: String {
        switch message.role {
        case .user: return "Du:"
        case .assistant: return "AI:"
        case .system: return "SYS:"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .primary
        case .assistant: return .blue
        case .system: return .orange
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

