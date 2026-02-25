import Foundation

struct ExternalBridgeConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var port: UInt16
    var allowedClients: [String]

    static let fallbackPort: UInt16 = 18888

    static let defaults = ExternalBridgeConfiguration(
        isEnabled: false,
        port: fallbackPort,
        allowedClients: []
    )
}

struct ExternalBridgeRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let query: [String: String]
    let remoteAddress: String?
}

struct ExternalBridgeResponse {
    let statusCode: Int
    let reasonPhrase: String
    let body: Data
    let contentType: String
    let extraHeaders: [String: String]

    static func json(data: Data, statusCode: Int = 200) -> ExternalBridgeResponse {
        return ExternalBridgeResponse(
            statusCode: statusCode,
            reasonPhrase: statusText(for: statusCode),
            body: data,
            contentType: "application/json; charset=utf-8",
            extraHeaders: [:]
        )
    }

    static func plainText(_ text: String, statusCode: Int = 200) -> ExternalBridgeResponse {
        return ExternalBridgeResponse(
            statusCode: statusCode,
            reasonPhrase: statusText(for: statusCode),
            body: Data(text.utf8),
            contentType: "text/plain; charset=utf-8",
            extraHeaders: [:]
        )
    }

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Error"
        }
    }
}

struct ExternalBridgeHealthResponse: Codable {
    let service: String
    let status: String
    let enabled: Bool
    let port: UInt16
    let timestamp: String
}

struct ExternalBridgeBriefingResponse: Codable {
    let hasBriefing: Bool
    let briefing: Briefing?
}

struct ExternalBridgeActionItemResponse: Codable {
    let count: Int
    let items: [ActionItem]
}

struct ExternalBridgeConnectedServiceInfo: Codable {
    let serviceId: String
    let serviceName: String
    let isConnected: Bool
    let status: String
    let lastSyncAt: Date?
}

struct ExternalBridgeConnectedServicesResponse: Codable {
    let services: [ExternalBridgeConnectedServiceInfo]
    let connectedCount: Int
    let totalCount: Int
}

struct ExternalBridgeContextOverviewResponse: Codable {
    let timestamp: Date
    let hasBriefing: Bool
    let briefing: Briefing?
    let openActionItemsCount: Int
    let openActionItems: [ActionItem]
    let connectedServicesCount: Int
    let connectedServices: [ExternalBridgeConnectedServiceInfo]
}
