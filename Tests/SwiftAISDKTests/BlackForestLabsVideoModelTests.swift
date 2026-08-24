import Foundation
import Testing
@testable import SwiftAISDK

private let bflVideoPollOptions: [String: JSONValue] = [
    "pollIntervalMillis": 1,
    "pollTimeoutMillis": 1_000
]

private actor DelayedPendingBlackForestLabsVideoTransport: AITransport {
    private var recordedRequests: [AIHTTPRequest] = []

    func requests() -> [AIHTTPRequest] {
        recordedRequests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        recordedRequests.append(request)
        if recordedRequests.count == 1 {
            return jsonResponse(#"{"id":"bfl-slow-poll","polling_url":"https://api.bfl.ai/v1/get_result"}"#)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        return jsonResponse(#"{"status":"Pending"}"#)
    }
}

@Test func blackForestLabsProviderExposesVideoAliases() throws {
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    let video = try provider.video("flux-3-video")
    let videoModel = try provider.videoModel("flux-3-video")

    #expect(provider.supportedCapabilities.contains(.video))
    #expect(video.providerID == "black-forest-labs.video")
    #expect(video.modelID == "flux-3-video")
    #expect(videoModel.providerID == "black-forest-labs.video")
}

@Test func blackForestLabsVideoSubmitsPollsAndReturnsSignedURLWithSettledMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-video-1","polling_url":"https://api.us1.bfl.ai/v1/get_result","cost":0.42,"input_mp":1.23,"output_mp":4.56}"#),
        AIHTTPResponse(
            statusCode: 200,
            headers: ["x-poll": "ready"],
            body: Data(#"{"status":"Ready","cost":0.85,"result":{"sample":"https://delivery.bfl.ai/video.mp4","seed":7,"start_time":1,"end_time":9,"duration":8,"draft_cache":"https://api.bfl.ai/draft.bin"}}"#.utf8)
        )
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    let result = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
        prompt: "A white kitten chases a butterfly.",
        providerOptions: ["blackForestLabs": .object(bflVideoPollOptions)],
        headers: ["x-request-id": "video-1"]
    ))

    #expect(result.urls == ["https://delivery.bfl.ai/video.mp4"])
    #expect(result.base64Videos.isEmpty)
    #expect(result.operationID == "bfl-video-1")
    #expect(result.mediaType == "video/mp4")
    #expect(result.responseMetadata.modelID == "flux-3-video")
    #expect(result.responseMetadata.headers["x-poll"] == "ready")
    let metadata = try #require(result.providerMetadata["blackForestLabs"]?["videos"]?[0])
    #expect(metadata["id"]?.stringValue == "bfl-video-1")
    #expect(metadata["videoUrl"]?.stringValue == "https://delivery.bfl.ai/video.mp4")
    #expect(metadata["seed"]?.intValue == 7)
    #expect(metadata["start_time"]?.intValue == 1)
    #expect(metadata["end_time"]?.intValue == 9)
    #expect(metadata["duration"]?.intValue == 8)
    #expect(metadata["draftCache"]?.stringValue == "https://api.bfl.ai/draft.bin")
    #expect(metadata["cost"]?.doubleValue == 0.85)
    #expect(metadata["inputMegapixels"]?.doubleValue == 1.23)
    #expect(metadata["outputMegapixels"]?.doubleValue == 4.56)

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.absoluteString == "https://api.bfl.ai/v1/flux-3-video")
    #expect(requests[0].headers["x-key"] == "bfl-key")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/black-forest-labs/2.0.30")
    #expect(requests[0].headers["x-request-id"] == "video-1")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body == .object([
        "mode": "t2v",
        "prompt": "A white kitten chases a butterfly."
    ]))
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.us1.bfl.ai/v1/get_result?id=bfl-video-1")
    #expect(requests[1].headers["x-key"] == "bfl-key")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/black-forest-labs/2.0.30")
    #expect(requests[1].headers["x-request-id"] == "video-1")
}

