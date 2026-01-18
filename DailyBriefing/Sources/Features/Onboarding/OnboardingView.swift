import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentStep = 0

    private let steps = [
        OnboardingStep(
            icon: "sun.horizon.fill",
            title: "Willkommen bei Daily Briefing",
            description: "Starte jeden Tag informiert mit einem personalisierten Briefing aus all deinen wichtigen Quellen.",
            accentColor: .orange
        ),
        OnboardingStep(
            icon: "square.stack.3d.up.fill",
            title: "Verbinde deine Quellen",
            description: "Google Calendar, Jira, Slack, Email – alles an einem Ort. Du entscheidest welche Quellen du nutzen möchtest.",
            accentColor: .blue
        ),
        OnboardingStep(
            icon: "waveform",
            title: "Hör dein Briefing",
            description: "Lass dir dein Briefing vorlesen während du deinen Kaffee trinkst. Quick oder Detailed – du wählst.",
            accentColor: .purple
        ),
        OnboardingStep(
            icon: "sparkles",
            title: "KI-generierte Zusammenfassung",
            description: "Unsere KI fasst das Wichtigste zusammen und priorisiert automatisch. Du verpasst nichts mehr.",
            accentColor: .pink
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentStep) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    OnboardingStepView(step: step)
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(maxHeight: .infinity)

            // Bottom section
            VStack(spacing: 20) {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentStep)
                    }
                }

                // Buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button("Zurück") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if currentStep < steps.count - 1 {
                        Button("Weiter") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Los geht's") {
                            appState.completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(32)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background {
            LinearGradient(
                colors: [
                    steps[currentStep].accentColor.opacity(0.1),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .animation(.easeInOut, value: currentStep)
        }
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
}

struct OnboardingStepView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(step.accentColor.gradient.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: step.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(step.accentColor.gradient)
            }

            // Text
            VStack(spacing: 16) {
                Text(step.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(step.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 400)
            }

            Spacer()
            Spacer()
        }
        .padding(32)
    }
}
