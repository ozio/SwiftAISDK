import Foundation
import Testing
@testable import ai_sdk_port

@Test func replicateImageUsesModelPredictionEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("replicate-png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        count: 2,
        extraBody: [
            "aspectRatio": .string("3:4"),
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/image.png"])
    #expect(result.base64Images == [Data("replicate-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
    #expect(request.headers["Authorization"] == "Bearer replicate-key")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat")
    #expect(body["input"]?["num_outputs"]?.intValue == 2)
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "3:4")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://replicate.example.com/image.png")
}

@Test func replicateImageMapsEditingInputsAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":"https://replicate.example.com/edited.webp"}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("edited-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("owner/inpaint-model")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Replace the masked area",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        mask: ImageInputFile(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png"),
        extraBody: [
            "replicate": .object([
                "guidance_scale": .number(7.5),
                "num_inference_steps": .number(30),
                "negative_prompt": .string("blur"),
                "maxWaitTimeInSeconds": .number(45)
            ])
        ]
    ))

    let requests = await transport.requests()
    let request = try #require(requests.first)
    #expect(request.headers["prefer"] == "wait=45")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "Replace the masked area")
    #expect(body["input"]?["image"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["input"]?["mask"]?.stringValue == "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())")
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["num_inference_steps"]?.intValue == 30)
    #expect(body["input"]?["negative_prompt"]?.stringValue == "blur")
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func replicateFlux2ImageMapsMultipleInputImages() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/flux.webp"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/webp"], body: Data("flux-webp".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-2-pro")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use reference images",
        files: [
            ImageInputFile(url: "https://example.com/reference-1.jpg"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(url: "https://example.com/reference-3.jpg")
        ],
        mask: ImageInputFile(url: "https://example.com/mask.png")
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["input_image"]?.stringValue == "https://example.com/reference-1.jpg")
    #expect(body["input"]?["input_image_2"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["input"]?["input_image_3"]?.stringValue == "https://example.com/reference-3.jpg")
    #expect(body["input"]?["mask"] == nil)
    #expect(body["input"]?["image"] == nil)
}

@Test func replicateVideoUsesPredictionEndpointAndReturnsOutputURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-video","status":"starting","output":null,"urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """),
        jsonResponse("""
        {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"}}
        """)
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("owner/video-model")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "guidance_scale": .number(7.5),
            "maxWaitTimeInSeconds": .number(30),
            "pollIntervalMs": .number(1),
            "pollTimeoutMs": .number(1_000)
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/models/owner/video-model/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?["prompt"]?.stringValue == "cat running")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["input"]?["duration"]?.intValue == 4)
    #expect(body["input"]?["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.replicate.com/v1/predictions/pred-video")
}

@Test func replicateVideoMapsNestedOptionsAndImageInput() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"pred-video","status":"succeeded","output":"https://replicate.example.com/video.mp4","urls":{"get":"https://api.replicate.com/v1/predictions/pred-video"},"metrics":{"predict_time":25.5}}
    """))
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.videoModel("stability-ai/stable-video-diffusion:abc123")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate the image",
        aspectRatio: "9:16",
        durationSeconds: 5,
        extraBody: [
            "replicate": .object([
                "resolution": .string("1920x1080"),
                "fps": .number(24),
                "seed": .number(42),
                "image": .object([
                    "data": .string("base64-image-data"),
                    "mediaType": .string("image/png")
                ]),
                "guidance_scale": .number(8),
                "motion_bucket_id": .number(127),
                "prompt_optimizer": .bool(true),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000),
                "maxWaitTimeInSeconds": .number(30)
            ])
        ]
    ))

    #expect(result.urls == ["https://replicate.example.com/video.mp4"])
    #expect(result.operationID == "pred-video")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.replicate.com/v1/predictions")
    #expect(request.headers["prefer"] == "wait=30")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["version"]?.stringValue == "abc123")
    #expect(body["input"]?["prompt"]?.stringValue == "Animate the image")
    #expect(body["input"]?["aspect_ratio"]?.stringValue == "9:16")
    #expect(body["input"]?["duration"]?.intValue == 5)
    #expect(body["input"]?["size"]?.stringValue == "1920x1080")
    #expect(body["input"]?["fps"]?.intValue == 24)
    #expect(body["input"]?["seed"]?.intValue == 42)
    #expect(body["input"]?["image"]?.stringValue == "data:image/png;base64,base64-image-data")
    #expect(body["input"]?["guidance_scale"]?.intValue == 8)
    #expect(body["input"]?["motion_bucket_id"]?.intValue == 127)
    #expect(body["input"]?["prompt_optimizer"]?.boolValue == true)
    #expect(body["input"]?["resolution"] == nil)
    #expect(body["input"]?["pollIntervalMs"] == nil)
    #expect(body["input"]?["pollTimeoutMs"] == nil)
    #expect(body["input"]?["maxWaitTimeInSeconds"] == nil)
    #expect(body["input"]?["replicate"] == nil)
}

