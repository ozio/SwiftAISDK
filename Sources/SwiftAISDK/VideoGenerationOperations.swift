import Foundation

/// A provider-owned reference to an asynchronous video generation operation.
///
/// `operation` must remain JSON serializable so callers can persist it and
/// resume status checks in a later process.
public struct VideoGenerationOperationStartResult: Sendable {
    public var operation: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        operation: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.operation = operation
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
    }
}

/// The result of one status check for an asynchronous video operation.
public enum VideoGenerationOperationStatusResult: Sendable {
    case pending(
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    )
    case completed(VideoGenerationResult)
    case failed(
        message: String,
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    )
}

public struct VideoGenerationOperationStartRequest: Sendable {
    public var request: VideoGenerationRequest
    public var webhookURL: String?

    public init(request: VideoGenerationRequest, webhookURL: String? = nil) {
        self.request = request
        self.webhookURL = webhookURL
    }
}

public struct VideoGenerationOperationStatusRequest: Sendable {
    public var operation: JSONValue
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        operation: JSONValue,
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.operation = operation
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

/// The notification delivered to a webhook endpoint for an asynchronous video operation.
public struct VideoGenerationOperationWebhook: Sendable, Equatable {
    public var headers: [String: String]
    public var body: JSONValue

    public init(headers: [String: String] = [:], body: JSONValue) {
        self.headers = headers
        self.body = body
    }
}

/// A webhook endpoint and the cancellation-aware receiver for its first notification.
public struct VideoGenerationWebhookRegistration: Sendable {
    public var url: String
    private let receiveImplementation: @Sendable (AIAbortSignal?) async throws -> VideoGenerationOperationWebhook

    public init(
        url: String,
        receive: @escaping @Sendable (AIAbortSignal?) async throws -> VideoGenerationOperationWebhook
    ) {
        self.url = url
        self.receiveImplementation = receive
    }

    public func receive(abortSignal: AIAbortSignal? = nil) async throws -> VideoGenerationOperationWebhook {
        try abortSignal?.throwIfAborted()
        return try await receiveImplementation(abortSignal)
    }
}

public typealias VideoGenerationWebhookFactory = @Sendable () async throws -> VideoGenerationWebhookRegistration
public typealias VideoGenerationDelay = @Sendable (_ milliseconds: Int, _ abortSignal: AIAbortSignal?) async throws -> Void

/// Polling and webhook-wait configuration for asynchronous video generation.
public struct VideoGenerationPollOptions: Sendable {
    public var intervalMilliseconds: Int
    public var timeoutMilliseconds: Int
    public var delay: VideoGenerationDelay

    public init(
        intervalMilliseconds: Int = 5_000,
        timeoutMilliseconds: Int = 600_000,
        delay: @escaping VideoGenerationDelay = { milliseconds, abortSignal in
            try await SwiftAISDK.delay(milliseconds, abortSignal: abortSignal)
        }
    ) {
        self.intervalMilliseconds = intervalMilliseconds
        self.timeoutMilliseconds = timeoutMilliseconds
        self.delay = delay
    }
}

public enum VideoGenerationOperationError: Error, Equatable, Sendable, CustomStringConvertible {
    case timedOut(milliseconds: Int)
    case providerFailed(String)
    case incompleteAfterWebhook

    public var description: String {
        switch self {
        case let .timedOut(milliseconds):
            return "Video generation timed out after \(milliseconds)ms."
        case let .providerFailed(message):
            return message
        case .incompleteAfterWebhook:
            return "Video generation did not complete after webhook notification."
        }
    }
}

/// A video model that exposes the provider V4 start/status operation surface.
///
/// Conformance is additive to `VideoModel`, so existing unary
/// `generateVideo(_:)` calls remain source compatible.
public protocol AsyncVideoModel: VideoModel {
    /// Maximum number of videos one start operation can request. Upstream V4
    /// defaults to one when a provider does not advertise a larger batch.
    var maxVideosPerCall: Int { get }
    var supportsVideoGenerationWebhooks: Bool { get }

