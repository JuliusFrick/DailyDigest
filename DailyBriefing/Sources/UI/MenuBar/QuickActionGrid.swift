import SwiftUI

// MARK: - QuickActionGrid

struct QuickActionGrid: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    // We observe AudioRecordingService to update the record button state
    @StateObject private var recordingService = AudioRecordingService.shared
    @State private var showPermissionAlert = false
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            
            // 1. Play / Record Action
            CommandButton(
                title: recordingService.isRecording ? "Stop Recording" : "Record Meeting",
                icon: recordingService.isRecording ? "stop.circle.fill" : "mic.circle.fill",
                color: recordingService.isRecording ? .red : .blue
            ) {
                Task {
                    if recordingService.isRecording {
                        // This will trigger the HUD manager flow if connected, 
                        // or we can call stop directly. The AppState handler monitors 
                        // notification .stopRecordingFromHUD, 
                        // but here we might want to stop directly or just show HUD.
                        // Ideally we use the HUD manager to show controls, 
                        // but if we want to toggle start/stop:
                        _ = recordingService.stopRecording()
                    } else {
                        do {
                            _ = try await recordingService.startRecording()
                        } catch RecordingError.permissionDenied {
                            showPermissionAlert = true
                        } catch {
                            print("Failed to start recording: \(error)")
                        }
                    }
                }
            }
            
            // 2. Refresh Briefing
            CommandButton(
                title: appState.isLoadingBriefing ? "Generating..." : "Refresh Digest",
                icon: "arrow.clockwise",
                color: .orange,
                isDisabled: appState.isLoadingBriefing
            ) {
                Task {
                    await appState.refreshBriefing()
                }
            }
            
            // 3. Open Dashboard
            CommandButton(
                title: "Open Dashboard",
                icon: "macwindow",
                color: .secondary
            ) {
                openMainWindow()
                dismiss() // Close menu bar
            }
            
            // 4. Settings (or Quit)
            CommandButton(
                title: "Settings",
                icon: "gearshape",
                color: .secondary
            ) {
                openSettings()
                dismiss()
            }
        }
        .padding(.horizontal, Spacing.md)
        .alert("Mikrofon-Zugriff erforderlich", isPresented: $showPermissionAlert) {
            Button("Einstellungen öffnen", role: .none) {
                recordingService.openMicrophoneSettings()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bitte erlaube den Zugriff auf das Mikrofon in den Systemeinstellungen, um Meetings aufzunehmen.")
        }
    }
    
    // Helper Functions
    private func openMainWindow() {
        MainWindowCoordinator.shared.openMainWindow()
    }
    
    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

private struct CommandButton: View {
    let title: String
    let icon: String
    var color: Color = .primary
    var isDisabled: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isDisabled ? .gray : color)
                
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.tuiHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered && !isDisabled ? 1.02 : 1.0)
        .animation(.tuiSnappy, value: isHovered)
    }
}
