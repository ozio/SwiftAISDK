import Foundation
import Testing
@testable import SwiftAISDK

@Test func falImageUsesStandardFieldsProviderOptionsWarningsAndMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"images":[{"url":"https://fal.example.com/image.png","width":1024,"height":1024,"content_type":"image/png"}],"seed":123,"timings":{"inference":1.5},"num_inference_steps":24,"has_nsfw_concepts":[false],"prompt":"cat"}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/qwen-image")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "16:9",
        seed: 123,
        count: 1,
        files: [
            ImageInputFile(url: "https://example.com/input-1.png"),
            ImageInputFile(url: "https://example.com/input-2.png")
        ],
        providerOptions: [
            "fal": .object([
                "guidanceScale": .number(3.5),
                "numInferenceSteps": .number(24),
                "outputFormat": .string("png")
            ])
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/image.png"])
    #expect(result.warnings == [
        AIWarning(
            type: "other",
            message: "Multiple input images provided but useMultipleImages is not enabled. Only the first image will be used. Set providerOptions.fal.useMultipleImages to true for models that support multiple images (e.g., fal-ai/flux-2/edit)."
        )
    ])
    #expect(result.providerMetadata["fal"]?["images"]?[0]?["contentType"]?.stringValue == "image/png")
    #expect(result.providerMetadata["fal"]?["images"]?[0]?["width"]?.intValue == 1024)
    #expect(result.providerMetadata["fal"]?["images"]?[0]?["nsfw"]?.boolValue == false)
    #expect(result.providerMetadata["fal"]?["seed"]?.intValue == 123)
    #expect(result.providerMetadata["fal"]?["timings"]?["inference"]?.doubleValue == 1.5)
    #expect(result.providerMetadata["fal"]?["numInferenceSteps"]?.intValue == 24)
    #expect(result.providerMetadata["fal"]?["prompt"] == nil)
    #expect(result.providerMetadata["fal"]?["hasNsfwConcepts"] == nil)

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["image_size"]?.stringValue == "landscape_16_9")
    #expect(body["seed"]?.intValue == 123)
    #expect(body["num_images"]?.intValue == 1)
    #expect(body["image_url"]?.stringValue == "https://example.com/input-1.png")
    #expect(body["image_urls"] == nil)
    #expect(body["guidance_scale"]?.doubleValue == 3.5)
    #expect(body["num_inference_steps"]?.intValue == 24)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["fal"] == nil)
}

@Test func falImageAcceptsDeprecatedSnakeCaseProviderOptionsWithWarning() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"image":{"url":"https://fal.example.com/image.png","content_type":"image/png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/qwen-image")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: [
            "fal": .object([
                "image_url": .string("https://example.com/input.png"),
                "guidance_scale": .number(7.5),
                "num_inference_steps": .number(50)
            ])
        ]
    ))

    #expect(result.warnings.count == 1)
    #expect(result.warnings[0].type == "other")
    #expect(result.warnings[0].message?.contains("deprecated snake_case") == true)
    #expect(result.warnings[0].message?.contains("'image_url' (use 'imageUrl')") == true)
    #expect(result.warnings[0].message?.contains("'guidance_scale' (use 'guidanceScale')") == true)
    #expect(result.warnings[0].message?.contains("'num_inference_steps' (use 'numInferenceSteps')") == true)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image_url"]?.stringValue == "https://example.com/input.png")
    #expect(body["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["num_inference_steps"]?.intValue == 50)
}

@Test func falImageProviderOptionsValidateAndScopeLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"image":{"url":"https://fal.example.com/image.png","content_type":"image/png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/qwen-image")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["fal": false]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["fal": ["guidanceScale": 0]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["fal": ["outputFormat": "webp"]]))
    }

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: [
            "openai": ["guidanceScale": 7.5],
            "fal": [
                "guidanceScale": nil,
                "custom_param": "kept"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["guidance_scale"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["custom_param"]?.stringValue == "kept")
}

@Test func falVideoUsesStandardImageSeedProviderOptionsAndMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/req-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","width":1280,"height":720,"duration":5,"fps":24,"content_type":"video/mp4"},"seed":42,"timings":{"inference":3.5},"prompt":"Animate this"}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/luma-dream-machine")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate this",
        aspectRatio: "16:9",
        durationSeconds: 5,
        image: ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
        seed: 42,
        providerOptions: [
            "fal": .object([
                "resolution": .string("720p"),
                "motionStrength": .number(0.6),
                "negativePrompt": .string("rain"),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000)
            ])
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/video.mp4"])
    #expect(result.providerMetadata["fal"]?["videos"]?[0]?["url"]?.stringValue == "https://fal.example.com/video.mp4")
    #expect(result.providerMetadata["fal"]?["videos"]?[0]?["contentType"]?.stringValue == "video/mp4")
    #expect(result.providerMetadata["fal"]?["seed"]?.intValue == 42)
    #expect(result.providerMetadata["fal"]?["timings"]?["inference"]?.doubleValue == 3.5)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["prompt"]?.stringValue == "Animate this")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "5s")
    #expect(body["image_url"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["resolution"]?.stringValue == "720p")
    #expect(body["motion_strength"]?.doubleValue == 0.6)
    #expect(body["negative_prompt"]?.stringValue == "rain")
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["fal"] == nil)
}

