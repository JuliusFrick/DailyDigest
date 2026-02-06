import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

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
        /// Some providers require comma-separated scopes (e.g. Slack), others space-separated (e.g. Google, Atlassian).
        let scopeSeparator: String
        /// Provider-specific extra parameters for the authorization URL (e.g. Atlassian `audience`, Google `access_type`).
        let additionalAuthorizationQueryItems: [URLQueryItem]
        /// Enables PKCE (recommended/required for some native-app providers like Google).
        let usePKCE: Bool
        /// When true, open the auth page in the default browser and wait for the redirect.
        let useExternalBrowser: Bool
        /// Callback URL scheme used by `ASWebAuthenticationSession` to capture redirects.
        /// For custom schemes use e.g. "dailybriefing"; for loopback redirects use "http".
        let callbackURLScheme: String

        var scopeString: String {
            scopes.joined(separator: scopeSeparator)
        }

        init(
            clientId: String,
            clientSecret: String?,
            authorizationURL: URL,
            tokenURL: URL,
            redirectURI: String,
            scopes: [String],
            scopeSeparator: String = " ",
            additionalAuthorizationQueryItems: [URLQueryItem] = [],
            usePKCE: Bool = false,
            useExternalBrowser: Bool = false,
            callbackURLScheme: String = "dailybriefing"
        ) {
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.authorizationURL = authorizationURL
            self.tokenURL = tokenURL
            self.redirectURI = redirectURI
            self.scopes = scopes
            self.scopeSeparator = scopeSeparator
            self.additionalAuthorizationQueryItems = additionalAuthorizationQueryItems
            self.usePKCE = usePKCE
            self.useExternalBrowser = useExternalBrowser
            self.callbackURLScheme = callbackURLScheme
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
    private var loopbackServer: LoopbackServer?

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
        defer {
            isAuthenticating = false
            loopbackServer?.stop()
            loopbackServer = nil
        }

        guard !configuration.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthError.missingClientId
        }

        // CSRF protection
        let state = Self.randomURLSafeString(length: 32)

        // Optional PKCE (RFC 7636)
        let pkce: PKCEPair? = configuration.usePKCE ? Self.generatePKCE() : nil

        // Determine redirect URI - for loopback with external browser, we need to start the server first
        let redirectURIUsed: String
        let isLoopbackRedirect = Self.isLoopbackRedirectURI(configuration.redirectURI)
        
        if configuration.useExternalBrowser && isLoopbackRedirect {
            // Start loopback server and get the actual port
            let path = Self.extractPath(from: configuration.redirectURI)
            loopbackServer = LoopbackServer(expectedPath: path)
            // We'll get the port after starting the server in the callback flow
            redirectURIUsed = configuration.redirectURI // Will be resolved with actual port below
        } else {
            // For ASWebAuthenticationSession or custom scheme redirects
            redirectURIUsed = Self.resolveRedirectURI(configuration.redirectURI)
        }

        let callbackURL: URL
        if configuration.useExternalBrowser {
            if isLoopbackRedirect {
                // Use loopback server for HTTP redirects
                callbackURL = try await openAuthPageInBrowserWithLoopback(state: state, pkce: pkce)
            } else {
                // Use custom URL scheme with OAuthCallbackRouter
                let authURL = try buildAuthorizationURL(redirectURI: redirectURIUsed, state: state, pkce: pkce)
                NSApplication.shared.activate(ignoringOtherApps: true)
                callbackURL = try await openAuthPageInBrowser(authURL, state: state)
            }
        } else {
            // Use ASWebAuthenticationSession
            let authURL = try buildAuthorizationURL(redirectURI: redirectURIUsed, state: state, pkce: pkce)
            NSApplication.shared.activate(ignoringOtherApps: true)
            callbackURL = try await startAuthSession(authURL)
        }

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.noAuthorizationCode
        }

        // Validate state
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw OAuthError.stateMismatch
        }

        // Get the redirect URI that was actually used (with the real port for loopback)
        let finalRedirectURI: String
        if let server = loopbackServer {
            let path = Self.extractPath(from: configuration.redirectURI)
            finalRedirectURI = "http://127.0.0.1:\(server.port)\(path)"
        } else {
            finalRedirectURI = redirectURIUsed
        }

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code, redirectURIUsed: finalRedirectURI, codeVerifier: pkce?.codeVerifier)

        // Save tokens
        try keychain.saveTokens(tokens, for: sourceId)

        return tokens
    }
    
    /// Build the authorization URL with all required parameters
    private func buildAuthorizationURL(redirectURI: String, state: String, pkce: PKCEPair?) throws -> URL {
        var components = URLComponents(url: configuration.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopeString)
        ]
        if !configuration.additionalAuthorizationQueryItems.isEmpty {
            components.queryItems?.append(contentsOf: configuration.additionalAuthorizationQueryItems)
        }
        components.queryItems?.append(URLQueryItem(name: "state", value: state))
        if let pkce {
            components.queryItems?.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
            components.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }

        guard let authURL = components.url else {
            throw OAuthError.invalidConfiguration
        }
        return authURL
    }

    /// Get current valid tokens, refreshing if necessary
    func getValidTokens() async throws -> KeychainService.OAuthTokens {
        var tokens = try keychain.loadTokens(for: sourceId)

        if tokens.isExpired, let refreshToken = tokens.refreshToken {
            tokens = try await refreshTokens(refreshToken)
            try keychain.saveTokens(tokens, for: sourceId)
        } else if tokens.isExpired {
            throw OAuthError.notAuthenticated
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

    private func exchangeCodeForTokens(_ code: String, redirectURIUsed: String, codeVerifier: String?) async throws -> KeychainService.OAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURIUsed)
        ]

        if let clientSecret = configuration.clientSecret {
            bodyComponents.queryItems?.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        if let codeVerifier {
            bodyComponents.queryItems?.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
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
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case invalidConfiguration
    case missingClientId
    case sessionStartFailed
    case noCallbackReceived
    case noAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notAuthenticated
    case stateMismatch
    case browserOpenFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "OAuth-Konfiguration ist ungültig"
        case .missingClientId:
            return "Client-ID fehlt (OAuth-Konfiguration in der App ist nicht gesetzt)"
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
        case .stateMismatch:
            return "Ungültige Authentifizierungs-Antwort (state stimmt nicht überein)"
        case .browserOpenFailed:
            return "Login-Seite konnte nicht geöffnet werden"
        }
    }
}

