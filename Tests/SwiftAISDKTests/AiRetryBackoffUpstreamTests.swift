import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiRetryBackoffUsesRetryAfterMsHeaderWhenPresentAndReasonableLikeUpstream() {
    let error = apiRetryError(headers: ["retry-after-ms": "3000"])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == milliseconds(3000))
}

@Test func aiRetryBackoffParsesRetryAfterHeaderInSecondsLikeUpstream() {
    let error = apiRetryError(headers: ["retry-after": "5"])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(5))
}

@Test func aiRetryBackoffUsesExponentialBackoffWhenRateLimitDelayIsTooLongLikeUpstream() {
    let error = apiRetryError(headers: ["retry-after-ms": "70000"])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(2))
}

@Test func aiRetryBackoffFallsBackToExponentialBackoffWhenNoRateLimitHeadersLikeUpstream() {
    let error = apiRetryError(headers: [:])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(2))
}

@Test func aiRetryBackoffHandlesInvalidRateLimitHeaderValuesLikeUpstream() {
    let error = apiRetryError(headers: [
        "retry-after-ms": "invalid",
        "retry-after": "not-a-number"
    ])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(2))
}

@Test func aiRetryBackoffHandlesAnthropicRetryAfterMsShapeLikeUpstream() {
    let error = AIError.apiCall(AIAPICallError(
        provider: "anthropic",
        url: "https://api.anthropic.com/v1/messages",
        statusCode: 429,
        responseHeaders: [
            "retry-after-ms": "5000",
            "x-request-id": "req_123456"
        ],
        responseBody: #"{"error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}"#,
        isRetryable: true
    ))

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(5))
}

@Test func aiRetryBackoffHandlesOpenAIRetryAfterShapeLikeUpstream() {
    let error = AIError.apiCall(AIAPICallError(
        provider: "openai",
        url: "https://api.openai.com/v1/chat/completions",
        statusCode: 429,
        responseHeaders: [
            "retry-after": "30",
            "x-request-id": "req_abcdef123456"
        ],
        responseBody: #"{"error":{"message":"Rate limit reached for requests","type":"requests","code":"rate_limit_exceeded"}}"#,
        isRetryable: true
    ))

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(30))
}

@Test func aiRetryBackoffProgressionKeepsRespectingReasonableRetryHeadersLikeUpstream() {
    let firstError = apiRetryError(headers: ["retry-after-ms": "5000"])
    let secondError = apiRetryError(headers: ["retry-after-ms": "2000"])

    let firstDelay = retryDelayNanoseconds(from: firstError, exponentialBackoffDelay: seconds(2))
    let secondDelay = retryDelayNanoseconds(from: secondError, exponentialBackoffDelay: seconds(4))

    #expect(firstDelay == seconds(5))
    #expect(secondDelay == seconds(2))
}

@Test func aiRetryBackoffPrefersRetryAfterMsOverRetryAfterWhenBothPresentLikeUpstream() {
    let error = apiRetryError(headers: [
        "retry-after-ms": "3000",
        "retry-after": "10"
    ])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(3))
}

@Test func aiRetryBackoffHandlesRetryAfterHeaderWithHTTPDateFormatLikeUpstream() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let future = now.addingTimeInterval(5)
    let error = apiRetryError(headers: ["retry-after": httpDateString(future)])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2), now: now)

    #expect(delay == seconds(5))
}

@Test func aiRetryBackoffFallsBackToExponentialBackoffWhenRateLimitDelayIsNegativeLikeUpstream() {
    let error = apiRetryError(headers: ["retry-after-ms": "-1000"])

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(2))
}

@Test func aiRetryBackoffRetriesGatewayInternalServerErrorLikeUpstream() async throws {
    let attempts = RetryAttemptCounter()

    let result = try await withRetry(
        policy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: milliseconds(1))
    ) {
        if attempts.increment() == 1 {
            throw AIError.gateway(GatewayError(
                type: .internalServerError,
                message: "Internal server error",
                statusCode: 503
            ))
        }
        return "success"
    }

    #expect(result == "success")
    #expect(attempts.value == 2)
}

@Test func aiRetryBackoffRetriesGatewayRateLimitErrorLikeUpstream() async throws {
    let attempts = RetryAttemptCounter()

    let result = try await withRetry(
        policy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: milliseconds(1))
    ) {
        if attempts.increment() == 1 {
            throw AIError.gateway(GatewayError(
                type: .rateLimitExceeded,
                message: "Rate limit exceeded",
                statusCode: 429
            ))
        }
        return "success"
    }

    #expect(result == "success")
    #expect(attempts.value == 2)
}

@Test func aiRetryBackoffDoesNotRetryNonRetryableGatewayAuthenticationErrorLikeUpstream() async throws {
    let attempts = RetryAttemptCounter()

    do {
        _ = try await withRetry(
            policy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: milliseconds(1))
        ) {
            attempts.increment()
            throw AIError.gateway(GatewayError(
                type: .authenticationError,
                message: "Invalid API key",
                statusCode: 401,
                isRetryable: false
            ))
        } as String
        Issue.record("Expected authentication error.")
    } catch {
        #expect(String(describing: error).contains("Invalid API key"))
    }

    #expect(attempts.value == 1)
}

@Test func aiRetryBackoffUsesRetryAfterHeadersFromGatewayErrorLikeUpstream() {
    let error = AIError.gateway(GatewayError(
        type: .internalServerError,
        message: "Internal server error",
        statusCode: 503,
        headers: ["retry-after-ms": "3000"]
    ))

    let delay = retryDelayNanoseconds(from: error, exponentialBackoffDelay: seconds(2))

    #expect(delay == seconds(3))
}

private func apiRetryError(headers: [String: String]) -> AIError {
    AIError.apiCall(AIAPICallError(
        provider: "test",
        url: "https://api.example.com",
        statusCode: 429,
        responseHeaders: headers,
        responseBody: "Rate limited",
        isRetryable: true
    ))
}

private func milliseconds(_ value: UInt64) -> UInt64 {
    value * 1_000_000
}

private func seconds(_ value: UInt64) -> UInt64 {
    value * 1_000_000_000
}

private func httpDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
    return formatter.string(from: date)
}

private final class RetryAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        count += 1
        let count = count
        lock.unlock()
        return count
    }
}
