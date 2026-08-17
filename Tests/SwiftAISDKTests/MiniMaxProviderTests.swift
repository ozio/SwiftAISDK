import Foundation
import Testing
@testable import SwiftAISDK

@Test func miniMaxProviderDefaultsAndAliasesMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"content":[{"type":"text","text":"callable"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#),
        jsonResponse(#"{"content":[{"type":"text","text":"language"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#),
        jsonResponse(#"{"content":[{"type":"text","text":"chat"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        environment: ["MINIMAX_API_KEY": "env-key"],
        transport: transport
    ))
    let callableModel = try provider("minimax-m3")
    let languageModel = try provider.languageModel("minimax-m2.5")
    let chatModel = try provider.chat("minimax-m2.1")

    #expect(provider.providerID == "minimax")
    #expect(provider.supportedCapabilities == [.language, .video])
    #expect(callableModel.providerID == "minimax.messages")
    #expect(languageModel.providerID == "minimax.messages")
    #expect(chatModel.providerID == "minimax.messages")
    #expect(callableModel.supportedURLs.isEmpty)

    _ = try await callableModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await languageModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.url.absoluteString == "https://api.minimax.io/anthropic/v1/messages" })
    #expect(requests.allSatisfy { $0.headers["x-api-key"] == "env-key" })
    #expect(requests.allSatisfy { $0.headers["anthropic-version"] == "2023-06-01" })
    #expect(requests.allSatisfy { $0.headers["user-agent"] == "ai-sdk/minimax/3.0.15" })
}

@Test func miniMaxCustomConfigurationMatchesUpstreamHeaderPrecedence() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#
    ))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "settings-key",
        baseURL: "https://minimax.example.com/custom/",
        headers: [
            "X-API-Key": "header-key",
            "Anthropic-Version": "custom-version",
            "User-Agent": "CustomApp/1.0",
            "X-Custom": "custom-value"
        ],
        environment: ["MINIMAX_API_KEY": "env-key"],
        transport: transport
    ))

    _ = try await provider.languageModel("future-minimax-model").generate(
        LanguageModelRequest(messages: [.user("Hi")])
    )

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://minimax.example.com/custom/messages")
    #expect(request.headers["x-api-key"] == "header-key")
    #expect(request.headers["anthropic-version"] == "custom-version")
    #expect(request.headers["x-custom"] == "custom-value")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/minimax/3.0.15")
}

@Test func miniMaxRequiresAPIKeyLikeUpstream() throws {
    #expect(throws: AIError.missingAPIKey(provider: "minimax", environmentVariables: ["MINIMAX_API_KEY"])) {
        _ = try AIProviders.miniMax(settings: MiniMaxProviderSettings(environment: [:]))
    }

    #expect(throws: AIError.missingAPIKey(provider: "minimax", environmentVariables: ["MINIMAX_API_KEY"])) {
        _ = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
            headers: ["x-api-key": "header-only-key"],
            environment: [:]
        ))
    }
}

