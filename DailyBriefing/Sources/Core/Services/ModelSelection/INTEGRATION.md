# Model Selection System - Integration Guide

## Overview

Das Model Selection System ermöglicht flexible Auswahl von KI-Modellen für verschiedene Features in DailyDigest. Jedes Feature (Transkription, Chat, Action Items, etc.) kann ein eigenes Modell verwenden.

## Features

- ✅ **Feature-spezifische Model-Auswahl**: Jedes Feature kann unabhängig konfiguriert werden
- ✅ **On-Device und Cloud**: Unterstützung für lokale (Ollama, Voxtral) und Cloud-Modelle (OpenAI, Anthropic, Deepgram)
- ✅ **Persistenz**: Auswahl wird in UserDefaults gespeichert
- ✅ **UI Components**: Fertige SwiftUI-Komponenten für Settings
- ✅ **Model Info**: Kontextfenster, Kosten, Beschreibungen

## Architecture

```
ModelSelectionService (Singleton)
├── FeatureType (enum)
│   ├── transcription
│   ├── chat
│   ├── actionItems
│   ├── summaries
│   └── embeddings
│
└── ModelProvider (enum)
    ├── ollama(model: String)      🏠 On-Device
    ├── openai(model: String)      ☁️ Cloud
    ├── anthropic(model: String)   ☁️ Cloud
    ├── deepgram                   ☁️ Cloud (Transkription)
    └── voxtral                    🏠 On-Device (Transkription)
```

## Usage in Services

### Example: Chat Service

```swift
import Foundation

@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [Message] = []
    
    private let modelService = ModelSelectionService.shared
    
    func sendMessage(_ text: String) async throws -> String {
        let selectedModel = modelService.getModel(for: .chat)
        
        switch selectedModel {
        case .ollama(let model):
            return try await callOllama(model: model, prompt: text)
            
        case .openai(let model):
            return try await callOpenAI(model: model, prompt: text)
            
        case .anthropic(let model):
            return try await callAnthropic(model: model, prompt: text)
            
        default:
            throw ChatError.unsupportedModel
        }
    }
    
    private func callOllama(model: String, prompt: String) async throws -> String {
        // Implementation
    }
    
    private func callOpenAI(model: String, prompt: String) async throws -> String {
        // Implementation
    }
    
    private func callAnthropic(model: String, prompt: String) async throws -> String {
        // Implementation
    }
}
```

### Example: Transcription Service Integration

Update `TranscriptionService.swift`:

```swift
import Foundation

@MainActor
final class EnhancedTranscriptionService: ObservableObject {
    @Published private(set) var isTranscribing = false
    
    private let modelService = ModelSelectionService.shared
    private let keychain = KeychainService.shared
    
    func transcribe(audioURL: URL) async throws -> String {
        let selectedModel = modelService.getModel(for: .transcription)
        
        switch selectedModel {
        case .voxtral:
            return try await transcribeWithVoxtral(audioURL: audioURL)
            
        case .deepgram:
            return try await transcribeWithDeepgram(audioURL: audioURL)
            
        case .openai(let model):
            return try await transcribeWithOpenAI(audioURL: audioURL, model: model)
            
        default:
            throw TranscriptionError.unsupportedModel
        }
    }
    
    private func transcribeWithVoxtral(audioURL: URL) async throws -> String {
        // On-device transcription with Voxtral
        // TODO: Implement Voxtral integration
        throw TranscriptionError.notImplemented
    }
    
    private func transcribeWithDeepgram(audioURL: URL) async throws -> String {
        // Cloud transcription with Deepgram
        // TODO: Implement Deepgram API integration
        throw TranscriptionError.notImplemented
    }
    
    private func transcribeWithOpenAI(audioURL: URL, model: String) async throws -> String {
        // Existing OpenAI Whisper implementation
        // (Keep current implementation)
    }
}
```

## UI Integration

### In SettingsView

