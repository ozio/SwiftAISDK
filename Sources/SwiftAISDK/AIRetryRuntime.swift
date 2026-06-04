import Foundation

func withRetry<Output: Sendable>(
    policy: AIRetryPolicy,
    abortSignal: AIAbortSignal? = nil,
    onRetry: @escaping @Sendable (AIRetryAttemptTelemetry) async -> Void = { _ in },
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    try validateRetryPolicy(policy)

    var errors: [String] = []
    var delay = policy.initialDelayNanoseconds

    while true {
        try Task.checkCancellation()
        try abortSignal?.throwIfAborted()
        do {
            return try await withTimeout(policy.timeoutNanoseconds, operation: operation)
        } catch is CancellationError {
            throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
        } catch let error as AIAbortError {
            throw error
        } catch {
            errors.append(String(describing: error))
            let attempts = errors.count
            guard policy.maxRetries > 0 else { throw error }
            guard isRetryable(error) else {
                if attempts == 1 { throw error }
                throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
            }
            guard attempts <= policy.maxRetries else {
                throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
            }
            let sleepDelay = retryAfterDelayNanoseconds(from: error) ?? delay
            await onRetry(AIRetryAttemptTelemetry(
                attempt: attempts,
                maxRetries: policy.maxRetries,
                errorDescription: String(describing: error),
                delayNanoseconds: sleepDelay
            ))
            if sleepDelay > 0 {
                try await sleep(nanoseconds: sleepDelay, abortSignal: abortSignal)
            }
            delay = nextDelay(current: delay, policy: policy)
        }
    }
}

func sleep(nanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws {
    try await sleepWithAbortSignal(nanoseconds: nanoseconds, abortSignal: abortSignal)
}

func validateRetryPolicy(_ policy: AIRetryPolicy) throws {
    guard policy.maxRetries >= 0 else {
        throw AIError.invalidArgument(argument: "maxRetries", message: "maxRetries must be >= 0.")
    }
    guard policy.backoffFactor >= 1 else {
        throw AIError.invalidArgument(argument: "backoffFactor", message: "backoffFactor must be >= 1.")
    }
    if let timeout = policy.timeoutNanoseconds {
        guard timeout > 0 else {
            throw AIError.invalidArgument(argument: "timeoutNanoseconds", message: "timeoutNanoseconds must be greater than zero.")
        }
    }
}

func withTimeout<Output: Sendable>(
    _ timeoutNanoseconds: UInt64?,
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    guard let timeoutNanoseconds else {
        return try await operation()
    }

    return try await withThrowingTaskGroup(of: Output.self) { group in
        defer { group.cancelAll() }

        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw AIError.timeout(durationNanoseconds: timeoutNanoseconds)
        }

        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}

func streamWithAbortSignal<Part: Sendable>(
    _ stream: AsyncThrowingStream<Part, Error>,
    abortSignal: AIAbortSignal?
) -> AsyncThrowingStream<Part, Error> {
    guard let abortSignal else { return stream }
    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try abortSignal.throwIfAborted()
                for try await part in stream {
                    try Task.checkCancellation()
                    try abortSignal.throwIfAborted()
                    continuation.yield(part)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let registration = abortSignal.addAbortHandler { _ in
            task.cancel()
        }
        continuation.onTermination = { _ in
            registration.cancel()
            task.cancel()
        }
    }
}

func streamWithTimeout<Part: Sendable>(
    _ stream: AsyncThrowingStream<Part, Error>,
    timeoutNanoseconds: UInt64?
) -> AsyncThrowingStream<Part, Error> {
    guard let timeoutNanoseconds else { return stream }
    guard timeoutNanoseconds > 0 else {
        return failingPartStream(AIError.invalidArgument(
            argument: "timeoutNanoseconds",
            message: "timeoutNanoseconds must be greater than zero."
        ))
    }

    return AsyncThrowingStream { continuation in
        let task = Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await part in stream {
                        try Task.checkCancellation()
                        continuation.yield(part)
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw AIError.timeout(durationNanoseconds: timeoutNanoseconds)
                }

                do {
                    _ = try await group.next()
                    group.cancelAll()
                    continuation.finish()
                } catch {
                    group.cancelAll()
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

func failingPartStream<Part: Sendable>(_ error: Error) -> AsyncThrowingStream<Part, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}

func isRetryable(_ error: Error) -> Bool {
    if let error = error as? AIError {
        if case let .httpStatus(_, statusCode, _) = error {
            return isRetryableHTTPStatus(statusCode)
        }
        if case let .httpStatusWithHeaders(_, statusCode, _, _) = error {
            return isRetryableHTTPStatus(statusCode)
        }
        if case let .gateway(gatewayError) = error {
            return gatewayError.isRetryable
        }
        return false
    }
    if let error = error as? AIAPICallError {
        return error.isRetryable
    }
    if let error = error as? URLError {
        switch error.code {
        case .cancelled, .userCancelledAuthentication:
            return false
        default:
            return true
        }
    }
    return false
}

func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
    statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
}

func retryAfterDelayNanoseconds(from error: Error) -> UInt64? {
    guard let headers = httpHeaders(from: error) else { return nil }
    guard let value = headerValue("retry-after", in: headers) else { return nil }
    return retryAfterDelayNanoseconds(from: value, now: Date())
}

func httpHeaders(from error: Error) -> [String: String]? {
    if let error = error as? AIError {
        if case let .httpStatusWithHeaders(_, _, _, headers) = error {
            return headers
        }
        if case let .gateway(gatewayError) = error {
            return gatewayError.headers
        }
    }
    if let error = error as? AIAPICallError {
        return error.responseHeaders
    }
    return nil
}

func headerValue(_ name: String, in headers: [String: String]) -> String? {
    if let value = headers[name] {
        return value
    }
    let lowercasedName = name.lowercased()
    return headers.first { key, _ in key.lowercased() == lowercasedName }?.value
}

func retryAfterDelayNanoseconds(from value: String, now: Date) -> UInt64? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let seconds = Double(trimmed) {
        return nanoseconds(fromSeconds: seconds)
    }
    guard let date = httpDate(from: trimmed) else { return nil }
    return nanoseconds(fromSeconds: date.timeIntervalSince(now))
}

func nanoseconds(fromSeconds seconds: Double) -> UInt64? {
    guard seconds.isFinite else { return nil }
    guard seconds > 0 else { return 0 }
    let nanoseconds = seconds * 1_000_000_000
    guard nanoseconds.isFinite else { return UInt64.max }
    if nanoseconds >= Double(UInt64.max) {
        return UInt64.max
    }
    return UInt64(nanoseconds.rounded(.up))
}

func httpDate(from value: String) -> Date? {
    let formats = [
        "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
        "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz",
        "EEE MMM d HH':'mm':'ss yyyy"
    ]
    for format in formats {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        if let date = formatter.date(from: value) {
            return date
        }
    }
    return nil
}

func nextDelay(current: UInt64, policy: AIRetryPolicy) -> UInt64 {
    guard current > 0 else { return 0 }
    let next = Double(current) * policy.backoffFactor
    guard next.isFinite, next < Double(UInt64.max) else {
        return policy.maxDelayNanoseconds
    }
    return Swift.min(UInt64(next), policy.maxDelayNanoseconds)
}
