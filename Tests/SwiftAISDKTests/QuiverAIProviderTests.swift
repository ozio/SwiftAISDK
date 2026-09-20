import Foundation
import Testing
@testable import SwiftAISDK

@Suite(.serialized)
struct QuiverAIProviderTests {

@Test func quiverAIImageGeneratesSVGAndForwardsOptions() async throws {
    let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
    let transport = RecordingTransport(response: quiverAIResponse(svg: svg, id: "svg-gen-1", created: 1_713_374_400, usage: true, headers: ["x-quiver": "image"]))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw a square icon.",
        count: 1,
        files: [
            ImageInputFile(url: "https://example.com/reference-1.png"),
            ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png")
        ],
        providerOptions: [
            "quiverai": .object([
                "instructions": "Use clean geometry.",
                "temperature": 0.4,
                "topP": 0.95,
                "presencePenalty": 0.2,
                "maxOutputTokens": 4096
            ])
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    #expect(result.usage?.inputTokens == 12)
    #expect(result.usage?.outputTokens == 9)
    #expect(result.usage?.totalTokens == 21)
    #expect(result.providerMetadata["quiverai"]?["images"]?[0]?["index"]?.intValue == 0)
    #expect(result.providerMetadata["quiverai"]?["images"]?[0]?["mimeType"]?.stringValue == "image/svg+xml")
    #expect(result.responseMetadata.id == "svg-gen-1")
    #expect(result.responseMetadata.modelID == "arrow-1")
    #expect(result.responseMetadata.headers["x-quiver"] == "image")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/generations")
    #expect(request.headers["authorization"] == "Bearer quiver-key")
    #expect(request.headers["user-agent"] == "ai-sdk/quiverai/2.0.45")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["prompt"]?.stringValue == "Draw a square icon.")
    #expect(body["n"]?.intValue == 1)
    #expect(body["stream"]?.boolValue == false)
    #expect(body["instructions"]?.stringValue == "Use clean geometry.")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.95)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["max_output_tokens"]?.intValue == 4096)
    #expect(body["references"]?[0]?["url"]?.stringValue == "https://example.com/reference-1.png")
    #expect(body["references"]?[1]?["base64"]?.stringValue == "BAUG")
}

@Test func quiverAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-custom"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(
        apiKey: "quiver-key",
        baseURL: "https://api.quiver.ai/v1",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.imageModel("arrow-1")

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw a square."))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer quiver-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/quiverai/2.0.45")
}

@Test func quiverAIReadsEnvironmentSettingsLikeUpstream() async throws {
    try await withTemporaryQuiverAIEnvironment([
        "QUIVERAI_API_KEY": "env-quiver-key",
        "QUIVERAI_BASE_URL": "https://env.quiver.ai/v1/"
    ]) {
        let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-env"))
        let provider = try AIProviders.quiverAI(settings: ProviderSettings(transport: transport))
        let model = try provider.imageModel("arrow-1")

        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw from env."))

        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://env.quiver.ai/v1/svgs/generations")
        #expect(request.headers["authorization"] == "Bearer env-quiver-key")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["model"]?.stringValue == "arrow-1")
    }
}

@Test func quiverAIMissingAPIKeyMatchesUpstreamLoadError() async throws {
    _ = await withTemporaryQuiverAIEnvironment([
        "QUIVERAI_API_KEY": nil
    ]) {
        #expect(throws: AIError.missingAPIKey(provider: "quiverai", environmentVariables: ["QUIVERAI_API_KEY"])) {
            _ = try AIProviders.quiverAI(settings: ProviderSettings(transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "unused"))))
        }
    }
}

