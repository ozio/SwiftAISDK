import Foundation
import Testing
@testable import SwiftAISDK

@Test func WeeklyRemainingProviders20260913ByteDanceWebhookPrecedenceAndExpiry() async throws {
    let callbackCases: [(webhook: String?, raw: String?, expected: String?)] = [
        ("https://example.com/explicit", nil, "https://example.com/explicit"),
        (nil, nil, nil),
        (nil, "https://example.com/raw", "https://example.com/raw"),
        ("https://example.com/explicit", "https://example.com/raw", "https://example.com/explicit")
    ]

    for callbackCase in callbackCases {
        let transport = RecordingTransport(response: jsonResponse(#"{"id":"task-callback"}"#))
        let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: transport))
        let model = try #require(try provider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)
        var rawOptions: [String: JSONValue] = [:]
        if let raw = callbackCase.raw { rawOptions["callback_url"] = .string(raw) }

        _ = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
            request: VideoGenerationRequest(
                prompt: "callback",
                providerOptions: ["bytedance": .object(rawOptions)]
            ),
            webhookURL: callbackCase.webhook
        ))

        let request = try #require(await transport.requests().first)
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["callback_url"]?.stringValue == callbackCase.expected)
    }

    let asyncTransport = RecordingTransport(response: jsonResponse(
        #"{"id":"task-expired","status":"expired","error":{"code":"TaskExpired","message":"The task has expired."}}"#
    ))
    let asyncProvider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: asyncTransport))
    let asyncModel = try #require(try asyncProvider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)
    let status = try await asyncModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: ["taskId": "task-expired"]
    ))
    guard case let .failed(message, _, _) = status else {
        Issue.record("Expected expired ByteDance operation to be terminal")
        return
    }
    #expect(message == "Video generation expired. Task ID: task-expired. The task has expired.")

    let unaryTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task-expired"}"#),
        jsonResponse(#"{"id":"task-expired","status":"expired","error":{"message":"The task has expired."}}"#)
    ])
    let unaryProvider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: unaryTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "bytedance.video",
        message: "Video generation expired. Task ID: task-expired. The task has expired."
    )) {
        _ = try await unaryProvider.videoModel("seedance-1-0-pro-250528").generateVideo(VideoGenerationRequest(
            prompt: "expiry",
            providerOptions: ["bytedance": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
        ))
    }
}

@Test func WeeklyRemainingProviders20260913ByteDanceUnaryMetadataAndSafeTaskIDPaths() async throws {
    let taskID = "task/with?query=value#fragment"
    let unaryTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"task/with?query=value#fragment"}"#),
        jsonResponse(
            #"{"id":"task/with?query=value#fragment","status":"succeeded","content":{"video_url":"https://cdn.example.com/video.mp4","last_frame_url":"https://cdn.example.com/last-frame.png"},"usage":{"completion_tokens":42}}"#
        )
    ])
    let unaryProvider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: unaryTransport))
    let unaryResult = try await unaryProvider.videoModel("seedance-1-0-pro-250528").generateVideo(VideoGenerationRequest(
        prompt: "safe task ID",
        providerOptions: ["bytedance": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))

    #expect(unaryResult.urls == ["https://cdn.example.com/video.mp4"])
    #expect(unaryResult.providerMetadata["bytedance"]?["taskId"]?.stringValue == taskID)
    #expect(unaryResult.providerMetadata["bytedance"]?["usage"]?["completion_tokens"]?.intValue == 42)
    #expect(unaryResult.providerMetadata["bytedance"]?["lastFrameUrl"]?.stringValue == "https://cdn.example.com/last-frame.png")
    let unaryRequests = await unaryTransport.requests()
    #expect(unaryRequests[1].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task%2Fwith%3Fquery%3Dvalue%23fragment")

    let statusTransport = RecordingTransport(response: jsonResponse(
        #"{"id":"task/with?query=value#fragment","status":"running"}"#
    ))
    let statusProvider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: statusTransport))
    let statusModel = try #require(try statusProvider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)
    let pending = try await statusModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: ["taskId": .string(taskID)]
    ))
    guard case .pending = pending else {
        Issue.record("Expected ByteDance running operation to remain pending")
        return
    }
    #expect((await statusTransport.requests())[0].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/task%2Fwith%3Fquery%3Dvalue%23fragment")

    let dotSegmentTransport = RecordingTransport(response: jsonResponse(#"{"id":"..","status":"running"}"#))
    let dotSegmentProvider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "key", transport: dotSegmentTransport))
    let dotSegmentModel = try #require(try dotSegmentProvider.videoModel("seedance-1-0-pro-250528") as? any AsyncVideoModel)
    _ = try await dotSegmentModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: ["taskId": ".."]
    ))
    #expect((await dotSegmentTransport.requests())[0].url.absoluteString == "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks/%2E%2E")
}

