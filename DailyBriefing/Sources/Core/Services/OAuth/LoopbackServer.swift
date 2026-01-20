import Foundation
import Network

/// A minimal HTTP server that listens on a loopback port for OAuth callbacks.
/// Used for Google OAuth which requires loopback redirects instead of custom URL schemes.
@MainActor
final class LoopbackServer {
    
    enum LoopbackError: LocalizedError {
        case serverStartFailed
        case timeout
        case cancelled
        case invalidRequest
        
        var errorDescription: String? {
            switch self {
            case .serverStartFailed: return "Lokaler Server konnte nicht gestartet werden"
            case .timeout: return "Zeitüberschreitung beim Warten auf Login"
            case .cancelled: return "Login abgebrochen"
            case .invalidRequest: return "Ungültige OAuth-Antwort"
            }
        }
    }
    
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private let expectedPath: String
    private let timeoutSeconds: TimeInterval
    private var timeoutTask: Task<Void, Never>?
    
    /// The port the server is listening on (available after `start()`)
    private(set) var port: UInt16 = 0
    
    /// Creates a loopback server expecting callbacks at the given path.
    /// - Parameters:
    ///   - path: The expected path (e.g., "/oauth/google")
    ///   - timeoutSeconds: How long to wait for the callback (default: 5 minutes)
    init(expectedPath: String, timeoutSeconds: TimeInterval = 300) {
        self.expectedPath = expectedPath
        self.timeoutSeconds = timeoutSeconds
    }
    
    /// Starts the server on a random available port.
    /// - Returns: The port the server is listening on
    func start() async throws -> UInt16 {
        // Start the listener
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        
        // Get the actual port once the listener is ready
        let port = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        cont.resume(returning: port)
                    } else {
                        cont.resume(throwing: LoopbackError.serverStartFailed)
                    }
                case .failed(let error):
                    cont.resume(throwing: error)
                case .cancelled:
                    cont.resume(throwing: LoopbackError.cancelled)
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { connection in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.handleConnection(connection)
                }
            }
            
            listener.start(queue: .main)
        }
        
        self.port = port
        return port
    }
    
    /// Waits for the OAuth callback.
    /// - Returns: The full callback URL including query parameters
    func waitForCallback() async throws -> URL {
        // Wait for the callback with timeout
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                self.continuation = cont
                
                // Set up timeout
                self.timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
                    if !Task.isCancelled {
                        self.cancel(with: LoopbackError.timeout)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(with: LoopbackError.cancelled)
            }
        }
    }
    
    /// Stops the server and cancels any pending callback.
    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        continuation = nil
    }
    
    private func cancel(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.receiveData(from: connection)
                case .failed, .cancelled:
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }
    
    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self, let data = data, error == nil else {
                    connection.cancel()
                    return
                }
                
                // Parse HTTP request
                guard let requestString = String(data: data, encoding: .utf8),
                      let callbackURL = self.parseHTTPRequest(requestString) else {
                    self.sendResponse(to: connection, success: false)
                    return
                }
                
                // Send success response
                self.sendResponse(to: connection, success: true)
                
                // Resume continuation with the callback URL
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.listener?.cancel()
                self.listener = nil
                self.continuation?.resume(returning: callbackURL)
                self.continuation = nil
            }
        }
    }
    
    private func parseHTTPRequest(_ request: String) -> URL? {
        // Parse first line: "GET /oauth/google?code=xxx&state=yyy HTTP/1.1"
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        
        let path = parts[1]
        
        // Verify the path starts with expected path
        guard path.hasPrefix(expectedPath) else { return nil }
        
        // Construct full URL
        return URL(string: "http://127.0.0.1:\(port)\(path)")
    }
    
    private func sendResponse(to connection: NWConnection, success: Bool) {
        let html: String
        if success {
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>Anmeldung erfolgreich</title>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        color: white;
                    }
                    .container {
                        text-align: center;
                        padding: 40px;
                        background: rgba(255,255,255,0.1);
                        border-radius: 20px;
                        backdrop-filter: blur(10px);
                    }
                    h1 { margin-bottom: 10px; }
                    p { opacity: 0.9; }
                    .checkmark {
                        font-size: 64px;
                        margin-bottom: 20px;
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="checkmark">✓</div>
                    <h1>Anmeldung erfolgreich!</h1>
                    <p>Du kannst dieses Fenster jetzt schließen und zur App zurückkehren.</p>
                </div>
                <script>
                    // Try to close the window after a short delay
                    setTimeout(function() { window.close(); }, 2000);
                </script>
            </body>
            </html>
            """
        } else {
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>Fehler</title>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        background: #f44336;
                        color: white;
                    }
                    .container { text-align: center; padding: 40px; }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>Fehler bei der Anmeldung</h1>
                    <p>Bitte versuche es erneut.</p>
                </div>
            </body>
            </html>
            """
        }
        
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
