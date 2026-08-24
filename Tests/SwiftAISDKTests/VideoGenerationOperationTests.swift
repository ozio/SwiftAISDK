import Foundation
import Testing
@testable import SwiftAISDK

@Test func videoStartFacadeReturnsImmediatelyAndReusesOneLogicalStartAcrossRetriesLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "mock": ["asyncJob": ["jobId": "job-1", "webhookSigningSecret": "secret-1"]]
    ]
    let responseMetadata = AIResponseMetadata(id: "response-1", modelID: "mock-video")
    let state = VideoOperationTestState(
        startFailures: 1,
        startResult: VideoGenerationOperationStartResult(
            operation: ["id": "operation-1"],
            warnings: [AIWarning(type: "other", message: "queued")],
            providerMetadata: providerMetadata,
            responseMetadata: responseMetadata
        )
    )
    let model = VideoOperationTestModel(state: state)
    let promptImage = ImageInputFile(url: "https://example.com/prompt.png")
    let firstFrame = ImageInputFile(url: "https://example.com/first.png")

    let result = try await AI.startVideo(
        model: model,
        request: VideoGenerationRequest(
            prompt: "a cat walking on a beach",
            image: promptImage,
            frameImages: [VideoFrameImage(image: firstFrame, frameType: .firstFrame)]
        ),
        webhookURL: "https://example.com/hook",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
    )

    #expect(result.operation == ["id": "operation-1"])
    #expect(result.providerMetadata == providerMetadata)
    #expect(result.responseMetadata == responseMetadata)
    #expect(result.warnings.map(\.message) == [
        "prompt.image was ignored because a first_frame frameImage was provided; the first_frame frameImage takes precedence as the start image.",
        "queued"
    ])
    #expect(await state.startCallCount() == 2)
    #expect(await state.statusCallCount() == 0)
    #expect(await state.startImages() == [firstFrame, firstFrame])
    #expect(await state.startWebhookURLs().compactMap { $0 } == [
        "https://example.com/hook", "https://example.com/hook"
    ])
    let idempotencyKeys = await state.startHeaders().compactMap { headers in
        headers.first { $0.key.lowercased() == "idempotency-key" }?.value
    }
    #expect(idempotencyKeys.count == 2)
    #expect(idempotencyKeys[0].hasPrefix("aisdk_vid_"))
    #expect(idempotencyKeys[0] == idempotencyKeys[1])
}

@Test func videoStartFacadeRejectsCountsAboveOneOperationLimitLikeUpstream() async throws {
    let state = VideoOperationTestState()
    let model = VideoOperationTestModel(state: state)

    await #expect(throws: AIError.invalidArgument(
        argument: "count",
        message: "Video model mock-video supports at most 1 video(s) per call, but 2 were requested. Split the batch across multiple startVideo calls."
    )) {
        _ = try await AI.startVideo(
            model: model,
            request: VideoGenerationRequest(prompt: "two clips", count: 2),
            retryPolicy: .none
        )
    }

    #expect(await state.startCallCount() == 0)
}

@Test func videoStatusFacadePerformsOneRetryableStatusCheckLikeUpstream() async throws {
    let state = VideoOperationTestState(
        statusFailures: 1,
        statuses: [.pending(providerMetadata: ["mock": ["state": "queued"]])]
    )
    let model = VideoOperationTestModel(state: state)

    let status = try await AI.getVideoStatus(
        model: model,
        operation: ["id": "operation-1"],
        headers: ["x-status": "one-shot"],
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
    )

    guard case let .pending(_, providerMetadata, _) = status else {
        Issue.record("Expected a pending operation status.")
        return
    }
    #expect(providerMetadata == ["mock": ["state": "queued"]])
    #expect(await state.startCallCount() == 0)
    #expect(await state.statusCallCount() == 2)
    #expect(await state.statusHeaders() == [
        ["x-status": "one-shot"], ["x-status": "one-shot"]
    ])
}

