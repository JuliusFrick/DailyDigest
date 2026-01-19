import Foundation

@MainActor
final class OAuthCallbackRouter: ObservableObject {
    static let shared = OAuthCallbackRouter()

    private var continuations: [String: CheckedContinuation<URL, Error>] = [:]

    private init() {}

    func waitForCallback(state: String) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                Task { @MainActor in
                    continuations[state] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                OAuthCallbackRouter.shared.cancel(state: state, error: CancellationError())
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let state = url.queryValue(for: "state") else { return }
        guard let continuation = continuations.removeValue(forKey: state) else { return }
        continuation.resume(returning: url)
    }

    private func cancel(state: String, error: Error) {
        guard let continuation = continuations.removeValue(forKey: state) else { return }
        continuation.resume(throwing: error)
    }
}

private extension URL {
    func queryValue(for name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}