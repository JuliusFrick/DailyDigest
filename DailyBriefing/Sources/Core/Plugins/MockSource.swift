import SwiftUI

/// A mock source for development and testing
final class MockSource: BriefingSource, ObservableObject {
    static let sourceId = "mock"
    static let displayName = "Demo Quelle"
    static let iconName = "sparkles"
    static let brandColor = Color.purple

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: Error?

    init() {}

    func authenticate() async throws {
        isLoading = true
        defer { isLoading = false }

        try await Task.sleep(for: .seconds(1))
        isAuthenticated = true
    }

    func disconnect() async {
        isAuthenticated = false
    }

    func fetchItems(since: Date) async throws -> [BriefingItem] {
        isLoading = true
        defer { isLoading = false }

        try await Task.sleep(for: .milliseconds(500))

        return [
            BriefingItem(
                title: "Team Meeting um 10:00",
                subtitle: "Google Meet",
                body: "Wöchentliches Team-Standup",
                timestamp: Date(),
                priority: .high
            ),
            BriefingItem(
                title: "JIRA-1234: Bug in Login Flow",
                subtitle: "Zugewiesen an dich",
                body: "User können sich nicht mit SSO anmelden",
                timestamp: Date().addingTimeInterval(-3600),
                priority: .urgent
            ),
            BriefingItem(
                title: "3 neue Slack-Nachrichten",
                subtitle: "#engineering",
                body: "Anna: Hat jemand Zeit für ein Code-Review?",
                timestamp: Date().addingTimeInterval(-1800),
                priority: .medium
            )
        ]
    }

    @MainActor
    func configurationView() -> AnyView {
        AnyView(MockSourceConfigView(source: self))
    }
}

struct MockSourceConfigView: View {
    @ObservedObject var source: MockSource

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Demo Quelle")
                .font(.headline)

            Text("Diese Quelle generiert Beispieldaten für Entwicklung und Testing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if source.isAuthenticated {
                Label("Verbunden", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button("Trennen") {
                    Task { await source.disconnect() }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Verbinden") {
                    Task { try? await source.authenticate() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
