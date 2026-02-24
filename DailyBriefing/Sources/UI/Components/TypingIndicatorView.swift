import SwiftUI

/// Animated typing indicator with three pulsing dots
struct TypingIndicatorView: View {
    @State private var animationOffset: CGFloat = 0
    
    var dotSize: CGFloat = 6
    var dotSpacing: CGFloat = 4
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animationOffset(for: index))
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                animationOffset = 1
            }
        }
    }
    
    private func animationOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = (animationOffset + CGFloat(delay)).truncatingRemainder(dividingBy: 1.0)
        return sin(progress * .pi) * -4
    }
}

/// Chat bubble with typing indicator
struct TypingBubbleView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // AI Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                )
            
            // Typing bubble
            HStack(spacing: 4) {
                TypingIndicatorView(dotSize: 5, color: .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.tuiPanel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tuiBorder, lineWidth: 1)
            )
            
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct TypingIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TypingIndicatorView()
            TypingBubbleView()
        }
        .padding()
        .background(Color.tuiBackground)
    }
}
