import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.showOnboarding {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .frame(minWidth: 380, minHeight: 600)
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedTab) {
            ForEach(AppState.Tab.allCases) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
}

struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.selectedTab {
        case .dashboard:
            DashboardView()
        case .history:
            BriefingHistoryView()
        case .sources:
            SourcesView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
