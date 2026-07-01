import Foundation
import Testing
@testable import SwiftAISDK

private let generateVideoPrompt = "a cat walking on a beach"
private let generateVideoMP4Base64 = "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDE="
private let generateVideoWebMBase64 = "GkXfo59ChoEBQveBAULygQRC84EIQoKEd2Vib"

@Test func aiGenerateVideoSendsArgsToModelLikeUpstream() async throws {
    let abortController = AIAbortController()
    let image = ImageInputFile(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png")
    let providerOptions: [String: JSONValue] = [
        "mock-provider": [
            "loop": true
        ]
    ]
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(
            prompt: generateVideoPrompt,
            aspectRatio: "16:9",
            durationSeconds: 5,
            image: image,
            resolution: "1920x1080",
            fps: 30,
            seed: 12_345,
            count: 1,
            providerOptions: providerOptions,
            headers: [
                "custom-request-header": "request-header-value"
            ],
            abortSignal: abortController.signal
        )
    )

    let request = try #require(model.requests.first)
    #expect(request.prompt == generateVideoPrompt)
    #expect(request.aspectRatio == "16:9")
    #expect(request.durationSeconds == 5)
    #expect(request.image == image)
    #expect(request.frameImages.isEmpty)
    #expect(request.inputReferences.isEmpty)
    #expect(request.resolution == "1920x1080")
    #expect(request.fps == 30)
    #expect(request.seed == 12_345)
    #expect(request.count == 1)
    #expect(request.providerOptions == providerOptions)
    #expect(request.headers == ["custom-request-header": "request-header-value"])
    #expect(request.abortSignal === abortController.signal)
}

@Test func aiGenerateVideoNormalizesAndPassesFrameImagesLikeUpstream() async throws {
    let first = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/first.png"),
        frameType: .firstFrame
    )
    let last = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/last.png"),
        frameType: .lastFrame
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", frameImages: [first, last])
    )

    let request = try #require(model.requests.first)
    #expect(request.image == first.image)
    #expect(request.frameImages == [first, last])
    #expect(request.inputReferences.isEmpty)
}

@Test func aiGenerateVideoPrefersFirstFrameOverPromptImageAndWarnsLikeUpstream() async throws {
    let promptImage = ImageInputFile(url: "https://example.com/prompt-image.png")
    let first = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/frame-first.png"),
        frameType: .firstFrame
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", image: promptImage, frameImages: [first])
    )

    let request = try #require(model.requests.first)
    #expect(request.image == first.image)
    #expect(request.frameImages == [first])
    #expect(result.warnings.contains(AIWarning(
        type: "other",
        message: "prompt.image was ignored because a first_frame frameImage was provided; the first_frame frameImage takes precedence as the start image."
    )))
}

@Test func aiGenerateVideoKeepsPromptImageWhenOnlyLastFrameIsProvidedLikeUpstream() async throws {
    let promptImage = ImageInputFile(url: "https://example.com/prompt-image.png")
    let last = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/last.png"),
        frameType: .lastFrame
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", image: promptImage, frameImages: [last])
    )

    let request = try #require(model.requests.first)
    #expect(request.image == promptImage)
    #expect(request.frameImages == [last])
}

@Test func aiGenerateVideoPassesOnlyLastFrameWithoutSettingImageLikeUpstream() async throws {
    let last = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/last.png"),
        frameType: .lastFrame
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", frameImages: [last])
    )

    let request = try #require(model.requests.first)
    #expect(request.image == nil)
    #expect(request.frameImages == [last])
}

@Test func aiGenerateVideoNormalizesAndPassesInputReferencesLikeUpstream() async throws {
    let references = [
        ImageInputFile(url: "https://example.com/ref-1.png"),
        ImageInputFile(url: "https://example.com/ref-2.png")
    ]
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    _ = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", inputReferences: references)
    )

    let request = try #require(model.requests.first)
    #expect(request.inputReferences == references)
    #expect(request.frameImages.isEmpty)
}

@Test func aiGenerateVideoIgnoresInputReferencesWhenFrameImagesAreProvidedLikeUpstream() async throws {
    let first = VideoFrameImage(
        image: ImageInputFile(url: "https://example.com/first.png"),
        frameType: .firstFrame
    )
    let references = [
        ImageInputFile(url: "https://example.com/ref-1.png"),
        ImageInputFile(url: "https://example.com/ref-2.png")
    ]
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: "a clip", frameImages: [first], inputReferences: references)
    )

    let request = try #require(model.requests.first)
    #expect(request.frameImages == [first])
    #expect(request.inputReferences.isEmpty)
    #expect(result.warnings.contains(AIWarning(
        type: "other",
        message: "inputReferences were ignored because frameImages were provided; frameImages and inputReferences cannot be combined."
    )))
}

