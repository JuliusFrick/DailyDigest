import Foundation
import SwiftData

/// Persisted user settings
@Model
final class UserSettings {
    var id: UUID

    // Briefing preferences
    var defaultDetailLevel: String
    var preferredLanguage: String
    var autoRefreshTime: Date?
    var autoRefreshEnabled: Bool

    // Audio preferences
    var ttsProvider: String
    var ttsVoiceId: String?
    var playbackSpeed: Double

    // LLM preferences
    var llmProvider: String
    var llmApiKey: String?

    // UI preferences
    var sourceOrder: [String]
    var theme: String

    // Keyboard Shortcut preferences
    var globalShortcutEnabled: Bool
    var globalShortcutKeyCode: UInt16
    var globalShortcutModifiers: UInt

    // Notification preferences
    var notificationsEnabled: Bool
    var morningReminderEnabled: Bool
    var morningReminderTime: Date?

    init(
        id: UUID = UUID(),
        defaultDetailLevel: String = "quick",
        preferredLanguage: String = "de",
        autoRefreshTime: Date? = nil,
        autoRefreshEnabled: Bool = false,
        ttsProvider: String = "apple",
        ttsVoiceId: String? = nil,
        playbackSpeed: Double = 1.0,
        llmProvider: String = "openai",
        llmApiKey: String? = nil,
        sourceOrder: [String] = [],
        theme: String = "system",
        globalShortcutEnabled: Bool = false,
        globalShortcutKeyCode: UInt16 = 0x02,  // D key
        globalShortcutModifiers: UInt = 0x180100,  // Cmd + Shift
        notificationsEnabled: Bool = true,
        morningReminderEnabled: Bool = false,
        morningReminderTime: Date? = nil
    ) {
        self.id = id
        self.defaultDetailLevel = defaultDetailLevel
        self.preferredLanguage = preferredLanguage
        self.autoRefreshTime = autoRefreshTime
        self.autoRefreshEnabled = autoRefreshEnabled
        self.ttsProvider = ttsProvider
        self.ttsVoiceId = ttsVoiceId
        self.playbackSpeed = playbackSpeed
        self.llmProvider = llmProvider
        self.llmApiKey = llmApiKey
        self.sourceOrder = sourceOrder
        self.theme = theme
        self.globalShortcutEnabled = globalShortcutEnabled
        self.globalShortcutKeyCode = globalShortcutKeyCode
        self.globalShortcutModifiers = globalShortcutModifiers
        self.notificationsEnabled = notificationsEnabled
        self.morningReminderEnabled = morningReminderEnabled
        self.morningReminderTime = morningReminderTime
    }
}

/// Configuration for an individual source
@Model
final class SourceConfiguration {
    var id: UUID
    var sourceId: String
    var isEnabled: Bool
    var displayOrder: Int
    var lastSyncDate: Date?
    var configurationData: Data?

    init(
        id: UUID = UUID(),
        sourceId: String,
        isEnabled: Bool = true,
        displayOrder: Int = 0,
        lastSyncDate: Date? = nil,
        configurationData: Data? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.isEnabled = isEnabled
        self.displayOrder = displayOrder
        self.lastSyncDate = lastSyncDate
        self.configurationData = configurationData
    }
}

/// Cached briefing for offline access
@Model
final class CachedBriefing {
    var id: UUID
    var generatedAt: Date
    var briefingData: Data

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        briefingData: Data
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.briefingData = briefingData
    }
}
