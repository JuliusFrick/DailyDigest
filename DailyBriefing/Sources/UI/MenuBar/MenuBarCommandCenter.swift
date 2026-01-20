import SwiftUI

struct MenuBarCommandCenter: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // A. The Pulse Header
            CommandCenterHeader()
            
            Divider()
                .padding(.vertical, 8)
            
            // B. Quick Action Grid
            QuickActionGrid()
                .padding(.bottom, 12)
            
            Divider()
            
            // C. Insight Stream
            InsightStream()
                .padding(.vertical, 12)
            
            Divider()
            
            // D. Quick Capture Input
            QuickCaptureField()
                .padding(.vertical, 12)
            
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
        .background(Material.regular) // Or generic background
    }
}
