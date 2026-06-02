import Foundation
import Testing
@testable import SwiftAISDK

@Test func fireworksLanguageTransformsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"fw"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.languageModel("accounts/fireworks/models/kimi-k2-thinking")

    #expect(model.providerID == "fireworks.chat")
    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "thinking": .object(["type": "enabled", "budgetTokens": 2048]),
            "reasoningHistory": "interleaved",
            "reasoning_effort": "xhigh"
        ]
    ))

    #expect(result.text == "fw")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 2048)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "interleaved")
    #expect(body["reasoningHistory"] == nil)
    #expect(body["reasoning_effort"]?.stringValue == "high")
}

@Test func fireworksImageUsesWorkflowBinaryEndpoint() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8)))
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-1-schnell-fp8")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", aspectRatio: "16:9", seed: 42, count: 1))

    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    #expect(result.warnings.isEmpty)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-1-schnell-fp8/text_to_image")
    #expect(request.headers["Authorization"] == "Bearer fireworks-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["samples"]?.intValue == 1)
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["seed"]?.intValue == 42)
}

@Test func fireworksAsyncImagePollsAndDownloadsResult() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-1"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png", "download-header": "yes"], body: Data("async-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", count: 2))

    #expect(result.urls == ["https://assets.example.com/fireworks.png"])
    #expect(result.base64Images == [Data("async-png".utf8).base64EncodedString()])
    #expect(result.responseMetadata.headers["download-header"] == "yes")
    #expect(result.responseMetadata.body == nil)
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "This model does not support the `size` option. Use `aspectRatio` instead.")
    ])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro")
    let submitBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(submitBody["prompt"]?.stringValue == "cat")
    #expect(submitBody["samples"]?.intValue == 2)
    #expect(submitBody["width"]?.stringValue == "1024")
    #expect(submitBody["height"]?.stringValue == "768")
    #expect(requests[1].url.absoluteString == "https://api.fireworks.ai/inference/v1/workflows/accounts/fireworks/models/flux-kontext-pro/get_result")
    let pollBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(pollBody["id"]?.stringValue == "fw-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://assets.example.com/fireworks.png")
}

@Test func fireworksImageMapsProviderOptionsAndInputImage() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-edit"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks-edit.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("edit-png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "restyle",
        aspectRatio: "16:9",
        seed: 7,
        files: [
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([7, 8, 9]), mediaType: "image/png"),
        providerOptions: [
            "fireworks": .object([
                "seed": 99,
                "output_format": "jpeg"
            ]),
            "openai": .object([
                "quality": "hd"
            ])
        ],
        extraBody: [
            "raw_param": .string("raw"),
            "fireworks": .object([
                "seed": 11,
                "strength": 0.7
            ])
        ]
    ))
    #expect(result.warnings == [
        AIWarning(type: "other", message: "Fireworks only supports a single input image. Additional images are ignored."),
        AIWarning(type: "unsupported", feature: "mask", message: "Fireworks Kontext models do not support explicit masks. Use the prompt to describe the areas to edit.")
    ])

    let submitBody = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(submitBody["prompt"]?.stringValue == "restyle")
    #expect(submitBody["input_image"]?.stringValue == "data:image/png;base64,\(Data([1, 2, 3]).base64EncodedString())")
    #expect(submitBody["aspect_ratio"]?.stringValue == "16:9")
    #expect(submitBody["seed"]?.intValue == 99)
    #expect(submitBody["output_format"]?.stringValue == "jpeg")
    #expect(submitBody["raw_param"]?.stringValue == "raw")
    #expect(submitBody["strength"]?.doubleValue == 0.7)
    #expect(submitBody["quality"] == nil)
    #expect(submitBody["fireworks"] == nil)
}

@Test func fireworksImageWarningsAndSizeMappingMatchBackendSupport() async throws {
    let workflowTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: Data("png".utf8)))
    let workflowProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: workflowTransport))
    let workflowModel = try workflowProvider.imageModel("accounts/fireworks/models/flux-1-dev-fp8")

    let workflowResult = try await workflowModel.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024", aspectRatio: "1:1"))
    #expect(workflowResult.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "This model does not support the `size` option. Use `aspectRatio` instead.")
    ])
    let workflowBody = try decodeJSONBody(try #require((await workflowTransport.requests()).first?.body))
    #expect(workflowBody["width"]?.stringValue == "1024")
    #expect(workflowBody["height"] == nil)
    #expect(workflowBody["aspect_ratio"]?.stringValue == "1:1")

    let sizeTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: Data("png".utf8)))
    let sizeProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: sizeTransport))
    let sizeModel = try sizeProvider.imageModel("accounts/fireworks/models/playground-v2-5-1024px-aesthetic")

    let sizeResult = try await sizeModel.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", aspectRatio: "1:1", seed: 42))
    #expect(sizeResult.warnings == [
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "This model does not support the `aspectRatio` option.")
    ])
    let body = try decodeJSONBody(try #require((await sizeTransport.requests()).first?.body))
    #expect(body["width"]?.stringValue == "1024")
    #expect(body["height"]?.stringValue == "768")
    #expect(body["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["seed"]?.intValue == 42)
}

@Test func fireworksAsyncImagePollErrorsUseUpstreamMessages() async throws {
    let failedTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-error"}"#),
        jsonResponse(#"{"status":"Error","result":null}"#)
    ])
    let failedProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: failedTransport))
    let failedModel = try failedProvider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    await #expect(throws: AIError.invalidResponse(provider: "fireworks.image", message: "Fireworks image generation failed with status: Error")) {
        _ = try await failedModel.generateImage(ImageGenerationRequest(prompt: "cat"))
    }

    let missingSampleTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-ready"}"#),
        jsonResponse(#"{"status":"Ready","result":{}}"#)
    ])
    let missingSampleProvider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: missingSampleTransport))
    let missingSampleModel = try missingSampleProvider.imageModel("accounts/fireworks/models/flux-kontext-pro")

    await #expect(throws: AIError.invalidResponse(provider: "fireworks.image", message: "Fireworks poll response is Ready but missing result.sample.")) {
        _ = try await missingSampleModel.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}
