import Foundation
import ServiceManagement

/// Service responsible for managing the app's launch at login behavior
/// Uses SMAppService (macOS 13+) for modern login item management
@MainActor
final class LaunchAtLoginService: ObservableObject {

    // MARK: - Singleton

    static let shared = LaunchAtLoginService()

    // MARK: - Published Properties

    @Published private(set) var enabled: Bool = false

    // MARK: - Private Properties

    private let loginItem = SMAppService.mainApp

    // MARK: - Initialization

    private init() {
        updateStatus()
    }

    // MARK: - Public API

    /// Enable launch at login
    /// Registers the app as a login item
    func enable() {
        do {
            try loginItem.register()
            updateStatus()
        } catch {
            print("Failed to enable launch at login: \(error.localizedDescription)")
        }
    }

    /// Disable launch at login
    /// Unregisters the app as a login item
    func disable() {
        do {
            try loginItem.unregister()
            updateStatus()
        } catch {
            print("Failed to disable launch at login: \(error.localizedDescription)")
        }
    }

    /// Check if launch at login is currently enabled
    /// - Returns: True if the app is registered as a login item
    func isEnabled() -> Bool {
        return loginItem.status == .enabled
    }

    /// Toggle launch at login state
    func toggle() {
        if enabled {
            disable()
        } else {
            enable()
        }
    }

    // MARK: - Private Methods

    private func updateStatus() {
        enabled = loginItem.status == .enabled
    }
}
