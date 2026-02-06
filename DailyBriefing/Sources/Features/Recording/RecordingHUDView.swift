import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var recordingService = AudioRecordingService.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Drag handle / Icon
            Text("🎤")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            // Recording Indicator
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(recordingService.isRecording ? 0.5 : 0), radius: 4)
                    .opacity(recordingService.isRecording ? 1 : 0.5)
                    .scaleEffect(recordingService.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)
                
                Text(recordingService.isRecording ? "REC" : "READY")
                    .font(.tuiMonoTiny)
                    .fontWeight(.bold)
                    .foregroundStyle(recordingService.isRecording ? .red : .primary)
            }
            
            Divider()
                .frame(height: 12)
                .background(Color.tuiBorder)
            
            // Duration
            Text(recordingService.formattedDuration())
                .font(.tuiMonoSmall)
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .leading)
            
            Spacer(minLength: 0)
            
            // Stop Button
            Button {
                NotificationCenter.default.post(name: .stopRecordingFromHUD, object: nil)
            } label: {
                Text("⏹")
                    .font(.system(size: 10))
                    .padding(4)
                    .background(Color.red.opacity(isHovered ? 0.2 : 0.1))
                    .foregroundStyle(.red)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Aufnahme beenden")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.tuiBackground.opacity(0.4)
                
                if recordingService.isRecording {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.2), lineWidth: 2)
                        .blur(radius: 2)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.tuiBorder, lineWidth: 1)
        )
        .frame(width: 220, height: 40)
    }
}

// Visual Effect View for that nice macOS blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct RecordingHUDView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingHUDView()
            .padding()
    }
}
