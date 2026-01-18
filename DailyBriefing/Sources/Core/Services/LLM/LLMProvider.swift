import Foundation
import SwiftUI

/// Supported LLM providers
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .ollama: return "Ollama (Lokal)"
        }
    }

    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "sparkles"
        case .google: return "g.circle.fill"
        case .ollama: return "desktopcomputer"
        }
    }

    var brandColor: Color {
        switch self {
        case .openai: return Color(red: 0.0, green: 0.65, blue: 0.52)
        case .anthropic: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .ollama: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openai, .anthropic, .google: return true
        case .ollama: return false
        }
    }

    var availableModels: [LLMModel] {
        switch self {
        case .openai:
            return [
                LLMModel(id: "gpt-4o", name: "GPT-4o", description: "Schnellstes und günstigstes GPT-4 Modell"),
                LLMModel(id: "gpt-4o-mini", name: "GPT-4o Mini", description: "Kompaktes Modell für einfache Aufgaben"),
                LLMModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", description: "Leistungsstarkes Modell mit großem Kontext"),
                LLMModel(id: "gpt-4", name: "GPT-4", description: "Originales GPT-4 Modell")
            ]
        case .anthropic:
            return [
                LLMModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", description: "Ausgewogenes Modell für die meisten Aufgaben"),
                LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", description: "Schnelles und intelligentes Modell"),
                LLMModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", description: "Schnellstes Claude Modell"),
                LLMModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", description: "Leistungsstärkstes Claude Modell")
            ]
        case .google:
            return [
                LLMModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", description: "Neuestes und schnellstes Modell"),
                LLMModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", description: "Leistungsstarkes Modell mit 1M Token Kontext"),
                LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", description: "Schnelles Modell für einfache Aufgaben")
            ]
        case .ollama:
            return [
                LLMModel(id: "llama3.2", name: "Llama 3.2", description: "Metas neuestes Open-Source Modell"),
                LLMModel(id: "llama3.1", name: "Llama 3.1", description: "Leistungsstarkes Open-Source Modell"),
                LLMModel(id: "mistral", name: "Mistral", description: "Effizientes französisches Modell"),
                LLMModel(id: "mixtral", name: "Mixtral", description: "Mixture-of-Experts Modell"),
                LLMModel(id: "qwen2.5", name: "Qwen 2.5", description: "Alibabas neuestes Modell"),
                LLMModel(id: "phi3", name: "Phi-3", description: "Microsofts kompaktes Modell"),
                LLMModel(id: "gemma2", name: "Gemma 2", description: "Googles Open-Source Modell")
            ]
        }
    }

    var defaultModel: LLMModel {
        availableModels.first!
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        case .ollama: return ""
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .google: return URL(string: "https://aistudio.google.com/apikey")
        case .ollama: return URL(string: "https://ollama.com/download")
        }
    }
}

/// Model information for a specific LLM
struct LLMModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
}

/// Configuration for an LLM provider
struct LLMConfiguration: Codable {
    var provider: LLMProvider
    var modelId: String
    var ollamaBaseURL: String

    init(
        provider: LLMProvider = .openai,
        modelId: String? = nil,
        ollamaBaseURL: String = "http://localhost:11434"
    ) {
        self.provider = provider
        self.modelId = modelId ?? provider.defaultModel.id
        self.ollamaBaseURL = ollamaBaseURL
    }

    var selectedModel: LLMModel? {
        provider.availableModels.first { $0.id == modelId }
    }
}
