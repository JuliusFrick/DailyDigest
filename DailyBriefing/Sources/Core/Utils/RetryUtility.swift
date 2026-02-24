import Foundation

/// Utility for retrying operations with exponential backoff
actor RetryUtility {
    
    static let shared = RetryUtility()
    
    private init() {}
    
    /// Retry an async operation with exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts
    ///   - initialDelay: Initial delay in seconds
    ///   - maxDelay: Maximum delay cap
    ///   - backoffMultiplier: Multiplier for exponential backoff
    ///   - operation: The async operation to retry
    /// - Returns: The result of the operation
    /// - Throws: The last error if all attempts fail
    func retry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        backoffMultiplier: Double = 2.0,
        retryOn errorTypes: [Any.Type]? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        
        var lastError: Error?
        var currentDelay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as RetryableError {
                // Always retry RetryableError
                lastError = error
            } catch let error {
                // Check if error type should be retried
                if let retryTypes = errorTypes {
                    let shouldRetry = retryTypes.contains { type(of: error) == $0 }
                    if !shouldRetry {
                        throw error
                    }
                }
                lastError = error
            }
            
            // Don't retry on the last attempt
            if attempt < maxAttempts {
                // Wait with exponential backoff
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                
                // Calculate next delay with jitter (10%)
                let jitter = Double.random(in: 0.9...1.1)
                currentDelay = min(currentDelay * backoffMultiplier * jitter, maxDelay)
            }
        }
        
        throw RetryError.exhausted(maxAttempts: maxAttempts, lastError: lastError)
    }
    
    /// Retry an async operation using a RetryPolicy
    func retry<T>(with policy: RetryPolicy, operation: () async throws -> T) async throws -> T {
        try await retry(
            maxAttempts: policy.maxAttempts,
            initialDelay: policy.initialDelay,
            maxDelay: policy.maxDelay,
            backoffMultiplier: policy.backoffMultiplier,
            retryOn: policy.retryOn.isEmpty ? nil : policy.retryOn,
            operation: operation
        )
    }
    
    /// Retry a synchronous operation with exponential backoff
    func retrySync<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        backoffMultiplier: Double = 2.0,
        operation: () throws -> T
    ) throws -> T {
        
        var lastError: Error?
        var currentDelay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try operation()
            } catch {
                lastError = error
                
                if attempt < maxAttempts {
                    // Calculate next delay with jitter
                    let jitter = Double.random(in: 0.9...1.1)
                    let sleepTime = currentDelay * jitter
                    
                    // Use Thread.sleep for sync operations
                    Thread.sleep(forTimeInterval: sleepTime)
                    currentDelay = min(currentDelay * backoffMultiplier, maxDelay)
                }
            }
        }
        
        throw RetryError.exhausted(maxAttempts: maxAttempts, lastError: lastError)
    }
}

// MARK: - Error Types

/// Errors that should trigger a retry
enum RetryableError: Error, LocalizedError {
    case networkUnavailable
    case serverError(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is unavailable"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited. Please wait before retrying"
        case .timeout:
            return "Request timed out"
        case .serviceUnavailable:
            return "Service is temporarily unavailable"
        }
    }
}

/// Error thrown when all retry attempts are exhausted
enum RetryError: Error, LocalizedError {
    case exhausted(maxAttempts: Int, lastError: Error?)
    
    var errorDescription: String? {
        switch self {
        case .exhausted(let maxAttempts, let lastError):
            var message = "Failed after \(maxAttempts) attempts"
            if let error = lastError {
                message += ": \(error.localizedDescription)"
            }
            return message
        }
    }
}

// MARK: - Retry Policy

/// Configuration for retry behavior
struct RetryPolicy {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    let retryOn: [Any.Type]
    
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 10.0,
        backoffMultiplier: 2.0,
        retryOn: [RetryableError.self]
    )
    
    static let aggressive = RetryPolicy(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 30.0,
        backoffMultiplier: 2.0,
        retryOn: [RetryableError.self]
    )
    
    static let conservative = RetryPolicy(
        maxAttempts: 2,
        initialDelay: 2.0,
        maxDelay: 20.0,
        backoffMultiplier: 1.5,
        retryOn: [RetryableError.self]
    )
}

// MARK: - Convenience Extensions

extension RetryUtility {
    /// Fetch data from a URL with automatic retry
    func fetchData(
        from url: URL,
        policy: RetryPolicy = .default
    ) async throws -> Data {
        return try await retry(with: policy) {
            let (fetchedData, fetchedResponse) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = fetchedResponse as? HTTPURLResponse else {
                return fetchedData
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return fetchedData
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw RetryableError.rateLimited(retryAfter: retryAfter)
            case 500...599:
                throw RetryableError.serverError(statusCode: httpResponse.statusCode)
            case 503:
                throw RetryableError.serviceUnavailable
            default:
                throw RetryableError.serverError(statusCode: httpResponse.statusCode)
            }
        }
    }
    
    /// Perform a URLRequest with automatic retry
    func performRequest(
        _ request: URLRequest,
        policy: RetryPolicy = .default
    ) async throws -> (Data, URLResponse) {
        return try await retry(with: policy) {
            try await URLSession.shared.data(for: request)
        }
    }
}