```swift
Section {
    ModelSelectionRow(
        feature: .transcription,
        title: "Transkription",
        icon: "waveform"
    )
    
    ModelSelectionRow(
        feature: .chat,
        title: "Chat mit Transkript",
        icon: "message"
    )
    
    // ... more features
} header: {
    Text("Model Configuration")
} footer: {
    Text("🏠 On-Device Modelle laufen lokal und sind kostenlos. ☁️ Cloud-Modelle benötigen API-Keys.")
}
```

## Adding New Models

### 1. Add to availableModels in ModelSelectionService

```swift
func availableModels(for feature: FeatureType) -> [ModelProvider] {
    switch feature {
    case .chat:
        return [
            .ollama(model: "mistral"),
            .ollama(model: "llama3.2"),
            .openai(model: "gpt-4o-mini"),
            // Add your new model:
            .openai(model: "gpt-4o-2024-11-20"),
        ]
    // ...
    }
}
```

### 2. Add ModelInfo

```swift
case .openai(let model):
    switch model {
    case "gpt-4o-2024-11-20":
        return ModelInfo(
            provider: provider,
            contextWindow: 128_000,
            costPer1MTokens: 2.50,
            description: "Neuestes GPT-4o Modell mit verbesserter Reasoning"
        )
    // ...
    }
```

### 3. Handle in Service

```swift
func processWithModel() async throws {
    let model = modelService.getModel(for: .chat)
    
    switch model {
    case .openai(let modelId):
        // Handle OpenAI models including new ones
        return try await callOpenAI(model: modelId)
    // ...
    }
}
```

## Adding New Features

### 1. Add to FeatureType enum

```swift
enum FeatureType: String, CaseIterable {
    case transcription
    case chat
    case actionItems
    case summaries
    case embeddings
    case newFeature  // ← Add here
    
    var displayName: String {
        switch self {
        // ...
        case .newFeature: return "My New Feature"
        }
    }
}
```

### 2. Define available models

```swift
func availableModels(for feature: FeatureType) -> [ModelProvider] {
    switch feature {
    // ...
    case .newFeature:
        return [
            .ollama(model: "llama3.2"),
            .openai(model: "gpt-4o-mini")
        ]
    }
}
```

### 3. Set default

```swift
static func defaultProvider(for feature: FeatureType) -> ModelProvider {
    switch feature {
    // ...
    case .newFeature:
        return .ollama(model: "llama3.2")
    }
}
```

### 4. Add to Settings UI

```swift
ModelSelectionRow(
    feature: .newFeature,
    title: "My New Feature",
    icon: "star.fill"
)
```

## Testing

```swift
// Get current selection
let model = ModelSelectionService.shared.getModel(for: .chat)
print("Current chat model: \(model.displayName)")

// Change selection
ModelSelectionService.shared.setModel(
    for: .chat,
    provider: .anthropic(model: "claude-3-5-sonnet-20241022")
)

// List available models
let available = ModelSelectionService.shared.availableModels(for: .transcription)
for model in available {
    let info = ModelInfo.info(for: model)
    print("- \(model.displayName): \(info.description)")
}

// Reset to defaults
ModelSelectionService.shared.resetToDefaults()
```

## Persistence Format

Models are stored in UserDefaults with the format:

```
selectedModel.transcription = "voxtral"
selectedModel.chat = "anthropic:claude-3-5-haiku-20241022"
selectedModel.actionItems = "openai:gpt-4o-mini"
selectedModel.summaries = "ollama:llama3.2"
selectedModel.embeddings = "openai:text-embedding-3-small"
```

Format: `{provider}:{model}` or just `{provider}` for simple cases.

## Next Steps

### Immediate (Phase 1):
- ✅ Core service created
- ✅ UI components created
- ✅ Settings integration
- ⏳ Test with existing services

### Phase 2:
- [ ] Implement Voxtral transcription service
- [ ] Implement Deepgram transcription service
- [ ] Create ChatService using ModelSelectionService
- [ ] Migrate existing LLMService to use ModelSelectionService

### Phase 3:
- [ ] Add model capability detection (check if Ollama models are downloaded)
- [ ] Add model performance metrics (speed, quality)
- [ ] Add A/B testing support for model comparison
- [ ] Add cost tracking per feature

## Questions?

Contact: Daily Briefing Team
Issues: Create PR or open GitHub issue
