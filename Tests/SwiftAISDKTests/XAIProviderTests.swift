import Foundation
import Testing
@testable import SwiftAISDK

@Test func xAISpeechAndTranscriptionUseNativeAudioEndpoints() async throws {
    let speechTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/wav", "xai-request-id": "speech-request", "x-trace-id": "trace-binary"],
        body: Data("xai-speech".utf8)
    ))
    let speechProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: speechTransport))
    let speechModel = try speechProvider.speech()

    let speech = try await speechModel.speak(SpeechRequest(
        text: "Hello [pause] world",
        voice: "eve",
        format: "wav",
        speed: 1.1,
        language: "ja",
        instructions: "speak softly",
        providerOptions: [
            "xai": [
                "sampleRate": 24_000,
                "bitRate": 128_000,
                "optimizeStreamingLatency": 2,
                "textNormalization": true
            ]
        ]
    ))

    #expect(speech.audio == Data("xai-speech".utf8))
    #expect(speech.contentType == "audio/wav")
    #expect(speech.warnings == [
        AIWarning(type: "unsupported", feature: "instructions", message: "xAI speech models do not support the `instructions` option. Use xAI speech tags in `text` to control delivery."),
        AIWarning(type: "unsupported", feature: "providerOptions", message: "xAI `bitRate` is supported only for mp3 output. It was ignored.")
    ])
    #expect(speech.responseMetadata.headers["xai-request-id"] == "speech-request")
    #expect(speech.providerMetadata["xai"]?["traceId"]?.stringValue == "trace-binary")
    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://api.x.ai/v1/tts")
    #expect(speechRequest.headers["authorization"] == "Bearer xai-key")
    #expect(speechRequest.headers["user-agent"] == "ai-sdk/xai/4.0.43")
    let speechBody = try decodeJSONBody(try #require(speechRequest.body))
    #expect(speechBody["text"]?.stringValue == "Hello [pause] world")
    #expect(speechBody["voice_id"]?.stringValue == "eve")
    #expect(speechBody["language"]?.stringValue == "ja")
    #expect(speechBody["speed"]?.doubleValue == 1.1)
    #expect(speechBody["output_format"]?["codec"]?.stringValue == "wav")
    #expect(speechBody["output_format"]?["sample_rate"]?.intValue == 24_000)
    #expect(speechBody["output_format"]?["bit_rate"] == nil)
    #expect(speechBody["optimize_streaming_latency"]?.intValue == 2)
    #expect(speechBody["text_normalization"]?.boolValue == true)

    let transcriptionTransport = RecordingTransport(response: jsonResponse("""
    {"text":"hello xai","language":"en","duration":1.25,"words":[{"text":"hello","start":0.1,"end":0.5},{"text":"xai","start":0.7,"end":1.2}]}
    """, headers: ["xai-request-id": "stt-request"]))
    let transcriptionProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcription()
    let transcription = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "xai": [
                "audioFormat": "pcm",
                "sampleRate": 16_000,
                "language": "en",
                "format": true,
                "multichannel": true,
                "channels": 2,
                "diarize": true,
                "keyterm": ["Grok", "xAI"],
                "fillerWords": true
            ]
        ]
    ))

    #expect(transcription.text == "hello xai")
    #expect(transcription.language == "en")
    #expect(transcription.durationInSeconds == 1.25)
    #expect(transcription.segments == [
        TranscriptionSegment(text: "hello", startSecond: 0.1, endSecond: 0.5),
        TranscriptionSegment(text: "xai", startSecond: 0.7, endSecond: 1.2)
    ])
    #expect(transcription.responseMetadata.headers["xai-request-id"] == "stt-request")
    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.url.absoluteString == "https://api.x.ai/v1/stt")
    #expect(transcriptionRequest.headers["authorization"] == "Bearer xai-key")
    #expect(transcriptionRequest.headers["user-agent"] == "ai-sdk/xai/4.0.43")
    #expect(transcriptionRequest.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let transcriptionBody = String(data: try #require(transcriptionRequest.body), encoding: .utf8) ?? ""
    #expect(transcriptionBody.contains("name=\"audio_format\""))
    #expect(transcriptionBody.contains("pcm"))
    #expect(transcriptionBody.contains("name=\"sample_rate\""))
    #expect(transcriptionBody.contains("16000"))
    #expect(transcriptionBody.contains("name=\"keyterm\""))
    #expect(transcriptionBody.contains("Grok"))
    #expect(transcriptionBody.contains("xAI"))
    #expect(transcriptionBody.contains("name=\"file\"; filename=\"audio.wav\""))
    #expect(transcription.requestMetadata.body?["audio_format"]?.stringValue == "pcm")
    #expect(transcription.requestMetadata.body?["sample_rate"]?.intValue == 16_000)
    #expect(transcription.requestMetadata.body?["keyterm"]?[0]?.stringValue == "Grok")
    #expect(transcription.requestMetadata.body?["file"]?["filename"]?.stringValue == "audio.wav")
}