// MARK: - Helpers (PKCE / Redirect URI)

private extension OAuthService {
    /// Open auth page in external browser using custom URL scheme callback (for Jira, Slack, etc.)
    func openAuthPageInBrowser(_ authURL: URL, state: String) async throws -> URL {
        guard NSWorkspace.shared.open(authURL) else {
            throw OAuthError.browserOpenFailed
        }
        return try await OAuthCallbackRouter.shared.waitForCallback(state: state)
    }
    
    /// Open auth page in external browser using loopback HTTP callback (for Google)
    func openAuthPageInBrowserWithLoopback(state: String, pkce: PKCEPair?) async throws -> URL {
        guard let server = loopbackServer else {
            throw OAuthError.invalidConfiguration
        }
        
        // Start the server to get the actual port
        let port = try await server.start()
        
        // Start waiting for the callback in the background
        async let callbackTask = server.waitForCallback()
        
        // Build auth URL with the actual server port
        let path = Self.extractPath(from: configuration.redirectURI)
        let redirectURI = "http://127.0.0.1:\(port)\(path)"
        let authURL = try buildAuthorizationURL(redirectURI: redirectURI, state: state, pkce: pkce)
        
        // Ensure app is foregrounded
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Open the browser
        guard NSWorkspace.shared.open(authURL) else {
            server.stop()
            throw OAuthError.browserOpenFailed
        }
        
        // Wait for the callback
        return try await callbackTask
    }

    func startAuthSession(_ authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: configuration.callbackURLScheme
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
    }

    struct PKCEPair {
        let codeVerifier: String
        let codeChallenge: String
    }
    
    /// Check if the redirect URI is a loopback redirect (http://127.0.0.1 or http://localhost)
    static func isLoopbackRedirectURI(_ redirectURI: String) -> Bool {
        guard let url = URL(string: redirectURI),
              let host = url.host,
              (host == "localhost" || host == "127.0.0.1" || host == "::1"),
              url.scheme == "http" || url.scheme == "https"
        else {
            return false
        }
        return true
    }
    
    /// Extract the path component from a redirect URI
    static func extractPath(from redirectURI: String) -> String {
        guard let url = URL(string: redirectURI) else {
            return "/oauth/callback"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    static func resolveRedirectURI(_ redirectURI: String) -> String {
        // Replace ":0" port placeholder for loopback URIs.
        guard var url = URL(string: redirectURI),
              let host = url.host,
              (host == "localhost" || host == "127.0.0.1" || host == "::1"),
              url.scheme == "http" || url.scheme == "https"
        else {
            return redirectURI
        }

        if url.port == 0 {
            let port = Int.random(in: 49152...65535)
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.port = port
            if let resolved = comps?.url {
                url = resolved
            }
        }

        return url.absoluteString
    }

    static func generatePKCE() -> PKCEPair {
        // RFC 7636: code_verifier length 43-128, URL-safe.
        let verifier = randomURLSafeString(length: 64)
        let challenge = base64URLEncode(SHA256.hash(data: Data(verifier.utf8)))
        return PKCEPair(codeVerifier: verifier, codeChallenge: challenge)
    }

    static func randomURLSafeString(length: Int) -> String {
        // Base64URL characters + unreserved RFC3986.
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = String()
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset[Int.random(in: 0..<charset.count)])
        }
        return result
    }

    static func base64URLEncode(_ digest: SHA256.Digest) -> String {
        let data = Data(digest)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