@Test func videoOperationsReuseOneIdempotencyKeyAcrossStartRetriesAndDoNotRestartForStatusRetries() async throws {
    let state = VideoOperationTestState(
        startFailures: 1,
        statusFailures: 1,
        startResult: VideoGenerationOperationStartResult(
            operation: ["id": "operation-1"],
            warnings: [AIWarning(type: "other", message: "start warning")],
            providerMetadata: [
                "mock": ["phase": "start", "videos": [["id": "start"]]]
            ]
        ),
        statuses: [
            .pending(
                warnings: [AIWarning(type: "other", message: "pending warning")],
                providerMetadata: [
                    "mock": ["phase": "pending", "videos": [["id": "pending"]]]
                ]
            ),
            .completed(VideoGenerationResult(
                urls: ["https://example.com/video.mp4"],
                rawValue: ["status": "completed"],
                warnings: [AIWarning(type: "other", message: "completed warning")],
                providerMetadata: [
                    "mock": ["phase": "completed", "videos": [["id": "completed"]]]
                ]
            ))
        ]
    )
    let model = VideoOperationTestModel(state: state)

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "make a clip", headers: ["x-test": "value"]),
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0, delay: { _, _ in })
    )

    let startHeaders = await state.startHeaders()
    #expect(startHeaders.count == 2)
    let firstKey = startHeaders[0].first { $0.key.lowercased() == "idempotency-key" }?.value
    let secondKey = startHeaders[1].first { $0.key.lowercased() == "idempotency-key" }?.value
    #expect(firstKey?.hasPrefix("aisdk_vid_") == true)
    #expect(firstKey == secondKey)
    #expect(await state.startCallCount() == 2)
    #expect(await state.statusCallCount() == 3)
    #expect(await state.statusHeaders() == [["x-test": "value"], ["x-test": "value"], ["x-test": "value"]])
    #expect(result.warnings.map(\.message) == ["start warning", "pending warning", "completed warning"])
    #expect(result.providerMetadata["mock"]?["phase"]?.stringValue == "completed")
    #expect(result.providerMetadata["mock"]?["videos"] == [
        ["id": "start"], ["id": "pending"], ["id": "completed"]
    ])
}

@Test func videoOperationsPreserveCallerIdempotencyKeyCaseInsensitively() async throws {
    let state = VideoOperationTestState(statuses: [.completed(videoOperationTestResult())])
    let model = VideoOperationTestModel(state: state)

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(
            prompt: "caller token",
            headers: ["Idempotency-Key": "caller-owned"]
        ),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0, delay: { _, _ in })
    )

    let headers = try #require(await state.startHeaders().first)
    #expect(headers["Idempotency-Key"] == "caller-owned")
    #expect(headers.keys.filter { $0.lowercased() == "idempotency-key" }.count == 1)
}

@Test func videoOperationsPreferSupportedWebhookAndCheckStatusOnceAfterNotification() async throws {
    let state = VideoOperationTestState(
        supportsWebhooks: true,
        statuses: [.completed(videoOperationTestResult())]
    )
    let factoryCalls = VideoOperationCounter()
    let model = VideoOperationTestModel(state: state)

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "webhook"),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(timeoutMilliseconds: 1_000),
        webhook: {
            await factoryCalls.increment()
            return VideoGenerationWebhookRegistration(url: "https://hooks.example.com/video") { _ in
                VideoGenerationOperationWebhook(headers: ["x-event": "ready"], body: ["ready": true])
            }
        }
    )

    #expect(await factoryCalls.value() == 1)
    #expect(await state.webhookHandlerCallCount() == 1)
    #expect(await state.startWebhookURLs() == ["https://hooks.example.com/video"])
    #expect(await state.statusCallCount() == 1)
}

@Test func videoOperationsDoNotCreateUnsupportedWebhookAndFallBackToPolling() async throws {
    let state = VideoOperationTestState(statuses: [.completed(videoOperationTestResult())])
    let factoryCalls = VideoOperationCounter()
    let delayCalls = VideoOperationCounter()
    let model = VideoOperationTestModel(state: state)

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "poll fallback"),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0, delay: { _, _ in
            await delayCalls.increment()
        }),
        webhook: {
            await factoryCalls.increment()
            return VideoGenerationWebhookRegistration(url: "https://unused.example.com") { _ in
                VideoGenerationOperationWebhook(body: [:])
            }
        }
    )

    #expect(await factoryCalls.value() == 0)
    #expect(await state.webhookHandlerCallCount() == 0)
    #expect(await delayCalls.value() == 1)
    #expect(result.warnings.first == AIWarning(
        type: "unsupported",
        feature: "webhook",
        message: "This model does not support webhooks. Falling back to polling."
    ))
}

