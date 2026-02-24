import SwiftUI
import AppKit
import SwiftTerm

struct TerminalsPanelView: View {
    @StateObject private var sessionManager = TerminalSessionManager.shared

    @State private var requestedSessionName = ""
    @State private var isCreatingSession = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            HStack(spacing: 0) {
                sessionList

                Divider()

                terminalHost
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.tuiBackground)
        .onAppear {
            if sessionManager.selectedSessionID == nil, let first = sessionManager.sessions.first?.id {
                sessionManager.selectedSessionID = first
            }
        }
        .alert("Neue Sitzung benennen", isPresented: $isCreatingSession) {
            TextField("Name", text: $requestedSessionName)
                .textFieldStyle(.roundedBorder)
            Button("Erstellen") {
                let title = requestedSessionName.isEmpty ? "Terminal" : requestedSessionName
                let sessionID = sessionManager.openSession(title: title)
                sessionManager.selectSession(sessionID)
                requestedSessionName = ""
            }
            Button("Abbrechen", role: .cancel) {
                requestedSessionName = ""
            }
        } message: {
            Text("Gib einen Titel für die neue Sitzung ein.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            Text("Terminals")
                .font(.tuiMonoSmall)
                .foregroundStyle(.secondary)
                .padding(.leading, Spacing.md)

            Spacer()

            Button("Neue Sitzung") {
                requestedSessionName = "Terminal \(sessionManager.sessions.count + 1)"
                isCreatingSession = true
            }
            .buttonStyle(.tui)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Terminal schließen") {
                if let selected = sessionManager.activeSession?.id {
                    sessionManager.closeSession(selected)
                }
            }
            .buttonStyle(.tui)
            .disabled(sessionManager.sessions.count <= 1)
            .help("Mindestens eine Sitzung bleibt erhalten")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var sessionList: some View {
        List(selection: $sessionManager.selectedSessionID) {
            Section("Sitzungen") {
                ForEach(sessionManager.sessions) { session in
                    HStack {
                        Text(session.title)
                            .lineLimit(1)
                            .font(.tuiMonoSmall)
                        Spacer()
                        if sessionManager.selectedSessionID == session.id {
                            Text("●")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .tag(session.id)
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(minWidth: 230, maxWidth: 260)
        .listStyle(.sidebar)
        .onChange(of: sessionManager.selectedSessionID) { _, newValue in
            if let newValue {
                sessionManager.selectSession(newValue)
            }
        }
    }

    @ViewBuilder
    private var terminalHost: some View {
        if let session = sessionManager.activeSession {
            SwiftTermHostView(session: session)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: "terminal")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Keine aktive Sitzung")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.quaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SwiftTermHostView: NSViewRepresentable {
    let session: TerminalSessionManager.Session

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: CGRect.zero)
        terminalView.translatesAutoresizingMaskIntoConstraints = true
        terminalView.autoresizingMask = [.width, .height]
        context.coordinator.bind(view: terminalView, to: session)
        startSessionIfNeeded(on: terminalView)
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.updateSessionIfNeeded(session, terminal: nsView)
        startSessionIfNeeded(on: nsView)
    }

    private func startSessionIfNeeded(on terminal: LocalProcessTerminalView) {
        if !terminal.process.running {
            terminal.startProcess(currentDirectory: session.workingDirectory)
            if let command = session.initialCommand, !command.isEmpty {
                DispatchQueue.main.async {
                    terminal.send(txt: "\(command)\n")
                }
            }
        }
    }

    func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    final class Coordinator {
        private var lastSessionID: UUID?

        func bind(view: LocalProcessTerminalView, to session: TerminalSessionManager.Session) {
            lastSessionID = session.id
        }

        func updateSessionIfNeeded(_ session: TerminalSessionManager.Session, terminal: LocalProcessTerminalView) {
            guard lastSessionID != session.id else { return }
            lastSessionID = session.id
            terminal.process.terminate()
            terminal.startProcess(currentDirectory: session.workingDirectory)
            if let command = session.initialCommand, !command.isEmpty {
                DispatchQueue.main.async {
                    terminal.send(txt: "\(command)\n")
                }
            }
        }
    }
}
