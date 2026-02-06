# Model Selection System

Ein flexibles System zur Auswahl von KI-Modellen für verschiedene Features in DailyDigest.

## 🎯 Überblick

Das Model Selection System erlaubt es, für jedes Feature (Transkription, Chat, Action Items, etc.) unabhängig ein KI-Modell auszuwählen. Es unterstützt sowohl lokale On-Device-Modelle (Ollama, Voxtral) als auch Cloud-Modelle (OpenAI, Anthropic, Deepgram).

### Features

- ✅ **Feature-spezifische Auswahl**: Jedes Feature kann sein eigenes Modell nutzen
- ✅ **On-Device & Cloud**: Unterstützung für lokale und Cloud-Modelle
- ✅ **Persistenz**: Einstellungen werden automatisch gespeichert
- ✅ **UI-Komponenten**: Fertige SwiftUI-Views für Settings
- ✅ **Model-Informationen**: Kontextfenster, Kosten, Beschreibungen
- ✅ **Einfache Integration**: Wenige Zeilen Code für neue Services

## 📂 Struktur

```
ModelSelection/
├── ModelSelectionService.swift  # Core Service (Singleton)
├── README.md                    # Diese Datei
└── INTEGRATION.md               # Detaillierte Integration-Anleitung
```

UI-Komponenten:
```
Features/Settings/
└── ModelSelectionRow.swift      # SwiftUI Component für Settings
```

## 🚀 Quick Start

### 1. Model für Feature abrufen

```swift
import Foundation

@MainActor
final class YourService {
    private let modelService = ModelSelectionService.shared
    
    func processData() async throws {
        // Hole das ausgewählte Modell für dein Feature
        let model = modelService.getModel(for: .chat)
        
        // Verarbeite basierend auf dem Modell
        switch model {
        case .ollama(let modelName):
            return try await processWithOllama(model: modelName)
        case .openai(let modelName):
            return try await processWithOpenAI(model: modelName)
        case .anthropic(let modelName):
            return try await processWithAnthropic(model: modelName)
        default:
            throw YourError.unsupportedModel
        }
    }
}
```

### 2. UI in Settings hinzufügen

```swift
Section {
    ModelSelectionRow(
        feature: .chat,
        title: "Chat",
        icon: "message"
    )
} header: {
    Text("Model Configuration")
}
```

### 3. Fertig! 🎉

Das war's! ModelSelectionService kümmert sich um:
- Persistenz in UserDefaults
- UI für Model-Auswahl
- Model-Informationen und Kosten
- On-Device vs. Cloud-Kennzeichnung

## 🔧 Verfügbare Features

```swift
enum FeatureType {
    case transcription  // Sprache zu Text
    case chat          // Chat mit Transkript
    case actionItems   // Action Items extrahieren
    case summaries     // Zusammenfassungen generieren
    case embeddings    // Vector Embeddings
}
```

## 🤖 Verfügbare Models

### On-Device (🏠)
- **Ollama**: mistral, llama3.2, mixtral, qwen2.5, phi3, gemma2, etc.
- **Voxtral**: On-device Spracherkennung

### Cloud (☁️)
- **OpenAI**: GPT-4o, GPT-4o-mini, Whisper, Embeddings
- **Anthropic**: Claude 4 Sonnet, Claude 3.5 Sonnet, Claude 3.5 Haiku
- **Deepgram**: Schnelle Cloud-Transkription

## 📊 Model-Informationen

Jedes Modell enthält:
- **Display Name**: User-friendly Name mit 🏠/☁️ Icon
- **Context Window**: Max. Token-Anzahl
- **Cost**: Kosten pro 1M Tokens
- **Description**: Was das Modell kann

```swift
let info = ModelInfo.info(for: .anthropic(model: "claude-3-5-haiku-20241022"))
print(info.description)        // "Schnellstes Claude Modell"
print(info.contextWindow)      // 200,000
print(info.costPer1MTokens)    // 0.80
```

## 🔄 Migration bestehender Services

### Vorher (altes System):

```swift
final class OldService {
    func process() async throws {
        let config = loadLLMConfiguration()
        let service = LLMServiceFactory.create(
            provider: config.provider,
            apiKey: apiKey,
            modelId: config.modelId
        )
        return try await service.complete(...)
    }
}
```

