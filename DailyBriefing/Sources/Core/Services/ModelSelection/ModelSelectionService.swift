import Foundation
import SwiftUI

// MARK: - Feature Types

/// Features that can use different models
enum FeatureType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case chat
    case actionItems
    case summaries
    case embeddings
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transcription: return "Transkription"
        case .chat: return "Chat mit Transkript"
        case .actionItems: return "Action Items"
        case .summaries: return "Zusammenfassungen"
        case .embeddings: return "Embeddings"
        }
    }
    
    var iconName: String {
        switch self {
        case .transcription: return "waveform"
        case .chat: return "message"
        case .actionItems: return "checkmark.circle"
        case .summaries: return "doc.text"
        case .embeddings: return "brain"
        }
    }
}

// MARK: - Model Provider

/// Available model providers
enum ModelProvider: Codable, Equatable, Hashable {
    case ollama(model: String)      // on-device
    case openai(model: String)
    case anthropic(model: String)
    case mistral(model: String)     // Mistral AI cloud
    case deepgram                    // transcription only
    case voxtral                     // transcription only
    
    var displayName: String {
        switch self {
        case .ollama(let model): return "🏠 Ollama (\(model))"
        case .openai(let model): return "☁️ OpenAI (\(model))"
        case .anthropic(let model): return "☁️ Anthropic (\(model))"
        case .mistral(let model): return "☁️ Mistral (\(model))"
        case .deepgram: return "☁️ Deepgram"
        case .voxtral: return "🏠 Voxtral"
        }
    }
    
    var shortName: String {
        switch self {
        case .ollama(let model): return model
        case .openai(let model): return model
        case .anthropic(let model): return model
        case .mistral(let model): return model
        case .deepgram: return "Deepgram"
        case .voxtral: return "Voxtral"
        }
    }
    
    var providerName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .mistral: return "Mistral"
        case .deepgram: return "Deepgram"
        case .voxtral: return "Voxtral"
        }
    }
    
    var isOnDevice: Bool {
        switch self {
        case .ollama, .voxtral: return true
        case .openai, .anthropic, .mistral, .deepgram: return false
        }
    }
    
    var iconName: String {
        isOnDevice ? "house.fill" : "cloud.fill"
    }
    
    var color: Color {
        switch self {
        case .ollama: return .gray
        case .openai: return Color(red: 0.0, green: 0.65, blue: 0.52)
        case .anthropic: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .mistral: return Color(red: 1.0, green: 0.45, blue: 0.0)  // Mistral orange
        case .deepgram: return Color(red: 0.2, green: 0.6, blue: 0.86)
        case .voxtral: return .purple
        }
    }
}

// MARK: - Model Selection Service

/// Service for managing model selection per feature
@MainActor
final class ModelSelectionService: ObservableObject {
    static let shared = ModelSelectionService()
    
    @Published private(set) var selectedModels: [FeatureType: ModelProvider]
    @Published var lastFallback: (feature: FeatureType, from: ModelProvider, to: ModelProvider)?
    
    private let userDefaultsPrefix = "selectedModel"
    
    private init() {
        // Load saved selections or use defaults
        var models: [FeatureType: ModelProvider] = [:]
        
        for feature in FeatureType.allCases {
            if let savedValue = UserDefaults.standard.string(forKey: "\(userDefaultsPrefix).\(feature.rawValue)"),
               let provider = Self.decodeProvider(from: savedValue) {
                models[feature] = provider
            } else {
                models[feature] = Self.defaultProvider(for: feature)
            }
        }
        
        self.selectedModels = models
    }
    
    // MARK: - Public Methods
    
    /// Get the selected model for a feature
    func getModel(for feature: FeatureType) -> ModelProvider {
        return selectedModels[feature] ?? Self.defaultProvider(for: feature)
    }
    
    /// Set the model for a feature
    func setModel(for feature: FeatureType, provider: ModelProvider) {
        selectedModels[feature] = provider
        
        // Persist to UserDefaults
        let encoded = Self.encodeProvider(provider)
        UserDefaults.standard.set(encoded, forKey: "\(userDefaultsPrefix).\(feature.rawValue)")
        
        // Notify observers
        objectWillChange.send()
    }
    