@Test func xAIAudioProviderOptionsValidateLikeUpstreamSchemas() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.sampleRate", message: "xAI sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000.")) {
        _ = try await provider.speech().speak(SpeechRequest(text: "Hi", providerOptions: ["xai": ["sampleRate": 12_345]]))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.optimizeStreamingLatency", message: "xAI optimizeStreamingLatency must be 0, 1, or 2.")) {
        _ = try await provider.speech().speak(SpeechRequest(text: "Hi", providerOptions: ["xai": ["optimizeStreamingLatency": 3]]))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.withTimestamps", message: "xAI withTimestamps must be a boolean.")) {
        _ = try await provider.speech().speak(SpeechRequest(text: "Hi", providerOptions: ["xai": ["withTimestamps": "yes"]]))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.replace", message: "xAI replace must be an object with string values.")) {
        _ = try await provider.speech().speak(SpeechRequest(text: "Hi", providerOptions: ["xai": ["replace": ["xAI": true]]]))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.audioFormat", message: "xAI audioFormat must be pcm, mulaw, or alaw.")) {
        _ = try await provider.transcription().transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), providerOptions: ["xai": ["audioFormat": "mp3"]]))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.channels", message: "xAI channels must be an integer from 2 to 8.")) {
        _ = try await provider.transcription().transcribe(AudioTranscriptionRequest(audio: Data("wav".utf8), providerOptions: ["xai": ["channels": 1]]))
    }
}

@Test func xAIAudioProviderOptionsAreNullishLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/mpeg"],
        body: Data("audio".utf8)
    ))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    let result = try await provider.speech().speak(SpeechRequest(
        text: "Hi",
        providerOptions: [
            "xai": [
                "sampleRate": .null,
                "bitRate": .null,
                "optimizeStreamingLatency": .null,
                "textNormalization": .null,
                "withTimestamps": .null,
                "replace": .null
            ]
        ]
    ))

    #expect(result.audio == Data("audio".utf8))
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["output_format"]?["sample_rate"] == nil)
    #expect(body["output_format"]?["bit_rate"] == nil)
    #expect(body["optimize_streaming_latency"] == nil)
    #expect(body["text_normalization"] == nil)
    #expect(body["with_timestamps"] == nil)
    #expect(body["replace"] == nil)

    let transcriptionTransport = RecordingTransport(response: jsonResponse(#"{"text":"hello"}"#))
    let transcriptionProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transcriptionTransport))
    _ = try await transcriptionProvider.transcription().transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        providerOptions: [
            "xai": [
                "audioFormat": .null,
                "sampleRate": .null,
                "language": .null,
                "format": .null,
                "multichannel": .null,
                "channels": .null,
                "diarize": .null,
                "keyterm": .null,
                "fillerWords": .null
            ]
        ]
    ))

    let transcriptionRequest = try #require((await transcriptionTransport.requests()).first)
    let transcriptionBody = String(data: try #require(transcriptionRequest.body), encoding: .utf8) ?? ""
    for field in ["audio_format", "sample_rate", "language", "format", "multichannel", "channels", "diarize", "keyterm", "filler_words"] {
        #expect(!transcriptionBody.contains("name=\"\(field)\""))
    }
}

