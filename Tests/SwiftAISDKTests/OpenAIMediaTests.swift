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
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/images/edits")
    #expect(request.headers["Authorization"] == "Bearer test-key")
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
