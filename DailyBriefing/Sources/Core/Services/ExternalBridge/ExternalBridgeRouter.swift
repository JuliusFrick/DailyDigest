import Foundation

@MainActor
final class ExternalBridgeRouter {
    private let auth: ExternalBridgeAuth
    private let briefingCacheService: BriefingCacheService
    private let actionItemStore: ActionItemStore
    private let connectionManager: ServiceConnectionManager
    private let encoder = JSONEncoder()

    init(
        auth: ExternalBridgeAuth,
        briefingCacheService: BriefingCacheService,
        actionItemStore: ActionItemStore,
        connectionManager: ServiceConnectionManager
    ) {
        self.auth = auth
        self.briefingCacheService = briefingCacheService
        self.actionItemStore = actionItemStore
        self.connectionManager = connectionManager
        self.encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func route(
        _ request: ExternalBridgeRequest,
        configuration: ExternalBridgeConfiguration
    ) async -> ExternalBridgeResponse {
        guard request.method == "GET" else {
            return methodNotAllowedResponse()
        }

        if !isHostAllowed(request.remoteAddress, allowlist: configuration.allowedClients) {
            return forbiddenResponse("Client-IP nicht erlaubt.")
        }

        guard auth.isAuthorized(
            headers: request.headers,
            expectedToken: auth.currentSecret()
        ) else {
            return unauthorizedResponse("Ungültiges oder fehlendes Token.")
        }
        
        switch normalizedPath(request.path) {
        case "/health":
            return healthResponse(port: configuration.port)
        case "/briefings/latest":
            return latestBriefingResponse()
        case "/action-items/open":
            return openActionItemsResponse()
        case "/services/connected":
            return connectedServicesResponse()
        case "/context/overview":
            return contextOverviewResponse()
        default:
            return notFoundResponse()
        }
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") && path.count > 1
            ? String(path.dropLast())
            : path
    }

    private func isHostAllowed(_ host: String?, allowlist: [String]) -> Bool {
        guard !allowlist.isEmpty else { return true }
        guard let host else { return false }
        let normalizedHost = host.lowercased()
        
        if allowlist.contains("*") {
            return true
        }

        return allowlist.contains { allowed in
            let normalizedAllowed = allowed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedAllowed.isEmpty else { return false }
            return normalizedHost == normalizedAllowed
        }
    }

    private func healthResponse(port: UInt16) -> ExternalBridgeResponse {
        let payload = ExternalBridgeHealthResponse(
            service: "dailybriefing-bridge",
            status: "ok",
            enabled: true,
            port: port,
            timestamp: Date().formatted()
        )
        return jsonResponse(payload)
    }

    private func latestBriefingResponse() -> ExternalBridgeResponse {
        guard let briefing = briefingCacheService.loadLatest() else {
            return notFoundResponse("No briefing available")
        }
        let payload = ExternalBridgeBriefingResponse(hasBriefing: true, briefing: briefing)
        return jsonResponse(payload)
    }

    private func openActionItemsResponse() -> ExternalBridgeResponse {
        let items = actionItemStore.openItems()
        let payload = ExternalBridgeActionItemResponse(
            count: items.count,
            items: items
        )
        return jsonResponse(payload)
    }

    private func connectedServicesResponse() -> ExternalBridgeResponse {
        let connected = connectedServicesSnapshot()

        let payload = ExternalBridgeConnectedServicesResponse(
            services: connected,
            connectedCount: connected.filter(\.isConnected).count,
            totalCount: connected.count
        )

        return jsonResponse(payload)
    }

    private func contextOverviewResponse() -> ExternalBridgeResponse {
        let briefing = briefingCacheService.loadLatest()
        let openItems = actionItemStore.openItems()
        let connectedServices = connectedServicesSnapshot()

        let payload = ExternalBridgeContextOverviewResponse(
            timestamp: Date(),
            hasBriefing: briefing != nil,
            briefing: briefing,
            openActionItemsCount: openItems.count,
            openActionItems: openItems,
            connectedServicesCount: connectedServices.filter(\.isConnected).count,
            connectedServices: connectedServices
        )

        return jsonResponse(payload)
    }

    private func connectedServicesSnapshot() -> [ExternalBridgeConnectedServiceInfo] {
        var connected: [ExternalBridgeConnectedServiceInfo] = []

        for serviceType in ServiceType.allCases {
            let status = connectionManager.connectionStatus(for: serviceType)
            let isConnected = status == .connected
            let connection = connectionManager.connections[serviceType.rawValue]

            connected.append(
                ExternalBridgeConnectedServiceInfo(
                    serviceId: serviceType.rawValue,
                    serviceName: serviceType.displayName,
                    isConnected: isConnected,
                    status: status.rawValue,
                    lastSyncAt: connection?.lastSyncAt
                )
            )
        }

        return connected
    }

    private func jsonResponse<T: Encodable>(_ payload: T) -> ExternalBridgeResponse {
        do {
            let data = try encoder.encode(payload)
            return ExternalBridgeResponse.json(data: data)
        } catch {
            return ExternalBridgeResponse.json(
                data: Data("{\"error\":\"serialization_failed\"}".utf8),
                statusCode: 500
            )
        }
    }

    private func methodNotAllowedResponse() -> ExternalBridgeResponse {
        ExternalBridgeResponse.plainText("Method not allowed", statusCode: 405)
    }

    private func notFoundResponse(_ message: String = "Endpoint nicht gefunden") -> ExternalBridgeResponse {
        ExternalBridgeResponse.plainText(message, statusCode: 404)
    }

    private func forbiddenResponse(_ message: String) -> ExternalBridgeResponse {
        ExternalBridgeResponse.plainText(message, statusCode: 403)
    }

    private func unauthorizedResponse(_ message: String) -> ExternalBridgeResponse {
        ExternalBridgeResponse.plainText(message, statusCode: 401)
    }
}