@Test func falImageUsesRunEndpoint() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"image":{"url":"https://fal.example.com/image.png","content_type":"image/png"}}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-png".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/flux/schnell")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        extraBody: [
            "aspectRatio": .string("16:9"),
            "guidanceScale": .number(3.5),
            "numInferenceSteps": .number(24),
            "outputFormat": .string("png"),
            "syncMode": .bool(true),
            "useMultipleImages": .bool(true)
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/image.png"])
    #expect(result.base64Images == [Data("fal-png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let request = try #require(requests.first)
    #expect(request.url.absoluteString == "https://fal.run/fal-ai/flux/schnell")
    #expect(request.headers["Authorization"] == "Key fal-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["image_size"]?.stringValue == "landscape_16_9")
    #expect(body["guidance_scale"]?.doubleValue == 3.5)
    #expect(body["num_inference_steps"]?.intValue == 24)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["sync_mode"]?.boolValue == true)
    #expect(body["aspectRatio"] == nil)
    #expect(body["useMultipleImages"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://fal.example.com/image.png")
    #expect(requests[1].headers["Authorization"] == nil)
}

@Test func falImageMapsFilesMaskAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"images":[{"url":"https://fal.example.com/edited.png","content_type":"image/png"}]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fal-edited".utf8))
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.imageModel("fal-ai/flux-2/edit")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Blend references",
        files: [
            ImageInputFile(url: "https://example.com/reference-1.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([9, 8, 7]), mediaType: "image/png"),
        extraBody: [
            "fal": .object([
                "useMultipleImages": .bool(true),
                "guidanceScale": .number(7.5),
                "numInferenceSteps": .number(30),
                "enableSafetyChecker": .bool(false),
                "outputFormat": .string("png"),
                "syncMode": .bool(true),
                "safetyTolerance": .number(5)
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "Blend references")
    #expect(body["image_urls"]?[0]?.stringValue == "https://example.com/reference-1.png")
    #expect(body["image_urls"]?[1]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(body["mask_url"]?.stringValue == "data:image/png;base64,\(Data([9, 8, 7]).base64EncodedString())")
    #expect(body["guidance_scale"]?.doubleValue == 7.5)
    #expect(body["num_inference_steps"]?.intValue == 30)
    #expect(body["enable_safety_checker"]?.boolValue == false)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["sync_mode"]?.boolValue == true)
    #expect(body["safety_tolerance"]?.intValue == 5)
    #expect(body["useMultipleImages"] == nil)
    #expect(body["fal"] == nil)
}

@Test func falVideoUsesQueueAndResponseURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/kling-video/requests/req-1"}"#),
        AIHTTPResponse(statusCode: 422, headers: ["content-type": "application/json"], body: Data(#"{"detail":"Request is still in progress"}"#.utf8)),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","content_type":"video/mp4"},"seed":123}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/kling-video/v1/standard/text-to-video")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 4,
        extraBody: [
            "motionStrength": .number(0.5),
            "negativePrompt": .string("rain"),
            "promptOptimizer": .bool(true),
            "pollIntervalMs": .number(1),
            "pollTimeoutMs": .number(1_000)
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/video.mp4"])
    #expect(result.operationID == "req-1")
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/v1/standard/text-to-video")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat running")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "4s")
    #expect(body["motion_strength"]?.doubleValue == 0.5)
    #expect(body["negative_prompt"]?.stringValue == "rain")
    #expect(body["prompt_optimizer"]?.boolValue == true)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/requests/req-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://queue.fal.run/fal-ai/kling-video/requests/req-1")
}

@Test func falVideoMapsNestedOptionsAndImageInput() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"req-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/req-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4","content_type":"video/mp4","width":1280,"height":720},"seed":42}"#)
    ])
    let provider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transport))
    let model = try provider.videoModel("fal-ai/luma-dream-machine")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "Animate this",
        aspectRatio: "16:9",
        durationSeconds: 5,
        extraBody: [
            "fal": .object([
                "image": .object([
                    "data": .string("base64-image"),
                    "mediaType": .string("image/png")
                ]),
                "loop": .bool(true),
                "motionStrength": .number(0.6),
                "resolution": .string("720p"),
                "negativePrompt": .string("rain"),
                "promptOptimizer": .bool(true),
                "pollIntervalMs": .number(1),
                "pollTimeoutMs": .number(1_000)
            ])
        ]
    ))

    #expect(result.urls == ["https://fal.example.com/video.mp4"])
    #expect(result.operationID == "req-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "Animate this")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["duration"]?.stringValue == "5s")
    #expect(body["image_url"]?.stringValue == "data:image/png;base64,base64-image")
    #expect(body["loop"]?.boolValue == true)
    #expect(body["motion_strength"]?.doubleValue == 0.6)
    #expect(body["resolution"]?.stringValue == "720p")
    #expect(body["negative_prompt"]?.stringValue == "rain")
    #expect(body["prompt_optimizer"]?.boolValue == true)
    #expect(body["pollIntervalMs"] == nil)
    #expect(body["pollTimeoutMs"] == nil)
    #expect(body["fal"] == nil)
}

