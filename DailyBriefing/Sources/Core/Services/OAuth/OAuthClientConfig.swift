import Foundation

struct OAuthClientConfig: Decodable {
    struct Provider: Decodable {
        let clientId: String
        let clientSecret: String?
    }

    let google: Provider?
    let slack: Provider?
    let jira: Provider?
}

enum OAuthClientConfigStore {
    static let shared: OAuthClientConfig? = load()

    private static func load() -> OAuthClientConfig? {
        if let inlineJSON = ProcessInfo.processInfo.environment["OAUTH_CLIENTS_JSON"],
           !inlineJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = inlineJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OAuthClientConfig.self, from: data) {
            return decoded
        }

        if let jsonPath = ProcessInfo.processInfo.environment["OAUTH_CLIENTS_JSON_PATH"],
           !jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: jsonPath)
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(OAuthClientConfig.self, from: data) {
                return decoded
            }
        }

        let bundles: [Bundle] = [Bundle.main, Bundle.module]
        for bundle in bundles {
            if let url = bundle.url(forResource: "oauth_clients", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(OAuthClientConfig.self, from: data) {
                return decoded
            }
        }

        return nil
    }

    static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
