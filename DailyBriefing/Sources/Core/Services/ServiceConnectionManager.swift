import Foundation
import SwiftUI
import Combine

/// Central manager for all service connections
/// Handles credential storage, connection status, and service lifecycle
@MainActor
final class ServiceConnectionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ServiceConnectionManager()

    // MARK: - Published Properties

    @Published private(set) var connections: [String: ServiceConnection] = [:]
    @Published private(set) var isLoading = false

    // MARK: - Service Instances

    @Published var googleCalendarSource: GoogleCalendarSource?
    @Published var gmailSource: GmailSource?
    @Published var slackSource: SlackSource?
    @Published var jiraSource: JiraSource?
    @Published var appleMailSource: AppleMailSource?
    @Published var appleRemindersSource: AppleRemindersSource?

    // MARK: - Private Properties

    private let keychain = KeychainService.shared
    private let userDefaults = UserDefaults.standard
    private let connectionsKey = "service_connections"
    private let iCloudSyncEnabledKey = "icloud_credentials_sync_enabled"

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadConnections()
        restoreConnectionsFromKeychain()
        initializeServices()
        setupICloudSync()
    }

    // MARK: - Public API

    /// Get the connection status for a service
    func connectionStatus(for serviceType: ServiceType) -> ConnectionStatus {
        connections[serviceType.rawValue]?.status ?? .disconnected
    }

    /// Check if a service is connected
    func isConnected(_ serviceType: ServiceType) -> Bool {
        connectionStatus(for: serviceType) == .connected
    }

    /// Connect a service
    func connect(_ serviceType: ServiceType) async throws {
        isLoading = true
        defer { isLoading = false }

        updateConnectionStatus(serviceType, status: .connecting)

        do {
            switch serviceType {
            case .googleCalendar:
                if googleCalendarSource == nil {
                    googleCalendarSource = GoogleCalendarSource()
                }
                try await googleCalendarSource?.authenticate()

            case .gmail:
                if gmailSource == nil {
                    gmailSource = GmailSource()
                }
                try await gmailSource?.authenticate()

            case .slack:
                if slackSource == nil {
                    slackSource = SlackSource()
                }
                try await slackSource?.authenticate()

            case .jira:
                if jiraSource == nil {
                    jiraSource = JiraSource()
                }
                try await jiraSource?.authenticate()

            case .appleMail:
                if appleMailSource == nil {
                    appleMailSource = AppleMailSource()
                }
                try await appleMailSource?.authenticate()

            case .appleReminders:
                if appleRemindersSource == nil {
                    appleRemindersSource = AppleRemindersSource()
                }
                try await appleRemindersSource?.authenticate()
            }

            updateConnectionStatus(serviceType, status: .connected)
            saveConnections()
        } catch {
            updateConnectionStatus(serviceType, status: .error, errorMessage: error.localizedDescription)
            throw error
        }
    }

    /// Disconnect a service
    func disconnect(_ serviceType: ServiceType) async {
        switch serviceType {
        case .googleCalendar:
            await googleCalendarSource?.disconnect()
            googleCalendarSource = nil

        case .gmail:
            await gmailSource?.disconnect()
            gmailSource = nil

        case .slack:
            await slackSource?.disconnect()
            slackSource = nil

        case .jira:
            await jiraSource?.disconnect()
            jiraSource = nil

        case .appleMail:
            await appleMailSource?.disconnect()
            appleMailSource = nil

        case .appleReminders:
            await appleRemindersSource?.disconnect()
            appleRemindersSource = nil
        }

        connections.removeValue(forKey: serviceType.rawValue)
        saveConnections()
    }

    /// Reconnect a service (disconnect and connect again)
    func reconnect(_ serviceType: ServiceType) async throws {
        await disconnect(serviceType)
        try await connect(serviceType)
    }

    /// Ensure a source instance exists (useful for configuration before connecting)
    func ensureSource(_ serviceType: ServiceType) {
        switch serviceType {
        case .googleCalendar:
            if googleCalendarSource == nil { googleCalendarSource = GoogleCalendarSource() }
        case .gmail:
            if gmailSource == nil { gmailSource = GmailSource() }
        case .slack:
            if slackSource == nil { slackSource = SlackSource() }
        case .jira:
            if jiraSource == nil { jiraSource = JiraSource() }
        case .appleMail:
            if appleMailSource == nil { appleMailSource = AppleMailSource() }
        case .appleReminders:
            if appleRemindersSource == nil { appleRemindersSource = AppleRemindersSource() }
        }
    }

    /// Get the source for a service type
    func source(for serviceType: ServiceType) -> (any BriefingSource)? {
        switch serviceType {
        case .googleCalendar: return googleCalendarSource
        case .gmail: return gmailSource
        case .slack: return slackSource
        case .jira: return jiraSource
        case .appleMail: return appleMailSource
        case .appleReminders: return appleRemindersSource
        }
    }

    /// Get all connected sources
    var connectedSources: [any BriefingSource] {
        var sources: [any BriefingSource] = []
        if let source = googleCalendarSource, source.isAuthenticated { sources.append(source) }
        if let source = gmailSource, source.isAuthenticated { sources.append(source) }
        if let source = slackSource, source.isAuthenticated { sources.append(source) }
        if let source = jiraSource, source.isAuthenticated { sources.append(source) }
        if let source = appleMailSource, source.isAuthenticated { sources.append(source) }
        if let source = appleRemindersSource, source.isAuthenticated { sources.append(source) }
        return sources
    }

    // MARK: - iCloud Sync

    var iCloudSyncEnabled: Bool {
        get { userDefaults.bool(forKey: iCloudSyncEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: iCloudSyncEnabledKey)
            if newValue {
                syncToICloud()
            }
        }
    }

    private func setupICloudSync() {
        guard iCloudSyncEnabled else { return }

        // Listen for iCloud changes
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .sink { [weak self] _ in
                self?.syncFromICloud()
            }
            .store(in: &cancellables)

        // Initial sync from iCloud
        syncFromICloud()
    }

    private func syncToICloud() {
        guard iCloudSyncEnabled else { return }

        let store = NSUbiquitousKeyValueStore.default

        // Sync connection metadata (not sensitive tokens)
        if let data = try? JSONEncoder().encode(Array(connections.values)) {
            store.set(data, forKey: connectionsKey)
            store.synchronize()
        }
    }

    private func syncFromICloud() {
        guard iCloudSyncEnabled else { return }

        let store = NSUbiquitousKeyValueStore.default

        if let data = store.data(forKey: connectionsKey),
           let syncedConnections = try? JSONDecoder().decode([ServiceConnection].self, from: data) {
            // Merge with local connections, preferring local token status
            for connection in syncedConnections {
                if connections[connection.serviceId] == nil {
                    // Check if we have local tokens for this connection
                    if keychain.hasTokens(for: connection.serviceId) {
                        var updatedConnection = connection
                        updatedConnection.status = .connected
                        connections[connection.serviceId] = updatedConnection
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func initializeServices() {
        // Initialize services for existing connections
        for (serviceId, connection) in connections {
            guard connection.status == .connected || keychain.hasTokens(for: serviceId) else { continue }

            switch ServiceType(rawValue: serviceId) {
            case .googleCalendar:
                googleCalendarSource = GoogleCalendarSource()
            case .gmail:
                gmailSource = GmailSource()
            case .slack:
                slackSource = SlackSource()
            case .jira:
                jiraSource = JiraSource()
            case .appleMail:
                appleMailSource = AppleMailSource()
            case .appleReminders:
                appleRemindersSource = AppleRemindersSource()
            case .none:
                break
            }
        }
    }

    private func restoreConnectionsFromKeychain() {
        var didUpdate = false

        for serviceType in ServiceType.allCases {
            guard keychain.hasTokens(for: serviceType.rawValue) else { continue }

            var connection = connections[serviceType.rawValue] ?? ServiceConnection(
                serviceId: serviceType.rawValue,
                serviceName: serviceType.displayName
            )

            if connection.status != .connected {
                connection.status = .connected
                didUpdate = true
            }

            connections[serviceType.rawValue] = connection
        }

        if didUpdate {
            saveConnections()
        }
    }

    private func updateConnectionStatus(_ serviceType: ServiceType, status: ConnectionStatus, errorMessage: String? = nil) {
        var connection = connections[serviceType.rawValue] ?? ServiceConnection(
            serviceId: serviceType.rawValue,
            serviceName: serviceType.displayName
        )

        connection.status = status
        connection.errorMessage = errorMessage

        if status == .connected {
            connection.lastSyncAt = Date()
        }

        connections[serviceType.rawValue] = connection
    }

    private func loadConnections() {
        if let data = userDefaults.data(forKey: connectionsKey),
           let loadedConnections = try? JSONDecoder().decode([ServiceConnection].self, from: data) {
            connections = Dictionary(uniqueKeysWithValues: loadedConnections.map { ($0.serviceId, $0) })
        }
    }

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(Array(connections.values)) {
            userDefaults.set(data, forKey: connectionsKey)
        }

        // Also sync to iCloud if enabled
        syncToICloud()
    }

    // MARK: - Disconnect All Sources

    /// Disconnect all connected services and set their status to disconnected
    func disconnectAllSources() async {
        for serviceType in ServiceType.allCases {
            await disconnect(serviceType)
        }
        connections.removeAll()
        saveConnections()
    }
}
