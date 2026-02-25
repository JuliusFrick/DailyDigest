import SwiftUI

struct AppShellStatusBarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var connectionManager = ServiceConnectionManager.shared

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(appState.isOnline ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(appState.isOnline ? "online" : "offline")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(connectionManager.connectedSources.isEmpty ? Color.secondary : Color.blue)
                    .frame(width: 6, height: 6)

                Text("\(connectionManager.connectedSources.count) src")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
            }

            if appState.isLoadingBriefing {
                Text(appState.generationProgress.displayText)
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                AppShellKeyHintView(key: "CMD+R", action: "quick")
                AppShellKeyHintView(key: "CMD+SHIFT+D", action: "detail")

                if appState.currentBriefing != nil {
                    AppShellKeyHintView(key: "SPACE", action: appState.isPlayingAudio ? "pause" : "play")
                    if appState.isPlayingAudio {
                        AppShellKeyHintView(key: "CMD+.", action: "stop")
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.tuiBackground.opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.tuiBorder)
                .frame(height: 1)
        }
    }
}

private struct AppShellKeyHintView: View {
    let key: String
    let action: String

    var body: some View {
        Text("\(key) \(action)")
            .font(.tuiMonoTiny)
            .foregroundStyle(.tertiary)
    }
}
