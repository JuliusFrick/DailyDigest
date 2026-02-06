import Foundation
import Combine
import AppKit

/// Service to detect active meetings (Google Meet, Slack Huddles)
@MainActor
final class MeetingPresenceService: ObservableObject {
    static let shared = MeetingPresenceService()
    
    // MARK: - Published Properties
    
    /// Whether a meeting is currently detected
    @Published private(set) var isMeetingActive = false
    
    /// Description of the active meeting source (e.g., "Google Meet (Chrome)", "Slack Huddle")
    @Published private(set) var activeMeetingSource: String?
    
    /// Whether the service has encountered permission issues
    @Published private(set) var hasPermissionError = false
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private let checkInterval: TimeInterval = 5.0
    private let queue = DispatchQueue(label: "com.dailybriefing.meetingpresence", qos: .userInitiated)
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring for meetings
    func startMonitoring() {
        stopMonitoring()
        print("Starting meeting presence monitoring...")
        // Run immediately once
        checkMeetingStatus()
        
        // Schedule timer
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkMeetingStatus()
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Detection Logic
    
    private func checkMeetingStatus() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Check Google Meet
            if let meetSource = self.checkGoogleMeet() {
                Task { @MainActor in
                    self.updateStatus(isActive: true, source: meetSource)
                }
                return
            }
            
            // Check Slack Huddle
            if let slackSource = self.checkSlackHuddle() {
                Task { @MainActor in
                    self.updateStatus(isActive: true, source: slackSource)
                }
                return
            }
            
            // No meeting found
            Task { @MainActor in
                self.updateStatus(isActive: false, source: nil)
            }
        }
    }
    
    @MainActor
    private func updateStatus(isActive: Bool, source: String?) {
        if self.isMeetingActive != isActive || self.activeMeetingSource != source {
            self.isMeetingActive = isActive
            self.activeMeetingSource = source
            print("Meeting Status Changed: \(isActive ? "Active" : "Inactive") (\(source ?? "None"))")
        }
    }
    
    // MARK: - AppleScript Checks
    
    private func checkGoogleMeet() -> String? {
        let script = """
        tell application "System Events"
            set meetFound to false
            set foundSource to ""
            
            -- Check Google Chrome
            if (name of processes) contains "Google Chrome" then
                tell application "Google Chrome"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if title of t contains "Meet" or title of t contains "Google Meet" then
                                set meetFound to true
                                set foundSource to "Google Meet (Chrome)"
                                exit repeat
                            end if
                        end repeat
                        if meetFound then exit repeat
                    end repeat
                end tell
            end if
            
            if not meetFound and (name of processes) contains "Arc" then
                tell application "Arc"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if title of t contains "Meet" or title of t contains "Google Meet" then
                                set meetFound to true
                                set foundSource to "Google Meet (Arc)"
                                exit repeat
                            end if
                        end repeat
                        if meetFound then exit repeat
                    end repeat
                end tell
            end if
            
            if not meetFound and (name of processes) contains "Safari" then
                tell application "Safari"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if name of t contains "Meet" or name of t contains "Google Meet" then
                                set meetFound to true
                                set foundSource to "Google Meet (Safari)"
                                exit repeat
                            end if
                        end repeat
                        if meetFound then exit repeat
                    end repeat
                end tell
            end if
            
            if meetFound then
                return foundSource
            else
                return ""
            end if
        end tell
        """
        
        return runAppleScript(script)
    }
    
    private func checkSlackHuddle() -> String? {
        // Checking for "Huddle" in window titles of Slack
        let script = """
        tell application "System Events"
            if (name of processes) contains "Slack" then
                tell process "Slack"
                    try
                        repeat with w in windows
                            if name of w contains "Huddle" then
                                return "Slack Huddle"
                            end if
                        end repeat
                    on error
                        return "ERROR_PERMISSIONS"
                    end try
                end tell
            end if
            return ""
        end tell
        """
        
        let result = runAppleScript(script)
        if result == "ERROR_PERMISSIONS" {
            Task { @MainActor in
                self.hasPermissionError = true
            }
            return nil
        }
        return result
    }
    
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
                return nil
            }
            let stringValue = output.stringValue
            return (stringValue?.isEmpty ?? true) ? nil : stringValue
        }
        return nil
    }
}