@Test func xAISpeechTimestampsReplacementsMetadataAndErrorsMatchUpstream() async throws {
    let timestampTransport = RecordingTransport(response: jsonResponse(#"{"audio":"AQIDBA==","content_type":"audio/mpeg","duration":1.19,"audio_timestamps":{"graph_chars":["H","i"],"graph_times":[[0.04,0.06],[0.06,0.1]]}}"#, headers: ["x-trace-id": "trace-timestamps"]))
    let timestampProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: timestampTransport))

    let result = try await timestampProvider.speech().speak(SpeechRequest(
        text: "Hi xAI",
        providerOptions: [
            "xai": [
                "withTimestamps": true,
                "replace": ["xAI": "ex eye"]
            ]
        ]
    ))

    #expect(result.audio == Data([1, 2, 3, 4]))
    #expect(result.contentType == "audio/mpeg")
    #expect(result.providerMetadata["xai"]?["traceId"]?.stringValue == "trace-timestamps")
    #expect(result.providerMetadata["xai"]?["duration"]?.doubleValue == 1.19)
    #expect(result.providerMetadata["xai"]?["contentType"]?.stringValue == "audio/mpeg")
    #expect(result.providerMetadata["xai"]?["audioTimestamps"]?["graphChars"]?[1]?.stringValue == "i")
    #expect(result.providerMetadata["xai"]?["audioTimestamps"]?["graphTimes"]?[0]?[0]?.doubleValue == 0.04)
    #expect(result.responseMetadata.body?["audio"]?.stringValue == "AQIDBA==")
    let body = try decodeJSONBody(try #require((await timestampTransport.requests()).first?.body))
    #expect(body["with_timestamps"]?.boolValue == true)
    #expect(body["replace"]?["xAI"]?.stringValue == "ex eye")

    let errorTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["x-trace-id": "trace-error"],
        body: Data(#"{"error":"speed must be between 0.7 and 1.5"}"#.utf8)
    ))
    let errorProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: errorTransport))
    await #expect(throws: AIError.apiCall(
        provider: "xai.speech",
        statusCode: 400,
        body: "speed must be between 0.7 and 1.5",
        headers: ["x-trace-id": "trace-error"]
    )) {
        _ = try await errorProvider.speech().speak(SpeechRequest(text: "Hi", speed: 2))
    }
}

