import SwiftUI
import AppKit

/// Apple Mail integration using AppleScript for macOS Mail access
@MainActor
final class AppleMailSource: BriefingSource, ObservableObject {
    nonisolated static let sourceId = "apple_mail"
    static let displayName = "Apple Mail"
    static let iconName = "envelope.fill"
    static let brandColor = Color(red: 0.0, green: 0.48, blue: 1.0)

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Configuration

    @Published var fetchUnreadOnly: Bool = true
    @Published var maxEmailsToFetch: Int = 20
    @Published var selectedMailboxes: Set<String> = ["INBOX"]

    // MARK: - Initialization

    init() {
        checkMailAccess()
    }

    // MARK: - BriefingSource Protocol

    func authenticate() async throws {
        isLoading = true
        connectionStatus = .connecting
        lastError = nil
        defer { isLoading = false }

        do {
            // Request Mail access permission
            let hasAccess = try await requestMailAccess()

            if hasAccess {
                isAuthenticated = true
                connectionStatus = .connected
            } else {
                throw SourceError.authenticationFailed("Zugriff auf Mail wurde verweigert")
            }
        } catch {
            lastError = error
            connectionStatus = .error
            throw error
        }
    }

    func disconnect() async {
        isAuthenticated = false
        connectionStatus = .disconnected
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        guard isAuthenticated else {
            throw SourceError.authenticationFailed("Kein Zugriff auf Apple Mail")
        }

        // Use AppleScript to fetch emails since MailKit has limited direct API
        let emails = try await fetchEmailsViaAppleScript(since: since)

        return emails.prefix(maxEmailsToFetch).map { email in
            BriefingItem(
                title: email.subject,
                subtitle: email.sender,
                body: email.preview,
                timestamp: email.date,
                deepLink: URL(string: "message://\(email.messageId)"),
                priority: email.isRead ? .low : .medium,
                metadata: [
                    "messageId": email.messageId,
                    "mailbox": email.mailbox,
                    "sender": email.sender
                ]
            )
        }
    }

    func configurationView() -> AnyView {
        AnyView(AppleMailConfigView(source: self))
    }

    // MARK: - Private Methods

    private func checkMailAccess() {
        // Check if we have Mail access by trying to run a simple AppleScript
        Task {
            do {
                _ = try await runAppleScript("""
                    tell application "Mail"
                        return name of first account
                    end tell
                """)
                isAuthenticated = true
                connectionStatus = .connected
            } catch {
                isAuthenticated = false
                connectionStatus = .disconnected
            }
        }
    }

    private func requestMailAccess() async throws -> Bool {
        do {
            // Ensure the app is foregrounded so macOS can show the permission prompt.
            NSApplication.shared.activate(ignoringOtherApps: true)

            // Try to access Mail - this will trigger permission dialog if needed
            _ = try await runAppleScript("""
                tell application "Mail"
                    return count of accounts
                end tell
            """)
            return true
        } catch {
            throw SourceError.authenticationFailed("Mail-Zugriff wurde nicht gewährt. Bitte erlaube den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit > Automation.")
        }
    }

    private func fetchEmailsViaAppleScript(since: Date) async throws -> [AppleMailMessage] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let sinceString = dateFormatter.string(from: since)

        let unreadFilter = fetchUnreadOnly ? "whose read status is false" : ""

        let script = """
        tell application "Mail"
            set resultList to {}
            set cutoffDate to date "\(sinceString)"

            repeat with acc in accounts
                try
                    set inboxMailbox to mailbox "INBOX" of acc
                    set msgs to (messages of inboxMailbox \(unreadFilter))

                    repeat with msg in msgs
                        try
                            if date received of msg > cutoffDate then
                                set msgData to {¬
                                    subject:(subject of msg), ¬
                                    sender:(sender of msg), ¬
                                    dateReceived:(date received of msg as string), ¬
                                    messageId:(message id of msg), ¬
                                    isRead:(read status of msg), ¬
                                    preview:(content of msg) ¬
                                }
                                set end of resultList to msgData
                            end if
                        end try

                        if (count of resultList) ≥ \(maxEmailsToFetch) then exit repeat
                    end repeat
                end try

                if (count of resultList) ≥ \(maxEmailsToFetch) then exit repeat
            end repeat

            return resultList
        end tell
        """

        let result = try await runAppleScript(script)
        return parseAppleScriptResult(result)
    }

    private func runAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unbekannter AppleScript-Fehler"
                    continuation.resume(throwing: SourceError.networkError(errorMessage))
                } else if let result = result {
                    continuation.resume(returning: result.stringValue ?? "")
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func parseAppleScriptResult(_ result: String) -> [AppleMailMessage] {
        // AppleScript returns a list of records, parse them
        // This is a simplified parser - in production you'd want more robust parsing
        // For now, return empty array if parsing fails
        // In a real implementation, you would parse the AppleScript record format

        return []
    }
}

// MARK: - Data Models

struct AppleMailMessage {
    let subject: String
    let sender: String
    let date: Date
    let messageId: String
    let isRead: Bool
    let preview: String
    let mailbox: String
}

// MARK: - Alternative Implementation using Mail.framework (when available)

extension AppleMailSource {
    /// Alternative method using scripting bridge if AppleScript fails
    func fetchEmailsUsingScriptingBridge() async throws -> [AppleMailMessage] {
        // ScriptingBridge approach would go here
        // Requires generating bridge headers from Mail.sdef
        return []
    }
}