@Test func miniMaxUnsupportedModelFamiliesMatchUpstream() throws {
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "test-key"))

    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .embedding, modelID: "embed")) {
        _ = try provider.textEmbeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func miniMaxReasoningRequestAndResponseMatchUpstreamFixture() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id": "msg_minimax_reasoning",
      "type": "message",
      "role": "assistant",
      "model": "minimax-m3",
      "content": [
        {
          "type": "thinking",
          "thinking": "Counting the letters...",
          "signature": "sig_123"
        },
        {"type": "text", "text": "There are 3 \\\"r\\\"s."}
      ],
      "stop_reason": "end_turn",
      "stop_sequence": null,
      "usage": {"input_tokens": 4, "output_tokens": 30}
    }
    """))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))
    let model = try provider("minimax-m3")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "minimax": [
                "thinking": ["type": "adaptive"]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.minimax.io/anthropic/v1/messages")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "minimax-m3")
    #expect(body["thinking"] == ["type": "adaptive"])

    #expect(result.text == "There are 3 \"r\"s.")
    #expect(result.reasoning == "Counting the letters...")
    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, metadata) = result.content[0] else {
        Issue.record("Expected reasoning content first")
        return
    }
    #expect(reasoning == "Counting the letters...")
    #expect(metadata["anthropic"]?["signature"]?.stringValue == "sig_123")
    guard case let .text(text, _) = result.content[1] else {
        Issue.record("Expected text content second")
        return
    }
    #expect(text == "There are 3 \"r\"s.")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 4)
    #expect(result.usage?.outputTokens == 30)
    #expect(result.responseMetadata.id == "msg_minimax_reasoning")
    #expect(result.providerMetadata["minimax"]?["usage"]?["output_tokens"]?.intValue == 30)
}

@Test func miniMaxStreamingReasoningUsesSharedAnthropicLifecycle() async throws {
    let transport = RecordingTransport(response: sseResponse("""
        data: {"type":"message_start","message":{"id":"msg_stream","model":"minimax-m3","usage":{"input_tokens":4,"output_tokens":0}}}

        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Think"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"signed"}}

        data: {"type":"content_block_stop","index":0}

        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Done"}}

        data: {"type":"content_block_stop","index":1}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

        data: {"type":"message_stop"}

        """))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))

    var parts: [LanguageStreamPart] = []
    for try await part in try provider("minimax-m3").stream(
        LanguageModelRequest(
            messages: [.user("Think")],
            providerOptions: ["minimax": ["thinking": ["type": "adaptive"]]]
        )
    ) {
        parts.append(part)
    }

    #expect(!parts.contains(.reasoningDelta("Think")))
    #expect(!parts.contains(.textDelta("Done")))
    #expect(parts.contains { part in
        guard case let .reasoningDeltaPart(_, delta, _) = part else { return false }
        return delta == "Think"
    })
    #expect(parts.contains { part in
        guard case let .textDeltaPart(_, delta, _) = part else { return false }
        return delta == "Done"
    })
    #expect(parts.contains { part in
        guard case let .reasoningDeltaPart(_, _, metadata) = part else { return false }
        return metadata["anthropic"]?["signature"]?.stringValue == "signed"
    })
    #expect(parts.contains { part in
        guard case let .finishMetadata(reason, usage, _) = part else { return false }
        return reason == "stop" && usage?.inputTokens == 4 && usage?.outputTokens == 2
    })
}

@Test func miniMaxDisabledThinkingAndMixedContentPreserveUpstreamOrder() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id": "msg_minimax_mixed",
      "model": "minimax-m3",
      "content": [
        {
          "type": "server_tool_use",
          "id": "search_1",
          "name": "web_search",
          "input": {"query": "MiniMax"}
        },
        {"type": "redacted_thinking", "data": "encrypted_reasoning"},
        {"type": "thinking", "thinking": "Plan", "signature": "sig_mixed"},
        {
          "type": "web_search_tool_result",
          "tool_use_id": "search_1",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/result",
              "title": "Search result",
              "page_age": "1 day",
              "encrypted_content": "encrypted_result"
            }
          ]
        },
        {
          "type": "text",
          "text": "Answer",
          "citations": [
            {
              "type": "web_search_result_location",
              "url": "https://example.com/citation",
              "title": "Citation",
              "cited_text": "Answer",
              "encrypted_index": "encrypted_index"
            }
          ]
        },
        {"type": "compaction", "content": "Compact context"}
      ],
      "stop_reason": "tool_use",
      "usage": {"input_tokens": 3, "output_tokens": 8}
    }
    """))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))

    let result = try await provider("minimax-m3").generate(LanguageModelRequest(
        messages: [.user("Use tools")],
        providerOptions: ["minimax": ["thinking": ["type": "disabled"]]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"] == ["type": "disabled"])

    #expect(result.text == "AnswerCompact context")
    #expect(result.reasoning == "Plan")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.map(\.id) == ["search_1"])
    #expect(result.toolResults.map(\.toolCallID) == ["search_1"])
    #expect(result.sources.map(\.url) == [
        "https://example.com/result",
        "https://example.com/citation"
    ])
    #expect(result.content.count == 8)

    guard case let .toolCall(toolCall) = result.content[0] else {
        Issue.record("Expected provider tool call first")
        return
    }
    #expect(toolCall.id == "search_1")
    guard case let .reasoning(redacted, redactedMetadata) = result.content[1] else {
        Issue.record("Expected redacted reasoning second")
        return
    }
    #expect(redacted.isEmpty)
    #expect(redactedMetadata["anthropic"]?["redactedData"]?.stringValue == "encrypted_reasoning")
    guard case let .reasoning(thinking, thinkingMetadata) = result.content[2] else {
        Issue.record("Expected signed reasoning third")
        return
    }
    #expect(thinking == "Plan")
    #expect(thinkingMetadata["anthropic"]?["signature"]?.stringValue == "sig_mixed")
    guard case let .toolResult(toolResult) = result.content[3] else {
        Issue.record("Expected provider tool result fourth")
        return
    }
    #expect(toolResult.toolCallID == "search_1")
    guard case let .source(searchSource) = result.content[4] else {
        Issue.record("Expected search-result source after its tool result")
        return
    }
    #expect(searchSource.url == "https://example.com/result")
    guard case let .text(answer, answerMetadata) = result.content[5] else {
        Issue.record("Expected cited text after the search result")
        return
    }
    #expect(answer == "Answer")
    #expect(answerMetadata["anthropic"]?["citations"]?[0]?["url"]?.stringValue == "https://example.com/citation")
    guard case let .source(citationSource) = result.content[6] else {
        Issue.record("Expected citation source immediately after its text")
        return
    }
    #expect(citationSource.url == "https://example.com/citation")
    guard case let .text(compaction, compactionMetadata) = result.content[7] else {
        Issue.record("Expected compaction content last")
        return
    }
    #expect(compaction == "Compact context")
    #expect(compactionMetadata["anthropic"]?["type"]?.stringValue == "compaction")
}

