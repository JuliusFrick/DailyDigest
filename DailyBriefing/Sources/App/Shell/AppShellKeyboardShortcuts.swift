import SwiftUI

struct AppShellKeyboardShortcuts: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onKeyPress("1", modifiers: .command) {
                appState.selectedPanel = .dashboard
                return .handled
            }
            .onKeyPress("2", modifiers: .command) {
                appState.selectedPanel = .openClawChat
                return .handled
            }
            .onKeyPress("3", modifiers: .command) {
                appState.selectedPanel = .slack
                return .handled
            }
            .onKeyPress("4", modifiers: .command) {
                appState.selectedPanel = .jira
                return .handled
            }
            .onKeyPress("5", modifiers: .command) {
                appState.selectedPanel = .mail
                return .handled
            }
            .onKeyPress("6", modifiers: .command) {
                appState.selectedPanel = .terminals
                return .handled
            }
            .onKeyPress(",", modifiers: .command) {
                appState.selectedPanel = .settings
                return .handled
            }
            .onKeyPress("r", modifiers: .command) {
                Task {
                    await appState.refreshBriefing(detailLevel: .quick)
                }
                return .handled
            }
            .onKeyPress("q", modifiers: [.command, .shift]) {
                Task {
                    await appState.refreshBriefing(detailLevel: .quick)
                }
                return .handled
            }
            .onKeyPress("d", modifiers: [.command, .shift]) {
                Task {
                    await appState.refreshBriefing(detailLevel: .detailed)
                }
                return .handled
            }
            .onKeyPress(.space) {
                appState.toggleAudioPlayback()
                return .handled
            }
            .onKeyPress(".", modifiers: .command) {
                appState.stopAudioPlayback()
                return .handled
            }
    }
}
