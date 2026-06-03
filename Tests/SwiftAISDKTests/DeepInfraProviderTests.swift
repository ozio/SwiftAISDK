import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepInfraChatCorrectsGemmaReasoningUsageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"test-id","object":"chat.completion","created":1234567890,"model":"google/gemma-2-9b-it","choices":[{"index":0,"message":{"role":"assistant","content":"Test response"},"finish_reason":"stop"}],"usage":{"prompt_tokens":19,"completion_tokens":84,"total_tokens":1184,"prompt_tokens_details":null,"completion_tokens_details":{"reasoning_tokens":1081}}}
    """))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.languageModel("google/gemma-2-9b-it")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Test prompt")]))

    #expect(result.text == "Test response")
    #expect(result.usage?.inputTokens == 19)
    #expect(result.usage?.outputTokens == 1165)
    #expect(result.usage?.outputTextTokens == 84)
    #expect(result.usage?.outputReasoningTokens == 1081)
    #expect(result.usage?.totalTokens == 2265)
    #expect(result.usage?.rawValue?["completion_tokens"]?.intValue == 1165)
    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["user-agent"] == "ai-sdk/deepinfra/2.0.52")
}

@Test func deepInfraChatCorrectsGemmaReasoningUsageOnStreamFinish() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"test-id","object":"chat.completion.chunk","created":1234567890,"model":"google/gemma-2-9b-it","choices":[{"index":0,"delta":{"content":"Test"},"finish_reason":null}]}

    data: {"id":"test-id","object":"chat.completion.chunk","created":1234567890,"model":"google/gemma-2-9b-it","choices":[{"index":0,"delta":{"content":" response"},"finish_reason":"stop"}],"usage":{"prompt_tokens":19,"completion_tokens":84,"total_tokens":1184,"completion_tokens_details":{"reasoning_tokens":1081}}}

    """))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.languageModel("google/gemma-2-9b-it")

    var text = ""
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Test prompt")])) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .finish(_, finalUsage):
            usage = finalUsage
        default:
            break
        }
    }

    #expect(text == "Test response")
    #expect(usage?.outputTokens == 1165)
    #expect(usage?.outputTextTokens == 84)
    #expect(usage?.outputReasoningTokens == 1081)
    #expect(usage?.totalTokens == 2265)
}

@Test func deepInfraImageUsesInferenceEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,deepinfra-image"]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", seed: 42, count: 1))

    #expect(result.base64Images == ["deepinfra-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/inference/black-forest-labs/FLUX-1-schnell")
    #expect(request.headers["authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["user-agent"] == "ai-sdk/deepinfra/2.0.52")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["num_images"]?.intValue == 1)
    #expect(body["width"]?.stringValue == "1024")
    #expect(body["height"]?.stringValue == "768")
    #expect(body["seed"]?.intValue == 42)
}

@Test func deepInfraImageMapsProviderOptions() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,nested-image"]}"#))
    let generateProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: generateTransport))
    let generateModel = try generateProvider.imageModel("black-forest-labs/FLUX-1-schnell")

    _ = try await generateModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        aspectRatio: "16:9",
        seed: 7,
        count: 1,
        providerOptions: [
            "deepinfra": .object([
                "seed": 100,
                "additional_param": "provider"
            ]),
            "openai": .object([
                "quality": "hd"
            ])
        ],
        extraBody: [
            "raw_param": .string("raw"),
            "deepinfra": .object([
                "seed": 42,
                "additional_param": "legacy"
            ])
        ]
    ))

    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["prompt"]?.stringValue == "cat")
    #expect(generateBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(generateBody["seed"]?.intValue == 100)
    #expect(generateBody["raw_param"]?.stringValue == "raw")
    #expect(generateBody["additional_param"]?.stringValue == "provider")
    #expect(generateBody["quality"] == nil)
    #expect(generateBody["deepinfra"] == nil)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let editProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: editTransport))
    let editModel = try editProvider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data("png".utf8), mediaType: "image/png", fileName: "input.png")],
        providerOptions: [
            "deepinfra": .object([
                "guidance": 7.5
            ])
        ],
        extraBody: [
            "deepinfra": .object([
                "guidance_scale": 2.5,
                "tags": ["a", "b"]
            ])
        ]
    ))

    let editRequest = try #require(await editTransport.requests().first)
    let bodyText = String(data: try #require(editRequest.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains(#"name="guidance_scale""#))
    #expect(bodyText.contains("2.5"))
    #expect(bodyText.contains(#"name="guidance""#))
    #expect(bodyText.contains("7.5"))
    #expect(bodyText.contains(#"name="tags""#))
    #expect(bodyText.contains("\r\na\r\n"))
    #expect(bodyText.contains("\r\nb\r\n"))
    #expect(!bodyText.contains(#"name="deepinfra""#))
}

@Test func deepInfraImageEditUsesOpenAICompatibleMultipartEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited-image"}]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "turn the cat into a dog",
        size: "1024x1024",
        count: 1,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png", fileName: "input.png")],
        mask: ImageInputFile(data: Data([255, 255, 255, 0]), mediaType: "image/png", fileName: "mask.png"),
        extraBody: ["guidance": 7.5]
    ))

    #expect(result.base64Images == ["edited-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepinfra.com/v1/openai/images/edits")
    #expect(request.headers["authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["user-agent"] == "ai-sdk/deepinfra/2.0.52")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let body = try #require(request.body)
    #expect(body.range(of: Data(#"name="model""#.utf8)) != nil)
    #expect(body.range(of: Data("black-forest-labs/FLUX.1-Kontext-dev".utf8)) != nil)
    #expect(body.range(of: Data(#"name="prompt""#.utf8)) != nil)
    #expect(body.range(of: Data("turn the cat into a dog".utf8)) != nil)
    #expect(body.range(of: Data(#"name="image"; filename="input.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="mask"; filename="mask.png""#.utf8)) != nil)
    #expect(body.range(of: Data(#"name="size""#.utf8)) != nil)
    #expect(body.range(of: Data("1024x1024".utf8)) != nil)
    #expect(body.range(of: Data(#"name="guidance""#.utf8)) != nil)
    #expect(body.range(of: Data("7.5".utf8)) != nil)
}

@Test func deepInfraAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,image"]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(
        apiKey: "deepinfra-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer deepinfra-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/deepinfra/2.0.52")
}

@Test func deepInfraImageSizeMappingMatchesUpstreamSplit() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,size-image"]}"#))
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024", aspectRatio: "1:1"))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["width"]?.stringValue == "1024")
    #expect(body["height"] == nil)
    #expect(body["aspect_ratio"]?.stringValue == "1:1")
}

@Test func deepInfraImageRejectsMoreThanOneImagePerCall() async throws {
    let provider = try AIProviders.deepInfra(settings: ProviderSettings(
        apiKey: "deepinfra-key",
        transport: RecordingTransport(response: jsonResponse(#"{"images":[]}"#))
    ))
    let model = try provider.imageModel("black-forest-labs/FLUX-1-schnell")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "DeepInfra image models support at most 1 image per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }
}