@Test func xAIImageAndVideoUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"data":[{"url":"https://x.ai/image.png","revised_prompt":"cat!"}],"usage":{"cost_in_usd_ticks":123}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("xai-png".utf8))
    ])
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", aspectRatio: "16:9", count: 2, extraBody: ["quality": "high", "output_format": "png"]))

    #expect(image.urls == ["https://x.ai/image.png"])
    #expect(image.base64Images == [Data("xai-png".utf8).base64EncodedString()])
    #expect(image.providerMetadata["xai"]?["images"]?[0]?["revisedPrompt"]?.stringValue == "cat!")
    #expect(image.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 123)
    let imageRequests = await imageTransport.requests()
    #expect(imageRequests.count == 2)
    let imageRequest = try #require(imageRequests.first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/generations")
    #expect(imageRequest.headers["authorization"] == "Bearer xai-key")
    #expect(imageRequest.headers["user-agent"] == "ai-sdk/xai/4.0.43")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["n"]?.intValue == 2)
    #expect(imageBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(imageBody["response_format"]?.stringValue == "b64_json")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageRequests[1].method == "GET")
    #expect(imageRequests[1].headers["authorization"] == nil)
    #expect(imageRequests[1].headers["user-agent"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","duration":6,"respect_moderation":true},"progress":100}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running", aspectRatio: "16:9", durationSeconds: 6, resolution: "1280x720", extraBody: ["pollIntervalMs": 1]))

    #expect(video.urls == ["https://x.ai/video.mp4"])
    #expect(video.operationID == "vid-1")
    #expect(video.providerMetadata["xai"]?["requestId"]?.stringValue == "vid-1")
    #expect(video.providerMetadata["xai"]?["videoUrl"]?.stringValue == "https://x.ai/video.mp4")
    #expect(video.providerMetadata["xai"]?["duration"]?.intValue == 6)
    #expect(video.providerMetadata["xai"]?["progress"]?.intValue == 100)
    let requests = await videoTransport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    #expect(requests[0].headers["authorization"] == "Bearer xai-key")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/xai/4.0.43")
    let videoBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(videoBody["model"]?.stringValue == "grok-2-video")
    #expect(videoBody["prompt"]?.stringValue == "cat running")
    #expect(videoBody["duration"]?.intValue == 6)
    #expect(videoBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.x.ai/v1/videos/vid-1")
    #expect(requests[1].headers["authorization"] == "Bearer xai-key")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/xai/4.0.43")

    let editTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"edit-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/edit.mp4","respect_moderation":true}}"#)
    ])
    let editProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: editTransport))
    let editModel = try editProvider.videoModel("grok-2-video")

    let edit = try await editModel.generateVideo(VideoGenerationRequest(
        prompt: "make it brighter",
        aspectRatio: "16:9",
        durationSeconds: 6,
        extraBody: ["videoUrl": "https://x.ai/source.mp4", "pollIntervalMs": 1]
    ))

    #expect(edit.urls == ["https://x.ai/edit.mp4"])
    #expect(edit.warnings.contains(AIWarning(type: "unsupported", feature: "duration", message: "xAI video editing does not support custom duration.")))
    #expect(edit.warnings.contains(AIWarning(type: "unsupported", feature: "aspectRatio", message: "xAI video editing does not support custom aspect ratio.")))
    let editRequests = await editTransport.requests()
    #expect(editRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/edits")
    #expect(editRequests[0].headers["authorization"] == "Bearer xai-key")
    #expect(editRequests[0].headers["user-agent"] == "ai-sdk/xai/4.0.43")
    #expect(editRequests[1].headers["authorization"] == "Bearer xai-key")
    #expect(editRequests[1].headers["user-agent"] == "ai-sdk/xai/4.0.43")
    let editBody = try decodeJSONBody(try #require(editRequests[0].body))
    #expect(editBody["video"]?["url"]?.stringValue == "https://x.ai/source.mp4")
    #expect(editBody["aspect_ratio"] == nil)
    #expect(editBody["duration"] == nil)
}

@Test func xAIImageReportsModerationBlocksBeforeDownloading() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"url":null,"b64_json":null,"respect_moderation":false}]}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    await #expect(throws: AIError.invalidResponse(
        provider: "xai.image",
        message: "Image generation was blocked due to a content policy violation."
    )) {
        _ = try await provider.imageModel("grok-2-image").generateImage(ImageGenerationRequest(prompt: "blocked"))
    }

    #expect(await transport.requests().count == 1)
}

