import Foundation

final class ExternalBridgeAuth {
    private let keychain = KeychainService.shared

    func currentSecret() -> String? {
        guard let secret = keychain.loadExternalBridgeSecret() else {
            return nil
        }
        return secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : secret
    }

    @discardableResult
    func ensureSecretExists() -> String {
        if let existing = currentSecret() {
            return existing
        }

        let generated = generateSecret()
        try? keychain.saveExternalBridgeSecret(generated)
        return generated
    }

    func rotateSecret() throws -> String {
        let generated = generateSecret()
        try keychain.saveExternalBridgeSecret(generated)
        return generated
    }

    func deleteSecret() throws {
        if currentSecret() != nil {
            try keychain.deleteExternalBridgeSecret()
        }
    }

    func isAuthorized(headers: [String: String], expectedToken: String?) -> Bool {
        guard let expectedToken,
              !expectedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let token = extractToken(from: headers)
        guard let token else { return false }
        return token == expectedToken
    }

    private func extractToken(from headers: [String: String]) -> String? {
        if let authorization = headers["authorization"] {
            let trimmed = authorization.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("bearer ") {
                return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !trimmed.isEmpty { return trimmed }
        }

        if let apiKey = headers["x-api-key"] {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return nil
    }

    private func generateSecret() -> String {
        let chunks = [
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16),
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        ]
        return "\(chunks[0])-\(chunks[1])"
    }
}

