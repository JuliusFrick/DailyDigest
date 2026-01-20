import SwiftUI

struct CommandCenterHeader: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack {
            // Status Indicator & Text
            if appState.isPlayingAudio {
                // Audio Playing State
                Label("Playing Briefing", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if appState.isLoadingBriefing {
                // Generating State
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Generating Digest...")
                }
                .foregroundStyle(.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Idle / Default State
                HStack(spacing: Spacing.sm) {
                    Text(greeting)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Simple weather/status placeholder or online status
                    if !appState.isOnline {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            // "Pulse" logic could go here or be part of the background
        }
        .font(.system(.body, design: .rounded).weight(.medium))
        .padding()
        .background {
            if appState.isPlayingAudio {
                Color.blue.opacity(0.1)
            } else if appState.isLoadingBriefing {
                Color.orange.opacity(0.1)
            } else {
                Color.clear
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isPlayingAudio)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isLoadingBriefing)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good Morning"
        case 12..<18: return "Good Afternoon"
        default: return "Good Evening"
        }
    }
}
