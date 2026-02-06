import SwiftUI

// MARK: - MenuBarCommandCenter

struct MenuBarCommandCenter: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // A. The Pulse Header
            CommandCenterHeader()
            
            Divider()
                .padding(.vertical, Spacing.sm)
            
            // B. Quick Action Grid
            QuickActionGrid()
                .padding(.bottom, Spacing.md)
            
            Divider()
            
            // C. Insight Stream
            InsightStream()
                .padding(.vertical, Spacing.md)
            
            Divider()
            
            // D. Quick Capture Input
            QuickCaptureField()
                .padding(.vertical, Spacing.md)
            
            // Footer (optional version/branding)
            // HStack {
            //    Spacer() 
            //    Text("v1.0")
            //        .font(.caption2)
            //        .foregroundStyle(.tertiary)
            // }
            // .padding(.bottom, 4)
        }
        .frame(width: 320) // Slightly wider than standard to accommodate grid
        .background(Color.tuiBackground)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }
}
