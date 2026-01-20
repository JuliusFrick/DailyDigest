import SwiftUI

struct SetupGuideView: View {
    let title: String
    let steps: [SetupStep]
    let onCompletion: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.body, design: .monospaced))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.tuiBackground)
            
            Divider()
            
            // Content
            TabView(selection: $currentStepIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepView(step: step)
                        .tag(index)
                        .padding()
                }
            }
            #if os(macOS)
            .tabViewStyle(.automatic) // Changed from .page which might not be available or behave differently
            #else
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            
            Divider()
            
            // Footer
            HStack {
                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStepIndex ? Color.tuiAccent : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                // Navigation buttons
                if currentStepIndex > 0 {
                    Button("Zurück") {
                        withAnimation {
                            currentStepIndex -= 1
                        }
                    }
                    .buttonStyle(.tui)
                }
                
                if currentStepIndex < steps.count - 1 {
                    Button("Weiter") {
                        withAnimation {
                            currentStepIndex += 1
                        }
                    }
                    .buttonStyle(.tuiPrimary)
                } else {
                    Button("Fertig") {
                        onCompletion()
                        dismiss()
                    }
                    .buttonStyle(.tuiPrimary)
                }
            }
            .padding()
            .background(Color.tuiBackground)
        }
        .frame(width: 500, height: 400)
    }
}

struct SetupStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let imageSystemName: String?
    let actionButtonTitle: String?
    let actionURL: URL?
    
    init(title: String, description: String, imageSystemName: String? = nil, actionButtonTitle: String? = nil, actionURL: URL? = nil) {
        self.title = title
        self.description = description
        self.imageSystemName = imageSystemName
        self.actionButtonTitle = actionButtonTitle
        self.actionURL = actionURL
    }
}

struct StepView: View {
    let step: SetupStep
    
    var body: some View {
        VStack(spacing: 20) {
            if let imageName = step.imageSystemName {
                Image(systemName: imageName)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.tuiAccent)
                    .padding()
                    .background(Color.tuiAccent.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Text(step.title)
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(step.description)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let actionTitle = step.actionButtonTitle, let url = step.actionURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack {
                        Text(actionTitle)
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(.tui)
                .padding(.top)
            }
            
            Spacer()
        }
    }
}