@Test func xAIImageAndVideoWarningsProviderOptionsAndStandardInputsMatchUpstream() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"xai-image","revised_prompt":"revised"}],"usage":{"cost_in_usd_ticks":321}}"#))
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        seed: 42,
        mask: ImageInputFile(data: Data([9, 9]), mediaType: "image/png"),
        providerOptions: ["xai": .object(["aspect_ratio": "1:1", "quality": "high"])]
    ))

    #expect(image.base64Images == ["xai-image"])
    #expect(image.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "This model does not support the `size` option. Use `aspectRatio` instead."),
        AIWarning(type: "unsupported", feature: "seed"),
        AIWarning(type: "unsupported", feature: "mask")
    ])
    #expect(image.providerMetadata["xai"]?["images"]?[0]?["revisedPrompt"]?.stringValue == "revised")
    #expect(image.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 321)
    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["aspect_ratio"]?.stringValue == "1:1")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["size"] == nil)
    #expect(imageBody["seed"] == nil)
    #expect(imageBody["mask"] == nil)
    #expect(imageBody["xai"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-opts"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/generated.mp4","duration":7,"respect_moderation":true},"usage":{"cost_in_usd_ticks":654},"progress":99}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"),
        resolution: "854x480",
        fps: 30,
        seed: 7,
        count: 2,
        providerOptions: ["xai": .object(["pollIntervalMs": 1, "pollTimeoutMs": 1000])]
    ))

    #expect(video.urls == ["https://x.ai/generated.mp4"])
    #expect(video.warnings == [
        AIWarning(type: "unsupported", feature: "fps", message: "xAI video models do not support custom FPS."),
        AIWarning(type: "unsupported", feature: "seed", message: "xAI video models do not support seed."),
        AIWarning(type: "unsupported", feature: "n", message: "xAI video models do not support generating multiple videos per call. Only 1 video will be generated.")
    ])
    #expect(video.providerMetadata["xai"]?["requestId"]?.stringValue == "video-opts")
    #expect(video.providerMetadata["xai"]?["videoUrl"]?.stringValue == "https://x.ai/generated.mp4")
    #expect(video.providerMetadata["xai"]?["duration"]?.intValue == 7)
    #expect(video.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 654)
    #expect(video.providerMetadata["xai"]?["progress"]?.intValue == 99)
    let videoBody = try decodeJSONBody(try #require((await videoTransport.requests()).first?.body))
    #expect(videoBody["resolution"]?.stringValue == "480p")
    #expect(videoBody["image"]?["url"]?.stringValue == "data:image/png;base64,\(Data([137, 80, 78, 71]).base64EncodedString())")
    #expect(videoBody["fps"] == nil)
    #expect(videoBody["seed"] == nil)
    #expect(videoBody["n"] == nil)
    #expect(videoBody["xai"] == nil)
}

@Test func xAIMapsNestedImageEditAndVideoOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let imageProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("grok-2-image")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        extraBody: [
            "xai": .object([
                "aspect_ratio": "1:1",
                "output_format": "png",
                "sync_mode": true,
                "resolution": "2k",
                "quality": "high",
                "user": "user-1"
            ])
        ]
    ))

    #expect(image.base64Images == ["edited-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.x.ai/v1/images/edits")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "grok-2-image")
    #expect(imageBody["aspect_ratio"]?.stringValue == "1:1")
    #expect(imageBody["output_format"]?.stringValue == "png")
    #expect(imageBody["sync_mode"]?.boolValue == true)
    #expect(imageBody["resolution"]?.stringValue == "2k")
    #expect(imageBody["quality"]?.stringValue == "high")
    #expect(imageBody["user"]?.stringValue == "user-1")
    #expect(imageBody["images"]?[0]?["url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["images"]?[0]?["type"]?.stringValue == "image_url")
    #expect(imageBody["images"]?[1]?["url"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(imageBody["xai"] == nil)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"r2v-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/r2v.mp4","respect_moderation":true}}"#)
    ])
    let videoProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("grok-2-video")

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "reference scene",
        aspectRatio: "16:9",
        extraBody: [
            "xai": .object([
                "mode": "reference-to-video",
                "referenceImageUrls": ["https://example.com/ref-1.png", "https://example.com/ref-2.png"],
                "resolution": "720p",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1000
            ])
        ]
    ))

    let videoRequests = await videoTransport.requests()
    #expect(videoRequests[0].url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let videoBody = try decodeJSONBody(try #require(videoRequests[0].body))
    #expect(videoBody["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/ref-1.png")
    #expect(videoBody["reference_images"]?[1]?["url"]?.stringValue == "https://example.com/ref-2.png")
    #expect(videoBody["resolution"]?.stringValue == "720p")
    #expect(videoBody["xai"] == nil)
    #expect(videoBody["pollIntervalMs"] == nil)
}

@Test func xAIVideoMapsFrameImagesLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"frame-images"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/frame-images.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(url: "https://example.com/image-input.png"),
        frameImages: [
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/first.png"), frameType: .firstFrame),
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/last.png"), frameType: .lastFrame)
        ],
        providerOptions: [
            "xai": [
                "referenceImageUrls": ["https://example.com/legacy-reference.png"],
                "pollIntervalMs": 1
            ]
        ]
    ))

    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "frameImages",
        message: "xAI video models do not support last_frame frameImages. The last_frame image will be ignored."
    )))
    let request = try #require((await transport.requests()).first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["image"]?["url"]?.stringValue == "https://example.com/first.png")
    #expect(body["reference_images"] == nil)
}

@Test func xAIVideoMapsFileFrameImageLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"file-frame"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/file-frame.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        frameImages: [
            VideoFrameImage(image: ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png"), frameType: .firstFrame)
        ],
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image"]?["url"]?.stringValue == "data:image/png;base64,iVBORw==")
}

@Test func xAIVideoMapsInputReferencesLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"input-references"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/input-references.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        inputReferences: [
            ImageInputFile(url: "https://example.com/ref-1.png"),
            ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")
        ],
        providerOptions: [
            "xai": [
                "referenceImageUrls": ["https://example.com/legacy-reference.png"],
                "pollIntervalMs": 1
            ]
        ]
    ))

    let request = try #require((await transport.requests()).first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/videos/generations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/ref-1.png")
    #expect(body["reference_images"]?[1]?["url"]?.stringValue == "data:image/png;base64,iVBORw==")
}

@Test func xAIVideo15Maps1080pReferenceVoicesAndModelWarningsLikeUpstream() async throws {
    let referenceTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"r2v-1080"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/r2v-1080.mp4","respect_moderation":true}}"#)
    ])
    let referenceProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: referenceTransport))
    let referenceResult = try await referenceProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
        prompt: "talking cat",
        inputReferences: [ImageInputFile(url: "https://example.com/cat.png", mediaType: "image/png")],
        resolution: "1920x1080",
        providerOptions: ["xai": ["referenceVoiceIds": ["eve", "ara"], "pollIntervalMs": 1]]
    ))

    let referenceBody = try decodeJSONBody(try #require((await referenceTransport.requests()).first?.body))
    #expect(referenceBody["resolution"]?.stringValue == "720p")
    #expect(referenceBody["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/cat.png")
    #expect(referenceBody["reference_audios"]?[0]?["voice_id"]?.stringValue == "eve")
    #expect(referenceBody["reference_audios"]?[1]?["voice_id"]?.stringValue == "ara")
    #expect(referenceBody["referenceVoiceIds"] == nil)
    #expect(referenceResult.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "resolution",
        message: "xAI reference-to-video is limited to 720p. The request was downgraded from 1080p to 720p."
    )))

    let nativeTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"t2v-1080"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/t2v-1080.mp4","respect_moderation":true}}"#)
    ])
    let nativeProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: nativeTransport))
    let nativeResult = try await nativeProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        resolution: "1920x1080",
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))
    let nativeBody = try decodeJSONBody(try #require((await nativeTransport.requests()).first?.body))
    #expect(nativeBody["resolution"]?.stringValue == "1080p")
    #expect(nativeResult.warnings.isEmpty)

    let legacyTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"legacy-1080"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/legacy-1080.mp4","respect_moderation":true}}"#)
    ])
    let legacyProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: legacyTransport))
    let legacyResult = try await legacyProvider.videoModel("grok-imagine-video").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": ["resolution": "1080p", "pollIntervalMs": 1]]
    ))
    #expect(legacyResult.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "resolution",
        message: "xAI model \"grok-imagine-video\" does not support 1080p. Use \"grok-imagine-video-1.5\" for 1080p, or a lower resolution. The request was sent with 1080p."
    )))
}

