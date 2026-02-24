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

    @Published var fetchUnreadOnly: Bool = true {
        didSet {
            UserDefaults.standard.set(fetchUnreadOnly, forKey: Self.fetchUnreadOnlyKey)
        }
    }
    @Published var includeStarredOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(includeStarredOnly, forKey: Self.includeStarredOnlyKey)
        }
    }
    @Published var includeImportantOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(includeImportantOnly, forKey: Self.includeImportantOnlyKey)
        }
    }
    @Published var maxEmailsToFetch: Int = 20 {
        didSet {
            UserDefaults.standard.set(maxEmailsToFetch, forKey: Self.maxEmailsToFetchKey)
        }
    }
    @Published var selectedMailboxes: Set<String> = ["INBOX"] {
        didSet {
            UserDefaults.standard.set(Array(selectedMailboxes), forKey: Self.selectedMailboxesKey)
        }
    }

    private static let fetchUnreadOnlyKey = "applemail_fetch_unread_only"
    private static let includeStarredOnlyKey = "applemail_include_starred_only"
    private static let includeImportantOnlyKey = "applemail_include_important_only"
    private static let maxEmailsToFetchKey = "applemail_max_emails_to_fetch"
    private static let selectedMailboxesKey = "applemail_selected_mailboxes"

    // MARK: - Initialization

    init() {
        let defaults = UserDefaults.standard
        fetchUnreadOnly = defaults.object(forKey: Self.fetchUnreadOnlyKey) as? Bool ?? true
        includeStarredOnly = defaults.object(forKey: Self.includeStarredOnlyKey) as? Bool ?? false
        includeImportantOnly = defaults.object(forKey: Self.includeImportantOnlyKey) as? Bool ?? false
        maxEmailsToFetch = defaults.object(forKey: Self.maxEmailsToFetchKey) as? Int ?? 20
        if let savedMailboxes = defaults.array(forKey: Self.selectedMailboxesKey) as? [String], !savedMailboxes.isEmpty {
            selectedMailboxes = Set(savedMailboxes)
        }
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

        let mailboxList = selectedMailboxes.sorted().map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        let mailboxExpression = mailboxList.isEmpty ? "\"INBOX\"" : mailboxList.joined(separator: ", ")

        let script = """
        on sanitizeField(theText)
            try
                set theText to theText as text
                set AppleScript's text item delimiters to {"\\r", "\\n", "\\t", "|||"}
                set theText to every text item of theText
                set AppleScript's text item delimiters to " "
                set theText to theText as text
                set AppleScript's text item delimiters to ""
                return theText
            on error
                return ""
            end try
        end sanitizeField

        tell application "Mail"
            set resultText to ""
            set resultCount to 0
            set maxResults to \(maxEmailsToFetch)
            set shouldFetchUnreadOnly to \(fetchUnreadOnly ? "true" : "false")
            set shouldFetchStarredOnly to \(includeStarredOnly ? "true" : "false")
            set shouldFetchImportantOnly to \(includeImportantOnly ? "true" : "false")
            set selectedMailboxNames to {\(mailboxExpression)}
            set cutoffDate to date "\(sinceString)"

            repeat with acc in accounts
                repeat with mb in mailboxes of acc
                    set mailboxName to name of mb

                    if mailboxName is in selectedMailboxNames then
                        set msgs to messages of mb
                        repeat with msg in msgs
                            if resultCount ≥ maxResults then
                                exit repeat
                            end if

                            try
                                if date received of msg > cutoffDate then
                                    set shouldInclude to true

                                    if shouldFetchUnreadOnly and (read status of msg) then
                                        set shouldInclude to false
                                    end if

                                    if shouldFetchStarredOnly and not (flagged status of msg) then
                                        set shouldInclude to false
                                    end if

                                    if shouldFetchImportantOnly and ((priority of msg) is not 1) then
                                        set shouldInclude to false
                                    end if

                                    if shouldInclude then
                                        set msgSubject to sanitizeField(subject of msg)
                                        set msgSender to sanitizeField(sender of msg as text)
                                        set msgDate to date received of msg as string
                                        set msgId to message id of msg as text
                                        set msgRead to (read status of msg) as text
                                        set msgStarred to (flagged status of msg) as text
                                        set msgPriority to (priority of msg) as text
                                        set msgMailbox to sanitizeField(mailboxName)
                                        set msgPreview to sanitizeField(content of msg)

                                        set msgLine to msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & msgId & "|||" & msgRead & "|||" & msgStarred & "|||" & msgPriority & "|||" & msgMailbox & "|||" & msgPreview
                                        if resultText is "" then
                                            set resultText to msgLine
                                        else
                                            set resultText to resultText & linefeed & msgLine
                                        end if
                                        set resultCount to resultCount + 1
                                    end if
                                end if
                            end try
                        end repeat
                    end if

                    if resultCount ≥ maxResults then
                        exit repeat
                    end if
                end repeat

                if resultCount ≥ maxResults then
                    exit repeat
                end if
            end repeat

            return resultText
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
        let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResult.isEmpty else { return [] }

        return trimmedResult
            .components(separatedBy: CharacterSet.newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "|||")
                guard parts.count >= 8 else { return nil }

                return AppleMailMessage(
                    subject: parts[0],
                    sender: parts[1],
                    date: parseAppleScriptDate(parts[2]),
                    messageId: parts[3],
                    isRead: parts[4] == "true",
                    preview: parts[7],
                    mailbox: parts[6]
                )
            }
    }

    private func parseAppleScriptDate(_ value: String) -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Date() }

        let formats = [
            "EEEE, MMM d, yyyy 'at' h:mm:ss a",
            "EEEE, MMM d, yyyy 'at' h:mm:ss",
            "EEEE, MMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy 'at' h:mm:ss a",
            "yyyy-MM-dd",
            "EEE MMM d HH:mm:ss yyyy",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        if let cased = DateFormatter().date(from: trimmed) {
            return cased
        }

        return Date()
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
