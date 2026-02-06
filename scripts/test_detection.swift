import Foundation
import AppKit

func runAppleScript(_ script: String) -> String? {
    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            print("Error: \(error)")
            return nil
        }
        return result.stringValue
    }
    return nil
}

func checkGoogleMeet() {
    let script = """
    tell application "System Events"
        set meetFound to false
        
        -- Check Google Chrome
        if (name of processes) contains "Google Chrome" then
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "Meet" or title of t contains "Google Meet" then
                            set meetFound to true
                        end if
                    end repeat
                end repeat
            end tell
        end if
        
        -- Check Arc
        if (name of processes) contains "Arc" then
            tell application "Arc"
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "Meet" or title of t contains "Google Meet" then
                            set meetFound to true
                        end if
                    end repeat
                end repeat
            end tell
        end if
        
        -- Check Safari
        if (name of processes) contains "Safari" then
            tell application "Safari"
                repeat with w in windows
                   repeat with t in tabs of w
                       if name of t contains "Meet" or name of t contains "Google Meet" then
                           set meetFound to true
                       end if
                   end repeat
                end repeat
            end tell
        end if

        return meetFound
    end tell
    """
    
    if let result = runAppleScript(script) {
        print("Google Meet Detected: \(result)")
    } else {
        print("Google Meet Check Failed")
    }
}

func checkSlackHuddle() {
    // Slack doesn't easily expose Huddle status via AppleScript window titles reliably in all versions, 
    // but often the window title changes to "Slack - ... Huddle" or similar if it's the active window, 
    // or there might be a separate window.
    // A more robust way often involves checking for "Huddle" in the window name.
    
    let script = """
    tell application "System Events"
        if (name of processes) contains "Slack" then
            tell process "Slack"
                repeat with w in windows
                    if name of w contains "Huddle" then
                        return true
                    end if
                end repeat
            end tell
        end if
        return false
    end tell
    """
    // Note: 'tell process' requires Accessibility permissions. 
    
    if let result = runAppleScript(script) {
        print("Slack Huddle Detected: \(result)")
    } else {
        print("Slack Huddle Check Failed (likely needs Accessibility permissions)")
    }
}

print("Checking for meetings...")
checkGoogleMeet()
checkSlackHuddle()