@Test func xAIVideoDoesNotRouteNonImageReferencesOrVoicesToReferenceMode() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"non-image-reference"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/non-image-reference.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let result = try await provider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        inputReferences: [
            ImageInputFile(url: "https://example.com/voice.mp3", mediaType: "audio/mpeg"),
            ImageInputFile(url: "https://example.com/source.mp4", mediaType: "video/mp4")
        ],
        providerOptions: ["xai": ["referenceVoiceIds": ["eve"], "pollIntervalMs": 1]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reference_images"] == nil)
    #expect(body["reference_audios"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "inputReferences",
        message: "xAI reference-to-video requires at least one image reference. The references were ignored."
    )))
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "referenceVoiceIds",
        message: "xAI only supports reference voices for reference-to-video generation. The reference voices were ignored."
    )))
}

@Test func xAIVideoModerationAndMissingURLAreTerminalErrorsLikeUpstream() async throws {
    let moderationTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"moderated"}"#),
        jsonResponse(#"{"status":"done","video":{"respect_moderation":false}}"#)
    ])
    let moderationProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: moderationTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "xai.video",
        message: "Video generation was blocked due to a content policy violation."
    )) {
        _ = try await moderationProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
    }
    #expect(await moderationTransport.requests().count == 2)

    let missingURLTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"missing-url"}"#),
        jsonResponse(#"{"status":"done","video":{"respect_moderation":true}}"#)
    ])
    let missingURLProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: missingURLTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "xai.video",
        message: "Video generation completed but no video URL was returned."
    )) {
        _ = try await missingURLProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
    }
    #expect(await missingURLTransport.requests().count == 2)
}

@Test func xAIVideoFailedAndExpiredStatusesWinOverStaleURLsLikeUpstream() async throws {
    let failedTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"failed"}"#),
        jsonResponse(#"{"status":"failed","video":{"url":"https://x.ai/stale.mp4"},"error":{"message":"GPU unavailable"}}"#)
    ])
    let failedProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: failedTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "xai.video",
        message: "Video generation failed: GPU unavailable"
    )) {
        _ = try await failedProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
    }
    #expect(await failedTransport.requests().count == 2)

    let expiredTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"expired"}"#),
        jsonResponse(#"{"status":"expired","video":{"url":"https://x.ai/stale.mp4"}}"#)
    ])
    let expiredProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: expiredTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "xai.video",
        message: "Video generation request expired."
    )) {
        _ = try await expiredProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
    }
    #expect(await expiredTransport.requests().count == 2)
}

@Test func xAIVideoIgnoresInputReferencesWithFrameImagesLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"frame-over-refs"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/frame-over-refs.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        frameImages: [
            VideoFrameImage(image: ImageInputFile(url: "https://example.com/first.png"), frameType: .firstFrame)
        ],
        inputReferences: [
            ImageInputFile(url: "https://example.com/ref-1.png")
        ],
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))

    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "inputReferences",
        message: "xAI only supports inputReferences for reference-to-video generation. The reference images were ignored."
    )))
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image"]?["url"]?.stringValue == "https://example.com/first.png")
    #expect(body["reference_images"] == nil)
}

@Test func xAIVideoIgnoresInputReferencesInEditModeLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"edit-over-refs"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/edit-over-refs.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "make it brighter",
        inputReferences: [
            ImageInputFile(url: "https://example.com/ref-1.png")
        ],
        providerOptions: [
            "xai": [
                "mode": "edit-video",
                "videoUrl": "https://x.ai/source.mp4",
                "pollIntervalMs": 1
            ]
        ]
    ))

    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "inputReferences",
        message: "xAI only supports inputReferences for reference-to-video generation. The reference images were ignored."
    )))
    let request = try #require((await transport.requests()).first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/videos/edits")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["video"]?["url"]?.stringValue == "https://x.ai/source.mp4")
    #expect(body["reference_images"] == nil)
}

