import SwiftUI

struct IntegrationSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServiceIntegrationsView()
                .navigationTitle("Setup-Wizard")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") {
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