@Test func quiverAIPrefersExplicitSettingsAndSupportsCanonicalModelIDsLikeUpstream() async throws {
    try await withTemporaryQuiverAIEnvironment([
        "QUIVERAI_API_KEY": "env-quiver-key",
        "QUIVERAI_BASE_URL": "https://env.quiver.ai/v1"
    ]) {
        let transport = RecordingTransport(responses: [
            quiverAIResponse(svg: "<svg>1</svg>", id: "svg-arrow-1"),
            quiverAIResponse(svg: "<svg>2</svg>", id: "svg-arrow-1-1"),
            quiverAIResponse(svg: "<svg>3</svg>", id: "svg-arrow-1-1-max"),
            quiverAIResponse(svg: "<svg>4</svg>", id: "svg-arrow-2"),
            quiverAIResponse(svg: "<svg>5</svg>", id: "svg-arrow-2-telos")
        ])
        let provider = try AIProviders.quiverAI(settings: ProviderSettings(
            apiKey: "explicit-quiver-key",
            baseURL: "https://override.quiver.ai/v1/",
            headers: ["X-QuiverAI-Test": "1"],
            transport: transport
        ))

        for modelID in ["arrow-1", "arrow-1.1", "arrow-1.1-max", "arrow-2", "arrow-2-telos"] {
            let imageModel = try provider.imageModel(modelID)
            #expect(imageModel.providerID == "quiverai.image")
            #expect(imageModel.modelID == modelID)
            let result = try await imageModel.generateImage(ImageGenerationRequest(prompt: "Draw \(modelID)."))
            #expect(result.responseMetadata.modelID == modelID)
        }

        let requests = await transport.requests()
        #expect(requests.map(\.url.absoluteString) == [
            "https://override.quiver.ai/v1/svgs/generations",
            "https://override.quiver.ai/v1/svgs/generations",
            "https://override.quiver.ai/v1/svgs/generations",
            "https://override.quiver.ai/v1/svgs/generations",
            "https://override.quiver.ai/v1/svgs/generations"
        ])
        #expect(requests.allSatisfy { $0.headers["authorization"] == "Bearer explicit-quiver-key" })
        #expect(requests.allSatisfy { $0.headers["x-quiverai-test"] == "1" })
        let bodies = try requests.map { try decodeJSONBody(try #require($0.body)) }
        #expect(bodies.map { $0["model"]?.stringValue } == ["arrow-1", "arrow-1.1", "arrow-1.1-max", "arrow-2", "arrow-2-telos"])
    }
}

@Test func quiverAIVectorizesSingleImage() async throws {
    let svg = #"<svg viewBox="0 0 4 4"><path d="M0 0L4 4"/></svg>"#
    let transport = RecordingTransport(response: quiverAIResponse(svg: svg, id: "svg-vec-1", created: 1_713_374_460))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/logo.png")],
        providerOptions: [
            "quiverai": .object([
                "autoCrop": true,
                "targetSize": 1024,
                "temperature": 0.4,
                "topP": 0.95,
                "presencePenalty": 0.2,
                "maxOutputTokens": 4096
            ])
        ],
        extraBody: [
            "quiverai": .object([
                "operation": "vectorize",
                "autoCrop": false,
                "targetSize": 512
            ])
        ]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == svg)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/vectorizations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "arrow-1")
    #expect(body["image"]?["url"]?.stringValue == "https://example.com/logo.png")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.95)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["max_output_tokens"]?.intValue == 4096)
    #expect(body["auto_crop"]?.boolValue == true)
    #expect(body["target_size"]?.intValue == 1024)
    #expect(body["stream"]?.boolValue == false)
}

@Test func quiverAIProviderOptionsAreSchemaScopedLikeUpstream() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-schema"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw a crisp mark.",
        count: 1,
        providerOptions: [
            "quiverai": .object([
                "operation": "generate",
                "instructions": "Use crisp geometry.",
                "temperature": 0.4,
                "topP": 0.8,
                "presencePenalty": .null,
                "maxOutputTokens": 256,
                "autoCrop": true,
                "targetSize": 1024,
                "top_p": 0.1,
                "presence_penalty": 0.9,
                "max_output_tokens": 12,
                "seed": 123,
                "ignored": true
            ])
        ],
        extraBody: [
            "quiverai": .object([
                "temperature": 1.2,
                "topP": 0.2,
                "presencePenalty": 0.5,
                "maxOutputTokens": 100
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/generations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instructions"]?.stringValue == "Use crisp geometry.")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.8)
    #expect(body["presence_penalty"] == .null)
    #expect(body["max_output_tokens"]?.intValue == 256)
    #expect(body["seed"] == nil)
    #expect(body["ignored"] == nil)
    #expect(body["auto_crop"] == nil)
    #expect(body["target_size"] == nil)
}

@Test func quiverAIProviderOptionsValidateLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-schema-validation"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-1")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.quiverai", message: "QuiverAI provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": "bad"]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["operation": "paint"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["instructions": ""]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["temperature": 3]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["topP": -0.1]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["presencePenalty": -3]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["maxOutputTokens": 1.5]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["autoCrop": "true"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["targetSize": 127]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["temperature": nil]]))
    }

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw",
        providerOptions: ["quiverai": .null],
        extraBody: ["quiverai": ["temperature": 1.2]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["temperature"]?.doubleValue == 1.2)
}

