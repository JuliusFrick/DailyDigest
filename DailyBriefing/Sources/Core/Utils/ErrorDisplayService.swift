import SwiftUI
import Combine

/// Service for managing and displaying errors to users
@MainActor
final class ErrorDisplayService: ObservableObject {
    static let shared = ErrorDisplayService()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentError: DisplayableError?
    @Published private(set) var errorQueue: [DisplayableError] = []
    @Published var showErrorBanner: Bool = false
    
    // MARK: - Private Properties
    
    private var dismissTask: Task<Void, Never>?
    private let maxQueueSize = 5
    
    private init() {}
    
    // MARK: - Public API
    
    /// Show an error with automatic dismissal
    func showError(_ error: Error, title: String? = nil, retryAction: (() -> Void)? = nil) {
        let displayableError = DisplayableError(
            id: UUID(),
            title: title ?? extractTitle(from: error),
            message: error.localizedDescription,
            severity: severity(for: error),
            retryAction: retryAction,
            timestamp: Date()
        )
        
        presentError(displayableError)
    }
    
    /// Show a custom error
    func showError(
        title: String,
        message: String,
        severity: ErrorSeverity = .error,
        retryAction: (() -> Void)? = nil
    ) {
        let displayableError = DisplayableError(
            id: UUID(),
            title: title,
            message: message,
            severity: severity,
            retryAction: retryAction,
            timestamp: Date()
        )
        
        presentError(displayableError)
    }
    
    /// Dismiss the current error
    func dismissCurrent() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentError = nil
            showErrorBanner = false
        }
    }
    
    /// Dismiss after a delay
    func dismissAfter(seconds: TimeInterval = 5) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                dismissCurrent()
            }
        }
    }
    
    /// Clear the error queue
    func clearQueue() {
        errorQueue.removeAll()
    }
    
    /// Retry the current error action
    func retryCurrent() {
        if let error = currentError, let action = error.retryAction {
            dismissCurrent()
            action()
        }
    }
    
    // MARK: - Private Methods
    
    private func presentError(_ error: DisplayableError) {
        // If there's already an error, queue this one
        if currentError != nil {
            guard errorQueue.count < maxQueueSize else {
                return // Queue full, drop error
            }
            errorQueue.append(error)
            return
        }
        
        withAnimation(.easeIn(duration: 0.2)) {
            currentError = error
            showErrorBanner = true
        }
        
        // Auto-dismiss after timeout for non-critical errors
        if error.severity != .critical {
            dismissAfter(seconds: 8)
        }
    }
    
    private func extractTitle(from error: Error) -> String {
        if let displayable = error as? LocalizedError {
            return displayable.errorDescription ?? "Unknown Error"
        }
        return "Error"
    }
    
    private func severity(for error: Error) -> ErrorSeverity {
        if let retryable = error as? RetryableError {
            switch retryable {
            case .networkUnavailable:
                return .warning
            case .serverError:
                return .error
            case .rateLimited:
                return .info
            case .timeout:
                return .warning
            case .serviceUnavailable:
                return .error
            }
        }
        
        if error is URLError {
            switch (error as? URLError)?.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .warning
            case .timedOut:
                return .warning
            default:
                return .error
            }
        }
        
        return .error
    }
}

// MARK: - Supporting Types

/// An error that can be displayed to the user
struct DisplayableError: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let severity: ErrorSeverity
    let retryAction: (() -> Void)?
    let timestamp: Date
    
    static func == (lhs: DisplayableError, rhs: DisplayableError) -> Bool {
        lhs.id == rhs.id
    }
}

/// Severity levels for errors
enum ErrorSeverity: Comparable {
    case info
    case warning
    case error
    case critical
    
    var sortOrder: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        case .critical: return 3
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "bolt.horizontal.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }
}

// MARK: - SwiftUI Views

extension ErrorDisplayService {
    /// A view that displays the current error banner
    var errorBannerView: some View {
        VStack {
            if let error = currentError {
                ErrorBannerView(error: error) {
                    self.dismissCurrent()
                } onRetry: {
                    self.retryCurrent()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
        .animation(.easeIn(duration: 0.2), value: currentError != nil)
        .allowsHitTesting(currentError != nil)
    }
}

/// A banner view for displaying errors
struct ErrorBannerView: View {
    let error: DisplayableError
    let onDismiss: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: error.severity.icon)
                .font(.system(size: 20))
                .foregroundColor(error.severity.color)
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(error.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if error.retryAction != nil {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(error.severity.color)
                }
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.tertiary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - View Modifier

/// View modifier for displaying errors
struct ErrorBannerModifier: ViewModifier {
    @ObservedObject var errorService = ErrorDisplayService.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if errorService.showErrorBanner {
                    errorService.errorBannerView
                        .padding(.top, 40)
                }
            }
    }
}

extension View {
    func errorBanner() -> some View {
        modifier(ErrorBannerModifier())
    }
}
