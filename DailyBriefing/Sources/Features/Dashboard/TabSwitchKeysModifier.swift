import SwiftUI

// MARK: - Tab Switch Keyboard Modifier

struct TabSwitchKeysModifier: ViewModifier {
    @Binding var selectedTab: TUIDashboardView.DashboardTab
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(.tab) {
                withAnimation(.tuiSnappy) {
                    // Toggle between tabs using Tab key
                    selectedTab = selectedTab == .briefing ? .calendar : .briefing
                }
                return .handled
            }
            .onKeyPress("t", modifiers: .command) {
                withAnimation(.tuiSnappy) {
                    // Toggle between tabs using Cmd+T
                    selectedTab = selectedTab == .briefing ? .calendar : .briefing
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
