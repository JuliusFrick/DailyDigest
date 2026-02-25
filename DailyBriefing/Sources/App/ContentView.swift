import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.showOnboarding {
                OnboardingView()
            } else {
                AppShellView()
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}