    func handleVideoGenerationWebhookOption(
        _ factory: @escaping VideoGenerationWebhookFactory
    ) async throws -> VideoGenerationWebhookRegistration

    func startVideoGeneration(
        _ request: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult

    func videoGenerationStatus(
        _ request: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult
}

public extension AsyncVideoModel {
    var maxVideosPerCall: Int { 1 }
    var supportsVideoGenerationWebhooks: Bool { false }

    func handleVideoGenerationWebhookOption(
        _ factory: @escaping VideoGenerationWebhookFactory
    ) async throws -> VideoGenerationWebhookRegistration {
        try await factory()
    }
}

func generateVideoUsingOperations(
    model: any AsyncVideoModel,
    request: VideoGenerationRequest,
    poll: VideoGenerationPollOptions?,
    webhook: VideoGenerationWebhookFactory?,
    retryPolicy: AIRetryPolicy
) async throws -> VideoGenerationResult {
    let requestedCount = request.count ?? 1
    guard requestedCount > 0 else {
        throw AIError.invalidArgument(argument: "count", message: "count must be greater than zero.")
    }
    guard model.maxVideosPerCall > 0 else {
        throw AIError.invalidArgument(
            argument: "model.maxVideosPerCall",
            message: "maxVideosPerCall must be greater than zero."
        )
    }

    var callCounts: [Int] = []
    var remaining = requestedCount
    while remaining > 0 {
        let callCount = min(remaining, model.maxVideosPerCall)
        callCounts.append(callCount)
        remaining -= callCount
    }

    guard callCounts.count > 1 else {
        var callRequest = request
        callRequest.count = callCounts[0]
        return try await generateSingleVideoUsingOperations(
            model: model,
            request: callRequest,
            poll: poll,
            webhook: webhook,
            retryPolicy: retryPolicy
        )
    }

    let indexedResults = try await withThrowingTaskGroup(
        of: (Int, VideoGenerationResult).self,
        returning: [(Int, VideoGenerationResult)].self
    ) { group in
        for (index, callCount) in callCounts.enumerated() {
            var callRequest = request
            callRequest.count = callCount
            let resolvedCallRequest = callRequest
            group.addTask {
                let result = try await generateSingleVideoUsingOperations(
                    model: model,
                    request: resolvedCallRequest,
                    poll: poll,
                    webhook: webhook,
                    retryPolicy: retryPolicy
                )
                return (index, result)
            }
        }

        var output: [(Int, VideoGenerationResult)] = []
        output.reserveCapacity(callCounts.count)
        for try await result in group {
            output.append(result)
        }
        return output
    }

    return mergeVideoOperationResults(
        indexedResults.sorted { $0.0 < $1.0 }.map(\.1),
        request: request
    )
}

private func generateSingleVideoUsingOperations(
    model: any AsyncVideoModel,
    request: VideoGenerationRequest,
    poll: VideoGenerationPollOptions?,
    webhook: VideoGenerationWebhookFactory?,
    retryPolicy: AIRetryPolicy
) async throws -> VideoGenerationResult {
    let options = poll ?? VideoGenerationPollOptions()
    guard options.intervalMilliseconds >= 0 else {
        throw AIError.invalidArgument(
            argument: "poll.intervalMilliseconds",
            message: "intervalMilliseconds must be greater than or equal to zero."
        )
    }
    guard options.timeoutMilliseconds > 0 else {
        throw AIError.invalidArgument(
            argument: "poll.timeoutMilliseconds",
            message: "timeoutMilliseconds must be greater than zero."
        )
    }

    var warnings: [AIWarning] = []
    var webhookRegistration: VideoGenerationWebhookRegistration?
    if let webhook {
        if model.supportsVideoGenerationWebhooks {
            webhookRegistration = try await model.handleVideoGenerationWebhookOption(webhook)
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "webhook",
                message: "This model does not support webhooks. Falling back to polling."
            ))
        }
    }

