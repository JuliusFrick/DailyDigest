import SwiftUI

// MARK: - Tab Switch Keyboard Modifier

struct TabSwitchKeysModifier: ViewModifier {
    @Binding var selectedTab: TUIDashboardView.DashboardTab
    
    func body(content: Content) -> some View {
        content
            .onKeyPress("t", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Toggle between tabs using Cmd+T
                    switch selectedTab {
                    case .cockpit:
                        selectedTab = .workspace
                    case .workspace:
                        selectedTab = .briefing
                    case .briefing:
                        selectedTab = .calendar
                    case .calendar:
                        selectedTab = .recordings
                    case .recordings:
                        selectedTab = .history
                    case .history:
                        selectedTab = .cockpit
                    }
                }
                return .handled
            }
            .onKeyPress("0", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    selectedTab = .cockpit
                }
                return .handled
            }
            .onKeyPress("w", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Switch to workspace tab
                    selectedTab = .workspace
                }
                return .handled
            }
            .onKeyPress("b", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Switch to briefing tab
                    selectedTab = .briefing
                }
                return .handled
            }
            .onKeyPress("k", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Switch to calendar tab
                    selectedTab = .calendar
                }
                return .handled
            }
            .onKeyPress("h", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Switch to history tab
                    selectedTab = .history
                }
                return .handled
            }
            .onKeyPress("r", modifiers: [.command, .shift]) {
                withAnimation(.tuiSnappy) {
                    // Switch to recordings tab
                    selectedTab = .recordings
                }
                return .handled
            }
    }
}