@Test func miniMaxVideoGeneratesTextToVideoAndReportsTaskMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_minimax_1"}"#),
        jsonResponse(#"{"task":{"id":"task_minimax_1","status":"running"}}"#),
        jsonResponse(
            #"{"task":{"id":"task_minimax_1","status":"succeeded","content":{"url":"https://cdn.example.com/minimax.mp4"},"duration":5,"ratio":"16:9","resolution":"2K","usage":{"total_seconds":5,"input_seconds":1,"output_seconds":5}}}"#,
            headers: ["x-minimax-poll": "final"]
        )
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "video-key",
        videoBaseURL: "https://video.minimax.example.com/",
        transport: transport
    ))
    let model = try provider.video("MiniMax-H3")

    #expect(model.providerID == "minimax.video")
    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "A white kitten chases a butterfly.",
        aspectRatio: "16:9",
        durationSeconds: 5,
        resolution: "2560x1440",
        providerOptions: [
            "minimax": [
                "aigcWatermark": true,
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ],
        headers: ["x-request": "video"]
    ))

    #expect(result.urls == ["https://cdn.example.com/minimax.mp4"])
    #expect(result.operationID == "task_minimax_1")
    #expect(result.mediaType == "video/mp4")
    #expect(result.warnings.isEmpty)
    #expect(result.providerMetadata["minimax"]?["taskId"]?.stringValue == "task_minimax_1")
    #expect(result.providerMetadata["minimax"]?["videoUrl"]?.stringValue == "https://cdn.example.com/minimax.mp4")
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["imageCount"]?.intValue == 0)
    #expect(result.providerMetadata["minimax"]?["usage"]?["totalSeconds"]?.intValue == 5)
    #expect(result.responseMetadata.modelID == "MiniMax-H3")
    #expect(result.responseMetadata.headers["x-minimax-poll"] == "final")
    #expect(result.responseMetadata.body == nil)

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.absoluteString == "https://video.minimax.example.com/v2/video_generation")
    #expect(requests[0].headers["authorization"] == "Bearer video-key")
    #expect(requests[0].headers["x-api-key"] == nil)
    #expect(requests[0].headers["anthropic-version"] == nil)
    #expect(requests[0].headers["user-agent"] == "ai-sdk/minimax/3.0.15")
    #expect(requests[0].headers["x-request"] == "video")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["model"]?.stringValue == "MiniMax-H3")
    #expect(body["resolution"]?.stringValue == "2K")
    #expect(body["duration"]?.intValue == 5)
    #expect(body["ratio"]?.stringValue == "16:9")
    #expect(body["aigc_watermark"]?.boolValue == true)
    #expect(body["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["content"]?[0]?["text"]?.stringValue == "A white kitten chases a butterfly.")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://video.minimax.example.com/v2/query/video_generation/task_minimax_1")
    #expect(requests[1].headers["authorization"] == "Bearer video-key")
    #expect(requests[2].url == requests[1].url)
}