    var startRequest = request
    if !startRequest.headers.keys.contains(where: { $0.caseInsensitiveCompare("idempotency-key") == .orderedSame }) {
        startRequest.headers["idempotency-key"] = "aisdk_vid_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
    let resolvedStartRequest = startRequest
    let webhookURL = webhookRegistration?.url

    let startResult = try await withRetry(
        policy: retryPolicy,
        abortSignal: request.abortSignal
    ) {
        try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
            request: resolvedStartRequest,
            webhookURL: webhookURL
        ))
    }

    warnings.append(contentsOf: startResult.warnings)
    var providerMetadata = startResult.providerMetadata
    let started = DispatchTime.now().uptimeNanoseconds

    if let webhookRegistration {
        _ = try await waitForVideoGenerationWebhook(
            webhookRegistration,
            timeoutMilliseconds: options.timeoutMilliseconds,
            delay: options.delay,
            abortSignal: request.abortSignal
        )
    }

    while true {
        if webhookRegistration == nil {
            try request.abortSignal?.throwIfAborted()
            let elapsedMilliseconds = videoOperationElapsedMilliseconds(since: started)
            guard elapsedMilliseconds < options.timeoutMilliseconds else {
                throw VideoGenerationOperationError.timedOut(milliseconds: options.timeoutMilliseconds)
            }
            let remaining = options.timeoutMilliseconds - elapsedMilliseconds
            try await options.delay(min(options.intervalMilliseconds, remaining), request.abortSignal)
            guard videoOperationElapsedMilliseconds(since: started) < options.timeoutMilliseconds else {
                throw VideoGenerationOperationError.timedOut(milliseconds: options.timeoutMilliseconds)
            }
        }

        let status = try await withRetry(
            policy: retryPolicy,
            abortSignal: request.abortSignal
        ) {
            try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
                operation: startResult.operation,
                headers: request.headers,
                abortSignal: request.abortSignal
            ))
        }

        switch status {
        case let .pending(statusWarnings, statusMetadata, _):
            warnings.append(contentsOf: statusWarnings)
            mergeVideoOperationProviderMetadata(&providerMetadata, statusMetadata)
            if webhookRegistration != nil {
                throw VideoGenerationOperationError.incompleteAfterWebhook
            }

        case var .completed(result):
            warnings.append(contentsOf: result.warnings)
            mergeVideoOperationProviderMetadata(&providerMetadata, result.providerMetadata)
            result.warnings = warnings
            result.providerMetadata = providerMetadata
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = videoGenerationRequestMetadata(request)
            }
            return result

        case let .failed(message, statusMetadata, _):
            mergeVideoOperationProviderMetadata(&providerMetadata, statusMetadata)
            throw VideoGenerationOperationError.providerFailed(message)
        }
    }
}

private func mergeVideoOperationResults(
    _ results: [VideoGenerationResult],
    request: VideoGenerationRequest
) -> VideoGenerationResult {
    precondition(!results.isEmpty)
    var providerMetadata: [String: JSONValue] = [:]
    for result in results {
        mergeVideoOperationProviderMetadata(&providerMetadata, result.providerMetadata)
    }
    let mediaTypes = Set(results.compactMap(\.mediaType))
    return VideoGenerationResult(
        urls: results.flatMap(\.urls),
        base64Videos: results.flatMap(\.base64Videos),
        operationID: nil,
        mediaType: mediaTypes.count == 1 ? mediaTypes.first : nil,
        rawValue: .array(results.map(\.rawValue)),
        warnings: results.flatMap(\.warnings),
        providerMetadata: providerMetadata,
        requestMetadata: videoGenerationRequestMetadata(request),
        responseMetadata: results.last?.responseMetadata ?? AIResponseMetadata()
    )
}

private func videoOperationElapsedMilliseconds(since started: UInt64) -> Int {
    let now = DispatchTime.now().uptimeNanoseconds
    let elapsed = now >= started ? now - started : 0
    return Int(min(elapsed / 1_000_000, UInt64(Int.max)))
}

