import Foundation

public enum AIError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingAPIKey(provider: String, environmentVariables: [String])
    case unsupportedModel(provider: String, capability: ModelCapability, modelID: String)
    case invalidArgument(argument: String, message: String)
    case invalidResponse(provider: String, message: String)
    case httpStatus(provider: String, statusCode: Int, body: String)
    case httpStatusWithHeaders(provider: String, statusCode: Int, body: String, headers: [String: String])
    case gateway(GatewayError)
    case invalidURL(String)
    case timeout(durationNanoseconds: UInt64)

    public var description: String {
        switch self {
        case let .missingAPIKey(provider, variables):
            return "\(provider) API key is missing. Pass it in ProviderSettings or set one of: \(variables.joined(separator: ", "))."
        case let .unsupportedModel(provider, capability, modelID):
            return "\(provider) does not provide \(capability.rawValue) model '\(modelID)'."
        case let .invalidArgument(argument, message):
            return "Invalid \(argument): \(message)"
        case let .invalidResponse(provider, message):
            return "\(provider) returned an invalid response: \(message)"
        case let .httpStatus(provider, statusCode, body):
            return "\(provider) request failed with HTTP \(statusCode): \(body)"
        case let .httpStatusWithHeaders(provider, statusCode, body, _):
            return "\(provider) request failed with HTTP \(statusCode): \(body)"
        case let .gateway(error):
            return error.description
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case let .timeout(durationNanoseconds):
            return "AI call timed out after \(durationNanoseconds) nanoseconds."
        }
    }
}

public enum AIRetryErrorReason: String, Sendable {
    case maxRetriesExceeded
    case errorNotRetryable
    case cancelled
}

public struct AIRetryError: Error, CustomStringConvertible, Sendable {
    public var reason: AIRetryErrorReason
    public var attempts: Int
    public var errors: [String]

    public init(reason: AIRetryErrorReason, attempts: Int, errors: [String]) {
        self.reason = reason
        self.attempts = attempts
        self.errors = errors
    }

    public var description: String {
        let lastError = errors.last ?? "unknown error"
        switch reason {
        case .maxRetriesExceeded:
            return "Failed after \(attempts) attempt(s). Last error: \(lastError)"
        case .errorNotRetryable:
            return "Failed with non-retryable error after \(attempts) attempt(s): \(lastError)"
        case .cancelled:
            return "Retry operation was cancelled after \(attempts) attempt(s)."
        }
    }
}

public struct AIRetryPolicy: Equatable, Sendable {
    public var maxRetries: Int
    public var initialDelayNanoseconds: UInt64
    public var backoffFactor: Double
    public var maxDelayNanoseconds: UInt64
    public var timeoutNanoseconds: UInt64?

    public init(
        maxRetries: Int = 2,
        initialDelayNanoseconds: UInt64 = 2_000_000_000,
        backoffFactor: Double = 2,
        maxDelayNanoseconds: UInt64 = 60_000_000_000,
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.maxRetries = maxRetries
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.backoffFactor = backoffFactor
        self.maxDelayNanoseconds = maxDelayNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public static let `default` = AIRetryPolicy()
    public static let none = AIRetryPolicy(maxRetries: 0, initialDelayNanoseconds: 0)
}