@Test func miniMaxVideoDefaultsTextToVideoAspectRatioToSixteenByNineLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_default_ratio"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/default-ratio.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))

    let result = try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "Default ratio.",
        providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["ratio"]?.stringValue == "16:9")
}

@Test func miniMaxVideoFallsBackFromUnsupportedTextToVideoRatiosLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_invalid_ratio"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/invalid-ratio.mp4"}}}"#),
        jsonResponse(#"{"task_id":"task_adaptive_ratio"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/adaptive-ratio.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))
    let model = try provider.video("MiniMax-H3")

    let invalidResult = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Invalid ratio.",
        aspectRatio: "2:1",
        providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))
    let adaptiveResult = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Adaptive ratio.",
        providerOptions: [
            "minimax": [
                "ratio": "adaptive",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    #expect(invalidResult.warnings.map(\.message) == [
        "MiniMax-H3 does not support the aspect ratio \"2:1\". Using the default (16:9)."
    ])
    #expect(adaptiveResult.warnings.map(\.message) == [
        "MiniMax-H3 text-to-video does not support the adaptive aspect ratio. Using the default (16:9)."
    ])
    let requests = await transport.requests()
    let invalidBody = try decodeJSONBody(try #require(requests[0].body))
    let adaptiveBody = try decodeJSONBody(try #require(requests[2].body))
    #expect(invalidBody["ratio"]?.stringValue == "16:9")
    #expect(adaptiveBody["ratio"]?.stringValue == "16:9")
}

@Test func miniMaxVideoMapsFrameInputsAndUpstreamWarnings() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_frames"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/frames.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))
    let firstFrame = ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
    let lastFrame = ImageInputFile(url: "https://assets.example.com/last.jpg", mediaType: "image/jpeg")

    let result = try await provider.videoModel("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "Animate the scene.",
        aspectRatio: "9:16",
        durationSeconds: 15.6,
        image: ImageInputFile(url: "https://assets.example.com/ignored.jpg", mediaType: "image/jpeg"),
        frameImages: [
            VideoFrameImage(image: firstFrame, frameType: .firstFrame),
            VideoFrameImage(image: lastFrame, frameType: .lastFrame)
        ],
        inputReferences: [ImageInputFile(url: "https://assets.example.com/reference.mp4", mediaType: "video/mp4")],
        resolution: "1080p",
        fps: 24,
        generateAudio: false,
        seed: 42,
        count: 2,
        providerOptions: [
            "minimax": [
                "resolution": "2K",
                "ratio": "9:16",
                "referenceAudioUrls": ["https://assets.example.com/reference.mp3"],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    #expect(result.warnings.map(\.feature) == [
        "fps", "seed", "n", "generateAudio", "resolution", "inputReferences", "aspectRatio", "duration", "duration"
    ])
    #expect(result.warnings[4].message == "Unrecognized resolution \"1080p\". MiniMax-H3 only supports \"2K\", so providerOptions.minimax.resolution (\"2K\") was used instead.")
    #expect(result.warnings[5].message == "MiniMax-H3 cannot combine frame images with reference inputs. The references were ignored.")
    #expect(result.warnings[7].message == "MiniMax-H3 requires a whole number of seconds. The requested duration of 15.6 was rounded to 16.")
    #expect(result.warnings[8].message == "MiniMax-H3 supports at most 15 seconds. The requested duration of 15.6 was clamped to 15.")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["resolution"]?.stringValue == "2K")
    #expect(body["duration"]?.intValue == 15)
    #expect(body["ratio"] == nil)
    #expect(body["content"]?.arrayValue?.count == 3)
    #expect(body["content"]?[1]?["role"]?.stringValue == "first_frame")
    #expect(body["content"]?[1]?["image_url"]?["url"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["content"]?[2]?["role"]?.stringValue == "last_frame")
    #expect(body["content"]?[2]?["image_url"]?["url"]?.stringValue == "https://assets.example.com/last.jpg")
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["imageCount"]?.intValue == 2)
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["referenceVideoUrls"]?.arrayValue == [])
}