@Test func aiGenerateVideoReturnsWarningsAndProviderMetadataLikeUpstream() async throws {
    let warning = AIWarning(type: "other", message: "Setting is not supported")
    let providerMetadata: [String: JSONValue] = [
        "testProvider": [
            "videos": [
                ["seed": 12_345, "duration": 5]
            ]
        ]
    ]
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:]),
        warnings: [warning],
        providerMetadata: providerMetadata
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: generateVideoPrompt)
    )

    #expect(result.warnings == [warning])
    #expect(result.providerMetadata == providerMetadata)
}

@Test func aiGenerateVideoLogsWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported"),
        AIWarning(
            type: "unsupported",
            feature: "duration",
            message: "Duration parameter not supported"
        )
    ]
    let recorder = GenerateVideoWarningLogRecorder()
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:]),
        warnings: expectedWarnings
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateVideo(
            model: model,
            request: VideoGenerationRequest(prompt: generateVideoPrompt)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-video")
    ])
}

@Test func aiGenerateVideoDoesNotLogEmptyWarningsLikeUpstream() async throws {
    let recorder = GenerateVideoWarningLogRecorder()
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:]),
        warnings: []
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateVideo(
            model: model,
            request: VideoGenerationRequest(prompt: generateVideoPrompt)
        )
    }

    #expect(await recorder.events().isEmpty)
}

@Test func aiGenerateVideoReturnsBase64VideosLikeUpstream() async throws {
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64, generateVideoWebMBase64],
        rawValue: .object([:])
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: generateVideoPrompt)
    )

    #expect(result.base64Videos == [generateVideoMP4Base64, generateVideoWebMBase64])
    #expect(result.urls == [])
    #expect(result.warnings == [])
    #expect(result.providerMetadata == [:])
}

@Test func aiGenerateVideoReturnsURLVideosLikeUpstream() async throws {
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: ["https://example.com/video.mp4"],
        rawValue: .object([:])
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: generateVideoPrompt)
    )

    #expect(result.urls == ["https://example.com/video.mp4"])
}

@Test func aiGenerateVideoThrowsNoVideoGeneratedWhenNoVideosLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id"
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [],
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .video, responses: [responseMetadata])) {
        _ = try await AI.generateVideo(
            model: model,
            request: VideoGenerationRequest(prompt: generateVideoPrompt)
        )
    }
}

@Test func aiGenerateVideoIncludesResponseHeadersInNoVideoErrorLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id",
        headers: [
            "custom-response-header": "response-header-value"
        ]
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [],
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .video, responses: [responseMetadata])) {
        _ = try await AI.generateVideo(
            model: model,
            request: VideoGenerationRequest(prompt: generateVideoPrompt)
        )
    }
}

@Test func aiGenerateVideoReturnsResponseMetadataLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model",
        headers: [
            "x-test": "value"
        ]
    )
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(prompt: generateVideoPrompt)
    )

    #expect(result.responseMetadata == responseMetadata)
}

@Test func aiGenerateVideoFillsRequestMetadataLikeUpstream() async throws {
    let image = ImageInputFile(url: "https://example.com/image.png", mediaType: "image/png")
    let model = MockVideoModel(result: VideoGenerationResult(
        urls: [],
        base64Videos: [generateVideoMP4Base64],
        rawValue: .object([:])
    ))

    let result = try await AI.generateVideo(
        model: model,
        request: VideoGenerationRequest(
            prompt: generateVideoPrompt,
            aspectRatio: "16:9",
            durationSeconds: 5,
            image: image,
            resolution: "1920x1080",
            fps: 30,
            seed: 12_345,
            count: 2,
            providerOptions: ["mock": ["loop": true]],
            headers: ["x-test": "value"]
        )
    )

    #expect(result.requestMetadata.headers == ["x-test": "value"])
    #expect(result.requestMetadata.body?["prompt"]?.stringValue == generateVideoPrompt)
    #expect(result.requestMetadata.body?["aspectRatio"]?.stringValue == "16:9")
    #expect(result.requestMetadata.body?["durationSeconds"]?.doubleValue == 5)
    #expect(result.requestMetadata.body?["image"]?["type"]?.stringValue == "url")
    #expect(result.requestMetadata.body?["image"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(result.requestMetadata.body?["image"]?["mediaType"]?.stringValue == "image/png")
    #expect(result.requestMetadata.body?["resolution"]?.stringValue == "1920x1080")
    #expect(result.requestMetadata.body?["fps"]?.doubleValue == 30)
    #expect(result.requestMetadata.body?["seed"]?.intValue == 12_345)
    #expect(result.requestMetadata.body?["count"]?.intValue == 2)
    #expect(result.requestMetadata.body?["providerOptions"]?["mock"]?["loop"]?.boolValue == true)
}

private actor GenerateVideoWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}
