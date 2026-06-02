import Foundation
import Testing
@testable import SwiftAISDK

@Test func lumaImageSubmitsPollsAndDownloadsImage() async throws {
    let transport = lumaTransport(submitHeaders: ["luma-header": "submit"], pollHeaders: ["luma-header": "poll"])
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "A cute baby sea otter",
        aspectRatio: "16:9",
        providerOptions: [
            "luma": .object([
                "pollIntervalMillis": .number(1),
                "maxPollAttempts": .number(3),
                "additional_param": .string("value")
            ]),
            "openai": .object(["unrelated": .string("ignored")])
        ]
    ))

    #expect(result.urls == ["https://luma.example.com/image.png"])
    #expect(result.base64Images == [Data("luma-png".utf8).base64EncodedString()])
    #expect(result.responseMetadata.id == "lum-1")
    #expect(result.responseMetadata.modelID == "photon-1")
    #expect(result.responseMetadata.headers["luma-header"] == "submit")
    #expect(result.responseMetadata.body?["assets"]?["image"]?.stringValue == "https://luma.example.com/image.png")

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.absoluteString == "https://api.lumalabs.ai/dream-machine/v1/generations/image")
    #expect(requests[0].headers["Authorization"] == "Bearer luma-key")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "A cute baby sea otter")
    #expect(body["model"]?.stringValue == "photon-1")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["additional_param"]?.stringValue == "value")
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["maxPollAttempts"] == nil)
    #expect(body["luma"] == nil)
    #expect(body["openai"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.lumalabs.ai/dream-machine/v1/generations/lum-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://luma.example.com/image.png")
}

@Test func lumaImageReturnsWarningsForUnsupportedSizeAndSeed() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        seed: 123,
        providerOptions: ["luma": .object(["pollIntervalMillis": .number(1)])]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "seed", message: "This model does not support the `seed` option."),
        AIWarning(type: "unsupported", feature: "size", message: "This model does not support the `size` option. Use `aspectRatio` instead.")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["aspect_ratio"] == nil)
    #expect(body["seed"] == nil)
}