@Test func miniMaxVideoRoutesAndCapsReferenceInputs() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_references"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/references.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))
    let imageReferences = (0..<10).map { index in
        ImageInputFile(url: "https://assets.example.com/image-\(index).png", mediaType: "image/png")
    }
    let videoReferences = (0..<4).map { index in
        ImageInputFile(url: "https://assets.example.com/video-\(index).mp4", mediaType: "video/mp4")
    }

    let result = try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "Use the references.",
        inputReferences: imageReferences + videoReferences + [
            ImageInputFile(url: "https://assets.example.com/document.pdf", mediaType: "application/pdf")
        ],
        providerOptions: [
            "minimax": [
                "referenceAudioUrls": [
                    "https://assets.example.com/audio-0.mp3",
                    "https://assets.example.com/audio-1.mp3",
                    "https://assets.example.com/audio-2.mp3",
                    "https://assets.example.com/audio-3.mp3"
                ],
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    #expect(result.warnings.map(\.message) == [
        "MiniMax-H3 only accepts image and video references; the \"application/pdf\" reference was ignored. Pass reference audio via providerOptions.minimax.referenceAudioUrls.",
        "MiniMax-H3 accepts at most 9 reference images. Extra images were ignored.",
        "MiniMax-H3 accepts at most 3 reference videos. Extra videos were ignored.",
        "MiniMax-H3 accepts at most 3 reference audios. Extra audios were ignored."
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["content"]?.arrayValue)
    #expect(body["ratio"] == nil)
    #expect(content.count == 16)
    #expect(content.filter { $0["role"]?.stringValue == "reference_image" }.count == 9)
    #expect(content.filter { $0["role"]?.stringValue == "reference_video" }.count == 3)
    #expect(content.filter { $0["role"]?.stringValue == "reference_audio" }.count == 3)
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["imageCount"]?.intValue == 9)
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["referenceVideoUrls"]?.arrayValue?.compactMap(\.stringValue) == [
        "https://assets.example.com/video-0.mp4",
        "https://assets.example.com/video-1.mp4",
        "https://assets.example.com/video-2.mp4"
    ])
}