@Test func falVideoProviderOptionsValidateNullishAndPassthroughLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/req-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","content_type":"video/mp4"}}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/luma-dream-machine")

    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "Animate", providerOptions: ["fal": ["motionStrength": 1.5]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "Animate", providerOptions: ["fal": ["promptOptimizer": "yes"]]))
    }

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate",
        providerOptions: [
            "fal": [
                "loop": nil,
                "motionStrength": nil,
                "negativePrompt": nil,
                "customNull": nil,
                "customValue": "kept",
                "pollIntervalMs": 1,
                "pollTimeoutMs": 1_000
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["loop"] == nil)
    #expect(body["motion_strength"] == nil)
    #expect(body["negative_prompt"] == nil)
    #expect(body["customNull"] == .null)
    #expect(body["customValue"]?.stringValue == "kept")
    #expect(body["pollIntervalMs"] == nil)
}

@Test func falSpeechUsesProviderOptionsAndWarnsForUnsupportedFormat() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.speechModel("fal-ai/minimax/speech-02-hd")

    let result = try await model.speak(SpeechRequest(
        text: "hello",
        voice: "voice-id",
        format: "wav",
        speed: 1.25,
        language: "en",
        providerOptions: [
            "fal": .object([
                "language_boost": .string("English"),
                "voice_setting": .object(["speed": .number(1.1)])
            ])
        ]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "language", message: "fal speech models don't support 'language' directly; consider providerOptions.fal.language_boost"),
        AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported outputFormat: wav. Using 'url' instead.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["text"]?.stringValue == "hello")
    #expect(body["voice"]?.stringValue == "voice-id")
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["output_format"]?.stringValue == "url")
    #expect(body["language_boost"]?.stringValue == "English")
    #expect(body["voice_setting"]?["speed"]?.doubleValue == 1.1)
}

@Test func falSpeechProviderOptionsValidateLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"}}"#))
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.speechModel("fal-ai/minimax/speech-02-hd")

    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(text: "hello", providerOptions: ["fal": false]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(text: "hello", providerOptions: ["fal": ["language_boost": "Klingon"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(text: "hello", providerOptions: ["fal": ["voice_setting": ["emotion": "bored"]]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.speak(SpeechRequest(text: "hello", providerOptions: ["fal": ["pronunciation_dict": ["AI": 123]]]))
    }

    #expect((await transport.requests()).isEmpty)
}

@Test func falTranscriptionUsesProviderOptionsPollsInProgressAndMapsChunks() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        AIHTTPResponse(statusCode: 422, headers: ["content-type": "application/json"], body: Data(#"{"detail":"Request is still in progress"}"#.utf8)),
        jsonResponse(#"{"text":"fal transcript","chunks":[{"text":"fal","timestamp":[0,0.4]},{"text":" transcript","timestamp":[0.4,1.2]}],"inferred_languages":["en"]}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.transcriptionModel("fal-ai/wizper")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "fal": .object([
                "language": .string("en"),
                "diarize": .bool(false),
                "chunkLevel": .string("word"),
                "batchSize": .number(32),
                "numSpeakers": .number(2)
            ])
        ]
    ))

    #expect(result.text == "fal transcript")
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 1.2)
    #expect(result.segments == [
        TranscriptionSegment(text: "fal", startSecond: 0, endSecond: 0.4),
        TranscriptionSegment(text: " transcript", startSecond: 0.4, endSecond: 1.2)
    ])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://queue.fal.run/fal-ai/wizper")
    #expect(requests[1].url.absoluteString == "https://queue.fal.run/fal-ai/wizper/requests/transcription-1")
    #expect(requests[2].url.absoluteString == "https://queue.fal.run/fal-ai/wizper/requests/transcription-1")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["language"]?.stringValue == "en")
    #expect(body["diarize"]?.boolValue == false)
    #expect(body["chunk_level"]?.stringValue == "word")
    #expect(body["batch_size"]?.intValue == 32)
    #expect(body["num_speakers"]?.intValue == 2)
    #expect(body["audio_url"]?.stringValue?.hasPrefix("data:audio/wav;base64,") == true)
}

@Test func falTranscriptionProviderOptionsValidateDefaultsAndStripUnknownLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[]}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.transcriptionModel("fal-ai/wizper")

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), providerOptions: ["fal": ["chunkLevel": "sentence"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), providerOptions: ["fal": ["diarize": "yes"]]))
    }

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "fal": [
                "unknown": "stripped",
                "numSpeakers": nil
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["language"]?.stringValue == "en")
    #expect(body["diarize"]?.boolValue == true)
    #expect(body["chunk_level"]?.stringValue == "segment")
    #expect(body["version"]?.stringValue == "3")
    #expect(body["batch_size"]?.intValue == 64)
    #expect(body["num_speakers"] == nil)
    #expect(body["unknown"] == nil)
}