### Nachher (neues System):

```swift
final class NewService {
    private let modelService = ModelSelectionService.shared
    
    func process() async throws {
        let model = modelService.getModel(for: .chat)
        
        switch model {
        case .ollama(let modelName):
            return try await processWithOllama(model: modelName)
        case .openai(let modelName):
            return try await processWithOpenAI(model: modelName)
        // ...
        }
    }
}
```

## 🎨 UI Preview

<img width="600" alt="Model Selection UI" src="docs/preview.png">

Features:
- ✅ Dropdown-Picker pro Feature
- ✅ 🏠/☁️ Icons für On-Device/Cloud
- ✅ Model-Beschreibungen
- ✅ Kosten-Informationen
- ✅ Context-Window-Anzeige
- ✅ Checkmark für aktuelle Auswahl

## 📖 Weitere Dokumentation

- **[INTEGRATION.md](./INTEGRATION.md)**: Detaillierte Integration-Anleitung
  - Neue Features hinzufügen
  - Neue Modelle hinzufügen
  - Testing
  - Beispiele

## 🛠️ Development

### Neue Modelle hinzufügen

1. Füge Model zu `availableModels(for:)` hinzu
2. Füge `ModelInfo` hinzu (optional)
3. Handle Model in deinem Service

### Neues Feature hinzufügen

1. Füge Case zu `FeatureType` hinzu
2. Definiere `availableModels` für Feature
3. Setze `defaultProvider` für Feature
4. Füge UI-Row in Settings hinzu

Siehe [INTEGRATION.md](./INTEGRATION.md) für Details.

## ⚙️ Konfiguration

Models werden in UserDefaults gespeichert:

```
selectedModel.transcription = "voxtral"
selectedModel.chat = "anthropic:claude-3-5-haiku-20241022"
selectedModel.actionItems = "openai:gpt-4o-mini"
selectedModel.summaries = "ollama:llama3.2"
selectedModel.embeddings = "openai:text-embedding-3-small"
```

## 🔮 Roadmap

### Phase 1: ✅ Core System (Done)
- [x] ModelSelectionService
- [x] UI Components
- [x] Settings Integration
- [x] BriefingChatService Migration

### Phase 2: 🚧 Enhanced Services
- [ ] Voxtral Transcription Service
- [ ] Deepgram Transcription Service
- [ ] TranscriptionService Migration
- [ ] LLMService Migration

### Phase 3: 🔮 Advanced Features
- [ ] Model capability detection (check if downloaded)
- [ ] Performance metrics (speed, quality)
- [ ] A/B testing for model comparison
- [ ] Cost tracking per feature
- [ ] Auto-fallback bei Fehlern

## 💡 Best Practices

1. **Use feature-specific models**: Nutze verschiedene Modelle für verschiedene Use-Cases
   - Schnelle Models für Chat (Haiku)
   - Präzise Models für Summaries (Sonnet)
   - On-Device für Privacy (Ollama)

2. **Fallback-Strategie**: Handle unsupported models gracefully
   ```swift
   default:
       print("Unsupported model, using fallback")
       return try await fallbackMethod()
   ```

3. **API-Key-Validierung**: Prüfe API-Keys bevor du Requests machst
   ```swift
   if provider.requiresAPIKey && apiKey == nil {
       throw Error.apiKeyMissing
   }
   ```

## 🐛 Troubleshooting

### "Model nicht verfügbar"
- Prüfe ob Ollama läuft (für On-Device Models)
- Prüfe API-Key (für Cloud Models)

### "Unsupported Model"
- Model existiert in `availableModels` aber nicht in Service-Handler
- Füge Case in Switch-Statement hinzu

### Settings werden nicht gespeichert
- Prüfe UserDefaults-Key Format: `selectedModel.{feature}`
- Prüfe ob `setModel()` aufgerufen wird

## 📝 Lizenz

Teil von DailyDigest
© 2025 Daily Briefing Team

## 🤝 Contributing

1. Branch erstellen: `git checkout -b feat/my-feature`
2. Changes committen: `git commit -am 'Add feature'`
3. Push: `git push origin feat/my-feature`
4. Pull Request erstellen

---

**Fragen?** Öffne ein Issue oder kontaktiere das Team!