@Test func quiverAIRejectsMoreThanMaxImagesPerCallLikeUpstream() async throws {
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "unused"))))
    let model = try provider.imageModel("arrow-1.1-max")

    await #expect(throws: AIError.invalidArgument(argument: "count", message: "QuiverAI image models support at most 16 images per call.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", count: 17))
    }
}

@Test func quiverAIRejectsInvalidResponseShapeLikeUpstreamSchema() async throws {
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: jsonResponse(#"{"id":"svg-bad","created":1,"data":[{"svg":"","mime_type":"image/svg+xml"}]}"#))))
    let model = try provider.imageModel("arrow-1")

    await #expect(throws: AIError.invalidResponse(provider: "quiverai.image", message: "QuiverAI image response is invalid.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw"))
    }
}

@Test func quiverAIUsesUpstreamHTTPErrorEnvelopeRetryability() async throws {
    let retryableTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 429,
        headers: ["content-type": "application/json"],
        body: Data(#"{"status":429,"code":"rate_limit","message":"Slow down.","request_id":"req_1"}"#.utf8)
    ))
    let retryableProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: retryableTransport))
    let retryableModel = try retryableProvider.imageModel("arrow-1")

    do {
        _ = try await retryableModel.generateImage(ImageGenerationRequest(prompt: "Draw"))
        Issue.record("Expected QuiverAI retryable API error.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.provider == "quiverai.image")
        #expect(apiError.statusCode == 429)
        #expect(apiError.isRetryable)
        #expect(apiError.responseBody.contains("Slow down."))
        #expect(apiError.responseBody.contains(#""request_id":"req_1""#))
    }

    let clientTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["content-type": "application/json"],
        body: Data(#"{"status":400,"code":"bad_request","message":"Prompt is invalid.","request_id":"req_2"}"#.utf8)
    ))
    let clientProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: clientTransport))
    let clientModel = try clientProvider.imageModel("arrow-1")

    do {
        _ = try await clientModel.generateImage(ImageGenerationRequest(prompt: "Draw"))
        Issue.record("Expected QuiverAI non-retryable API error.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.provider == "quiverai.image")
        #expect(apiError.statusCode == 400)
        #expect(!apiError.isRetryable)
        #expect(apiError.responseBody.contains("Prompt is invalid."))
    }
}

@Test func quiverAIWarnsForUnsupportedStandardImageOptions() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-warnings"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw",
        size: "1024x1024",
        aspectRatio: "1:1",
        seed: 42,
        mask: ImageInputFile(data: Data("mask".utf8), mediaType: "image/png")
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "QuiverAI SVG generation does not support the `size` option. The setting was ignored."),
        AIWarning(type: "unsupported", feature: "aspectRatio", message: "QuiverAI SVG generation does not support the `aspectRatio` option. The setting was ignored."),
        AIWarning(type: "unsupported", feature: "seed", message: "QuiverAI SVG generation does not support the `seed` option. The setting was ignored."),
        AIWarning(type: "unsupported", feature: "mask", message: "QuiverAI SVG generation does not support masks. The mask was ignored.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["size"] == nil)
    #expect(body["aspectRatio"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["mask"] == nil)
}

