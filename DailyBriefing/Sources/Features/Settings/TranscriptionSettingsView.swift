import SwiftUI

struct TranscriptionSettingsView: View {
    @StateObject private var transcriptionService = TranscriptionService.shared
    private let keychain = KeychainService.shared
    
    var body: some View {
        Form {
            Section {
                ForEach(LLMProvider.allCases.filter { $0.supportsTranscription }) { provider in
                    HStack {
                        Image(systemName: provider.iconName)
                            .foregroundStyle(provider.brandColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                            Text(provider == .groq ? "Schnell & Günstig" : "Genau & Bewährt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if transcriptionService.transcriptionProvider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        } else if keychain.loadLLMAPIKey(for: provider.rawValue) == nil {
                            Text("Kein API Key")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            transcriptionService.setProvider(provider)
                        }
                    }
                }
            } header: {
                Text("Transkriptions-Provider")
            } footer: {
                Text("Wähle den Dienst für die Umwandlung von Sprache in Text. Groq ist extrem schnell, OpenAI bietet sehr hohe Qualität.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.tuiBackground)
    }
}
