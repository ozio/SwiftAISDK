import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAITranscriptionUsesMultipartFormData() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"text":"transcribed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-1")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("abc".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        prompt: "Names",
        extraBody: ["timestampGranularities": ["word", "segment"]]
    ))

    #expect(result.text == "transcribed")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("whisper-1"))
    #expect(bodyText.contains("name=\"file\"; filename=\"clip.wav\""))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("segment"))
}

@Test func openAITranscriptionUsesJSONFormatForGPT4oProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe")

    _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("abc".utf8), mimeType: "audio/wav", extraBody: ["temperature": 0.1]))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("json"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.1"))
}

@Test func openAITranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("abc".utf8),
        mimeType: "audio/wav",
        extraBody: [
            "openai": .object([
                "timestampGranularities": .array([.string("word")]),
                "temperature": .number(0.1),
                "include": .array([.string("logprobs")])
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.1"))
    #expect(bodyText.contains("name=\"include[]\""))
    #expect(bodyText.contains("logprobs"))
    #expect(!bodyText.contains("name=\"openai\""))
}

@Test func openAITranscriptionMapsTypedProviderOptionsAndLanguageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed","language":"english","duration":1.5}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("abc".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "openai": [
                "timestampGranularities": ["word"],
                "temperature": 0.1,
                "include": ["logprobs"],
                "prompt": "Names"
            ]
        ]
    ))

    #expect(result.language == "en")
    #expect(result.durationInSeconds == 1.5)
    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.1"))
    #expect(bodyText.contains("name=\"include[]\""))
    #expect(bodyText.contains("logprobs"))
    #expect(bodyText.contains("name=\"prompt\""))
    #expect(bodyText.contains("Names"))
    #expect(!bodyText.contains("name=\"openai\""))
}

@Test func openAITranscriptionSupportsDiarizedResponsesAndDefaultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"Hello from Alice. Hello from Bob.","duration":3.2,"segments":[{"type":"transcript.text.segment","id":"seg-1","start":0,"end":1.5,"text":"Hello from Alice.","speaker":"A"},{"type":"transcript.text.segment","id":"seg-2","start":1.5,"end":3.2,"text":"Hello from Bob.","speaker":"B"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let result = try await provider.transcriptionModel("gpt-4o-transcribe-diarize").transcribe(
        AudioTranscriptionRequest(audio: Data("abc".utf8), mimeType: "audio/mpeg")
    )

    #expect(result.segments == [
        TranscriptionSegment(text: "Hello from Alice.", startSecond: 0, endSecond: 1.5),
        TranscriptionSegment(text: "Hello from Bob.", startSecond: 1.5, endSecond: 3.2)
    ])
    #expect(result.providerMetadata["openai"]?["segments"]?[0]?["speaker"]?.stringValue == "A")
    let bodyText = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("diarized_json"))
    #expect(bodyText.contains("name=\"chunking_strategy\""))
    #expect(bodyText.contains("auto"))
}

@Test func openAITranscriptionSerializesServerVADChunkingLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"done","segments":[]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.transcriptionModel("gpt-4o-transcribe-diarize").transcribe(
        AudioTranscriptionRequest(
            audio: Data("abc".utf8),
            mimeType: "audio/mpeg",
            providerOptions: ["openai": [
                "chunkingStrategy": [
                    "type": "server_vad",
                    "threshold": 0.7,
                    "prefixPaddingMs": 400,
                    "silenceDurationMs": 300
                ]
            ]]
        )
    )

    let bodyText = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains(#"{"prefix_padding_ms":400,"silence_duration_ms":300,"threshold":0.7,"type":"server_vad"}"#))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("diarized_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
}

