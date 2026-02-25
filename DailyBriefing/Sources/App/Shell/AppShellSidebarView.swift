import SwiftUI

struct AppShellSidebarView: View {
    @Binding var selectedPanel: AppState.AppPanel

    private let panelGroups: [AppShellPanelGroup] = [
        .init(id: "overview", title: "Uebersicht", panels: [.dashboard, .openClawChat]),
        .init(id: "integrations", title: "Integrationen", panels: [.slack, .jira, .mail]),
        .init(id: "tools", title: "Tools", panels: [.terminals, .settings])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(panelGroups) { group in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(group.title.uppercased())
                            .font(.tuiMonoTiny)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Spacing.sm)

                        ForEach(group.panels) { panel in
                            Button {
                                withAnimation(.tuiSnappy) {
                                    selectedPanel = panel
                                }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: panel.icon)
                                        .frame(width: 16)

                                    Text(panel.title)
                                        .font(.tuiMonoSmall)

                                    Spacer(minLength: 0)

                                    if let shortcut = shortcut(for: panel) {
                                        Text(shortcut)
                                            .font(.tuiMonoTiny)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedPanel == panel ? Color.tuiHighlight : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.never)
    }

    private func shortcut(for panel: AppState.AppPanel) -> String? {
        switch panel {
        case .dashboard: return "CMD+1"
        case .openClawChat: return "CMD+2"
        case .slack: return "CMD+3"
        case .jira: return "CMD+4"
        case .mail: return "CMD+5"
        case .terminals: return "CMD+6"
        case .settings: return "CMD+,"
        }
    }
}

private struct AppShellPanelGroup: Identifiable {
    let id: String
    let title: String
    let panels: [AppState.AppPanel]
}