@Test func xAIImageProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))))
    let model = try provider.imageModel("grok-2-image")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.sync_mode", message: "xAI sync_mode must be a boolean.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["sync_mode": "true"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 1k or 2k.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["resolution": "4k"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.quality", message: "xAI quality must be low, medium, or high.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["quality": "ultra"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.user", message: "xAI user must be a string.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["user": .null]]))
    }

    let stripTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
    let stripProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: stripTransport))
    let stripModel = try stripProvider.imageModel("grok-2-image")
    _ = try await stripModel.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["xai": ["quality": "high", "unknown": "drop-me"]]))
    let body = try decodeJSONBody(try #require((await stripTransport.requests()).first?.body))
    #expect(body["quality"]?.stringValue == "high")
    #expect(body["unknown"] == nil)
}

@Test func xAIVideoProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])))
    let model = try provider.videoModel("grok-2-video")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": true]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.mode", message: "xAI mode must be edit-video, extend-video, or reference-to-video.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["mode": "bad"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.videoUrl", message: "xAI videoUrl must be a non-empty string.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["videoUrl": ""]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.referenceImageUrls", message: "xAI referenceImageUrls must contain 1 to 7 non-empty strings.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": .object(["referenceImageUrls": .array(Array(repeating: .string("https://example.com/ref.png"), count: 8))])]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.pollIntervalMs", message: "xAI pollIntervalMs must be a positive number or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["pollIntervalMs": 0]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 480p, 720p, 1080p, or null.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["resolution": "4k"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.referenceVoiceIds", message: "xAI referenceVoiceIds must contain at most 3 non-empty strings.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["xai": ["referenceVoiceIds": ["a", "b", "c", "d"]]]))
    }
}

@Test func xAIVideoProviderOptionsPassthroughAndNullishResolutionMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-null"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": .object(["resolution": .null, "customFlag": true, "pollIntervalMs": 1])],
        extraBody: ["xai": .object(["resolution": "720p"])]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["resolution"] == nil)
    #expect(body["customFlag"]?.boolValue == true)
}

@Test func xAIVideoPollingHandlesHTTP202BodiesLikeUpstream() async throws {
    let pendingTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-pending"}"#),
        AIHTTPResponse(statusCode: 202, headers: ["content-type": "application/json"], body: Data(#"{"status":"pending","progress":42}"#.utf8)),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/pending.mp4","respect_moderation":true}}"#)
    ])
    let pendingProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: pendingTransport))
    let pendingResult = try await pendingProvider.videoModel("grok-2-video").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))
    #expect(pendingResult.urls == ["https://x.ai/pending.mp4"])
    #expect(await pendingTransport.requests().count == 3)

    let completedTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-complete"}"#),
        AIHTTPResponse(statusCode: 202, headers: ["content-type": "application/json"], body: Data(#"{"status":"done","video":{"url":"https://x.ai/complete.mp4","respect_moderation":true}}"#.utf8))
    ])
    let completedProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: completedTransport))
    let completedResult = try await completedProvider.videoModel("grok-2-video").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))
    #expect(completedResult.urls == ["https://x.ai/complete.mp4"])
    #expect(await completedTransport.requests().count == 2)
}

@Test func xAIVideoPollingTreatsEmptyAndUnparseableHTTP202AsPending() async throws {
    for pendingBody in [Data(), Data("not json".utf8)] {
        let transport = RecordingTransport(responses: [
            jsonResponse(#"{"request_id":"vid-fallback"}"#),
            AIHTTPResponse(statusCode: 202, body: pendingBody),
            jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/fallback.mp4","respect_moderation":true}}"#)
        ])
        let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
        let result = try await provider.videoModel("grok-2-video").generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
        #expect(result.urls == ["https://x.ai/fallback.mp4"])
        #expect(await transport.requests().count == 3)
    }
}

@Test func xAIVideoPollingRejectsOversizedHTTP202Body() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-large"}"#),
        AIHTTPResponse(statusCode: 202, body: Data(repeating: 0x78, count: 1024 * 1024 + 1))
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")

    await #expect(throws: AIError.invalidResponse(provider: "xai.video", message: "xAI video status response exceeded 1048576 bytes")) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "cat",
            providerOptions: ["xai": ["pollIntervalMs": 1]]
        ))
    }
}