private func mergeVideoOperationProviderMetadata(
    _ target: inout [String: JSONValue],
    _ source: [String: JSONValue]
) {
    for (provider, incoming) in source {
        guard let existing = target[provider],
              var existingObject = existing.objectValue,
              let incomingObject = incoming.objectValue else {
            target[provider] = incoming
            continue
        }

        let existingVideos = existingObject["videos"]?.arrayValue
        let incomingVideos = incomingObject["videos"]?.arrayValue
        existingObject.merge(incomingObject) { _, new in new }
        if let existingVideos, let incomingVideos {
            existingObject["videos"] = .array(existingVideos + incomingVideos)
        }
        target[provider] = .object(existingObject)
    }
}

private func waitForVideoGenerationWebhook(
    _ registration: VideoGenerationWebhookRegistration,
    timeoutMilliseconds: Int,
    delay: @escaping VideoGenerationDelay,
    abortSignal: AIAbortSignal?
) async throws -> VideoGenerationOperationWebhook {
    let state = VideoGenerationWebhookWaitState()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            state.install(continuation)

            let timeoutController = AIAbortController()
            let mergedSignal = mergeAbortSignals(abortSignal, timeoutController.signal)
            let worker = Task {
                do {
                    let notification = try await registration.receive(abortSignal: mergedSignal)
                    state.resolve(.success(notification))
                } catch {
                    state.resolve(.failure(error))
                }
            }
            state.setWorker(worker)

            let timeoutTask = Task {
                do {
                    try await delay(timeoutMilliseconds, timeoutController.signal)
                    timeoutController.abort(reason: "Video webhook timed out", reasonName: "TimeoutError")
                    state.resolve(.failure(VideoGenerationOperationError.timedOut(milliseconds: timeoutMilliseconds)))
                } catch is AIAbortError {
                    // Normal cleanup after the webhook or caller cancellation wins.
                } catch is CancellationError {
                    // Normal cleanup after the webhook or caller cancellation wins.
                } catch {
                    state.resolve(.failure(error))
                }
            }
            state.setTimeoutTask(timeoutTask, controller: timeoutController)

            if let abortSignal {
                let abortRegistration = abortSignal.addAbortHandler { reason in
                    state.resolve(.failure(AIAbortError(reason: reason, reasonName: abortSignal.reasonName)))
                }
                state.setAbortRegistration(abortRegistration)
            }
        }
    } onCancel: {
        state.resolve(.failure(CancellationError()))
    }
}

private final class VideoGenerationWebhookWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VideoGenerationOperationWebhook, Error>?
    private var pendingResult: Result<VideoGenerationOperationWebhook, Error>?
    private var worker: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var timeoutController: AIAbortController?
    private var abortRegistration: AIAbortHandlerRegistration?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<VideoGenerationOperationWebhook, Error>) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            isResolved = true
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setWorker(_ task: Task<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            task.cancel()
            return
        }
        worker = task
        lock.unlock()
    }

    func setTimeoutTask(_ task: Task<Void, Never>, controller: AIAbortController) {
        lock.lock()
        if isResolved {
            lock.unlock()
            controller.abort()
            task.cancel()
            return
        }
        timeoutTask = task
        timeoutController = controller
        lock.unlock()
    }

    func setAbortRegistration(_ registration: AIAbortHandlerRegistration) {
        lock.lock()
        if isResolved {
            lock.unlock()
            registration.cancel()
            return
        }
        abortRegistration = registration
        lock.unlock()
    }

    func resolve(_ result: Result<VideoGenerationOperationWebhook, Error>) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        guard let continuation else {
            pendingResult = result
            lock.unlock()
            return
        }
        isResolved = true
        self.continuation = nil
        let worker = self.worker
        let timeoutTask = self.timeoutTask
        let timeoutController = self.timeoutController
        let abortRegistration = self.abortRegistration
        self.worker = nil
        self.timeoutTask = nil
        self.timeoutController = nil
        self.abortRegistration = nil
        lock.unlock()

        timeoutController?.abort()
        worker?.cancel()
        timeoutTask?.cancel()
        abortRegistration?.cancel()
        continuation.resume(with: result)
    }
}
