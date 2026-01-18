import SwiftUI

/// Protocol that all briefing sources must implement
/// This enables a modular plugin architecture for adding new data sources
protocol BriefingSource: Identifiable, ObservableObject {
    /// Unique identifier for this source type
    static var sourceId: String { get }

    /// Display name shown in the UI
    static var displayName: String { get }

    /// SF Symbol name for the source icon
    static var iconName: String { get }

    /// Brand color for the source
    static var brandColor: Color { get }

    /// Current authentication state
    var isAuthenticated: Bool { get }

    /// Whether the source is currently fetching data
    var isLoading: Bool { get }

    /// Last error encountered
    var lastError: Error? { get }

    /// Authenticate with the service
    func authenticate() async throws

    /// Disconnect and clear credentials
    func disconnect() async

    /// Fetch items since a given date
    func fetchItems(since: Date) async throws -> [BriefingItem]

    /// Configuration view for this source
    @MainActor
    func configurationView() -> AnyView
}

// MARK: - Default Implementations

extension BriefingSource {
    var id: String { Self.sourceId }
}

// MARK: - Source Registration

/// Registry for available briefing sources
@MainActor
final class SourceRegistry: ObservableObject {
    static let shared = SourceRegistry()

    @Published private(set) var availableSources: [any BriefingSource.Type] = []
    @Published var activeSources: [any BriefingSource] = []

    private init() {
        registerBuiltInSources()
    }

    private func registerBuiltInSources() {
        // Will be populated as we implement each source
        // register(GoogleCalendarSource.self)
        // register(JiraSource.self)
        // register(SlackSource.self)
        // register(EmailSource.self)
    }

    func register<S: BriefingSource>(_ sourceType: S.Type) {
        guard !availableSources.contains(where: { $0.sourceId == sourceType.sourceId }) else {
            return
        }
        availableSources.append(sourceType)
    }

    func instantiate<S: BriefingSource>(_ sourceType: S.Type) -> S {
        S.init()
    }
}

// MARK: - Authentication State

enum AuthenticationState: Equatable {
    case notAuthenticated
    case authenticating
    case authenticated
    case failed(String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

// MARK: - Source Errors

enum SourceError: LocalizedError {
    case authenticationFailed(String)
    case networkError(String)
    case rateLimited
    case tokenExpired
    case configurationMissing(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let reason):
            return "Authentifizierung fehlgeschlagen: \(reason)"
        case .networkError(let reason):
            return "Netzwerkfehler: \(reason)"
        case .rateLimited:
            return "Rate-Limit erreicht. Bitte warte einen Moment."
        case .tokenExpired:
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        case .configurationMissing(let field):
            return "Konfiguration fehlt: \(field)"
        case .unknown(let error):
            return "Unbekannter Fehler: \(error.localizedDescription)"
        }
    }
}