@Test func blackForestLabsVideoTimeoutIncludesTimeSpentInPendingPollRequestsLikeUpstream() async throws {
    let transport = DelayedPendingBlackForestLabsVideoTransport()
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    await #expect(throws: AIError.invalidResponse(
        provider: "black-forest-labs.video",
        message: "Black Forest Labs video generation timed out after 100ms. Request id: bfl-slow-poll"
    )) {
        _ = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
            prompt: "slow polling",
            providerOptions: [
                "blackForestLabs": .object([
                    "pollIntervalMillis": 50,
                    "pollTimeoutMillis": 100
                ])
            ]
        ))
    }

    let requestCount = (await transport.requests()).count
    #expect((1...2).contains(requestCount))
}

@Test func blackForestLabsVideoMapsKeyframesResolutionDurationAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-video-options","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/video.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    let result = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
        prompt: "Two keyframes",
        durationSeconds: 24.6,
        frameImages: [
            VideoFrameImage(image: ImageInputFile(data: Data("last".utf8), mediaType: "image/png"), frameType: .lastFrame),
            VideoFrameImage(image: ImageInputFile(url: "https://cdn.example.com/first.png", mediaType: "image/png"), frameType: .firstFrame)
        ],
        resolution: "854x480",
        fps: 30,
        generateAudio: false,
        seed: 42,
        count: 2,
        providerOptions: [
            "blackForestLabs": .object(bflVideoPollOptions.merging([
                "aspectRatio": "auto",
                "safetyTolerance": 1,
                "draft": false,
                "version": "latest"
            ]) { _, new in new })
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["mode"]?.stringValue == "i2v")
    #expect(body["prompt"]?.stringValue == "Two keyframes")
    #expect(body["keyframes"] == .array([
        "https://cdn.example.com/first.png",
        Data("last".utf8).base64EncodedString()
    ]))
    #expect(body["aspect_ratio"]?.stringValue == "auto")
    #expect(body["resolution"]?.stringValue == "hd")
    #expect(body["duration"]?.intValue == 20)
    #expect(body["generate_audio"]?.boolValue == false)
    #expect(body["safety_tolerance"]?.intValue == 1)
    #expect(body["draft"]?.boolValue == false)
    #expect(body["version"]?.stringValue == "latest")
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "fps", message: "FLUX 3 video does not support a custom frame rate."),
        AIWarning(type: "unsupported", feature: "seed", message: "FLUX 3 video does not accept a seed."),
        AIWarning(type: "unsupported", feature: "n", message: "FLUX 3 video generates a single video per call. Only 1 video will be generated."),
        AIWarning(type: "compatibility", feature: "resolution", message: "FLUX 3 video renders at \"hd\" or \"fhd\"; the requested resolution \"854x480\" was mapped to \"hd\"."),
        AIWarning(type: "unsupported", feature: "duration", message: "FLUX 3 video requires a whole number of seconds. The requested duration of 24.6 was rounded to 25."),
        AIWarning(type: "unsupported", feature: "duration", message: "FLUX 3 video supports at most 20 seconds. The requested duration of 24.6 was clamped to 20.")
    ])
}

@Test func blackForestLabsVideoSupportsTimedProviderKeyframesAndRejectsUntimedThreeWithoutDuration() async throws {
    let rejectingTransport = RecordingTransport(response: jsonResponse("{}"))
    let rejectingProvider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: rejectingTransport))

    await #expect(throws: AIError.invalidArgument(
        argument: "duration",
        message: "FLUX 3 video requires an explicit duration when 3 or more keyframes are sent without a timestamp."
    )) {
        _ = try await rejectingProvider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
            prompt: "untimed",
            providerOptions: [
                "blackForestLabs": .object([
                    "keyframes": ["a", "b", "c"],
                    "pollIntervalMillis": 1,
                    "pollTimeoutMillis": 1_000
                ])
            ]
        ))
    }
    #expect((await rejectingTransport.requests()).isEmpty)

    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-timed","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/timed.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let result = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
        prompt: "timed",
        image: ImageInputFile(url: "https://cdn.example.com/top-level.png", mediaType: "image/png"),
        providerOptions: [
            "blackForestLabs": .object([
                "keyframes": [[0, "a"], [2.5, "b"], [4, "c"]],
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1_000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["mode"]?.stringValue == "i2v")
    #expect(body["keyframes"] == .array([
        .array([0, "a"]),
        .array([2.5, "b"]),
        .array([4, "c"])
    ]))
    #expect(body["duration"] == nil)
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "image",
            message: "FLUX 3 video takes a single keyframe list. providerOptions.blackForestLabs.keyframes was used and the top-level frame images were ignored."
        )
    ])
}

