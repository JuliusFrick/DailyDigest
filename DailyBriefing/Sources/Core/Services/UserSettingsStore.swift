import Foundation

/// Lightweight settings persistence for CLI builds (no SwiftData dependency).
@MainActor
final class UserSettingsStore: ObservableObject {
    static let shared = UserSettingsStore()

    @Published private(set) var settings: UserSettings

    private let storageKey = "dailyBriefing.userSettings.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.settings = Self.loadSettings(
            storageKey: storageKey,
            decoder: decoder
        ) ?? UserSettings()
    }

    func update(_ mutate: (inout UserSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        save()
    }

    func replace(_ newSettings: UserSettings) {
        settings = newSettings
        save()
    }

    func resetToDefaults() {
        replace(UserSettings())
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadSettings(storageKey: String, decoder: JSONDecoder) -> UserSettings? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(UserSettings.self, from: data)
    }
}

