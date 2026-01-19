import AppIntents
import Foundation

// MARK: - Generate Briefing Intent

/// App Intent for generating a daily briefing via Siri and Shortcuts
/// Usage: "Hey Siri, Daily Briefing" or via Shortcuts app
@available(macOS 13.0, *)
struct GenerateBriefingIntent: AppIntent {

    static var title: LocalizedStringResource = "Generate Daily Briefing"
    static var description = IntentDescription("Generates your daily briefing from all connected sources")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Detail Level", default: .quick)
    var detailLevel: BriefingDetailLevelEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let briefingService = BriefingGenerationService.shared

        // Generate the briefing
        let briefing = try await briefingService.generateBriefing(
            detailLevel: detailLevel.briefingDetailLevel
        )

        // Return the briefing summary as string value, plus dialog
        return .result(
            value: briefing.summary,
            dialog: "Here is your briefing for today."
        )
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Generate a \(\.$detailLevel) briefing")
    }
}

// MARK: - Show Briefing Intent

/// App Intent for showing the current briefing
@available(macOS 13.0, *)
struct ShowBriefingIntent: AppIntent {

    static var title: LocalizedStringResource = "Briefing anzeigen"
    static var description = IntentDescription("Zeigt das aktuelle tägliche Briefing an")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Simply open the app to show the briefing
        return .result()
    }
}

// MARK: - Get Today's Meetings Intent

/// App Intent for getting today's calendar events
@available(macOS 13.0, *)
struct GetTodaysMeetingsIntent: AppIntent {

    static var title: LocalizedStringResource = "Heutige Termine abrufen"
    static var description = IntentDescription("Gibt alle Kalender-Termine für heute als Text zurück")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let connectionManager = ServiceConnectionManager.shared

        guard let calendarSource = connectionManager.googleCalendarSource,
              calendarSource.isAuthenticated else {
            return .result(
                value: "Kein Kalender verbunden",
                dialog: "Du hast keinen Kalender verbunden. Bitte verbinde Google Calendar in den Einstellungen."
            )
        }

        // Fetch today's events
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        do {
            let items = try await calendarSource.fetchItems(since: startOfToday)

            // Filter to only today's events
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            let todayItems = items.filter { item in
                guard let timestamp = item.timestamp else { return true }
                return timestamp < endOfToday
            }

            if todayItems.isEmpty {
                return .result(
                    value: "Keine Termine heute",
                    dialog: "Du hast heute keine Termine im Kalender."
                )
            }

            // Format events as string
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "HH:mm"

            var result = "Termine für heute (\(todayItems.count)):\n\n"

            for item in todayItems {
                if let timestamp = item.timestamp {
                    result += "• \(formatter.string(from: timestamp)) - \(item.title)"
                } else {
                    result += "• \(item.title)"
                }
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    result += " (\(subtitle))"
                }
                result += "\n"
            }

            let summaryText = todayItems.count == 1
                ? "Du hast heute 1 Termin."
                : "Du hast heute \(todayItems.count) Termine."

            return .result(
                value: result,
                dialog: "\(summaryText)"
            )
        } catch {
            return .result(
                value: "Fehler beim Laden der Termine",
                dialog: "Termine konnten nicht geladen werden: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Get Unread Count Intent

/// App Intent for getting unread email and Slack message counts
@available(macOS 13.0, *)
struct GetUnreadCountIntent: AppIntent {

    static var title: LocalizedStringResource = "Ungelesene Nachrichten zählen"
    static var description = IntentDescription("Gibt die Anzahl ungelesener E-Mails und Slack-Nachrichten zurück")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let connectionManager = ServiceConnectionManager.shared

        var results: [String] = []
        var totalUnread = 0

        // Fetch Gmail unread count
        if let gmailSource = connectionManager.gmailSource,
           gmailSource.isAuthenticated {
            do {
                let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                let items = try await gmailSource.fetchItems(since: since)
                let unreadCount = items.count
                totalUnread += unreadCount
                results.append("E-Mails: \(unreadCount) ungelesen")
            } catch {
                results.append("E-Mails: Fehler beim Laden")
            }
        }

        // Fetch Slack unread count
        if let slackSource = connectionManager.slackSource,
           slackSource.isAuthenticated {
            do {
                let since = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                let items = try await slackSource.fetchItems(since: since)
                let messageCount = items.count
                totalUnread += messageCount
                results.append("Slack: \(messageCount) neue Nachrichten")
            } catch {
                results.append("Slack: Fehler beim Laden")
            }
        }

        if results.isEmpty {
            return .result(
                value: "Keine Quellen verbunden",
                dialog: "Du hast weder E-Mail noch Slack verbunden. Bitte verbinde mindestens einen Dienst in den Einstellungen."
            )
        }

        let resultString = results.joined(separator: "\n")
        let dialogText = totalUnread == 0
            ? "Keine ungelesenen Nachrichten."
            : totalUnread == 1
                ? "Du hast 1 ungelesene Nachricht."
                : "Du hast \(totalUnread) ungelesene Nachrichten."

        return .result(
            value: resultString,
            dialog: "\(dialogText)"
        )
    }
}

// MARK: - Play Briefing Intent

/// App Intent for playing the last briefing via TTS
@available(macOS 13.0, *)
struct PlayBriefingIntent: AppIntent {

    static var title: LocalizedStringResource = "Briefing vorlesen"
    static var description = IntentDescription("Startet die Sprachausgabe des letzten Briefings")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cacheService = BriefingCacheService.shared
        let ttsService = TTSService.shared

        // Get the latest cached briefing
        guard let briefing = cacheService.loadLatest() else {
            return .result(dialog: "Kein Briefing vorhanden. Bitte generiere zuerst ein Briefing.")
        }

        // Check if briefing is from today
        let calendar = Calendar.current
        let isFromToday = calendar.isDateInToday(briefing.generatedAt)

        // Start TTS playback
        ttsService.speak(text: briefing.summary)

        let dateInfo = isFromToday
            ? "von heute"
            : "vom \(formatDate(briefing.generatedAt))"

        return .result(dialog: "Spiele Briefing \(dateInfo) ab.")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM"
        return formatter.string(from: date)
    }
}