@Test func blackForestLabsVideoContinuesFromFirstVideoAndClassifiesReferences() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-v2v","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/v2v.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    let result = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
        prompt: "continue",
        inputReferences: [
            ImageInputFile(url: "https://cdn.example.com/untyped"),
            ImageInputFile(url: "https://cdn.example.com/second.mp4", mediaType: "video/mp4"),
            ImageInputFile(url: "https://cdn.example.com/image.png", mediaType: "image/png"),
            ImageInputFile(url: "https://cdn.example.com/audio.mp3", mediaType: "audio/mpeg")
        ],
        providerOptions: ["blackForestLabs": .object(bflVideoPollOptions)]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body == .object([
        "mode": "v2v",
        "prompt": "continue",
        "start_video": "https://cdn.example.com/untyped"
    ]))
    #expect(result.warnings.map(\.type) == ["compatibility", "unsupported", "unsupported", "unsupported"])
    #expect(result.warnings.map(\.feature) == ["inputReferences", "inputReferences", "inputReferences", "inputReferences"])
    #expect(result.warnings.last?.message == "FLUX 3 video continues from a single video. Only the first video reference was used.")
}

@Test func blackForestLabsVideoDraftEnhanceSendsOnlyReplayFieldsAndWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-enhance","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/enhanced.mp4"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    let result = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
        prompt: "ignored prompt",
        aspectRatio: "16:9",
        image: ImageInputFile(url: "https://cdn.example.com/frame.png", mediaType: "image/png"),
        fps: 24,
        count: 3,
        providerOptions: [
            "blackForestLabs": .object([
                "draftCache": "YmluYXJ5",
                "draft": true,
                "safetyTolerance": 1,
                "version": "latest",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1_000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body == .object([
        "mode": "draft_enhance",
        "draft_cache": "YmluYXJ5",
        "safety_tolerance": 1
    ]))
    #expect(result.warnings.map(\.feature) == [
        "prompt", "aspectRatio", "fps", "image", "version", "draft", "n"
    ])
}

@Test func blackForestLabsVideoStripsCredentialsFromForeignPollAndSurfacesTerminalDetails() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-moderated","polling_url":"https://poll.example.com/status"}"#),
        jsonResponse(#"{"status":"Content Moderated","details":"blocked by policy"}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))

    await #expect(throws: AIError.invalidResponse(
        provider: "black-forest-labs.video",
        message: "Black Forest Labs video generation failed with status \"Content Moderated\": blocked by policy. Request id: bfl-moderated"
    )) {
        _ = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
            prompt: "moderated",
            providerOptions: ["blackForestLabs": .object(bflVideoPollOptions)],
            headers: ["x-request-id": "moderated"]
        ))
    }

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[1].url.absoluteString == "https://poll.example.com/status?id=bfl-moderated")
    #expect(requests[1].headers["x-key"] == nil)
    #expect(requests[1].headers["user-agent"] == nil)
    #expect(requests[1].headers["x-request-id"] == nil)
}

@Test func blackForestLabsVideoRejectsInvalidOptionsAndReadyWithoutSample() async throws {
    let invalidTransport = RecordingTransport(response: jsonResponse("{}"))
    let invalidProvider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: invalidTransport))
    await #expect(throws: AIError.self) {
        _ = try await invalidProvider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
            prompt: "bad options",
            providerOptions: [
                "blackForestLabs": .object([
                    "keyframes": [[3, "a"], [2, "b"]]
                ])
            ]
        ))
    }
    #expect((await invalidTransport.requests()).isEmpty)

    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-empty","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    await #expect(throws: AIError.invalidResponse(
        provider: "black-forest-labs.video",
        message: "Black Forest Labs reported the video as Ready but returned no result.sample URL. Request id: bfl-empty"
    )) {
        _ = try await provider.videoModel("flux-3-video").generateVideo(VideoGenerationRequest(
            prompt: "empty",
            providerOptions: ["blackForestLabs": .object(bflVideoPollOptions)]
        ))
    }
}
