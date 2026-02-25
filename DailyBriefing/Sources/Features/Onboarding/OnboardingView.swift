import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentStep = 0
    @State private var typedText = ""
    @State private var showCursor = true

    private let steps = [
        OnboardingStep(
            title: "DAILY BRIEFING",
            description: "your morning intelligence. all sources. one summary."
        ),
        OnboardingStep(
            title: "SOURCES",
            description: "calendar. jira. slack. email. connect what you need."
        ),
        OnboardingStep(
            title: "AUDIO",
            description: "listen while you commute. quick or detailed mode."
        ),
        OnboardingStep(
            title: "AI SUMMARY",
            description: "auto-prioritized. nothing missed."
        )
    ]

    var body: some View {
        ZStack {
            Color.tuiBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ASCII art header
                Text(asciiHeader)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.xl)

                Spacer()

                // Content
                VStack(spacing: Spacing.lg) {
                    // Step counter
                    Text("[\(currentStep + 1)/\(steps.count)]")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.tertiary)

                    // Title with typing effect
                    HStack(spacing: 0) {
                        Text(steps[currentStep].title)
                            .font(.tuiMono)
                            .fontWeight(.bold)

                        Text(showCursor ? "_" : " ")
                            .font(.tuiMono)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }

                    // Description
                    Text(steps[currentStep].description)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Spacer()

                // Progress and controls
                VStack(spacing: Spacing.lg) {
                    // ASCII progress bar
                    Text(progressBar)
                        .font(.tuiMonoSmall)
                        .foregroundStyle(.tertiary)

                    // Controls
                    HStack(spacing: Spacing.md) {
                        if currentStep > 0 {
                            Button {
                                withAnimation(.tuiSnappy) {
                                    currentStep -= 1
                                }
                            } label: {
                                Text("← back")
                            }
                            .buttonStyle(.tuiGhost)
                        }

                        Spacer()

                        Button {
                            if currentStep < steps.count - 1 {
                                withAnimation(.tuiSnappy) {
                                    currentStep += 1
                                }
                            } else {
                                appState.completeOnboarding()
                            }
                        } label: {
                            Text(currentStep < steps.count - 1 ? "next →" : "start →")
                        }
                        .buttonStyle(.tuiPrimary)
                    }

                    // Keyboard hint
                    Text("ENTER zum Weiter machen")
                        .font(.tuiMonoTiny)
                        .foregroundStyle(.quaternary)
                }
                .padding(Spacing.xl)
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            startCursorBlink()
        }
        .onKeyPress(.return) {
            if currentStep < steps.count - 1 {
                withAnimation(.tuiSnappy) {
                    currentStep += 1
                }
            } else {
                appState.completeOnboarding()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if currentStep > 0 {
                withAnimation(.tuiSnappy) {
                    currentStep -= 1
                }
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if currentStep < steps.count - 1 {
                withAnimation(.tuiSnappy) {
                    currentStep += 1
                }
            }
            return .handled
        }
    }

    private var asciiHeader: String {
        """
        ╔═══════════════════════════════════════╗
        ║                                       ║
        ║          D A I L Y                    ║
        ║       B R I E F I N G                 ║
        ║                                       ║
        ╚═══════════════════════════════════════╝
        """
    }

    private var progressBar: String {
        let filled = String(repeating: "█", count: currentStep + 1)
        let empty = String(repeating: "░", count: steps.count - currentStep - 1)
        return "[\(filled)\(empty)]"
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            showCursor.toggle()
        }
    }
}

struct OnboardingStep {
    let title: String
    let description: String
}