@Test func lumaProviderOptionsAspectRatioPassthroughMatchesUpstream() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "wide landscape",
        aspectRatio: "16:9",
        providerOptions: [
            "luma": .object([
                "aspectRatio": .string("custom-passthrough"),
                "aspect_ratio": .string("1:1"),
                "pollIntervalMillis": .number(1)
            ])
        ],
        extraBody: [
            "luma": .object([
                "aspectRatio": .string("4:3")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["aspectRatio"]?.stringValue == "custom-passthrough")
}

@Test func lumaProviderOptionsValidateKnownSchemaFields() async throws {
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: lumaTransport()))
    let model = try provider.imageModel("photon-1")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.luma", message: "Luma provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Invalid namespace",
            providerOptions: ["luma": .string("bad")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Invalid reference type",
            providerOptions: ["luma": .object(["referenceType": .string("invalid")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Invalid weight",
            files: [ImageInputFile(url: "https://example.com/input.jpg")],
            providerOptions: ["luma": .object(["images": .array([.object(["weight": .number(2)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Invalid polling",
            providerOptions: ["luma": .object(["pollIntervalMillis": .string("fast")])]
        ))
    }
}

@Test func lumaProviderOptionsNullNamespaceUsesExtraBodyLikeUpstream() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use extra body",
        providerOptions: ["luma": .null],
        extraBody: [
            "luma": .object([
                "aspectRatio": .string("4:3"),
                "additional_param": .string("value"),
                "pollIntervalMillis": .number(1)
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["aspect_ratio"]?.stringValue == "4:3")
    #expect(body["additional_param"]?.stringValue == "value")
}

@Test func lumaMaxPollAttemptsZeroMatchesUpstreamNoPolling() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "No polling",
            providerOptions: ["luma": .object(["maxPollAttempts": .number(0)])]
        ))
    }

    let requests = await transport.requests()
    #expect(requests.count == 1)
    #expect(requests[0].method == "POST")
}

@Test func lumaProviderOptionsNullishFieldsClearExtraBodyDefaults() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Use default image references",
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        providerOptions: [
            "luma": .object([
                "referenceType": .null,
                "images": .null,
                "pollIntervalMillis": .number(1)
            ])
        ],
        extraBody: [
            "luma": .object([
                "referenceType": .string("style"),
                "images": .array([.object(["weight": .number(0.2)])])
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image"]?[0]?["url"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["image"]?[0]?["weight"]?.doubleValue == 0.85)
    #expect(body["style"] == nil)
}

@Test func lumaImageMapsURLFilesAsDefaultImageReferences() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Combine these concepts",
        files: [
            ImageInputFile(url: "https://example.com/input1.jpg"),
            ImageInputFile(url: "https://example.com/input2.jpg")
        ],
        providerOptions: [
            "luma": .object([
                "images": .array([.object(["weight": .number(0.5)])]),
                "pollIntervalMillis": .number(1)
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image"]?[0]?["url"]?.stringValue == "https://example.com/input1.jpg")
    #expect(body["image"]?[0]?["weight"]?.doubleValue == 0.5)
    #expect(body["image"]?[1]?["url"]?.stringValue == "https://example.com/input2.jpg")
    #expect(body["image"]?[1]?["weight"]?.doubleValue == 0.85)
    #expect(body["images"] == nil)
}

@Test func lumaImageMapsStyleReferences() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "A dog in this style",
        files: [ImageInputFile(url: "https://example.com/style.jpg")],
        providerOptions: [
            "luma": .object([
                "referenceType": .string("style"),
                "images": .array([.object(["weight": .number(0.6)])]),
                "pollIntervalMillis": .number(1),
                "additional_param": .string("value")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["style"]?[0]?["url"]?.stringValue == "https://example.com/style.jpg")
    #expect(body["style"]?[0]?["weight"]?.doubleValue == 0.6)
    #expect(body["additional_param"]?.stringValue == "value")
    #expect(body["referenceType"] == nil)
    #expect(body["images"] == nil)
}

@Test func lumaImageMapsCharacterReferencesWithIdentities() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Two people talking",
        files: [
            ImageInputFile(url: "https://example.com/person1.jpg"),
            ImageInputFile(url: "https://example.com/person2.jpg")
        ],
        providerOptions: [
            "luma": .object([
                "referenceType": .string("character"),
                "images": .array([
                    .object(["id": .string("identity0")]),
                    .object(["id": .string("identity1")])
                ]),
                "pollIntervalMillis": .number(1)
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["character"]?["identity0"]?["images"]?[0]?.stringValue == "https://example.com/person1.jpg")
    #expect(body["character"]?["identity1"]?["images"]?[0]?.stringValue == "https://example.com/person2.jpg")
}

@Test func lumaImageMapsModifyImageReference() async throws {
    let transport = lumaTransport()
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "Transform flowers",
        files: [ImageInputFile(url: "https://example.com/input.jpg")],
        providerOptions: ["luma": .object(["referenceType": .string("modify_image"), "pollIntervalMillis": .number(1)])]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["modify_image"]?["url"]?.stringValue == "https://example.com/input.jpg")
    #expect(body["modify_image"]?["weight"]?.intValue == 1)
}

@Test func lumaImageRejectsUnsupportedEditingInputs() async throws {
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: lumaTransport()))
    let model = try provider.imageModel("photon-1")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Masked edit",
            files: [ImageInputFile(url: "https://example.com/input.jpg")],
            mask: ImageInputFile(url: "https://example.com/mask.png")
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Data edit",
            files: [ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Too many",
            files: (1...5).map { ImageInputFile(url: "https://example.com/\($0).jpg") }
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "Edit multiple",
            files: [
                ImageInputFile(url: "https://example.com/input1.jpg"),
                ImageInputFile(url: "https://example.com/input2.jpg")
            ],
            providerOptions: ["luma": .object(["referenceType": .string("modify_image")])]
        ))
    }
}

private func lumaTransport(submitHeaders: [String: String] = [:], pollHeaders: [String: String] = [:]) -> RecordingTransport {
    RecordingTransport(responses: [
        jsonResponse(#"{"id":"lum-1","state":"queued","model":"photon-1"}"#, headers: submitHeaders),
        jsonResponse(#"{"id":"lum-1","state":"completed","model":"photon-1","assets":{"image":"https://luma.example.com/image.png"}}"#, headers: pollHeaders),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("luma-png".utf8))
    ])
}