@Test func WeeklyRemainingProviders20260913GladiaPreservesExpandedUtterances() async throws {
    let final = #"{"status":"done","result":{"metadata":{"audio_duration":2.4},"transcription":{"full_transcript":"hello world","languages":["en"],"utterances":[{"start":0,"end":1.2,"text":"hello","speaker":0,"confidence":0.98,"language":"en","words":[{"word":"hello","start":0,"end":1.2,"confidence":0.99}]},{"start":1.2,"end":2.4,"text":"world","speaker":"speaker-1"}]}}}"#
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-expanded"}"#),
        jsonResponse(final)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "key", transport: transport))
    let result = try await provider.transcriptionModel("default").transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav"
    ))

    let metadata = try #require(result.providerMetadata["gladia"])
    #expect(metadata == (try decodeJSONBody(Data(final.utf8))))
    let utterances = try #require(metadata["result"]?["transcription"]?["utterances"]?.arrayValue)
    #expect(utterances[0]["speaker"]?.intValue == 0)
    #expect(utterances[0]["confidence"]?.doubleValue == 0.98)
    #expect(utterances[0]["language"]?.stringValue == "en")
    #expect(utterances[0]["words"]?[0]?["word"]?.stringValue == "hello")
    #expect(utterances[0]["words"]?[0]?["confidence"]?.doubleValue == 0.99)
    #expect(utterances[1]["speaker"]?.stringValue == "speaker-1")
}

@Test func WeeklyRemainingProviders20260913GladiaRejectsMalformedExpandedUtterances() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-invalid"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":1},"transcription":{"full_transcript":"bad","languages":["en"],"utterances":[{"start":0,"end":1,"text":"bad","speaker":true}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "key", transport: transport))

    await #expect(throws: AIError.invalidResponse(
        provider: "gladia.transcription",
        message: "Gladia transcription result is invalid."
    )) {
        _ = try await provider.transcriptionModel("default").transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            mimeType: "audio/wav"
        ))
    }
}

@Test func WeeklyRemainingProviders20260913KlingWebhookMatrixAcrossAllEndpoints() async throws {
    let endpointCases: [(modelID: String, endpoint: String, request: VideoGenerationRequest)] = [
        (
            "kling-v2.6-t2v",
            "/v1/videos/text2video",
            VideoGenerationRequest(prompt: "text")
        ),
        (
            "kling-v2.6-i2v",
            "/v1/videos/image2video",
            VideoGenerationRequest(prompt: "image", image: ImageInputFile(url: "https://example.com/frame.png"))
        ),
        (
            "kling-v1.6-i2v",
            "/v1/videos/multi-image2video",
            VideoGenerationRequest(
                prompt: "references",
                inputReferences: [
                    ImageInputFile(url: "https://example.com/one.png"),
                    ImageInputFile(url: "https://example.com/two.png")
                ]
            )
        ),
        (
            "kling-v2.6-motion-control",
            "/v1/videos/motion-control",
            VideoGenerationRequest(
                prompt: "motion",
                image: ImageInputFile(url: "https://example.com/person.png"),
                providerOptions: ["klingai": [
                    "videoUrl": "https://example.com/reference.mp4",
                    "characterOrientation": "image",
                    "mode": "std"
                ]]
            )
        )
    ]
    let callbackCases: [(webhook: String?, raw: String?, expected: String?)] = [
        ("https://example.com/explicit", nil, "https://example.com/explicit"),
        (nil, nil, nil),
        (nil, "https://example.com/raw", "https://example.com/raw"),
        ("https://example.com/explicit", "https://example.com/raw", "https://example.com/explicit")
    ]

    for endpointCase in endpointCases {
        for callbackCase in callbackCases {
            let transport = RecordingTransport(response: jsonResponse(
                #"{"code":0,"message":"ok","data":{"task_id":"task-callback"}}"#,
                headers: ["x-kling-request": "start"]
            ))
            let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "key", transport: transport))
            let model = try #require(try provider.videoModel(endpointCase.modelID) as? any AsyncVideoModel)
            #expect(!model.supportsVideoGenerationWebhooks)
            var request = endpointCase.request
            var options = request.providerOptions["klingai"]?.objectValue ?? [:]
            if let raw = callbackCase.raw { options["callback_url"] = .string(raw) }
            request.providerOptions["klingai"] = .object(options)

            let started = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
                request: request,
                webhookURL: callbackCase.webhook
            ))

            #expect(started.operation["taskId"]?.stringValue == "task-callback")
            #expect(started.operation["endpointPath"]?.stringValue == endpointCase.endpoint)
            #expect(started.responseMetadata.headers["x-kling-request"] == "start")
            let sent = try #require(await transport.requests().first)
            #expect(sent.url.path == endpointCase.endpoint)
            let body = try decodeJSONBody(try #require(sent.body))
            #expect(body["callback_url"]?.stringValue == callbackCase.expected)
            if endpointCase.endpoint == "/v1/videos/multi-image2video" {
                #expect(body["image_list"]?.arrayValue?.count == 2)
            }
        }
    }
}

