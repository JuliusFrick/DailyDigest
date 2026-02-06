import Foundation
import Security

/// Simple Keychain wrapper for storing OAuth tokens securely
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.dailybriefing.app"

    private init() {}

    // MARK: - Public API

    func save(_ data: Data, for key: String) throws {
        // Delete existing item first
        try? delete(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status)
        }
    }

    func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, for: key)
    }

    func load(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    func loadString(for key: String) throws -> String {
        let data = try load(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    func exists(for key: String) -> Bool {
        do {
            _ = try load(for: key)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case unableToSave(OSStatus)
    case unableToDelete(OSStatus)
    case itemNotFound
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .unableToSave(let status):
            return "Keychain-Speicherfehler: \(status)"
        case .unableToDelete(let status):
            return "Keychain-Löschfehler: \(status)"
        case .itemNotFound:
            return "Element nicht in Keychain gefunden"
        case .encodingFailed:
            return "Fehler beim Kodieren der Daten"
        case .decodingFailed:
            return "Fehler beim Dekodieren der Daten"
        }
    }
}

// MARK: - OAuth Token Storage

extension KeychainService {
    struct OAuthTokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let tokenType: String

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    func saveTokens(_ tokens: OAuthTokens, for sourceId: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(tokens)
        try save(data, for: "oauth_\(sourceId)")
    }

    func loadTokens(for sourceId: String) throws -> OAuthTokens {
        let data = try load(for: "oauth_\(sourceId)")
        let decoder = JSONDecoder()
        return try decoder.decode(OAuthTokens.self, from: data)
    }

    func deleteTokens(for sourceId: String) throws {
        try delete(for: "oauth_\(sourceId)")
    }

    func hasTokens(for sourceId: String) -> Bool {
        exists(for: "oauth_\(sourceId)")
    }
}

// MARK: - LLM API Key Storage

extension KeychainService {
    private func llmKeyIdentifier(for provider: String) -> String {
        "llm_apikey_\(provider)"
    }

    /// Save an API key for an LLM provider
    func saveLLMAPIKey(_ apiKey: String, for provider: String) throws {
        try save(apiKey, for: llmKeyIdentifier(for: provider))
    }

    /// Load the API key for an LLM provider
    func loadLLMAPIKey(for provider: String) -> String? {
        try? loadString(for: llmKeyIdentifier(for: provider))
    }

    /// Delete the API key for an LLM provider
    func deleteLLMAPIKey(for provider: String) throws {
        try delete(for: llmKeyIdentifier(for: provider))
    }

    /// Check if an API key exists for an LLM provider
    func hasLLMAPIKey(for provider: String) -> Bool {
        exists(for: llmKeyIdentifier(for: provider))
    }
    
    // MARK: - Convenience Methods
    
    /// Get OpenAI API key
    func getOpenAIKey() -> String? {
        loadLLMAPIKey(for: "openai")
    }
    
    /// Get Anthropic API key
    func getAnthropicKey() -> String? {
        loadLLMAPIKey(for: "anthropic")
    }
    
    /// Get Deepgram API key
    func getDeepgramKey() -> String? {
        loadLLMAPIKey(for: "deepgram")
    }
    
    /// Get Mistral API key
    func getMistralKey() -> String? {
        loadLLMAPIKey(for: "mistral")
    }
    
    /// Set Mistral API key
    func setMistralKey(_ key: String) throws {
        try saveLLMAPIKey(key, for: "mistral")
    }
    
    /// Get Groq API key
    func getGroqKey() -> String? {
        loadLLMAPIKey(for: "groq")
    }
    
    /// Get Google AI API key
    func getGoogleAIKey() -> String? {
        loadLLMAPIKey(for: "google")
    }
}

// MARK: - Delete All Credentials

extension KeychainService {
    /// Delete all credentials stored in the keychain for this app
    func deleteAllCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }
}
