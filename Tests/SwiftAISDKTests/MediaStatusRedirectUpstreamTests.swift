import Foundation
import Testing
@testable import SwiftAISDK

private let metadataRedirect = AIHTTPResponse(
    statusCode: 302,
    headers: ["Location": "http://169.254.169.254/latest/meta-data/"]
)
private let metadataRedirectError = AIError.invalidArgument(
    argument: "url",
    message: "URL with IP address 169.254.169.254 is not allowed."
)

@Test func byteDanceDirectMediaStatusRedirectIsRejectedBeforeCredentialsCanLeaveTheConfiguredOrigin() async throws {
    let transport = RecordingTransport(response: metadataRedirect)
    let provider = try AIProviders.byteDance(settings: ProviderSettings(
        apiKey: "ark-key",
        baseURL: "http://localhost:3000/api/v3",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let model = try #require(try provider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)
    let abortController = AIAbortController()

    await #expect(throws: metadataRedirectError) {
        _ = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
            operation: ["taskId": "test-task-id-123"],
            headers: ["X-Request-Secret": "request-secret"],
            abortSignal: abortController.signal
        ))
    }

    try assertProtectedStatusRequest(
        await transport.requests(),
        expectedCount: 1,
        statusIndex: 0,
        expectedURL: "http://localhost:3000/api/v3/contents/generations/tasks/test-task-id-123",
        expectedAuthorization: "Bearer ark-key",
        abortSignal: abortController.signal
    )
}

@Test func byteDanceUnaryMediaPollingRedirectIsRejectedAfterOnlyCreateAndFirstStatusRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"test-task-id-123"}"#),
        metadataRedirect
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(
        apiKey: "ark-key",
        baseURL: "http://localhost:3000/api/v3",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let abortController = AIAbortController()

    await #expect(throws: metadataRedirectError) {
        _ = try await provider.videoModel("seedance-1-0-pro-250528").generateVideo(VideoGenerationRequest(
            prompt: "A test video",
            providerOptions: ["bytedance": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]],
            headers: ["X-Request-Secret": "request-secret"],
            abortSignal: abortController.signal
        ))
    }

    try assertProtectedStatusRequest(
        await transport.requests(),
        expectedCount: 2,
        statusIndex: 1,
        expectedURL: "http://localhost:3000/api/v3/contents/generations/tasks/test-task-id-123",
        expectedAuthorization: "Bearer ark-key",
        abortSignal: abortController.signal
    )
}

@Test func miniMaxUnaryMediaPollingRedirectIsRejectedAfterOnlyCreateAndFirstStatusRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"test-task-id-123"}"#),
        metadataRedirect
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "minimax-key",
        videoBaseURL: "http://localhost:3000",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let abortController = AIAbortController()

    await #expect(throws: metadataRedirectError) {
        _ = try await provider.videoModel("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "A test video",
            providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]],
            headers: ["X-Request-Secret": "request-secret"],
            abortSignal: abortController.signal
        ))
    }

    try assertProtectedStatusRequest(
        await transport.requests(),
        expectedCount: 2,
        statusIndex: 1,
        expectedURL: "http://localhost:3000/v2/query/video_generation/test-task-id-123",
        expectedAuthorization: "Bearer minimax-key",
        abortSignal: abortController.signal
    )
}

@Test func klingAIUnaryMediaPollingRedirectIsRejectedAfterOnlyCreateAndFirstStatusRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-abc-123","task_status":"submitted"}}"#),
        metadataRedirect
    ])
    let provider = try AIProviders.klingAI(settings: ProviderSettings(
        apiKey: "kling-token",
        baseURL: "http://localhost:3000",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let abortController = AIAbortController()

    await #expect(throws: metadataRedirectError) {
        _ = try await provider.videoModel("kling-v2.6-t2v").generateVideo(VideoGenerationRequest(
            prompt: "A test video",
            providerOptions: ["klingai": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]],
            headers: ["X-Request-Secret": "request-secret"],
            abortSignal: abortController.signal
        ))
    }

    try assertProtectedStatusRequest(
        await transport.requests(),
        expectedCount: 2,
        statusIndex: 1,
        expectedURL: "http://localhost:3000/v1/videos/text2video/task-abc-123",
        expectedAuthorization: "Bearer kling-token",
        abortSignal: abortController.signal
    )
}

private func assertProtectedStatusRequest(
    _ requests: [AIHTTPRequest],
    expectedCount: Int,
    statusIndex: Int,
    expectedURL: String,
    expectedAuthorization: String,
    abortSignal: AIAbortSignal
) throws {
    #expect(requests.count == expectedCount)
    let statusRequest = try #require(requests.indices.contains(statusIndex) ? requests[statusIndex] : nil)
    let headers = normalizeHeaders(statusRequest.headers)
    if statusIndex == 1 {
        #expect(requests[0].method == "POST")
    }
    #expect(statusRequest.method == "GET")
    #expect(statusRequest.url.absoluteString == expectedURL)
    #expect(!statusRequest.followRedirects)
    #expect(statusRequest.abortSignal === abortSignal)
    #expect(headers["authorization"] == expectedAuthorization)
    #expect(headers["x-provider-secret"] == "provider-secret")
    #expect(headers["x-request-secret"] == "request-secret")
    #expect(requests.allSatisfy { $0.url.host == "localhost" })
    #expect(requests.allSatisfy { $0.url.host != "169.254.169.254" })
}