    /// Get available models for a feature
    func availableModels(for feature: FeatureType) -> [ModelProvider] {
        switch feature {
        case .transcription:
            return [
                .voxtral,
                .deepgram,
                .openai(model: "whisper-1")
            ]
            
        case .chat:
            return [
                .ollama(model: "mistral"),
                .ollama(model: "llama3.2"),
                .openai(model: "gpt-4o-mini"),
                .openai(model: "gpt-4o"),
                .anthropic(model: "claude-3-5-haiku-20241022"),
                .anthropic(model: "claude-3-5-sonnet-20241022"),
                .anthropic(model: "claude-sonnet-4-20250514")
            ]
            
        case .actionItems:
            return [
                .ollama(model: "llama3.2"),
                .ollama(model: "mistral"),
                .openai(model: "gpt-4o-mini"),
                .openai(model: "gpt-4o"),
                .anthropic(model: "claude-3-5-haiku-20241022"),
                .anthropic(model: "claude-3-5-sonnet-20241022")
            ]
            
        case .summaries:
            return [
                .ollama(model: "llama3.2"),
                .ollama(model: "mistral"),
                .openai(model: "gpt-4o-mini"),
                .openai(model: "gpt-4o"),
                .anthropic(model: "claude-3-5-haiku-20241022"),
                .anthropic(model: "claude-3-5-sonnet-20241022"),
                .anthropic(model: "claude-sonnet-4-20250514")
            ]
            
        case .embeddings:
            return [
                .ollama(model: "nomic-embed-text"),
                .openai(model: "text-embedding-3-small"),
                .openai(model: "text-embedding-3-large")
            ]
        }
    }
    
    /// Get default provider for a feature
    static func defaultProvider(for feature: FeatureType) -> ModelProvider {
        switch feature {
        case .transcription:
            return .voxtral
        case .chat:
            return .anthropic(model: "claude-3-5-haiku-20241022")
        case .actionItems:
            return .openai(model: "gpt-4o-mini")
        case .summaries:
            return .anthropic(model: "claude-3-5-sonnet-20241022")
        case .embeddings:
            return .openai(model: "text-embedding-3-small")
        }
    }
    
    /// Reset all models to defaults
    func resetToDefaults() {
        for feature in FeatureType.allCases {
            setModel(for: feature, provider: Self.defaultProvider(for: feature))
        }
    }
    
    // MARK: - Persistence Helpers
    
    private static func encodeProvider(_ provider: ModelProvider) -> String {
        switch provider {
        case .ollama(let model):
            return "ollama:\(model)"
        case .openai(let model):
            return "openai:\(model)"
        case .anthropic(let model):
            return "anthropic:\(model)"
        case .mistral(let model):
            return "mistral:\(model)"
        case .deepgram:
            return "deepgram"
        case .voxtral:
            return "voxtral"
        }
    }
    
    private static func decodeProvider(from string: String) -> ModelProvider? {
        let components = string.split(separator: ":", maxSplits: 1).map(String.init)
        
        if components.count == 1 {
            // Simple provider without model
            switch components[0] {
            case "deepgram": return .deepgram
            case "voxtral": return .voxtral
            default: return nil
            }
        } else if components.count == 2 {
            // Provider with model
            let provider = components[0]
            let model = components[1]
            
            switch provider {
            case "ollama": return .ollama(model: model)
            case "openai": return .openai(model: model)
            case "anthropic": return .anthropic(model: model)
            case "mistral": return .mistral(model: model)
            default: return nil
            }
        }
        
        return nil
    }
}

// MARK: - Model Info

/// Additional information about a model
struct ModelInfo {
    let provider: ModelProvider
    let contextWindow: Int?
    let costPer1MTokens: Double?
    let description: String
    
