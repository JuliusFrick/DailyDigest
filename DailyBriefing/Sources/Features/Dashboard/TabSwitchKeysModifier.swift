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
                    case .briefing:
                        selectedTab = .calendar
                    case .calendar, .history:
                        selectedTab = .briefing
                    }
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
    }
}