@Test func videoOperationsTimeoutAndCancellationStopWebhookWaits() async throws {
    let timeoutState = VideoOperationTestState(supportsWebhooks: true)
    let timeoutModel = VideoOperationTestModel(state: timeoutState)

    await #expect(throws: VideoGenerationOperationError.timedOut(milliseconds: 5)) {
        _ = try await AI.generateVideo(
            model: timeoutModel,
            request: VideoGenerationRequest(prompt: "timeout"),
            retryPolicy: .none,
            poll: VideoGenerationPollOptions(timeoutMilliseconds: 5),
            webhook: waitingVideoOperationWebhookFactory
        )
    }
    #expect(await timeoutState.statusCallCount() == 0)

    let controller = AIAbortController()
    let cancellationState = VideoOperationTestState(supportsWebhooks: true)
    let cancellationModel = VideoOperationTestModel(state: cancellationState)
    let abortTask = Task {
        try? await Task.sleep(nanoseconds: 5_000_000)
        controller.abort(reason: "stop video", reasonName: "AbortError")
    }
    defer { abortTask.cancel() }

    do {
        _ = try await AI.generateVideo(
            model: cancellationModel,
            request: VideoGenerationRequest(prompt: "cancel", abortSignal: controller.signal),
            retryPolicy: .none,
            poll: VideoGenerationPollOptions(timeoutMilliseconds: 1_000),
            webhook: waitingVideoOperationWebhookFactory
        )
        Issue.record("Expected webhook wait to be aborted")
    } catch let error as AIAbortError {
        #expect(error.reason == "stop video")
    }
}

@Test func videoOperationsKeepUnaryModelsSourceCompatibleWhenOptionsAreSupplied() async throws {
    let model = UnaryVideoOperationTestModel()
    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "legacy"),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0)
    )

    #expect(await model.callCount() == 1)
    #expect(result.urls == ["https://example.com/unary.mp4"])
    #expect(result.warnings.first?.message == "poll/webhook options were provided but the model does not support start/status operations. Falling back to unary generateVideo.")
}

@Test func videoOperationsSplitCountByModelLimitAndMergeResultsInCallOrder() async throws {
    let state = VideoOperationTestState(statuses: [
        .completed(videoOperationTestResult(url: "https://example.com/one.mp4")),
        .completed(videoOperationTestResult(url: "https://example.com/two.mp4")),
        .completed(videoOperationTestResult(url: "https://example.com/three.mp4"))
    ])
    let model = VideoOperationTestModel(state: state)

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "three clips", count: 3),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0, delay: { _, _ in })
    )

    #expect(await state.startCallCount() == 3)
    #expect(await state.startCounts() == [1, 1, 1])
    let idempotencyKeys = await state.startHeaders().compactMap { headers in
        headers.first { $0.key.lowercased() == "idempotency-key" }?.value
    }
    #expect(Set(idempotencyKeys).count == 3)
    #expect(result.urls.count == 3)
    #expect(Set(result.urls) == Set([
        "https://example.com/one.mp4",
        "https://example.com/two.mp4",
        "https://example.com/three.mp4"
    ]))
    #expect(result.rawValue.arrayValue?.count == 3)
    #expect(result.operationID == nil)
}

@Test func videoFacadeSelectsStartStatusForAsyncOnlyModelsWithoutPollOptions() async throws {
    let controller = AIAbortController()
    let state = AsyncOnlyVideoOperationState()
    let model = AsyncOnlyVideoOperationTestModel(state: state, controller: controller)

    do {
        _ = try await AI.generateVideo(
            model: model,
            request: VideoGenerationRequest(prompt: "async only", abortSignal: controller.signal),
            retryPolicy: .none
        )
        Issue.record("Expected the start hook to abort the operation")
    } catch let error as AIAbortError {
        #expect(error.reason == "async-only-started")
    }

    #expect(await state.startCallCount() == 1)
}

private let waitingVideoOperationWebhookFactory: VideoGenerationWebhookFactory = {
    VideoGenerationWebhookRegistration(url: "https://hooks.example.com/wait") { signal in
        guard let signal else {
            throw AIError.invalidResponse(provider: "mock.video", message: "Missing webhook abort signal")
        }
        _ = await signal.waitUntilAborted()
        try signal.throwIfAborted()
        return VideoGenerationOperationWebhook(body: [:])
    }
}

private func videoOperationTestResult(
    url: String = "https://example.com/video.mp4"
) -> VideoGenerationResult {
    VideoGenerationResult(
        urls: [url],
        rawValue: ["status": "completed"]
    )
}

private final class VideoOperationTestModel: AsyncVideoModel, @unchecked Sendable {
    let providerID = "mock.video"
    let modelID = "mock-video"
    let supportsVideoGenerationWebhooks: Bool
    private let state: VideoOperationTestState

    init(state: VideoOperationTestState) {
        self.state = state
        supportsVideoGenerationWebhooks = state.webhookSupport
    }

    func handleVideoGenerationWebhookOption(
        _ factory: @escaping VideoGenerationWebhookFactory
    ) async throws -> VideoGenerationWebhookRegistration {
        await state.recordWebhookHandlerCall()
        return try await factory()
    }