    static func info(for provider: ModelProvider) -> ModelInfo {
        switch provider {
        // Transcription
        case .voxtral:
            return ModelInfo(
                provider: provider,
                contextWindow: nil,
                costPer1MTokens: nil,
                description: "On-device Spracherkennung mit höchster Privatsphäre"
            )
        case .deepgram:
            return ModelInfo(
                provider: provider,
                contextWindow: nil,
                costPer1MTokens: 0.0043,
                description: "Schnelle Cloud-Transkription mit hoher Genauigkeit"
            )
            
        // OpenAI
        case .openai(let model):
            switch model {
            case "whisper-1":
                return ModelInfo(
                    provider: provider,
                    contextWindow: nil,
                    costPer1MTokens: 0.006,
                    description: "OpenAI's Whisper für präzise Transkription"
                )
            case "gpt-4o-mini":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 128_000,
                    costPer1MTokens: 0.15,
                    description: "Schnelles und günstiges GPT-4o Modell"
                )
            case "gpt-4o":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 128_000,
                    costPer1MTokens: 2.50,
                    description: "Leistungsstärkstes GPT-4o Modell"
                )
            case "text-embedding-3-small":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 8191,
                    costPer1MTokens: 0.02,
                    description: "Kompakte Embeddings für Suche und Ähnlichkeit"
                )
            case "text-embedding-3-large":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 8191,
                    costPer1MTokens: 0.13,
                    description: "Hochdimensionale Embeddings für beste Qualität"
                )
            default:
                return ModelInfo(
                    provider: provider,
                    contextWindow: nil,
                    costPer1MTokens: nil,
                    description: "OpenAI Modell"
                )
            }
            
        // Anthropic
        case .anthropic(let model):
            switch model {
            case "claude-3-5-haiku-20241022":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 200_000,
                    costPer1MTokens: 0.80,
                    description: "Schnellstes Claude Modell"
                )
            case "claude-3-5-sonnet-20241022":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 200_000,
                    costPer1MTokens: 3.00,
                    description: "Ausgewogenes und intelligentes Modell"
                )
            case "claude-sonnet-4-20250514":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 200_000,
                    costPer1MTokens: 3.00,
                    description: "Neuestes Claude 4 Sonnet Modell"
                )
            default:
                return ModelInfo(
                    provider: provider,
                    contextWindow: 200_000,
                    costPer1MTokens: nil,
                    description: "Claude Modell"
                )
            }
            
        // Ollama
        case .ollama(let model):
            switch model {
            case "mistral":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 32_768,
                    costPer1MTokens: nil,
                    description: "Effizientes lokales Modell von Mistral AI"
                )
            case "llama3.2":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 128_000,
                    costPer1MTokens: nil,
                    description: "Metas neuestes Open-Source Modell"
                )
            case "nomic-embed-text":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 8192,
                    costPer1MTokens: nil,
                    description: "Lokale Embeddings für Suche und Ähnlichkeit"
                )
            default:
                return ModelInfo(
                    provider: provider,
                    contextWindow: nil,
                    costPer1MTokens: nil,
                    description: "Lokales Ollama Modell - kostenlos und privat"
                )
            }
            
        // Mistral
        case .mistral(let model):
            switch model {
            case "mistral-large-latest":
                return ModelInfo(
                    provider: provider,
                    contextWindow: 128_000,
                    costPer1MTokens: 2.00,
                    description: "Mistral's leistungsstärkstes Modell"
                )
            default:
                return ModelInfo(
                    provider: provider,
                    contextWindow: 128_000,
                    costPer1MTokens: nil,
                    description: "Mistral AI Cloud Modell"
                )
            }
        }
    }
}

// MARK: - Fallback Mechanism

extension ModelSelectionService {
    /// Get model with fallback chain
    func getModelWithFallback(for feature: FeatureType) async -> ModelProvider {
        let primary = getModel(for: feature)
        
        // Try primary
        if await isAvailable(primary) {
            // Clear any previous fallback notification for this feature
            if lastFallback?.feature == feature {
                lastFallback = nil
            }
            return primary
        }
        
        // Try fallback chain
        let fallbacks = getFallbackChain(for: feature)
        for fallback in fallbacks {
            if await isAvailable(fallback) {
                print("⚠️ Primary model unavailable, using fallback: \(fallback.displayName)")
                
                // Notify user on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.lastFallback = (feature, primary, fallback)
                }
                
                return fallback
            }
        }
        
        // Last resort: return primary and let caller handle error
        print("❌ No available models for \(feature.displayName)")
        return primary
    }
    
    /// Check if a model provider is available
    private func isAvailable(_ provider: ModelProvider) async -> Bool {
        switch provider {
        case .ollama(let model):
            // Check if Ollama is running and model exists
            return await OllamaAvailabilityService.shared.isModelAvailable(model)
            
        case .openai:
            // Check if API key exists
            return KeychainService.shared.getOpenAIKey() != nil
            
        case .anthropic:
            return KeychainService.shared.getAnthropicKey() != nil
            
        case .deepgram:
            return KeychainService.shared.getDeepgramKey() != nil
            
        case .mistral:
            return KeychainService.shared.getMistralKey() != nil
            
        case .voxtral:
            // Always available if installed (local transcription)
            return true
        }
    }
    
    /// Get fallback chain for a feature
    private func getFallbackChain(for feature: FeatureType) -> [ModelProvider] {
        switch feature {
        case .transcription:
            return [
                .voxtral,
                .ollama(model: "whisper"),
                .openai(model: "whisper-1")
            ]
            
        case .chat, .summaries, .actionItems:
            return [
                .ollama(model: "mistral"),
                .ollama(model: "llama3.2"),
                .mistral(model: "mistral-large-latest"),
                .openai(model: "gpt-4o-mini"),
                .anthropic(model: "claude-3-5-haiku-20241022")
            ]
            
        case .embeddings:
            return [
                .ollama(model: "nomic-embed-text"),
                .openai(model: "text-embedding-3-small")
            ]
        }
    }
}
