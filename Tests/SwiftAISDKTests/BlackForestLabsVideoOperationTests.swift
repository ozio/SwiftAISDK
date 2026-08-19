import Foundation
import Testing
@testable import SwiftAISDK

@Test func blackForestLabsVideoOperationStartReturnsSerializableUpstreamReference() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"id":"req-123","polling_url":"https://api.bfl.ai/v1/get_result","cost":0.42,"input_mp":1.23,"output_mp":4.56}"#,
        headers: ["x-submit": "accepted"]
    ))
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: transport
    ))
    let model = try #require(try provider.videoModel("flux-3-video") as? any AsyncVideoModel)

    let result = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
        request: VideoGenerationRequest(
            prompt: "a cinematic forest",
            headers: ["idempotency-key": "stable-start"]
        )
    ))

    #expect(result.operation == [
        "requestId": "req-123",
        "pollingUrl": "https://api.bfl.ai/v1/get_result",
        "cost": 0.42,
        "inputMegapixels": 1.23,
        "outputMegapixels": 4.56
    ])
    #expect(result.warnings.isEmpty)
    #expect(result.responseMetadata.modelID == "flux-3-video")
    #expect(result.responseMetadata.headers["x-submit"] == "accepted")

    let request = try #require(await transport.requests().first)
    #expect(request.method == "POST")
    #expect(request.headers["idempotency-key"] == "stable-start")
    #expect(try decodeJSONBody(try #require(request.body)) == [
        "mode": "t2v",
        "prompt": "a cinematic forest"
    ])
}

@Test func blackForestLabsVideoOperationStatusReturnsPendingThenCompletedWithSettledMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"status":"Generating"}"#),
        jsonResponse(
            #"{"status":"Ready","cost":0.85,"result":{"sample":"https://delivery.bfl.ai/video.mp4","seed":7,"duration":8}}"#,
            headers: ["x-poll": "ready"]
        )
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: transport
    ))
    let model = try #require(try provider.videoModel("flux-3-video") as? any AsyncVideoModel)
    let operation: JSONValue = [
        "requestId": "req-123",
        "pollingUrl": "https://api.bfl.ai/v1/get_result",
        "cost": 0.42,
        "inputMegapixels": 1.23,
        "outputMegapixels": 4.56
    ]

    let pending = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: operation,
        headers: ["x-request-id": "video-1"]
    ))
    guard case .pending = pending else {
        Issue.record("Expected one pending status")
        return
    }

    let completed = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: operation,
        headers: ["x-request-id": "video-1"]
    ))
    guard case let .completed(result) = completed else {
        Issue.record("Expected a completed status")
        return
    }

    #expect(result.urls == ["https://delivery.bfl.ai/video.mp4"])
    #expect(result.operationID == "req-123")
    #expect(result.mediaType == "video/mp4")
    #expect(result.responseMetadata.headers["x-poll"] == "ready")
    let metadata = try #require(result.providerMetadata["blackForestLabs"]?["videos"]?[0])
    #expect(metadata["id"]?.stringValue == "req-123")
    #expect(metadata["videoUrl"]?.stringValue == "https://delivery.bfl.ai/video.mp4")
    #expect(metadata["cost"]?.doubleValue == 0.85)
    #expect(metadata["inputMegapixels"]?.doubleValue == 1.23)
    #expect(metadata["outputMegapixels"]?.doubleValue == 4.56)

    let requests = await transport.requests()
    #expect(requests.map(\.url.absoluteString) == [
        "https://api.bfl.ai/v1/get_result?id=req-123",
        "https://api.bfl.ai/v1/get_result?id=req-123"
    ])
    #expect(requests.allSatisfy { $0.headers["x-request-id"] == "video-1" })
}

@Test func blackForestLabsVideoOperationStatusReturnsUpstreamTerminalFailure() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"status":"Content Moderated","details":"blocked by policy"}"#
    ))
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: transport
    ))
    let model = try #require(try provider.videoModel("flux-3-video") as? any AsyncVideoModel)

    let status = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: [
            "requestId": "req-123",
            "pollingUrl": "https://api.bfl.ai/v1/get_result"
        ]
    ))

    guard case let .failed(message, _, _) = status else {
        Issue.record("Expected a terminal failure")
        return
    }
    #expect(message == "Black Forest Labs video generation failed with status \"Content Moderated\": blocked by policy. Request id: req-123")
}

@Test func blackForestLabsVideoFacadeUsesV4StartStatusAndMintsIdempotencyKey() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"req-facade","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://delivery.bfl.ai/facade.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: transport
    ))
    let model = try provider.videoModel("flux-3-video")

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "facade operation"),
        retryPolicy: .none,
        poll: VideoGenerationPollOptions(intervalMilliseconds: 0, delay: { _, _ in })
    )

    #expect(result.urls == ["https://delivery.bfl.ai/facade.mp4"])
    #expect(result.operationID == "req-facade")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].headers["idempotency-key"]?.hasPrefix("aisdk_vid_") == true)
    #expect(requests[1].method == "GET")
}

@Test func blackForestLabsVideoStatusRedirectStripsCredentialsOnCrossOriginHop() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(
            statusCode: 302,
            headers: ["location": "https://delivery.example.com/signed/status"]
        ),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://delivery.example.com/video.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try #require(try provider.videoModel("flux-3-video") as? any AsyncVideoModel)

    let status = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: [
            "requestId": "req-redirect",
            "pollingUrl": "https://api.bfl.ai/v1/get_result"
        ],
        headers: ["X-Operation-Secret": "operation-secret"]
    ))
    guard case .completed = status else {
        Issue.record("Expected redirected BFL status to complete")
        return
    }

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { !$0.followRedirects })
    #expect(requests[0].headers["x-key"] == "bfl-key")
    #expect(requests[0].headers["X-Operation-Secret"] == "operation-secret")
    #expect(requests[1].url.absoluteString == "https://delivery.example.com/signed/status")
    #expect(requests[1].headers["x-key"] == nil)
    #expect(requests[1].headers["x-operation-secret"] == nil)
    #expect(requests[1].headers.keys.allSatisfy { $0.caseInsensitiveCompare("user-agent") == .orderedSame })
}