    func startVideoGeneration(
        _ request: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult {
        try await state.start(request)
    }

    func videoGenerationStatus(
        _ request: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult {
        try await state.status(request)
    }

    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        Issue.record("Unary generateVideo should not be called by operation tests")
        return videoOperationTestResult()
    }
}

private actor VideoOperationTestState {
    nonisolated let webhookSupport: Bool
    private var remainingStartFailures: Int
    private var remainingStatusFailures: Int
    private let configuredStartResult: VideoGenerationOperationStartResult
    private var configuredStatuses: [VideoGenerationOperationStatusResult]
    private var recordedStartHeaders: [[String: String]] = []
    private var recordedStartImages: [ImageInputFile?] = []
    private var recordedStartCounts: [Int?] = []
    private var recordedWebhookURLs: [String?] = []
    private var recordedStatusHeaders: [[String: String]] = []
    private var webhookHandlerCalls = 0

    init(
        supportsWebhooks: Bool = false,
        startFailures: Int = 0,
        statusFailures: Int = 0,
        startResult: VideoGenerationOperationStartResult = VideoGenerationOperationStartResult(operation: ["id": "operation-1"]),
        statuses: [VideoGenerationOperationStatusResult] = []
    ) {
        webhookSupport = supportsWebhooks
        remainingStartFailures = startFailures
        remainingStatusFailures = statusFailures
        configuredStartResult = startResult
        configuredStatuses = statuses
    }

    func recordWebhookHandlerCall() {
        webhookHandlerCalls += 1
    }

    func start(_ request: VideoGenerationOperationStartRequest) throws -> VideoGenerationOperationStartResult {
        recordedStartHeaders.append(request.request.headers)
        recordedStartImages.append(request.request.image)
        recordedStartCounts.append(request.request.count)
        recordedWebhookURLs.append(request.webhookURL)
        if remainingStartFailures > 0 {
            remainingStartFailures -= 1
            throw AIError.apiCall(AIAPICallError(
                provider: "mock.video",
                statusCode: 503,
                responseBody: "retry start"
            ))
        }
        return configuredStartResult
    }

    func status(_ request: VideoGenerationOperationStatusRequest) throws -> VideoGenerationOperationStatusResult {
        recordedStatusHeaders.append(request.headers)
        if remainingStatusFailures > 0 {
            remainingStatusFailures -= 1
            throw AIError.apiCall(AIAPICallError(
                provider: "mock.video",
                statusCode: 503,
                responseBody: "retry status"
            ))
        }
        guard !configuredStatuses.isEmpty else {
            return .pending()
        }
        return configuredStatuses.removeFirst()
    }

    func startHeaders() -> [[String: String]] { recordedStartHeaders }
    func startImages() -> [ImageInputFile?] { recordedStartImages }
    func startCounts() -> [Int?] { recordedStartCounts }
    func startWebhookURLs() -> [String?] { recordedWebhookURLs }
    func statusHeaders() -> [[String: String]] { recordedStatusHeaders }
    func startCallCount() -> Int { recordedStartHeaders.count }
    func statusCallCount() -> Int { recordedStatusHeaders.count }
    func webhookHandlerCallCount() -> Int { webhookHandlerCalls }
}

private final class AsyncOnlyVideoOperationTestModel: AsyncVideoModel, @unchecked Sendable {
    let providerID = "async-only.video"
    let modelID = "async-only"
    let supportsUnaryVideoGeneration = false
    private let state: AsyncOnlyVideoOperationState
    private let controller: AIAbortController

    init(state: AsyncOnlyVideoOperationState, controller: AIAbortController) {
        self.state = state
        self.controller = controller
    }

    func startVideoGeneration(
        _ request: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult {
        await state.recordStart()
        controller.abort(reason: "async-only-started", reasonName: "AbortError")
        return VideoGenerationOperationStartResult(operation: ["id": "async-only-operation"])
    }

    func videoGenerationStatus(
        _ request: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult {
        Issue.record("Status should not be reached after the start hook aborts")
        return .pending()
    }
}

private actor AsyncOnlyVideoOperationState {
    private var starts = 0
    func recordStart() { starts += 1 }
    func startCallCount() -> Int { starts }
}

private actor VideoOperationCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

private actor UnaryVideoOperationTestModel: VideoModel {
    nonisolated let providerID = "unary.video"
    nonisolated let modelID = "unary-video"
    private var calls = 0

    func generateVideo(_ request: VideoGenerationRequest) -> VideoGenerationResult {
        calls += 1
        return VideoGenerationResult(
            urls: ["https://example.com/unary.mp4"],
            rawValue: ["status": "completed"]
        )
    }

    func callCount() -> Int { calls }
}
