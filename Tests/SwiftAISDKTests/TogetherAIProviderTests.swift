import Foundation
import Testing
@testable import SwiftAISDK

@Test func togetherAIImageAndRerankingUseNativeEndpoints() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"base64-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    let image = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        seed: 42,
        files: [ImageInputFile(data: Data([137, 80, 78, 71]), mediaType: "image/png")],
        extraBody: [
            "steps": 4,
            "guidance": 3.5,
            "negativePrompt": "low quality",
            "disableSafetyChecker": true
        ]
    ))

    #expect(image.base64Images == ["base64-image"])
    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.url.absoluteString == "https://api.together.xyz/v1/images/generations")
    #expect(imageRequest.headers["authorization"] == "Bearer together-key")
    #expect(imageRequest.headers["user-agent"] == "ai-sdk/togetherai/2.0.53")
    let imageBody = try decodeJSONBody(try #require(imageRequest.body))
    #expect(imageBody["model"]?.stringValue == "black-forest-labs/FLUX.1-schnell-Free")
    #expect(imageBody["prompt"]?.stringValue == "cat")
    #expect(imageBody["width"]?.intValue == 1024)
    #expect(imageBody["height"]?.intValue == 768)
    #expect(imageBody["seed"]?.intValue == 42)
    #expect(imageBody["n"] == nil)
    #expect(imageBody["response_format"]?.stringValue == "base64")
    #expect(imageBody["steps"]?.intValue == 4)
    #expect(imageBody["guidance"]?.doubleValue == 3.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "low quality")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["image_url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"id":"rank-1","model":"Salesforce/Llama-Rank-v1","results":[{"index":1,"relevance_score":0.8},{"index":0,"relevance_score":0.2}],"usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, extraBody: ["rankFields": ["title", "text"]]))

    #expect(reranking.results.map(\.index) == [1, 0])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.together.xyz/v1/rerank")
    #expect(rerankRequest.headers["authorization"] == "Bearer together-key")
    #expect(rerankRequest.headers["user-agent"] == "ai-sdk/togetherai/2.0.53")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_n"]?.intValue == 1)
    #expect(rerankBody["return_documents"]?.boolValue == false)
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "title")
}

@Test func togetherAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(
        apiKey: "together-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer together-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/togetherai/2.0.53")
}

@Test func togetherAIMapsNestedProviderOptions() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"nested-image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    _ = try await imageModel.generateImage(ImageGenerationRequest(
        prompt: "cat",
        files: [ImageInputFile(url: "https://example.com/input.png")],
        providerOptions: [
            "togetherai": .object([
                "guidance": 4.5,
                "provider_only": "option"
            ]),
            "openai": .object([
                "quality": "hd"
            ])
        ],
        extraBody: [
            "togetherai": .object([
                "steps": 3,
                "guidance": 2.5,
                "negative_prompt": "blur",
                "disable_safety_checker": true,
                "custom": "value"
            ])
        ]
    ))

    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["steps"]?.intValue == 3)
    #expect(imageBody["guidance"]?.doubleValue == 4.5)
    #expect(imageBody["negative_prompt"]?.stringValue == "blur")
    #expect(imageBody["disable_safety_checker"]?.boolValue == true)
    #expect(imageBody["custom"]?.stringValue == "value")
    #expect(imageBody["provider_only"]?.stringValue == "option")
    #expect(imageBody["image_url"]?.stringValue == "https://example.com/input.png")
    #expect(imageBody["openai"] == nil)
    #expect(imageBody["togetherai"] == nil)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}],"usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")

    _ = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: ["a"],
        topK: 1,
        providerOptions: [
            "togetherai": .object([
                "rankFields": ["text"],
                "return_documents": true
            ]),
            "openai": .object([
                "rankFields": ["drop-me"]
            ])
        ],
        extraBody: ["togetherai": .object([
            "rankFields": ["title"],
            "rawRerank": "keep-me"
        ])]
    ))

    let rerankBody = try decodeJSONBody(try #require((await rerankTransport.requests()).first?.body))
    #expect(rerankBody["rank_fields"]?[0]?.stringValue == "text")
    #expect(rerankBody["return_documents"]?.boolValue == false)
    #expect(rerankBody["rawRerank"]?.stringValue == "keep-me")
    #expect(rerankBody["openai"] == nil)
    #expect(rerankBody["togetherai"] == nil)
}