@Test func miniMaxVideoParsesHTTPAndTerminalTaskErrors() async throws {
    let apiTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["x-request-id": "req_bad"],
        body: Data(#"{"type":"error","error":{"type":"invalid_request","message":"Invalid MiniMax video request","http_code":400},"request_id":"req_bad"}"#.utf8)
    ))
    let apiProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: apiTransport))

    await #expect(throws: AIError.apiCall(
        provider: "minimax.video",
        statusCode: 400,
        body: "Invalid MiniMax video request",
        headers: ["x-request-id": "req_bad"]
    )) {
        _ = try await apiProvider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(prompt: "bad"))
    }

    let failedTransport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_failed"}"#),
        jsonResponse(#"{"task":{"status":"failed","error":{"message":"Safety check failed","code":1008}}}"#)
    ])
    let failedProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: failedTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "minimax.video",
        message: "MiniMax video generation failed: Safety check failed (1008). Task ID: task_failed"
    )) {
        _ = try await failedProvider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "bad",
            providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
        ))
    }
}

@Test func miniMaxVideoRejectsMalformedSuccessMetadata() async throws {
    let malformedDurationTransport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_bad_duration"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/bad-duration.mp4"},"duration":"5"}}"#)
    ])
    let malformedDurationProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "video-key",
        transport: malformedDurationTransport
    ))

    await #expect(throws: AIError.invalidResponse(
        provider: "minimax.video",
        message: "MiniMax video status response did not match the expected schema: task.duration must be a number or null."
    )) {
        _ = try await malformedDurationProvider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "bad duration",
            providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
        ))
    }

    let malformedUsageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_bad_usage"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/bad-usage.mp4"},"usage":{"total_seconds":"5"}}}"#)
    ])
    let malformedUsageProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "video-key",
        transport: malformedUsageTransport
    ))

    await #expect(throws: AIError.invalidResponse(
        provider: "minimax.video",
        message: "MiniMax video status response did not match the expected schema: task.usage.total_seconds must be a number or null."
    )) {
        _ = try await malformedUsageProvider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "bad usage",
            providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
        ))
    }
}

@Test func miniMaxVideoValidatesProviderOptionsBeforeNetworkIO() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"task_id":"unused"}"#))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.minimax.ratio",
        message: "Expected one of: 16:9, 1:1, 21:9, 3:4, 4:3, 9:16, adaptive."
    )) {
        _ = try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "bad",
            providerOptions: ["minimax": ["ratio": "2:1"]]
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func miniMaxVideoTreatsNullProviderOptionsAsAbsent() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_null_options"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/null-options.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))

    let result = try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "Use defaults.",
        providerOptions: ["minimax": .null],
        extraBody: ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]
    ))

    #expect(result.urls == ["https://cdn.example.com/null-options.mp4"])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["resolution"]?.stringValue == "2K")
    #expect(body["duration"]?.intValue == 5)
}

@Test func miniMaxVideoRequestAuthorizationOverridesConfiguredAuthOnCreateAndPoll() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task_override_auth"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/override-auth.mp4"}}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "configured-key", transport: transport))

    _ = try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "Override auth.",
        providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]],
        headers: ["Authorization": "Bearer override-key"]
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.headers["authorization"] == "Bearer override-key" })
    #expect(requests.allSatisfy { $0.headers["Authorization"] == nil })
}

@Test func miniMaxVideoAbortDuringPollingStopsBeforeStatusRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"task_id":"task_abort"}"#))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "video-key", transport: transport))
    let controller = AIAbortController()
    let generation = Task {
        try await provider.video("MiniMax-H3").generateVideo(VideoGenerationRequest(
            prompt: "Abort while polling.",
            providerOptions: [
                "minimax": ["pollIntervalMs": 5_000, "pollTimeoutMs": 10_000]
            ],
            abortSignal: controller.signal
        ))
    }

    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while await transport.requests().isEmpty, DispatchTime.now().uptimeNanoseconds < deadline {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(await transport.requests().count == 1)

    controller.abort(reason: "Stop MiniMax polling")
    do {
        _ = try await generation.value
        Issue.record("Expected MiniMax polling to stop with AIAbortError.")
    } catch let error as AIAbortError {
        #expect(error.reason == "Stop MiniMax polling")
    } catch {
        Issue.record("Expected AIAbortError, got \(error).")
    }

    #expect(await transport.requests().count == 1)
}
