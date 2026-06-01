import Foundation
import Testing
@testable import SwiftAISDK

@Test func quiverAIImageGeneratesSVGAndForwardsOptions() async throws {
    let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
    let transport = RecordingTransport(response: quiverAIResponse(svg: svg, id: "svg-gen-1", created: 1_713_374_400, usage: true, headers: ["x-quiver": "image"]))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
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
    #expect(request.headers["Authorization"] == "Bearer quiver-key")
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

@Test func quiverAIVectorizesSingleImage() async throws {
    let svg = #"<svg viewBox="0 0 4 4"><path d="M0 0L4 4"/></svg>"#
    let transport = RecordingTransport(response: quiverAIResponse(svg: svg, id: "svg-vec-1", created: 1_713_374_460))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
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

@Test func quiverAIWarnsForUnsupportedStandardImageOptions() async throws {
    let transport = RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-warnings"))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
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
    let maxProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-max"))))
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

    let regularProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "svg-regular"))))
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
}

@Test func quiverAIFailsFastForInvalidOperationInputs() async throws {
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: RecordingTransport(response: quiverAIResponse(svg: "<svg/>", id: "unused"))))
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

private func quiverAIResponse(svg: String, id: String, created: Int = 1_713_374_400, usage: Bool = false, headers: [String: String] = [:]) -> AIHTTPResponse {
    let usageJSON = usage ? #","usage":{"total_tokens":21,"input_tokens":12,"output_tokens":9}"# : ""
    return jsonResponse("""
    {"id":"\(id)","created":\(created),"data":[{"svg":"\(svg.replacingOccurrences(of: "\"", with: "\\\""))","mime_type":"image/svg+xml"}]\(usageJSON)}
    """, headers: headers)
}