@Test func openAITranscriptionRejectsInvalidChunkingStrategiesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"done","segments":[]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.transcriptionModel("gpt-4o-transcribe-diarize")
    let invalidStrategies: [(JSONValue, AIError)] = [
        (
            .string("client_vad"),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy",
                message: "OpenAI chunkingStrategy must be auto or a server_vad object."
            )
        ),
        (
            .object(["type": .string("semantic_vad")]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.type",
                message: "OpenAI chunkingStrategy.type must be server_vad."
            )
        ),
        (
            .object(["type": .string("server_vad"), "threshold": .number(-0.1)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.threshold",
                message: "OpenAI chunkingStrategy.threshold must be a number between 0 and 1."
            )
        ),
        (
            .object(["type": .string("server_vad"), "threshold": .number(1.1)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.threshold",
                message: "OpenAI chunkingStrategy.threshold must be a number between 0 and 1."
            )
        ),
        (
            .object(["type": .string("server_vad"), "prefixPaddingMs": .number(-1)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.prefixPaddingMs",
                message: "OpenAI chunkingStrategy.prefixPaddingMs must be a nonnegative integer."
            )
        ),
        (
            .object(["type": .string("server_vad"), "prefixPaddingMs": .number(0.5)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.prefixPaddingMs",
                message: "OpenAI chunkingStrategy.prefixPaddingMs must be a nonnegative integer."
            )
        ),
        (
            .object(["type": .string("server_vad"), "silenceDurationMs": .number(-1)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.silenceDurationMs",
                message: "OpenAI chunkingStrategy.silenceDurationMs must be a nonnegative integer."
            )
        ),
        (
            .object(["type": .string("server_vad"), "silenceDurationMs": .number(0.5)]),
            .invalidArgument(
                argument: "providerOptions.openai.chunkingStrategy.silenceDurationMs",
                message: "OpenAI chunkingStrategy.silenceDurationMs must be a nonnegative integer."
            )
        )
    ]

    for (chunkingStrategy, expectedError) in invalidStrategies {
        await #expect(throws: expectedError) {
            _ = try await model.transcribe(AudioTranscriptionRequest(
                audio: Data("abc".utf8),
                mimeType: "audio/mpeg",
                providerOptions: ["openai": ["chunkingStrategy": chunkingStrategy]]
            ))
        }
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.openai.chunking_strategy.prefix_padding_ms",
        message: "OpenAI chunkingStrategy.prefixPaddingMs must be a nonnegative integer."
    )) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("abc".utf8),
            mimeType: "audio/mpeg",
            providerOptions: ["openai": [
                "chunking_strategy": [
                    "type": "server_vad",
                    "prefix_padding_ms": -1
                ]
            ]]
        ))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAISpeechUsesDefaultVoiceAndResponseFormat() async throws {
    let audio = Data("mp3".utf8)
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: audio))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.speechModel("tts-1")

    let result = try await model.speak(SpeechRequest(text: "Hello", extraBody: ["speed": 1.25, "instructions": "Calm"]))

    #expect(result.audio == audio)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/audio/speech")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "tts-1")
    #expect(body["input"]?.stringValue == "Hello")
    #expect(body["voice"]?.stringValue == "alloy")
    #expect(body["response_format"]?.stringValue == "mp3")
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["instructions"]?.stringValue == "Calm")
}

@Test func openAISpeechMapsTypedProviderOptionsAndWarningsLikeUpstream() async throws {
    let audio = Data("mp3".utf8)
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: audio))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.speechModel("tts-1")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "ogg",
        language: "ja",
        providerOptions: [
            "openai": [
                "speed": 1.25,
                "instructions": "Calm"
            ]
        ]
    ))

    #expect(result.warnings.map(\.feature).contains("outputFormat"))
    #expect(result.warnings.map(\.feature).contains("language"))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["response_format"]?.stringValue == "mp3")
    #expect(body["language"] == nil)
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["instructions"]?.stringValue == "Calm")
    #expect(body["openai"] == nil)
}

@Test func openAISpeechMapsNestedProviderOptions() async throws {
    let audio = Data("mp3".utf8)
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: audio))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.speechModel("tts-1")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        extraBody: [
            "openai": .object([
                "speed": .number(1.25),
                "instructions": .string("Calm")
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["speed"]?.doubleValue == 1.25)
    #expect(body["instructions"]?.stringValue == "Calm")
    #expect(body["openai"] == nil)
}

@Test func openAIImageMapsProviderOptionsAndDefaultResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"created":1710000000,"data":[{"b64_json":"image-b64","revised_prompt":"cat"}],"usage":{"total_tokens":10}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("dall-e-3")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "quality": "hd",
            "style": "vivid",
            "background": "transparent",
            "moderation": "low",
            "outputFormat": "webp",
            "outputCompression": 80,
            "user": "user-1"
        ]
    ))

    #expect(result.base64Images == ["image-b64"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/images/generations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "dall-e-3")
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["response_format"]?.stringValue == "b64_json")
    #expect(body["output_format"]?.stringValue == "webp")
    #expect(body["output_compression"]?.intValue == 80)
    #expect(body["quality"]?.stringValue == "hd")
    #expect(body["style"]?.stringValue == "vivid")
    #expect(body["background"]?.stringValue == "transparent")
    #expect(body["moderation"]?.stringValue == "low")
    #expect(body["user"]?.stringValue == "user-1")
}

@Test func openAIImageCarriesUsageAndProviderImageMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "created":1733837122,
      "size":"1024x1024",
      "quality":"high",
      "background":"transparent",
      "output_format":"webp",
      "data":[{"b64_json":"image-b64","revised_prompt":"a sharper cat"}],
      "usage":{
        "input_tokens":12,
        "output_tokens":0,
        "total_tokens":12,
        "input_tokens_details":{"image_tokens":7,"text_tokens":5}
      }
    }
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("gpt-image-1")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x1024", count: 1))

    #expect(result.base64Images == ["image-b64"])
    #expect(result.usage?.inputTokens == 12)
    #expect(result.usage?.outputTokens == 0)
    #expect(result.usage?.totalTokens == 12)
    let imageMetadata = try #require(result.providerMetadata["openai"]?["images"]?[0])
    #expect(imageMetadata["revisedPrompt"]?.stringValue == "a sharper cat")
    #expect(imageMetadata["created"]?.intValue == 1733837122)
    #expect(imageMetadata["size"]?.stringValue == "1024x1024")
    #expect(imageMetadata["quality"]?.stringValue == "high")
    #expect(imageMetadata["background"]?.stringValue == "transparent")
    #expect(imageMetadata["outputFormat"]?.stringValue == "webp")
    #expect(imageMetadata["imageTokens"]?.intValue == 7)
    #expect(imageMetadata["textTokens"]?.intValue == 5)
}

