import Foundation
import Carbon
import AppKit
import Combine

/// Service for handling global keyboard shortcuts
/// Allows users to trigger briefing generation from anywhere on the system
@MainActor
final class GlobalShortcutService: ObservableObject {

    // MARK: - Singleton

    static let shared = GlobalShortcutService()

    // MARK: - Published Properties

    @Published private(set) var isEnabled = false
    @Published var currentShortcut: KeyboardShortcut = .default

    // MARK: - Private Properties

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID(signature: 0x4442_5246, id: 1) // 'DBRF' signature

    // MARK: - Callbacks

    var onShortcutTriggered: (() -> Void)?

    // MARK: - Initialization

    private init() {
        loadSettings()
    }

    deinit {
        if let ref = hotKeyRef {
            Task { @MainActor in
                UnregisterEventHotKey(ref)
            }
        }
    }

    // MARK: - Public API

    /// Enable the global shortcut
    func enable() {
        guard !isEnabled else { return }

        do {
            try registerHotKey()
            isEnabled = true
            saveSettings()
        } catch {
            print("Failed to register global shortcut: \(error)")
        }
    }

    /// Disable the global shortcut
    func disable() {
        guard isEnabled else { return }

        unregisterHotKey()
        isEnabled = false
        saveSettings()
    }

    /// Update the keyboard shortcut
    func updateShortcut(_ shortcut: KeyboardShortcut) {
        let wasEnabled = isEnabled

        if isEnabled {
            unregisterHotKey()
        }

        currentShortcut = shortcut

        if wasEnabled {
            do {
                try registerHotKey()
                isEnabled = true
            } catch {
                isEnabled = false
                print("Failed to register new shortcut: \(error)")
            }
        }

        saveSettings()
    }

    /// Check if accessibility permissions are granted
    static func hasAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility permissions
    static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private Methods

    private func registerHotKey() throws {
        // First, unregister any existing hot key
        unregisterHotKey()

        // Install event handler if not already installed
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()

                    Task { @MainActor in
                        service.handleHotKeyEvent()
                    }

                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )

            guard status == noErr else {
                throw GlobalShortcutError.failedToInstallHandler(status)
            }
        }

        // Register the hot key
        let status = RegisterEventHotKey(
            UInt32(currentShortcut.keyCode),
            currentShortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw GlobalShortcutError.failedToRegister(status)
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func handleHotKeyEvent() {
        onShortcutTriggered?()
    }

    private func loadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: "globalShortcutEnabled")

        if let keyCode = UserDefaults.standard.object(forKey: "globalShortcutKeyCode") as? UInt16,
           let modifiers = UserDefaults.standard.object(forKey: "globalShortcutModifiers") as? UInt {
            currentShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        }

        if isEnabled {
            do {
                try registerHotKey()
            } catch {
                isEnabled = false
            }
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "globalShortcutEnabled")
        UserDefaults.standard.set(currentShortcut.keyCode, forKey: "globalShortcutKeyCode")
        UserDefaults.standard.set(currentShortcut.modifiers.rawValue, forKey: "globalShortcutModifiers")
    }
}

// MARK: - Supporting Types

/// Represents a keyboard shortcut
struct KeyboardShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    /// Default shortcut: Cmd + Shift + D
    static let `default` = KeyboardShortcut(
        keyCode: 0x02,  // D key
        modifiers: [.command, .shift]
    )

    /// Convert NSEvent modifiers to Carbon modifiers
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// Human-readable description of the shortcut
    var displayString: String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("^") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    /// Convert key code to string representation
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x2F: ".", 0x32: "`", 0x24: "\u{21A9}",  // Return
            0x30: "\u{21E5}",  // Tab
            0x31: "\u{2423}",  // Space
            0x33: "\u{232B}",  // Delete
            0x35: "\u{238B}",  // Escape
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
        ]

        return keyMap[keyCode] ?? "?"
    }
}

/// Errors for global shortcut operations
enum GlobalShortcutError: LocalizedError {
    case failedToInstallHandler(OSStatus)
    case failedToRegister(OSStatus)

    var errorDescription: String? {
        switch self {
        case .failedToInstallHandler(let status):
            return "Fehler beim Installieren des Event-Handlers: \(status)"
        case .failedToRegister(let status):
            return "Fehler beim Registrieren der Tastenkombination: \(status)"
        }
    }
}

// MARK: - Shortcut Recorder View

import SwiftUI

/// View for recording a keyboard shortcut
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    @State private var isRecording = false
    @State private var recordedShortcut: KeyboardShortcut?

    var body: some View {
        HStack {
            Text(isRecording ? "Drücke Tastenkombination..." : shortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isRecording ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            if !isRecording {
                Button("Ändern") {
                    startRecording()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Abbrechen") {
                    stopRecording()
                }
                .buttonStyle(.bordered)
            }
        }
        .onKeyDown { event in
            if isRecording {
                handleKeyEvent(event)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        recordedShortcut = nil
    }

    private func stopRecording() {
        isRecording = false
        if let recorded = recordedShortcut {
            shortcut = recorded
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Ignore modifier-only key presses
        guard event.keyCode != 55 && event.keyCode != 54 &&  // Command
              event.keyCode != 56 && event.keyCode != 60 &&  // Shift
              event.keyCode != 58 && event.keyCode != 61 &&  // Option
              event.keyCode != 59 && event.keyCode != 62     // Control
        else { return }

        // Require at least one modifier
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else { return }

        recordedShortcut = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = recordedShortcut!
        isRecording = false
    }
}

// MARK: - Key Event Modifier

extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Void) -> some View {
        self.background(KeyEventView(onKeyDown: action))
    }
}

struct KeyEventView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