@Test func WeeklyRemainingProviders20260913KlingStatusLifecycleAndSafeOperation() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task/one","task_status":"processing"}}"#),
        jsonResponse(
            #"{"code":0,"message":"ok","data":{"task_id":"task/one","task_status":"succeed","task_result":{"videos":[{"id":"video-1","url":"https://cdn.example.com/video.mp4","watermark_url":"https://cdn.example.com/watermarked.mp4","duration":"5.0"}]}}}"#,
            headers: ["x-kling-request": "status"]
        )
    ])
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "key", transport: transport))
    let model = try #require(try provider.videoModel("kling-v2.6-t2v") as? any AsyncVideoModel)
    let operation: JSONValue = [
        "taskId": "task/one",
        "endpointPath": "/v1/videos/text2video"
    ]

    let pending = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: operation))
    guard case .pending = pending else {
        Issue.record("Expected Kling processing operation to remain pending")
        return
    }
    let completed = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: operation))
    guard case let .completed(result) = completed else {
        Issue.record("Expected Kling successful operation to complete")
        return
    }
    #expect(result.urls == ["https://cdn.example.com/video.mp4"])
    #expect(result.providerMetadata["klingai"]?["videos"]?[0]?["watermarkUrl"]?.stringValue == "https://cdn.example.com/watermarked.mp4")
    #expect(result.responseMetadata.headers["x-kling-request"] == "status")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString.hasSuffix("/v1/videos/text2video/task%2Fone"))

    let invalidTransport = RecordingTransport(response: jsonResponse("{}"))
    let invalidProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "key", transport: invalidTransport))
    let invalidModel = try #require(try invalidProvider.videoModel("kling-v2.6-t2v") as? any AsyncVideoModel)
    await #expect(throws: AIError.self) {
        _ = try await invalidModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: [
            "taskId": "task",
            "endpointPath": "//attacker.example/path"
        ]))
    }
    #expect((await invalidTransport.requests()).isEmpty)
}

