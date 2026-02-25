import SwiftUI

struct AppShellHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Briefing")
                    .font(.tuiMonoSmall)
                    .fontWeight(.semibold)

                Text("Aktiv: \(appState.selectedPanel.title)")
                    .font(.tuiMonoTiny)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Date.now.formatted(date: .abbreviated, time: .shortened))
                .font(.tuiMonoTiny)
                .foregroundStyle(.tertiary)

            HStack(spacing: Spacing.sm) {
                Button {
                    Task {
                        await appState.refreshBriefing(detailLevel: .quick)
                    }
                } label: {
                    Label("Quick", systemImage: "bolt.fill")
                }
                .buttonStyle(.tui)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    Task {
                        await appState.refreshBriefing(detailLevel: .detailed)
                    }
                } label: {
                    Label("Detail", systemImage: "text.alignleft")
                }
                .buttonStyle(.tui)

                Button {
                    appState.toggleAudioPlayback()
                } label: {
                    Label(
                        appState.isPlayingAudio ? "Pause" : "Play",
                        systemImage: appState.isPlayingAudio ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.tuiGhost)
                .disabled(appState.currentBriefing == nil)
            }

            if appState.isLoadingBriefing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.tuiMonoSmall)
    }
}
