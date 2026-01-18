import Foundation
import AuthenticationServices

/// Generic OAuth 2.0 service for handling authentication flows
@MainActor
final class OAuthService: NSObject, ObservableObject {

    // MARK: - Configuration

    struct Configuration {
        let clientId: String
        let clientSecret: String?
        let authorizationURL: URL
        let tokenURL: URL
        let redirectURI: String
        let scopes: [String]

        var scopeString: String {
            scopes.joined(separator: " ")
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let sourceId: String
    private let keychain = KeychainService.shared

    @Published private(set) var isAuthenticating = false
    @Published private(set) var error: Error?

    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    // MARK: - Initialization

    init(configuration: Configuration, sourceId: String) {
        self.configuration = configuration
        self.sourceId = sourceId
        super.init()
    }

    // MARK: - Public API

    /// Start the OAuth authorization flow
    func authorize() async throws -> KeychainService.OAuthTokens {
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Build authorization URL
        var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopeString),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidConfiguration
        }

        // Start authentication session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "dailybriefing"
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OAuthError.noCallbackReceived)
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.authSession = session

            if !session.start() {
                continuation.resume(throwing: OAuthError.sessionStartFailed)
            }
        }

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.noAuthorizationCode
        }

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code)

        // Save tokens
        try keychain.saveTokens(tokens, for: sourceId)

        return tokens
    }

    /// Get current valid tokens, refreshing if necessary
    func getValidTokens() async throws -> KeychainService.OAuthTokens {
        var tokens = try keychain.loadTokens(for: sourceId)

        if tokens.isExpired, let refreshToken = tokens.refreshToken {
            tokens = try await refreshTokens(refreshToken)
            try keychain.saveTokens(tokens, for: sourceId)
        }

        return tokens
    }

    /// Revoke tokens and clear storage
    func logout() async throws {
        try keychain.deleteTokens(for: sourceId)
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        keychain.hasTokens(for: sourceId)
    }

    // MARK: - Private Methods

    private func exchangeCodeForTokens(_ code: String) async throws -> KeychainService.OAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI)
        ]

        if let clientSecret = configuration.clientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }

        return try parseTokenResponse(data)
    }

    private func refreshTokens(_ refreshToken: String) async throws -> KeychainService.OAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: configuration.clientId)
        ]

        if let clientSecret = configuration.clientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.tokenRefreshFailed
        }

        var tokens = try parseTokenResponse(data)

        // Some providers don't return a new refresh token
        if tokens.refreshToken == nil {
            tokens = KeychainService.OAuthTokens(
                accessToken: tokens.accessToken,
                refreshToken: refreshToken,
                expiresAt: tokens.expiresAt,
                tokenType: tokens.tokenType
            )
        }

        return tokens
    }

    private func parseTokenResponse(_ data: Data) throws -> KeychainService.OAuthTokens {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let token_type: String
        }

        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        let expiresAt: Date?
        if let expiresIn = response.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiresAt = nil
        }

        return KeychainService.OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: expiresAt,
            tokenType: response.token_type
        )
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor = presentationAnchor {
            return anchor
        }
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case invalidConfiguration
    case sessionStartFailed
    case noCallbackReceived
    case noAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "OAuth-Konfiguration ist ungültig"
        case .sessionStartFailed:
            return "Authentifizierung konnte nicht gestartet werden"
        case .noCallbackReceived:
            return "Keine Antwort vom Auth-Server erhalten"
        case .noAuthorizationCode:
            return "Kein Autorisierungscode erhalten"
        case .tokenExchangeFailed:
            return "Token-Austausch fehlgeschlagen"
        case .tokenRefreshFailed:
            return "Token-Aktualisierung fehlgeschlagen"
        case .notAuthenticated:
            return "Nicht authentifiziert"
        }
    }
}
