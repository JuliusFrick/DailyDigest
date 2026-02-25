import SwiftUI

struct AppShellContentView: View {
    @Binding var selectedPanel: AppState.AppPanel
    @Binding var selectedDashboardTab: TUIDashboardView.DashboardTab

    var body: some View {
        Group {
            switch selectedPanel {
            case .dashboard:
                TUIDashboardView(selectedTab: $selectedDashboardTab)
            case .openClawChat:
                BriefingChatView()
            case .slack:
                SlackPanelView()
            case .jira:
                JiraPanelView()
            case .mail:
                MailPanelView()
            case .terminals:
                TerminalsPanelView()
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}
