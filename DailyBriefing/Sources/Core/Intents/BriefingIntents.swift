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
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let briefingService = BriefingGenerationService.shared

        // Generate the briefing
        let briefing = try await briefingService.generateBriefing(
            detailLevel: detailLevel.briefingDetailLevel
        )

        // Return the briefing summary as string value, plus dialog and snippet view
        return .result(
            value: briefing.summary,
            dialog: "Here is your briefing for today.",
            view: BriefingSnippetView(briefing: briefing)
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
    }
}