@Test func quiverAIReferenceLimitsMatchUpstreamModels() async throws {
    let maxProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-max"))))
    let maxModel = try maxProvider.imageModel("arrow-1.1-max")

    _ = try await maxModel.generateImage(ImageGenerationRequest(
        prompt: "Draw",
        files: (0..<16).map { ImageInputFile(url: "https://example.com/reference-\($0).png") }
    ))

    do {
        _ = try await maxModel.generateImage(ImageGenerationRequest(
            prompt: "Draw",
            files: (0..<17).map { ImageInputFile(url: "https://example.com/reference-\($0).png") }
        ))
        Issue.record("Expected QuiverAI to reject too many reference images.")
    } catch let error as AIError {
        #expect(String(describing: error).contains("supports up to 16 reference images"))
    }

    let regularProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-regular"))))
    let regularModel = try regularProvider.imageModel("arrow-1")
    do {
        _ = try await regularModel.generateImage(ImageGenerationRequest(
            prompt: "Draw",
            files: (0..<5).map { ImageInputFile(url: "https://example.com/reference-\($0).png") }
        ))
        Issue.record("Expected QuiverAI regular models to reject more than 4 references.")
    } catch let error as AIError {
        #expect(String(describing: error).contains("supports up to 4 reference images"))
    }

    let arrow2Provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-arrow2-references"))))
    let arrow2Model = try arrow2Provider.imageModel("arrow-2")
    let sixteenReferences = (0..<16).map { ImageInputFile(url: "https://example.com/arrow2-reference-\($0).png") }
    _ = try await arrow2Model.generateImage(ImageGenerationRequest(prompt: "Draw", files: sixteenReferences))
    await #expect(throws: AIError.self) {
        _ = try await arrow2Model.generateImage(ImageGenerationRequest(prompt: "Draw", files: sixteenReferences + [sixteenReferences[0]]))
    }
}

@Test func quiverAIFailsFastForInvalidOperationInputs() async throws {
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "unused"))))
    let model = try provider.imageModel("arrow-1")

    do {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "   "))
        Issue.record("Expected QuiverAI generate to reject empty prompts.")
    } catch let error as AIError {
        #expect(String(describing: error).contains("requires a non-empty prompt"))
    }

    do {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "",
            providerOptions: ["quiverai": .object(["operation": "vectorize"])]
        ))
        Issue.record("Expected QuiverAI vectorize to require an image.")
    } catch let error as AIError {
        #expect(String(describing: error).contains("requires an input image"))
    }

    do {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "",
            files: [
                ImageInputFile(url: "https://example.com/one.png"),
                ImageInputFile(url: "https://example.com/two.png")
            ],
            providerOptions: ["quiverai": .object(["operation": "vectorize"])]
        ))
        Issue.record("Expected QuiverAI vectorize to reject multiple images.")
    } catch let error as AIError {
        #expect(String(describing: error).contains("accepts a single input image"))
    }
}

@Test func quiverAIArrow2ForwardsGenerationAndVectorizationOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        quiverAIResponse(svg: "<svg/>", id: "arrow2-generate", usage: true),
        quiverAIResponse(svg: "<svg/>", id: "arrow2-vectorize", usage: true)
    ])
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
    let model = try provider.imageModel("arrow-2")
    let arrow2Options: JSONValue = .object([
        "reasoningEffort": "high",
        "attributes": .object([
            "viewBox": .object(["minX": -10, "minY": 0, "width": 100, "height": 50])
        ]),
        "maxOutputTokens": 65_536
    ])

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Draw a mark.",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/reference.png")],
        providerOptions: ["quiverai": arrow2Options]
    ))
    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "",
        count: 1,
        files: [ImageInputFile(url: "https://example.com/reference.png")],
        providerOptions: [
            "quiverai": .object(try #require(arrow2Options.objectValue).merging(["operation": "vectorize"]) { _, new in new })
        ]
    ))

    let requests = await transport.requests()
    #expect(requests.map(\.url.absoluteString) == [
        "https://api.quiver.ai/v1/svgs/generations",
        "https://api.quiver.ai/v1/svgs/vectorizations"
    ])
    let bodies = try requests.map { try decodeJSONBody(try #require($0.body)) }
    for body in bodies {
        #expect(body["reasoning_effort"]?.stringValue == "high")
        #expect(body["attributes"]?["viewBox"]?["minX"]?.intValue == -10)
        #expect(body["attributes"]?["viewBox"]?["width"]?.intValue == 100)
        #expect(body["max_output_tokens"]?.intValue == 65_536)
        #expect(body["stream"]?.boolValue == false)
    }
    #expect(bodies[0]["n"]?.intValue == 1)
    #expect(bodies[1]["n"] == nil)
}

@Test func quiverAIAnimatesSVGAndPreservesTimingMetadataLikeUpstream() async throws {
    let sourceSVG = #"<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>"#
    let animatedSVG = #"<svg><circle><animate dur="1200ms"/></circle></svg>"#
    let response = jsonResponse("""
    {"id":"svg-animation-1","created":1713374520,"data":[{"svg":"\(animatedSVG.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml","loop_period_ms":1200,"opening_animation_ms":null}],"usage":{"total_tokens":24,"input_tokens":13,"output_tokens":11}}
    """)
    let transport = RecordingTransport(response: response)
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))

    let result = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(
        prompt: "",
        count: 1,
        files: [ImageInputFile(data: Data(sourceSVG.utf8), mediaType: "image/svg+xml")],
        providerOptions: ["quiverai": ["operation": "animate"]]
    ))

    #expect(String(data: Data(base64Encoded: try #require(result.base64Images.first)) ?? Data(), encoding: .utf8) == animatedSVG)
    #expect(result.providerMetadata["quiverai"]?["images"]?[0]?["loopPeriodMs"]?.intValue == 1200)
    #expect(result.providerMetadata["quiverai"]?["images"]?[0]?["openingAnimationMs"] == .null)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/animations")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body == .object([
        "model": "arrow-2",
        "svg_source": .object(["base64": .string(Data(sourceSVG.utf8).base64EncodedString())]),
        "stream": false
    ]))
}