@Test func togetherAIImageSizeMappingMatchesUpstreamParseInt() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: transport))
    let model = try provider.imageModel("stabilityai/stable-diffusion-xl")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024restx768rest"))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["width"]?.intValue == 1024)
    #expect(body["height"]?.intValue == 768)
}

@Test func togetherAIImageWarningsAndMaskErrorMirrorUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"warned-image"}]}"#))
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-kontext-pro")

    let image = try await model.generateImage(ImageGenerationRequest(
        prompt: "edit",
        aspectRatio: "1:1",
        files: [
            ImageInputFile(url: "https://example.com/input-1.png"),
            ImageInputFile(url: "https://example.com/input-2.png")
        ]
    ))

    #expect(image.warnings == [
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "This model does not support the `aspectRatio` option. Use `size` instead."),
        AIWarning(type: "other", message: "Together AI only supports a single input image. Additional images are ignored.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image_url"]?.stringValue == "https://example.com/input-1.png")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "inpaint",
            files: [ImageInputFile(url: "https://example.com/input.png")],
            mask: ImageInputFile(url: "https://example.com/mask.png")
        ))
    }
}

@Test func togetherAIImageRejectsMultipleImagesPerCallLikeUpstream() async throws {
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "TogetherAI image models support at most 1 image per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
    }
}

@Test func togetherAIImageRejectsInvalidResponseShapeLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{}]}"#))
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    await #expect(throws: AIError.invalidResponse(provider: "togetherai.image", message: "TogetherAI image response contained invalid b64_json data.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func togetherAIImageProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))))
    let model = try provider.imageModel("black-forest-labs/FLUX.1-schnell-Free")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai", message: "TogetherAI provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["togetherai": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.steps", message: "TogetherAI steps must be a number or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["togetherai": ["steps": "4"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.guidance", message: "TogetherAI guidance must be a number or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["togetherai": ["guidance": "3.5"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.negative_prompt", message: "TogetherAI negative_prompt must be a string or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["togetherai": ["negative_prompt": 1]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.disable_safety_checker", message: "TogetherAI disable_safety_checker must be a boolean or null.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["togetherai": ["disable_safety_checker": "false"]]))
    }
}

@Test func togetherAIRerankingSendsJSONDocumentsAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"rank-1","model":"Salesforce/Llama-Rank-v1","results":[{"index":0,"relevance_score":0.7},{"index":1,"relevance_score":0.3}],"usage":{"prompt_tokens":2,"completion_tokens":0,"total_tokens":2}}
    """))
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: transport))
    let model = try provider.rerankingModel("Salesforce/Llama-Rank-v1")

    let ranking = try await model.rerank(RerankingRequest(
        query: "rainy day",
        documents: [
            ["example": "sunny day at the beach"],
            ["example": "rainy day in the city"]
        ],
        topK: 2,
        providerOptions: ["togetherai": .object(["rankFields": ["example"]])]
    ))

    #expect(ranking.results.map(\.score) == [0.7, 0.3])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["documents"]?[0]?["example"]?.stringValue == "sunny day at the beach")
    #expect(body["documents"]?[1]?["example"]?.stringValue == "rainy day in the city")
    #expect(body["rank_fields"]?[0]?.stringValue == "example")
    #expect(body["return_documents"]?.boolValue == false)
}

@Test func togetherAIRerankingProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}],"usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}}"#))))
    let model = try provider.rerankingModel("Salesforce/Llama-Rank-v1")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai", message: "TogetherAI provider options must be an object.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["togetherai": true]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.rankFields", message: "TogetherAI rankFields must be an array of strings.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["togetherai": ["rankFields": "text"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.togetherai.rankFields", message: "TogetherAI rankFields must be an array of strings.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["togetherai": ["rankFields": ["text", 42]]]))
    }
}

@Test func togetherAIRerankingRejectsInvalidResponseShapeLikeUpstreamSchema() async throws {
    let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}]}"#))))
    let model = try provider.rerankingModel("Salesforce/Llama-Rank-v1")

    await #expect(throws: AIError.invalidResponse(provider: "togetherai.reranking", message: "TogetherAI reranking response did not contain valid usage.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"]))
    }
}
