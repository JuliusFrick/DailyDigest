import SwiftUI

struct TUIDockView: View {
    @Binding var selectedPanel: AppState.AppPanel

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(AppState.AppPanel.allCases) { panel in
                PanelLaunchButton(
                    selectedPanel: $selectedPanel,
                    panel: panel,
                    style: .dock
                )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tuiBackground.opacity(0.85))
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.tuiBorder, lineWidth: 1)
        )
    }
}