@Test func quiverAIAnimationForwardsURLInstructionAndSupportedOptions() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-animation-options"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))

    _ = try await provider.imageModel("arrow-2-telos").generateImage(ImageGenerationRequest(
        prompt: "Make the circle pulse gently.",
        files: [ImageInputFile(url: "https://example.com/source.svg")],
        providerOptions: [
            "quiverai": .object([
                "operation": "animate",
                "temperature": 0.4,
                "maxOutputTokens": 4096,
                "reasoningEffort": "medium"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body == .object([
        "model": "arrow-2-telos",
        "svg_source": .object(["url": "https://example.com/source.svg"]),
        "prompt": "Make the circle pulse gently.",
        "temperature": 0.4,
        "max_output_tokens": 4096,
        "reasoning_effort": "medium",
        "stream": false
    ]))
}

@Test func quiverAIArrow2EditsSVGWithReferencesAndSettingsLikeUpstream() async throws {
    let sourceSVG = #"<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>"#
    let referenceSVG = #"<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>"#
    let binaryReference = try prepareQuiverAIImageReference(Data(referenceSVG.utf8))
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg><rect fill=\"blue\"/></svg>", id: "svg-edit-1", usage: true))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))

    _ = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(
        prompt: "Change the rectangle fill to blue.",
        count: 1,
        files: [ImageInputFile(data: Data(sourceSVG.utf8), mediaType: "image/svg+xml")],
        providerOptions: [
            "quiverai": .object([
                "operation": "edit",
                "referenceImages": .array([
                    QuiverAIImageReference.url("https://example.com/reference.png").jsonValue,
                    binaryReference.jsonValue
                ]),
                "maxReviewSteps": 2,
                "reasoningEffort": "high",
                "maxOutputTokens": 4096,
                "orchestratorMaxOutputTokens": 2048,
                "shallowMaxOutputTokens": 1024,
                "temperature": 0.3
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/svgs/edits")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["svg_source"]?["base64"]?.stringValue == Data(sourceSVG.utf8).base64EncodedString())
    #expect(body["reference_images"]?[0]?["url"]?.stringValue == "https://example.com/reference.png")
    #expect(body["reference_images"]?[1]?["base64"]?.stringValue == Data(referenceSVG.utf8).base64EncodedString())
    #expect(body["max_review_steps"]?.intValue == 2)
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["settings"]?["max_output_tokens"]?.intValue == 4096)
    #expect(body["settings"]?["orchestrator_max_output_tokens"]?.intValue == 2048)
    #expect(body["settings"]?["shallow_max_output_tokens"]?.intValue == 1024)
    #expect(body["settings"]?["temperature"]?.doubleValue == 0.3)
}

@Test func prepareQuiverAIImageReferenceMatchesUpstreamInputsAndValidation() throws {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg"/>"#
    let svgData = Data(svg.utf8)
    let svgBase64 = svgData.base64EncodedString()

    #expect(try prepareQuiverAIImageReference(URL(string: "https://example.com/reference.svg")!) == .url("https://example.com/reference.svg"))
    #expect(try prepareQuiverAIImageReference("http://example.com/reference.png") == .url("http://example.com/reference.png"))
    #expect(try prepareQuiverAIImageReference(svgData) == .base64(svgBase64))
    #expect(try prepareQuiverAIImageReference(svgBase64) == .base64(svgBase64))
    #expect(try prepareQuiverAIImageReference("data:image/svg+xml;base64,\(svgBase64)") == .base64(svgBase64))
    #expect(throws: AIError.self) { _ = try prepareQuiverAIImageReference("ftp://example.com/reference.png") }
    #expect(throws: AIError.self) { _ = try prepareQuiverAIImageReference("not base64!") }
    #expect(throws: AIError.self) { _ = try prepareQuiverAIImageReference("data:image/bmp;base64,Qk0=") }
    #expect(throws: AIError.self) { _ = try prepareQuiverAIImageReference(Data([1, 2, 3])) }
}

@Test func quiverAIPreservesFixedCreditsWithoutUsageLikeUpstream() async throws {
    for credits in [0, 20] {
        let transport = RecordingTransport(response: jsonResponse("""
        {"id":"svg-credit","created":1713374400,"data":[{"svg":"<svg/>","mime_type":"image/svg+xml"}],"credits":\(credits)}
        """))
        let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))
        let result = try await provider.imageModel("arrow-1.1").generateImage(ImageGenerationRequest(prompt: "Draw"))
        #expect(result.usage == nil)
        #expect(result.providerMetadata["quiverai"]?["credits"]?.intValue == credits)
    }
}

