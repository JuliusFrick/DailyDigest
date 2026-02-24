import Foundation

/// Persisted user settings (stored as JSON in UserDefaults so `swift build` works without Xcode/SwiftData).
struct UserSettings: Codable, Equatable {
    // Briefing preferences
    var defaultDetailLevel: String
    var preferredLanguage: String
    var autoRefreshTime: Date?
    var autoRefreshEnabled: Bool

    // Daily digest source selection
    var dailyDigestSourceToggles: [String: Bool]?

    // Audio preferences
    var ttsProvider: String
    var ttsVoiceId: String?
    var playbackSpeed: Double

    // LLM preferences
    var llmProvider: String

    // UI preferences
    var sourceOrder: [String]
    var theme: String
    var showLeftPanel: Bool
    var showChatPanel: Bool

    // Keyboard Shortcut preferences
    var globalShortcutEnabled: Bool
    var globalShortcutKeyCode: UInt16
    var globalShortcutModifiers: UInt64

    // Notification preferences
    var notificationsEnabled: Bool
    var morningReminderEnabled: Bool
    var morningReminderTime: Date?

    init(
        defaultDetailLevel: String = "quick",
        preferredLanguage: String = "de",
        autoRefreshTime: Date? = nil,
        autoRefreshEnabled: Bool = false,
        dailyDigestSourceToggles: [String: Bool]? = nil,
        ttsProvider: String = "apple",
        ttsVoiceId: String? = nil,
        playbackSpeed: Double = 1.0,
        llmProvider: String = "openai",
        sourceOrder: [String] = [],
        theme: String = "system",
        showLeftPanel: Bool = true,
        showChatPanel: Bool = false,
        globalShortcutEnabled: Bool = false,
        globalShortcutKeyCode: UInt16 = 0x02,  // D key
        globalShortcutModifiers: UInt64 = 0x180100,  // Cmd + Shift
        notificationsEnabled: Bool = true,
        morningReminderEnabled: Bool = false,
        morningReminderTime: Date? = nil
    ) {
        self.defaultDetailLevel = defaultDetailLevel
        self.preferredLanguage = preferredLanguage
        self.autoRefreshTime = autoRefreshTime
        self.autoRefreshEnabled = autoRefreshEnabled
        self.dailyDigestSourceToggles = dailyDigestSourceToggles
        self.ttsProvider = ttsProvider
        self.ttsVoiceId = ttsVoiceId
        self.playbackSpeed = playbackSpeed
        self.llmProvider = llmProvider
        self.sourceOrder = sourceOrder
        self.theme = theme
        self.showLeftPanel = showLeftPanel
        self.showChatPanel = showChatPanel
        self.globalShortcutEnabled = globalShortcutEnabled
        self.globalShortcutKeyCode = globalShortcutKeyCode
        self.globalShortcutModifiers = globalShortcutModifiers
        self.notificationsEnabled = notificationsEnabled
        self.morningReminderEnabled = morningReminderEnabled
        self.morningReminderTime = morningReminderTime
    }
}
