import SwiftUI

struct SidebarView: View {
    @Binding var selectedPanel: AppState.AppPanel

    var body: some View {
        List(selection: $selectedPanel) {
            Section("Navigation") {
                ForEach(AppState.AppPanel.allCases) { panel in
                    Label(panel.title, systemImage: panel.icon)
                        .tag(panel)
                }
            }
        }
        .frame(minWidth: 210)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Daily Briefing")
    }
}
