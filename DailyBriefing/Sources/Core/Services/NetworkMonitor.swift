import Foundation
import Network
import Combine

/// Service responsible for monitoring network connectivity status
/// Uses NWPathMonitor to detect online/offline state changes
@MainActor
final class NetworkMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device currently has network connectivity
    @Published private(set) var isOnline: Bool = true

    /// The current network path status
    @Published private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.dailybriefing.networkmonitor")

    // MARK: - Types

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
        case none

        var displayName: String {
            switch self {
            case .wifi: return "WLAN"
            case .cellular: return "Mobilfunk"
            case .wired: return "Kabel"
            case .unknown: return "Unbekannt"
            case .none: return "Keine Verbindung"
            }
        }

        var iconName: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .wired: return "cable.connector"
            case .unknown: return "questionmark.circle"
            case .none: return "wifi.slash"
            }
        }
    }

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public API

    /// Start monitoring network changes
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                self.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stop monitoring network changes
    func stopMonitoring() {
        monitor.cancel()
    }

    /// Check if Ollama is available locally (for offline mode)
    func checkOllamaAvailability() async -> Bool {
        // Load Ollama configuration
        guard let config = loadLLMConfiguration(),
              config.provider == .ollama else {
            return false
        }

        // Try to reach Ollama server
        guard let url = URL(string: "\(config.ollamaBaseURL)/api/tags") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    /// Check if the current LLM configuration uses Ollama
    func isOllamaConfigured() -> Bool {
        guard let config = loadLLMConfiguration() else {
            return false
        }
        return config.provider == .ollama
    }

    // MARK: - Private Methods

    private func handlePathUpdate(_ path: NWPath) {
        isOnline = path.status == .satisfied
        connectionType = determineConnectionType(from: path)
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else {
            return .none
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        } else {
            return .unknown
        }
    }

    private func loadLLMConfiguration() -> LLMConfiguration? {
        if let data = UserDefaults.standard.data(forKey: "llm_configuration"),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        return nil
    }
}