@Test func falSpeechAndTranscriptionUseNativeFalEndpoints() async throws {
    let speechTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"},"duration_ms":1000,"request_id":"speech-1"}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let speechProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("fal-ai/minimax/speech-02-hd")

    let speech = try await speechModel.speak(SpeechRequest(text: "hello", voice: "voice-id", format: "url", extraBody: ["language_boost": "English"]))

    #expect(speech.audio == Data("fal-audio".utf8))
    let speechRequests = await speechTransport.requests()
    #expect(speechRequests.count == 2)
    #expect(speechRequests[0].url.absoluteString == "https://fal.run/fal-ai/minimax/speech-02-hd")
    #expect(speechRequests[0].headers["Authorization"] == "Key fal-key")
    let speechBody = try decodeJSONBody(try #require(speechRequests[0].body))
    #expect(speechBody["text"]?.stringValue == "hello")
    #expect(speechBody["voice"]?.stringValue == "voice-id")
    #expect(speechBody["output_format"]?.stringValue == "url")
    #expect(speechBody["language_boost"]?.stringValue == "English")
    #expect(speechRequests[1].method == "GET")
    #expect(speechRequests[1].url.absoluteString == "https://fal.example.com/audio.mp3")
    #expect(speechRequests[1].headers["Authorization"] == nil)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[{"text":"fal","timestamp":[0,0.4]}],"inferred_languages":["en"]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("whisper")

    let transcription = try await transcriptionModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav", language: "en", extraBody: ["chunkLevel": "segment", "batchSize": 32]))

    #expect(transcription.text == "fal transcript")
    let transcriptionRequests = await transcriptionTransport.requests()
    #expect(transcriptionRequests.count == 2)
    #expect(transcriptionRequests[0].url.absoluteString == "https://queue.fal.run/fal-ai/whisper")
    let transcriptionBody = try decodeJSONBody(try #require(transcriptionRequests[0].body))
    #expect(transcriptionBody["task"]?.stringValue == "transcribe")
    #expect(transcriptionBody["language"]?.stringValue == "en")
    #expect(transcriptionBody["diarize"]?.boolValue == true)
    #expect(transcriptionBody["chunk_level"]?.stringValue == "segment")
    #expect(transcriptionBody["batch_size"]?.intValue == 32)
    #expect(transcriptionBody["audio_url"]?.stringValue?.hasPrefix("data:audio/wav;base64,") == true)
    #expect(transcriptionRequests[1].method == "GET")
    #expect(transcriptionRequests[1].url.absoluteString == "https://queue.fal.run/fal-ai/whisper/requests/transcription-1")
}

@Test func falAudioModelsMapNestedProviderOptions() async throws {
    let speechTransport = RecordingTransport(responses: [
        jsonResponse(#"{"audio":{"url":"https://fal.example.com/audio.mp3"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("fal-audio".utf8))
    ])
    let speechProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("fal-ai/minimax/speech-02-hd")

    _ = try await speechModel.speak(SpeechRequest(
        text: "hello",
        voice: "voice-id",
        format: "url",
        extraBody: [
            "fal": .object([
                "voice_setting": .object([
                    "speed": .number(1.1),
                    "vol": .number(0.8),
                    "voice_id": .string("override-voice")
                ]),
                "language_boost": .string("English")
            ])
        ]
    ))

    let speechBody = try decodeJSONBody(try #require((await speechTransport.requests()).first?.body))
    #expect(speechBody["text"]?.stringValue == "hello")
    #expect(speechBody["voice"]?.stringValue == "voice-id")
    #expect(speechBody["output_format"]?.stringValue == "url")
    #expect(speechBody["voice_setting"]?["speed"]?.doubleValue == 1.1)
    #expect(speechBody["voice_setting"]?["vol"]?.doubleValue == 0.8)
    #expect(speechBody["voice_setting"]?["voice_id"]?.stringValue == "override-voice")
    #expect(speechBody["language_boost"]?.stringValue == "English")
    #expect(speechBody["fal"] == nil)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("whisper")

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        extraBody: [
            "fal": .object([
                "language": .string("en"),
                "diarize": .bool(false),
                "chunkLevel": .string("segment"),
                "batchSize": .number(32),
                "numSpeakers": .number(2)
            ])
        ]
    ))

    let transcriptionBody = try decodeJSONBody(try #require((await transcriptionTransport.requests()).first?.body))
    #expect(transcriptionBody["language"]?.stringValue == "en")
    #expect(transcriptionBody["diarize"]?.boolValue == false)
    #expect(transcriptionBody["chunk_level"]?.stringValue == "segment")
    #expect(transcriptionBody["batch_size"]?.intValue == 32)
    #expect(transcriptionBody["num_speakers"]?.intValue == 2)
    #expect(transcriptionBody["fal"] == nil)
    #expect(transcriptionBody["chunkLevel"] == nil)
    #expect(transcriptionBody["batchSize"] == nil)
    #expect(transcriptionBody["numSpeakers"] == nil)
}