@Test func WeeklyRemainingProviders20260913KlingFiltersMetadataToURLBearingVideos() async throws {
    let completedResponse = jsonResponse(
        #"{"code":0,"message":"ok","data":{"task_id":"task-filter","task_status":"succeed","task_result":{"videos":[{"id":"missing-url","watermark_url":"https://cdn.example.com/missing-watermark.mp4","duration":"5.0"},{"id":"empty-url","url":""},{"url":"https://cdn.example.com/valid.mp4","watermark_url":"","duration":""}]}}}"#
    )
    let statusTransport = RecordingTransport(response: completedResponse)
    let statusProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "key", transport: statusTransport))
    let statusModel = try #require(try statusProvider.videoModel("kling-v2.6-t2v") as? any AsyncVideoModel)
    let status = try await statusModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: [
        "taskId": "task-filter",
        "endpointPath": "/v1/videos/text2video"
    ]))
    guard case let .completed(statusResult) = status else {
        Issue.record("Expected URL-bearing Kling video to complete")
        return
    }
    #expect(statusResult.urls == ["https://cdn.example.com/valid.mp4"])
    #expect(statusResult.providerMetadata["klingai"]?["videos"] == [[
        "id": "",
        "url": "https://cdn.example.com/valid.mp4"
    ]])

    let unaryTransport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"task-filter","task_status":"submitted"}}"#),
        completedResponse
    ])
    let unaryProvider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "key", transport: unaryTransport))
    let unaryResult = try await unaryProvider.videoModel("kling-v2.6-t2v").generateVideo(VideoGenerationRequest(
        prompt: "filter metadata",
        providerOptions: ["klingai": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))
    #expect(unaryResult.urls == ["https://cdn.example.com/valid.mp4"])
    #expect(unaryResult.providerMetadata["klingai"]?["videos"] == [[
        "id": "",
        "url": "https://cdn.example.com/valid.mp4"
    ]])
}

@Test func WeeklyRemainingProviders20260913MiniMaxSafeOperationAndCompletedStatus() async throws {
    let taskID = "task/with?query=value#fragment"
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task/with?query=value#fragment"}"#, headers: ["x-minimax-request-id": "start"]),
        jsonResponse(
            #"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/final.mp4"},"duration":5,"ratio":"16:9","resolution":"2K","usage":{"total_seconds":5,"input_seconds":1,"output_seconds":4}}}"#,
            headers: ["x-minimax-request-id": "status"]
        )
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "key", transport: transport))
    let model = try #require(try provider.videoModel("MiniMax-H3") as? any AsyncVideoModel)
    #expect(!model.supportsVideoGenerationWebhooks)
    let duplicateVideo = ImageInputFile(url: "https://example.com/video.mp4", mediaType: "video/mp4")
    let request = VideoGenerationRequest(
        prompt: "private prompt",
        inputReferences: [
            ImageInputFile(url: "https://example.com/audio.mp3", mediaType: "audio/mpeg"),
            ImageInputFile(url: "https://example.com/image.png", mediaType: "image/png"),
            duplicateVideo,
            ImageInputFile(data: Data("inline-video".utf8), mediaType: "video/mp4"),
            duplicateVideo,
            ImageInputFile(url: "https://example.com/capped.mp4", mediaType: "video/mp4"),
            ImageInputFile(url: "https://example.com/untyped.png")
        ]
    )

    let started = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(
        request: request,
        webhookURL: "https://example.com/callback"
    ))
    #expect(started.operation == [
        "taskId": .string(taskID),
        "resolvedInputs": .object([
            "imageCount": 2,
            "referenceVideoIndices": [2, 4]
        ])
    ])
    #expect(started.responseMetadata.headers["x-minimax-request-id"] == "start")
    let serialized = try encodeJSONBody(started.operation)
    let serializedText = String(data: serialized, encoding: .utf8) ?? ""
    #expect(!serializedText.contains("https://"))
    #expect(!serializedText.contains("private prompt"))
    #expect(!serializedText.contains(Data("inline-video".utf8).base64EncodedString()))
    let restored = try decodeJSONBody(serialized)

    let status = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: restored))
    guard case let .completed(result) = status else {
        Issue.record("Expected MiniMax operation to complete")
        return
    }
    #expect(result.urls == ["https://cdn.example.com/final.mp4"])
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["imageCount"]?.intValue == 2)
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["referenceVideoIndices"]?.arrayValue?.compactMap(\.intValue) == [2, 4])
    #expect(result.providerMetadata["minimax"]?["usage"]?["outputSeconds"]?.intValue == 4)
    #expect(result.responseMetadata.headers["x-minimax-request-id"] == "status")

    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["callback_url"]?.stringValue == "https://example.com/callback")
    #expect(requests[1].url.absoluteString == "https://api.minimax.io/v2/query/video_generation/task%2Fwith%3Fquery%3Dvalue%23fragment")
}

