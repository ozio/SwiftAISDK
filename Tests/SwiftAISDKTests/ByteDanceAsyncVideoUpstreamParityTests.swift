import Foundation
import Testing
@testable import SwiftAISDK

@Test func byteDanceAsyncVideoStartsAndReturnsPendingThenCompletedMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-async-1"}"#, headers: ["x-create": "accepted"]),
        jsonResponse(#"{"id":"task-async-1","status":"running"}"#, headers: ["x-status": "running"]),
        jsonResponse(
            #"{"id":"task-async-1","model":"seedance-final","status":"succeeded","content":{"video_url":"https://bytedance.example.com/async.mp4","last_frame_url":"https://bytedance.example.com/last-frame.png"},"usage":{"completion_tokens":100}}"#,
            headers: ["x-status": "complete"]
        )
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try #require(try provider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)

    #expect(model.maxVideosPerCall == 1)
    #expect(!model.supportsVideoGenerationWebhooks)
    let started = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
        request: VideoGenerationRequest(
            prompt: "cat running",
            aspectRatio: "16:9",
            durationSeconds: 5,
            resolution: "1920x1080",
            fps: 30,
            seed: 42,
            providerOptions: [
                "bytedance": [
                    "serviceTier": "flex",
                    "pollIntervalMs": 500,
                    "pollTimeoutMs": 60_000
                ]
            ],
            headers: ["x-request-id": "async-1"]
        )
    ))

    #expect(started.operation == ["taskId": "task-async-1"])
    #expect(started.responseMetadata.modelID == "seedance-1-0-pro-250528")
    #expect(started.responseMetadata.headers["x-create"] == "accepted")
    #expect(started.warnings.contains { $0.type == "unsupported" && $0.feature == "fps" })
    #expect(started.warnings.contains { $0.type == "deprecated" && $0.setting == "pollIntervalMs" })
    #expect(started.warnings.contains { $0.type == "deprecated" && $0.setting == "pollTimeoutMs" })

    let pending = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: started.operation,
        headers: ["x-poll": "poll-1"]
    ))
    guard case let .pending(_, _, pendingResponse) = pending else {
        Issue.record("Expected ByteDance running task to be pending")
        return
    }
    #expect(pendingResponse.headers["x-status"] == "running")

    let completed = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: started.operation,
        headers: ["x-poll": "poll-2"]
    ))
    guard case let .completed(result) = completed else {
        Issue.record("Expected ByteDance succeeded task to complete")
        return
    }
    #expect(result.urls == ["https://bytedance.example.com/async.mp4"])
    #expect(result.operationID == "task-async-1")
    #expect(result.mediaType == "video/mp4")
    #expect(result.providerMetadata["bytedance"]?["taskId"]?.stringValue == "task-async-1")
    #expect(result.providerMetadata["bytedance"]?["usage"]?["completion_tokens"]?.intValue == 100)
    #expect(result.providerMetadata["bytedance"]?["lastFrameUrl"]?.stringValue == "https://bytedance.example.com/last-frame.png")
    #expect(result.responseMetadata.modelID == "seedance-final")
    #expect(result.responseMetadata.headers["x-status"] == "complete")

    let requests = await transport.requests()
    #expect(requests.map(\.method) == ["POST", "GET", "GET"])
    #expect(requests.map(\.url.absoluteString) == [
        "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks",
        "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task-async-1",
        "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task-async-1"
    ])
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model"]?.stringValue == "seedance-1-0-pro-250528")
    #expect(body["content"]?[0]?["text"]?.stringValue == "cat running")
    #expect(body["ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.intValue == 5)
    #expect(body["resolution"]?.stringValue == "1080p")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(requests[0].headers["x-request-id"] == "async-1")
    #expect(requests[1].headers["x-poll"] == "poll-1")
    #expect(requests[2].headers["x-poll"] == "poll-2")
}

@Test func byteDanceAsyncVideoReturnsTerminalFailureWithProviderReason() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"task-failed","status":"failed","error":{"code":"SensitiveContentDetected","message":"The prompt was rejected by the content filter."}}
    """))
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try #require(try provider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)

    let status = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: ["taskId": "task-failed"]
    ))
    guard case let .failed(message, _, response) = status else {
        Issue.record("Expected ByteDance failed task to return a terminal failure")
        return
    }
    #expect(message == "Video generation failed. Task ID: task-failed. The prompt was rejected by the content filter.")
    #expect(response.modelID == "seedance-1-0-pro-250528")
}
