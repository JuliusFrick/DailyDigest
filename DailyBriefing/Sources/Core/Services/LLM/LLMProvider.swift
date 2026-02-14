import Foundation
import SwiftUI

/// Supported LLM providers
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openai = "openai"
    case groq = "groq"
    case anthropic = "anthropic"
    case google = "google"
    case mistral = "mistral"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .mistral: return "Mistral"
        case .ollama: return "Ollama (Lokal)"
        }
    }

    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .groq: return "bolt.fill"
        case .anthropic: return "sparkles"
        case .google: return "g.circle.fill"
        case .mistral: return "wind"
        case .ollama: return "desktopcomputer"
        }
    }

    var brandColor: Color {
        switch self {
        case .openai: return Color(red: 0.0, green: 0.65, blue: 0.52)
        case .groq: return Color(red: 0.96, green: 0.33, blue: 0.23) // Groq Orange
        case .anthropic: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .mistral: return Color(red: 1.0, green: 0.45, blue: 0.0) // Mistral Orange
        case .ollama: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openai, .groq, .anthropic, .google, .mistral: return true
        case .ollama: return false
        }
    }

    var supportsTranscription: Bool {
        switch self {
        case .openai, .groq: return true
        case .anthropic, .google, .mistral, .ollama: return false
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
        case .groq:
            return [
                LLMModel(id: "llama3-70b-8192", name: "Llama 3 70B", description: "Leistungsstarkes & schnelles Modell"),
                LLMModel(id: "llama3-8b-8192", name: "Llama 3 8B", description: "Sehr schnelles, kompaktes Modell"),
                LLMModel(id: "mixtral-8x7b-32768", name: "Mixtral 8x7B", description: "Starkes Allround-Modell"),
                LLMModel(id: "gemma-7b-it", name: "Gemma 7B", description: "Google's Gemma optimiert für Groq")
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
        case .mistral:
            return [
                LLMModel(id: "mistral-large-latest", name: "Mistral Large", description: "Flaggschiff-Modell für komplexe Aufgaben"),
                LLMModel(id: "mistral-medium-latest", name: "Mistral Medium", description: "Ausgewogenes Modell für die meisten Aufgaben"),
                LLMModel(id: "mistral-small-latest", name: "Mistral Small", description: "Schnelles und kosteneffizientes Modell"),
                LLMModel(id: "open-mistral-nemo", name: "Mistral Nemo", description: "Open-Source 12B Modell"),
                LLMModel(id: "codestral-latest", name: "Codestral", description: "Spezialisiert auf Code-Generierung")
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
        availableModels.first ?? .gpt4o
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .groq: return "gsk_..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        case .mistral: return ""
        case .ollama: return ""
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .google: return URL(string: "https://aistudio.google.com/apikey")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
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