@Test func quiverAIArrow2ValidationsFailBeforeNetworkingLikeUpstream() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "unused"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", baseURL: "https://api.quiver.ai/v1", transport: transport))

    await #expect(throws: AIError.self) {
        _ = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(prompt: "Draw", providerOptions: ["quiverai": ["maxOutputTokens": 65_537]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await provider.imageModel("arrow-1.1").generateImage(ImageGenerationRequest(
            prompt: "",
            files: [ImageInputFile(url: "https://example.com/source.svg")],
            providerOptions: ["quiverai": ["operation": "animate"]]
        ))
    }
    await #expect(throws: AIError.self) {
        _ = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(
            prompt: "   ",
            files: [ImageInputFile(url: "https://example.com/source.svg")],
            providerOptions: ["quiverai": ["operation": "animate"]]
        ))
    }
    await #expect(throws: AIError.self) {
        _ = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(
            prompt: "Make it blue.",
            files: [ImageInputFile(data: Data("<svg><g></svg>".utf8), mediaType: "image/svg+xml")],
            providerOptions: ["quiverai": ["operation": "edit"]]
        ))
    }
    await #expect(throws: AIError.self) {
        _ = try await provider.imageModel("arrow-2").generateImage(ImageGenerationRequest(
            prompt: "Make it blue.",
            files: [ImageInputFile(url: "https://example.com/source.svg")],
            providerOptions: ["quiverai": ["operation": "edit", "maxReviewSteps": 6]]
        ))
    }
    #expect(await transport.requests().isEmpty)
}

}

private func quiverAIResponse(svg: String, id: String, created: Int = 1_713_374_400, usage: Bool = false, headers: [String: String] = [:]) -> AIHTTPResponse {
    let usageJSON = usage ? #","usage":{"total_tokens":21,"input_tokens":12,"output_tokens":9}"# : ""
    return jsonResponse("""
    {"id":"\(id)","created":\(created),"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}]\(usageJSON)}
    """, headers: headers)
}

private func withTemporaryQuiverAIEnvironment<T>(_ updates: [String: String?], operation: () async throws -> T) async rethrows -> T {
    var previous: [String: String] = [:]
    var missing = Set<String>()
    for key in updates.keys {
        if let existing = getenv(key).map({ String(cString: $0) }) {
            previous[key] = existing
        } else {
            missing.insert(key)
        }
    }
    for (key, value) in updates {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
    defer {
        for key in updates.keys {
            if missing.contains(key) {
                unsetenv(key)
            } else if let value = previous[key] {
                setenv(key, value, 1)
            }
        }
    }
    return try await operation()
}
