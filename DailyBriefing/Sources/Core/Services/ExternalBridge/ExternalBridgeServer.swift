import Foundation
import Network

/// Lightweight HTTP server based on Network.framework for the local OpenClaw bridge.
@MainActor
final class ExternalBridgeServer {
    enum ErrorType: Error, LocalizedError {
        case invalidRequest
        case failedToStart

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Ungültige HTTP-Anfrage empfangen."
            case .failedToStart:
                return "Externer Bridge-Server konnte nicht gestartet werden."
            }
        }
    }

    typealias RequestHandler = (ExternalBridgeRequest) async -> ExternalBridgeResponse

    private let requestHandler: RequestHandler
    private var listener: NWListener?

    init(requestHandler: @escaping RequestHandler) {
        self.requestHandler = requestHandler
    }

    /// Starts the server on requested port, returns the actual bound port.
    func start(port: UInt16) async throws -> UInt16 {
        stop()

        let listener: NWListener
        if port == 0 {
            listener = try NWListener(using: .tcp, on: .any)
        } else {
            guard let listenPort = NWEndpoint.Port(rawValue: port) else {
                throw ErrorType.failedToStart
            }
            listener = try NWListener(using: .tcp, on: listenPort)
        }

        self.listener = listener
        
        let assignedPort = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let boundPort = listener.port?.rawValue {
                        continuation.resume(returning: boundPort)
                    } else {
                        continuation.resume(throwing: ErrorType.failedToStart)
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: ErrorType.failedToStart)
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.handleConnection(connection)
                }
            }
            
            listener.start(queue: .main)
        }

        return assignedPort
    }

    /// Stops accepting new connections and closes the active listener.
    func stop() {
        listener?.cancel()
        listener = nil
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                let response = ExternalBridgeResponse.plainText("Bad Request", statusCode: 400)
                Task { @MainActor [weak self] in
                    self?.send(response, to: connection)
                }
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let request = self.parseRequest(from: requestString, endpoint: connection.endpoint) else {
                    let response = ExternalBridgeResponse.plainText("Bad Request", statusCode: 400)
                    self.send(response, to: connection)
                    return
                }

                let response = await self.requestHandler(request)
                self.send(response, to: connection)
            }
        }
    }

    private func parseRequest(from request: String, endpoint: NWEndpoint) -> ExternalBridgeRequest? {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        
        let requestParts = firstLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        
        let method = String(requestParts[0]).uppercased()
        let rawPath = String(requestParts[1])
        guard rawPath.hasPrefix("/") else { return nil }
        guard let url = URL(string: "http://127.0.0.1\(rawPath)") else { return nil }
        
        let path = url.path
        let query = parseQuery(from: url.query)
        var headers: [String: String] = [:]
        
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let remoteAddress = remoteAddress(from: endpoint)
        
        return ExternalBridgeRequest(
            method: method,
            path: path,
            headers: headers,
            query: query,
            remoteAddress: remoteAddress
        )
    }

    private func parseQuery(from rawQuery: String?) -> [String: String] {
        guard let rawQuery else { return [:] }
        guard let components = URLComponents(string: "http://127.0.0.1?\(rawQuery)") else { return [:] }
        var result: [String: String] = [:]
        components.queryItems?.forEach { item in
            if let value = item.value {
                result[item.name] = value
            }
        }
        return result
    }

    private func remoteAddress(from endpoint: NWEndpoint) -> String? {
        if case let .hostPort(host, _) = endpoint {
            return host.debugDescription.lowercased()
        }
        return nil
    }

    private func send(_ response: ExternalBridgeResponse, to connection: NWConnection) {
        var headerLines = [
            "Content-Type: \(response.contentType)",
            "Content-Length: \(response.body.count)",
            "Connection: close"
        ]

        for (headerName, value) in response.extraHeaders {
            headerLines.append("\(headerName): \(value)")
        }

        let responseString =
            "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)\r\n" +
            headerLines.joined(separator: "\r\n") +
            "\r\n\r\n"

        var payload = Data(responseString.utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

