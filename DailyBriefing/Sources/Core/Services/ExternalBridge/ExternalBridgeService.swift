import Foundation

@MainActor
final class ExternalBridgeService: ObservableObject {
    enum BridgeError: LocalizedError {
        case failedToStart(String)

        var errorDescription: String? {
            switch self {
            case .failedToStart(let reason):
                return "Bridge konnte nicht gestartet werden: \(reason)"
            }
        }
    }

    static let shared = ExternalBridgeService()

    private static let configurationStorageKey = "externalBridgeConfiguration"

    private let auth = ExternalBridgeAuth()
    private let router: ExternalBridgeRouter
    private var server: ExternalBridgeServer?
    private var runningPort: UInt16?

    @Published private(set) var configuration: ExternalBridgeConfiguration
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private init() {
        self.configuration = Self.loadConfiguration()
        self.router = ExternalBridgeRouter(
            auth: auth,
            briefingCacheService: BriefingCacheService.shared,
            actionItemStore: ActionItemStore.shared,
            connectionManager: ServiceConnectionManager.shared
        )
        _ = auth.ensureSecretExists()
    }

    var activePort: UInt16 {
        runningPort ?? configuration.port
    }

    var healthURL: URL? {
        guard isRunning, let port = runningPort else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)/health")
    }

    func startIfEnabled() async {
        if configuration.isEnabled {
            await start()
        } else {
            stop()
        }
    }

    func start() async {
        if isRunning, let runningPort, runningPort == configuration.port {
            return
        }

        stop()

        let server = ExternalBridgeServer { [weak self] request in
            guard let self = self else {
                return ExternalBridgeResponse.plainText("Service unavailable", statusCode: 503)
            }
            return await self.router.route(
                request,
                configuration: self.configuration
            )
        }

        do {
            let port = try await server.start(port: configuration.port)
            self.server = server
            runningPort = port
            isRunning = true
            lastErrorMessage = nil
            configuration.port = port
            saveConfiguration()
        } catch {
            self.server = nil
            runningPort = nil
            isRunning = false
            lastErrorMessage = BridgeError.failedToStart(error.localizedDescription).localizedDescription
        }
    }

    func stop() {
        server?.stop()
        server = nil
        runningPort = nil
        isRunning = false
    }

    func updateConfiguration(
        isEnabled: Bool? = nil,
        port: UInt16? = nil,
        allowedClients: [String]? = nil
    ) async {
        var next = configuration
        if let isEnabled {
            next.isEnabled = isEnabled
        }
        if let port {
            next.port = port
        }
        if let allowedClients {
            let sanitized = allowedClients
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.lowercased() }
            next.allowedClients = Array(Set(sanitized)).sorted()
        }

        guard next != configuration else { return }
        configuration = next
        saveConfiguration()

        if next.isEnabled {
            await start()
        } else {
            stop()
        }
    }

    func rotateSecret() async throws -> String {
        let newToken = try auth.rotateSecret()
        return newToken
    }

    func currentSecret() -> String? {
        auth.currentSecret()
    }

    func currentSecretMasked() -> String {
        guard let secret = auth.currentSecret(), secret.count >= 4 else {
            return "••••••••"
        }

        let suffixStartIndex = secret.index(secret.endIndex, offsetBy: -4)
        return String(repeating: "•", count: max(0, secret.count - 4)) + String(secret[suffixStartIndex...])
    }

    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Self.configurationStorageKey)
        }
    }

    private static func loadConfiguration() -> ExternalBridgeConfiguration {
        if let data = UserDefaults.standard.data(forKey: configurationStorageKey),
           let loaded = try? JSONDecoder().decode(ExternalBridgeConfiguration.self, from: data) {
            return loaded
        }
        return ExternalBridgeConfiguration.defaults
    }
}

