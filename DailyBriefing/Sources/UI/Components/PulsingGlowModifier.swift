import SwiftUI

// MARK: - Pulsing Glow Effect

struct PulsingGlowModifier: ViewModifier {
    let color: Color
    let intensity: Double
    let isActive: Bool
    
    @State private var pulse: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(intensity * (0.3 + pulse * 0.4)) : .clear,
                radius: isActive ? 8 + pulse * 4 : 0
            )
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                if isActive {
                    pulse = 1
                }
            }
            .onChange(of: isActive) { _, newValue in
                pulse = newValue ? 1 : 0
            }
    }
}

extension View {
    /// Adds a pulsing glow effect
    func pulsingGlow(color: Color = .orange, intensity: Double = 1.0, isActive: Bool = true) -> some View {
        modifier(PulsingGlowModifier(color: color, intensity: intensity, isActive: isActive))
    }
}

// MARK: - Meeting Urgency Indicator

struct MeetingUrgencyIndicator: View {
    let minutesUntilStart: Int
    
    private var urgencyLevel: UrgencyLevel {
        switch minutesUntilStart {
        case ..<0: return .inProgress
        case 0..<5: return .imminent
        case 5..<15: return .soon
        case 15..<30: return .upcoming
        default: return .normal
        }
    }
    
    enum UrgencyLevel {
        case inProgress, imminent, soon, upcoming, normal
        
        var color: Color {
            switch self {
            case .inProgress: return .red
            case .imminent: return .orange
            case .soon: return .yellow
            case .upcoming: return .blue
            case .normal: return .clear
            }
        }
        
        var shouldPulse: Bool {
            switch self {
            case .inProgress, .imminent: return true
            default: return false
            }
        }
        
        var label: String? {
            switch self {
            case .inProgress: return "LIVE"
            case .imminent: return "JETZT"
            case .soon: return "BALD"
            default: return nil
            }
        }
    }
    
    var body: some View {
        if let label = urgencyLevel.label {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(urgencyLevel.color)
                )
                .pulsingGlow(
                    color: urgencyLevel.color,
                    intensity: 0.8,
                    isActive: urgencyLevel.shouldPulse
                )
        }
    }
}

// MARK: - Urgency Border Modifier

struct UrgencyBorderModifier: ViewModifier {
    let minutesUntilStart: Int
    
    private var borderColor: Color {
        switch minutesUntilStart {
        case ..<0: return .red.opacity(0.6)
        case 0..<5: return .orange.opacity(0.6)
        case 5..<15: return .yellow.opacity(0.4)
        default: return .clear
        }
    }
    
    private var shouldPulse: Bool {
        minutesUntilStart < 5
    }
    
    @State private var pulse: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        borderColor.opacity(shouldPulse ? 0.5 + pulse * 0.5 : 1),
                        lineWidth: minutesUntilStart < 15 ? 2 : 0
                    )
            )
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                if shouldPulse { pulse = 1 }
            }
    }
}

extension View {
    func urgencyBorder(minutesUntilStart: Int) -> some View {
        modifier(UrgencyBorderModifier(minutesUntilStart: minutesUntilStart))
    }
}

#Preview {
    VStack(spacing: 20) {
        MeetingUrgencyIndicator(minutesUntilStart: -5)
        MeetingUrgencyIndicator(minutesUntilStart: 3)
        MeetingUrgencyIndicator(minutesUntilStart: 10)
        MeetingUrgencyIndicator(minutesUntilStart: 25)
        
        Text("Meeting Card")
            .padding()
            .background(Color.tuiPanel)
            .urgencyBorder(minutesUntilStart: 3)
    }
    .padding()
    .background(Color.tuiBackground)
}