@Test func WeeklyRemainingProviders20260913MiniMaxPendingErrorsAbortAndOperationValidation() async throws {
    let operation: JSONValue = [
        "taskId": "task-1",
        "resolvedInputs": ["imageCount": 0, "referenceVideoIndices": []]
    ]
    let controller = AIAbortController()
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"task":{"status":"running"}}"#),
        jsonResponse(#"{"task":{"status":"failed","error":{"code":1027,"message":"Rejected"}}}"#, headers: ["x-status": "failed"])
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "key", transport: transport))
    let model = try #require(try provider.videoModel("MiniMax-H3") as? any AsyncVideoModel)

    let pending = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: operation,
        abortSignal: controller.signal
    ))
    guard case .pending = pending else {
        Issue.record("Expected MiniMax running operation to remain pending")
        return
    }
    let failed = try await model.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: operation))
    guard case let .failed(message, _, response) = failed else {
        Issue.record("Expected MiniMax failure to be terminal")
        return
    }
    #expect(message == "MiniMax video generation failed: Rejected (1027). Task ID: task-1")
    #expect(response.headers["x-status"] == "failed")
    #expect((await transport.requests())[0].abortSignal === controller.signal)

    let invalidTransport = RecordingTransport(response: jsonResponse("{}"))
    let invalidProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "key", transport: invalidTransport))
    let invalidModel = try #require(try invalidProvider.videoModel("MiniMax-H3") as? any AsyncVideoModel)
    await #expect(throws: AIError.self) {
        _ = try await invalidModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(operation: [
            "taskId": "task",
            "resolvedInputs": ["imageCount": 10, "referenceVideoIndices": []]
        ]))
    }
    #expect((await invalidTransport.requests()).isEmpty)
}

@Test func WeeklyRemainingProviders20260913MiniMaxRedirectSafetyAndUnaryCompatibility() async throws {
    let operation: JSONValue = [
        "taskId": "task-redirect",
        "resolvedInputs": ["imageCount": 0, "referenceVideoIndices": []]
    ]
    let redirectTransport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 302, headers: ["Location": "https://cdn.example.com/status"]),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/final.mp4"}}}"#)
    ])
    let redirectProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "key",
        videoBaseURL: "https://video.minimax.example.com",
        headers: ["X-Provider-Secret": "provider"],
        transport: redirectTransport
    ))
    let redirectModel = try #require(try redirectProvider.videoModel("MiniMax-H3") as? any AsyncVideoModel)
    _ = try await redirectModel.videoGenerationStatus(VideoGenerationOperationStatusRequest(
        operation: operation,
        headers: ["X-Request-Secret": "request"]
    ))
    let redirectRequests = await redirectTransport.requests()
    #expect(normalizeHeaders(redirectRequests[0].headers)["authorization"] == "Bearer key")
    #expect(normalizeHeaders(redirectRequests[0].headers)["x-request-secret"] == "request")
    #expect(normalizeHeaders(redirectRequests[1].headers)["authorization"] == nil)
    #expect(normalizeHeaders(redirectRequests[1].headers)["x-provider-secret"] == nil)
    #expect(normalizeHeaders(redirectRequests[1].headers)["x-request-secret"] == nil)

    let unaryTransport = RecordingTransport(responses: [
        jsonResponse(#"{"task_id":"task-unary"}"#),
        jsonResponse(#"{"task":{"status":"succeeded","content":{"url":"https://cdn.example.com/unary.mp4"}}}"#)
    ])
    let unaryProvider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "key", transport: unaryTransport))
    let videoURL = "https://example.com/reference.mp4"
    let result = try await unaryProvider.videoModel("MiniMax-H3").generateVideo(VideoGenerationRequest(
        prompt: "unary",
        inputReferences: [ImageInputFile(url: videoURL, mediaType: "video/mp4")],
        providerOptions: ["minimax": ["pollIntervalMs": 1, "pollTimeoutMs": 1_000]]
    ))
    #expect(result.urls == ["https://cdn.example.com/unary.mp4"])
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["imageCount"]?.intValue == 0)
    #expect(result.providerMetadata["minimax"]?["resolvedInputs"]?["referenceVideoUrls"]?.arrayValue?.compactMap(\.stringValue) == [videoURL])
}