@Test func openAIImageDistributesTokenDetailsAcrossImagesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "created":1733837122,
      "data":[
        {"b64_json":"image-1"},
        {"b64_json":"image-2"},
        {"b64_json":"image-3"}
      ],
      "usage":{
        "input_tokens":30,
        "output_tokens":900,
        "total_tokens":930,
        "input_tokens_details":{"image_tokens":194,"text_tokens":28}
      }
    }
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("gpt-image-1")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x1024", count: 3))

    let images = try #require(result.providerMetadata["openai"]?["images"]?.arrayValue)
    #expect(images[0]["imageTokens"]?.intValue == 64)
    #expect(images[0]["textTokens"]?.intValue == 9)
    #expect(images[1]["imageTokens"]?.intValue == 64)
    #expect(images[1]["textTokens"]?.intValue == 9)
    #expect(images[2]["imageTokens"]?.intValue == 66)
    #expect(images[2]["textTokens"]?.intValue == 10)
}

@Test func openAIImageMapsNestedProviderOptionsForGenerateAndEdit() async throws {
    let generationTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image-b64"}]}"#))
    let generationProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: generationTransport))
    let generationModel = try generationProvider.imageModel("gpt-image-1")

    _ = try await generationModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x1024",
        count: 1,
        extraBody: [
            "openai": .object([
                "quality": .string("high"),
                "background": .string("transparent"),
                "moderation": .string("low"),
                "outputFormat": .string("webp"),
                "outputCompression": .number(80),
                "user": .string("user-1")
            ])
        ]
    ))

    let generationBody = try decodeJSONBody(try #require((await generationTransport.requests()).first?.body))
    #expect(generationBody["quality"]?.stringValue == "high")
    #expect(generationBody["background"]?.stringValue == "transparent")
    #expect(generationBody["moderation"]?.stringValue == "low")
    #expect(generationBody["output_format"]?.stringValue == "webp")
    #expect(generationBody["output_compression"]?.intValue == 80)
    #expect(generationBody["user"]?.stringValue == "user-1")
    #expect(generationBody["openai"] == nil)
    #expect(generationBody["outputFormat"] == nil)
    #expect(generationBody["outputCompression"] == nil)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-b64"}]}"#))
    let editProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: editTransport))
    let editModel = try editProvider.imageModel("gpt-image-1")

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png", fileName: "input.png")],
        extraBody: [
            "openai": .object([
                "outputFormat": .string("webp"),
                "outputCompression": .number(70),
                "inputFidelity": .string("high")
            ])
        ]
    ))

    let editBody = try #require((await editTransport.requests()).first?.body)
    #expect(editBody.range(of: Data(#"name="output_format""#.utf8)) != nil)
    #expect(editBody.range(of: Data("webp".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="output_compression""#.utf8)) != nil)
    #expect(editBody.range(of: Data("70".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="input_fidelity""#.utf8)) != nil)
    #expect(editBody.range(of: Data("high".utf8)) != nil)
    #expect(editBody.range(of: Data(#"name="openai""#.utf8)) == nil)
}

@Test func openAIImageEditUsesMultipartEditsEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"created":1710000000,"data":[{"b64_json":"edited-b64"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.imageModel("gpt-image-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "edit the image",
        size: "1024x1024",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png", fileName: "input.png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png", fileName: "mask.png"),
        extraBody: [
            "quality": "high",
            "background": "transparent",
            "outputFormat": "webp",
            "outputCompression": 80,
            "inputFidelity": "high",
            "user": "user-1"
        ]
    ))

    #expect(result.base64Images == ["edited-b64"])
    #expect(result.providerMetadata["openai"]?["images"]?[0]?["created"]?.intValue == 1710000000)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/images/edits")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.66")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let body = try #require(request.body)
    #expect(body.range(of: Data(#"name="model""#.utf8)) != nil)
    #expect(body.range(of: Data("gpt-image-1".utf8)) != nil)
    #expect(body.range(of: Data(#"name="prompt""#.utf8)) != nil)
    #expect(body.range(of: Data("edit the image".utf8)) != nil)
    #expect(body.range(of: Data(#"name="image"; filename="input.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="mask"; filename="mask.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="output_format""#.utf8)) != nil)
    #expect(body.range(of: Data("webp".utf8)) != nil)
    #expect(body.range(of: Data(#"name="output_compression""#.utf8)) != nil)
    #expect(body.range(of: Data("80".utf8)) != nil)
    #expect(body.range(of: Data(#"name="input_fidelity""#.utf8)) != nil)
    #expect(body.range(of: Data("high".utf8)) != nil)
}
