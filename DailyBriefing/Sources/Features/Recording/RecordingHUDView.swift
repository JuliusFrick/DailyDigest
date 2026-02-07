import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var recordingService = AudioRecordingService.shared
    @ObservedObject var hudManager = RecordingHUDManager.shared
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
                // Dithering Orb - The main visual element
            ZStack {
                // Dithering shader orb with audio reactivity
                DitheringOrbView(
                    shape: recordingService.isRecording ? .sphere : .ripple,
                    ditherType: .bayer4x4,
                    colorBack: recordingService.isRecording
                        ? Color.recordingActive.opacity(0.2)
                        : Color(red: 0.03, green: 0.02, blue: 0.06),
                    colorFront: recordingService.isRecording ? Color.recordingActive : Color.recordingIdle,
                    pixelSize: 2.5,
                    speed: recordingService.isRecording ? 1.2 : 0.6,
                    audioLevel: CGFloat(recordingService.audioLevel),
                    size: 50
                )
                
                // Recording indicator overlay
                if recordingService.isRecording {
                    // Show STOP on hover, otherwise Time
                    if isHovered {
                        VStack(spacing: 0) {
                            Image(systemName: "square.fill")
                                .font(.system(size: 12))
                            Text("Stop")
                                .font(.system(size: 8, weight: .bold))
                                .offset(y: 1)
                        }
                        .foregroundStyle(.white)
                    } else {
                        VStack(spacing: 1) {
                            Text("REC")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            
                            Text(recordingService.formattedDuration())
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                } else if hudManager.isReviewing {
                    // Review state indicator
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                } else {
                    // Idle state
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.7))
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                }
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
            .onTapGesture {
                if recordingService.isRecording {
                    stopAndReview()
                } else if !hudManager.isReviewing {
                    startRecording()
                }
            }
            
            // Review Controls
            if hudManager.isReviewing {
                HStack(spacing: 16) {
                    // Discard
                    Button {
                        withAnimation {
                            hudManager.discardReview()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Verwerfen")
                    
                    // Confirm
                    Button {
                        withAnimation {
                            hudManager.confirmReview()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.recordingActive))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Speichern")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordingService.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hudManager.isReviewing)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func startRecording() {
        Task {
            do {
                _ = try await recordingService.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func stopAndReview() {
        if let url = recordingService.stopRecording() {
            hudManager.startReview(url: url)
        }
    }
}

// Visual Effect View for macOS blur
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

// #Preview {
//     RecordingHUDView()
//         .padding()
//         .background(Color.black.opacity(0.5))
// }