// MARK: - Configure Schedule Intent

/// App Intent for configuring the automatic briefing schedule
@available(macOS 13.0, *)
struct ConfigureScheduleIntent: AppIntent {

    static var title: LocalizedStringResource = "Briefing-Zeit einstellen"
    static var description = IntentDescription("Stellt die Zeit für das automatische tägliche Briefing ein")

    @Parameter(title: "Uhrzeit")
    var time: Date

    @Parameter(title: "Aktiviert", default: true)
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let schedulingService = SchedulingService.shared

        if enabled {
            schedulingService.updateScheduledTime(time)
            schedulingService.enableScheduling()

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeString = formatter.string(from: time)

            return .result(dialog: "Dein tägliches Briefing wird jetzt jeden Tag um \(timeString) Uhr generiert.")
        } else {
            schedulingService.disableScheduling()
            return .result(dialog: "Automatisches Briefing wurde deaktiviert.")
        }
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$enabled, .equalTo, true) {
            Summary("Briefing täglich um \(\.$time)")
        } otherwise: {
            Summary("Automatisches Briefing deaktivieren")
        }
    }
}

// MARK: - Detail Level Entity

/// Entity for briefing detail level in App Intents
@available(macOS 13.0, *)
enum BriefingDetailLevelEntity: String, AppEnum {
    case quick
    case detailed

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Detailtiefe")
    }

    static var caseDisplayRepresentations: [BriefingDetailLevelEntity: DisplayRepresentation] {
        [
            .quick: DisplayRepresentation(title: "Kurz", subtitle: "2-3 Minuten"),
            .detailed: DisplayRepresentation(title: "Ausführlich", subtitle: "5-10 Minuten")
        ]
    }

    var briefingDetailLevel: Briefing.DetailLevel {
        switch self {
        case .quick: return .quick
        case .detailed: return .detailed
        }
    }
}

// MARK: - Snippet View for Siri

import SwiftUI

/// View shown in Siri response
@available(macOS 13.0, *)
struct BriefingSnippetView: View {
    let briefing: Briefing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(.orange)
                Text("Daily Briefing")
                    .font(.headline)
            }

            Text(briefing.summary)
                .font(.body)
                .lineLimit(6)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "doc.text")
                Text("\(briefing.sections.count) Quellen")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}

// MARK: - App Shortcuts Provider

/// Provides shortcuts for the Shortcuts app and Siri
@available(macOS 13.0, *)
struct DailyBriefingShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateBriefingIntent(),
            phrases: [
                "Daily Briefing",
                "Mein Briefing mit \(.applicationName)",
                "Briefing generieren mit \(.applicationName)",
                "Erstelle mein Briefing",
                "Was ist heute wichtig",
                "Zeig mir meine Zusammenfassung"
            ],
            shortTitle: "Daily Briefing",
            systemImageName: "sun.horizon.fill"
        )

        AppShortcut(
            intent: ShowBriefingIntent(),
            phrases: [
                "Zeig mein Briefing mit \(.applicationName)",
                "Öffne \(.applicationName)",
                "Briefing anzeigen"
            ],
            shortTitle: "Briefing anzeigen",
            systemImageName: "eye"
        )

        AppShortcut(
            intent: ConfigureScheduleIntent(),
            phrases: [
                "Briefing-Zeit einstellen mit \(.applicationName)",
                "Wann soll mein Briefing kommen"
            ],
            shortTitle: "Zeitplan",
            systemImageName: "clock"
        )

        AppShortcut(
            intent: GetTodaysMeetingsIntent(),
            phrases: [
                "Heutige Termine mit \(.applicationName)",
                "Was habe ich heute",
                "Meine Termine heute",
                "Kalender heute"
            ],
            shortTitle: "Heutige Termine",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: GetUnreadCountIntent(),
            phrases: [
                "Ungelesene Nachrichten mit \(.applicationName)",
                "Wie viele ungelesene E-Mails",
                "Neue Nachrichten zählen",
                "Ungelesene zählen"
            ],
            shortTitle: "Ungelesene Nachrichten",
            systemImageName: "envelope.badge"
        )

        AppShortcut(
            intent: PlayBriefingIntent(),
            phrases: [
                "Briefing vorlesen mit \(.applicationName)",
                "Lies mein Briefing vor",
                "Briefing abspielen",
                "Spiele mein Briefing"
            ],
            shortTitle: "Briefing vorlesen",
            systemImageName: "speaker.wave.3"
        )
    }
}
