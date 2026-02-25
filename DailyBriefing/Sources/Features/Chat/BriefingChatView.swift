import SwiftUI

/// Chat view for interacting with OpenClaw with thread-based sessions.
struct BriefingChatView: View {
    @StateObject private var chatService = OpenClawChatService.shared
    @State private var inputText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                chatHeader
                threadTabs
                contextHeader
            }
            .background(Color.tuiPanel.opacity(0.5))

            Divider()
                .background(Color.tuiBorder)

            if chatService.activeMessages.isEmpty {
                emptyState
            } else {
                messagesList
            }

            Divider()
                .background(Color.tuiBorder)

            inputArea
        }
        .background(Color.tuiBackground)
        .onAppear {
            if chatService.activeThread == nil {
                chatService.createThread(title: "Neuer Thread")
            }
            chatService.lastError = nil
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Text("OPENCLAW CHAT")
                .font(.tuiMonoTiny)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            Spacer()

            if !chatService.activeMessages.isEmpty {
                Button {
                    chatService.clearMessages()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("clear")
                    }
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Aktuellen Thread leeren")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Thread Tabs

    private var threadTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(chatService.threads) { thread in
                    ThreadTab(
                        thread: thread,
                        isActive: thread.id == chatService.activeThreadID,
                        onSelect: {
                            chatService.selectThread(thread.id)
                        },
                        onClose: {
                            chatService.closeThread(thread.id)
                        }
                    )
                }

                Button {
                    chatService.createThread(title: "Neuer Thread")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Thread")
                    }
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.tui)
                .help("Neuen Thread erstellen")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 36)
    }

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let context = chatService.activeThread?.context {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("Kontext")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(context.source)
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.secondary)
                }

                Text(context.title)
                    .font(.tuiMonoSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Text("Kein Kontext gesetzt")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Text("Frag mich zu einem beliebigen Thema oder nutze einen Context.")
                .font(.tuiMonoSmall)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                suggestionButton("Was steht heute an?")
                suggestionButton("Welche Meetings habe ich?")
                suggestionButton("Was ist am wichtigsten?")
                suggestionButton("Fasse die E-Mails zusammen")
                suggestionButton("Nächste Schritte?")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            Task {
                await sendMessage(using: chatService.activeThread)
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
                    ForEach(chatService.activeMessages) { message in
                        BriefingChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if chatService.isLoading {
                        loadingIndicator
                    }
                }
                .padding(Spacing.md)
            }
            .onChange(of: chatService.activeMessages.count) { _, _ in
                if let lastMessage = chatService.activeMessages.last {
                    withAnimation(.tuiSmooth) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastMessage = chatService.activeMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var loadingIndicator: some View {
        TypingBubbleView()
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .opacity
            ))
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: Spacing.xs) {
            if let error = chatService.lastError {
                Text(error.localizedDescription)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Spacing.sm) {
                TextField("Nachricht eingeben...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.tuiMonoSmall)
                    .focused($textFieldFocused)
                    .onSubmit {
                        Task {
                            await sendMessage(using: chatService.activeThread)
                        }
                    }
                    .disabled(chatService.isLoading)

                Button {
                    Task {
                        await sendMessage(using: chatService.activeThread)
                    }
                } label: {
                    Text(">")
                        .font(.tuiMonoSmall)
                        .fontWeight(.bold)
                }
                .buttonStyle(.tuiPrimary)
                .disabled(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading
                )
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Actions

    private func sendMessage(using thread: OpenClawChatThread?) async {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""
        textFieldFocused = true
        chatService.lastError = nil

        do {
            let targetID = thread?.id
            try await chatService.sendMessage(message, threadID: targetID)
        } catch {
            // Error is already surfaced through chatService.lastError.
        }
    }
}

// MARK: - Thread Tab

private struct ThreadTab: View {
    let thread: OpenClawChatThread
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: thread.context == nil ? "bubble.left" : "link")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.primary : .secondary)

            Text(thread.title)
                .font(.tuiMonoTiny)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.primary.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.primary.opacity(0.35) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Thread aktivieren") {
                onSelect()
            }
            Button("Thread schließen", role: .destructive) {
                onClose()
            }
        }
    }
}

// MARK: - Chat Message Row

struct BriefingChatMessageRow: View {
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
        case .assistant: return "OpenClaw:"
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
