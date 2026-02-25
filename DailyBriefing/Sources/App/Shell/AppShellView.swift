import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color.tuiBackground
                .ignoresSafeArea()

            DitheringBackgroundView(
                shape: .simplex,
                ditherType: .bayer8x8,
                colorBack: Color.clear,
                colorFront: Color.primary.opacity(0.02),
                pixelSize: 4,
                speed: 0.1,
                opacity: 0.5
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                AppShellHeaderView()
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)

                Rectangle()
                    .fill(Color.tuiBorder)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    AppShellSidebarView(selectedPanel: $appState.selectedPanel)
                        .frame(width: 240)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.md)
                        .background(Color.tuiPanel.opacity(0.7))

                    Rectangle()
                        .fill(Color.tuiBorder)
                        .frame(width: 1)

                    AppShellContentView(
                        selectedPanel: $appState.selectedPanel,
                        selectedDashboardTab: $appState.selectedTab
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AppShellStatusBarView()
            }
        }
        .modifier(AppShellKeyboardShortcuts(appState: appState))
    }
}
