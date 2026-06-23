import Foundation
import Testing
@testable import SwiftAISDK

@Test func blackForestLabsImageSubmitsPollsDownloadsAndPreservesMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-1","polling_url":"https://api.bfl.ai/v1/get_result","cost":0.01,"input_mp":0.5,"output_mp":0.75}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/image.png","seed":42,"start_time":1,"end_time":3,"duration":2}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png", "x-image": "yes"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        seed: 123,
        providerOptions: [
            "blackForestLabs": .object([
                "promptUpsampling": true,
                "outputFormat": "png",
                "imagePromptStrength": 0.4,
                "safetyTolerance": 2,
                "webhookUrl": "https://hooks.example.com/bfl",
                "inputImage": "image-b64",
                "unsupportedProperty": "drop-me",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ]),
            "openai": .object([
                "promptUpsampling": false
            ])
        ],
        headers: ["x-request-id": "req-1"]
    ))

    #expect(result.urls == ["https://bfl.example.com/image.png"])
    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "size",
            message: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
        )
    ])
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["seed"]?.intValue == 42)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["start_time"]?.intValue == 1)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["end_time"]?.intValue == 3)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["duration"]?.intValue == 2)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["cost"]?.doubleValue == 0.01)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["inputMegapixels"]?.doubleValue == 0.5)
    #expect(result.providerMetadata["blackForestLabs"]?["images"]?[0]?["outputMegapixels"]?.doubleValue == 0.75)
    #expect(result.responseMetadata.modelID == "flux-pro-1.1")
    #expect(result.responseMetadata.headers["x-image"] == "yes")
    #expect(result.responseMetadata.body == nil)
    #expect(result.requestMetadata.headers["x-request-id"] == "req-1")

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].method == "POST")
    #expect(requests[0].url.absoluteString == "https://api.bfl.ai/v1/flux-pro-1.1")
    #expect(requests[0].headers["x-key"] == "bfl-key")
    #expect(requests[0].headers["user-agent"] == "ai-sdk/black-forest-labs/1.0.38")
    #expect(requests[0].headers["x-request-id"] == "req-1")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["aspect_ratio"]?.stringValue == "4:3")
    #expect(body["width"]?.intValue == 1024)
    #expect(body["height"]?.intValue == 768)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["image_prompt_strength"]?.doubleValue == 0.4)
    #expect(body["safety_tolerance"]?.intValue == 2)
    #expect(body["webhook_url"]?.stringValue == "https://hooks.example.com/bfl")
    #expect(body["input_image"]?.stringValue == "image-b64")
    #expect(body["unsupportedProperty"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.bfl.ai/v1/get_result?id=bfl-1")
    #expect(requests[1].headers["x-key"] == "bfl-key")
    #expect(requests[1].headers["user-agent"] == "ai-sdk/black-forest-labs/1.0.38")
    #expect(requests[1].headers["x-request-id"] == "req-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://bfl.example.com/image.png")
    #expect(requests[2].headers["x-key"] == nil)
    #expect(requests[2].headers["user-agent"] == nil)
    #expect(requests[2].headers["x-request-id"] == nil)
}

@Test func blackForestLabsAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-1","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("bfl-png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.imageModel("flux-pro-1.1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "A forest path",
        providerOptions: ["blackForestLabs": .object(["pollIntervalMillis": .number(1), "pollTimeoutMillis": .number(1000)])]
    ))

    let requests = await transport.requests()
    #expect(requests[0].headers["x-key"] == "bfl-key")
    #expect(requests[0].headers["user-agent"] == "CustomApp/1.0 ai-sdk/black-forest-labs/1.0.38")
    #expect(requests[1].headers["x-key"] == "bfl-key")
    #expect(requests[1].headers["user-agent"] == "CustomApp/1.0 ai-sdk/black-forest-labs/1.0.38")
    #expect(requests[2].headers["x-key"] == nil)
    #expect(requests[2].headers["user-agent"] == nil)
}

@Test func blackForestLabsUsesUpstreamErrorMessageSchema() async throws {
    let submitProvider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 422,
            headers: ["x-bfl": "bad"],
            body: Data(#"{"detail":{"error":"bad prompt"}}"#.utf8)
        ))
    ))
    let submitModel = try submitProvider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.apiCall(
        provider: "black-forest-labs.image",
        statusCode: 422,
        body: #"{"error":"bad prompt"}"#,
        headers: ["x-bfl": "bad"]
    )) {
        _ = try await submitModel.generateImage(ImageGenerationRequest(prompt: "bad"))
    }

    let pollProvider = try AIProviders.blackForestLabs(settings: ProviderSettings(
        apiKey: "bfl-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"id":"bfl-poll-error","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
            AIHTTPResponse(statusCode: 500, headers: [:], body: Data(#"{"message":"poll failed"}"#.utf8))
        ])
    ))
    let pollModel = try pollProvider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.apiCall(
        provider: "black-forest-labs.image",
        statusCode: 500,
        body: "poll failed"
    )) {
        _ = try await pollModel.generateImage(ImageGenerationRequest(
            prompt: "poll error",
            providerOptions: ["blackForestLabs": .object(["pollIntervalMillis": 1, "pollTimeoutMillis": 1000])]
        ))
    }
}

@Test func blackForestLabsProviderOptionsValidateAndMapUpstreamSchemaFields() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-schema","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/schema.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: [
            "blackForestLabs": .object([
                "imagePrompt": "style-image",
                "imagePromptStrength": 0.75,
                "inputImage": "input-1",
                "inputImage2": "input-2",
                "steps": 30,
                "guidance": 2.5,
                "width": 1024,
                "height": 768,
                "outputFormat": "jpeg",
                "promptUpsampling": true,
                "raw": false,
                "safetyTolerance": 6,
                "webhookSecret": "secret",
                "webhookUrl": "https://hooks.example.com/bfl",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["image_prompt"]?.stringValue == "style-image")
    #expect(body["image_prompt_strength"]?.doubleValue == 0.75)
    #expect(body["input_image"]?.stringValue == "input-1")
    #expect(body["input_image_2"]?.stringValue == "input-2")
    #expect(body["steps"]?.intValue == 30)
    #expect(body["guidance"]?.doubleValue == 2.5)
    #expect(body["width"]?.intValue == 1024)
    #expect(body["height"]?.intValue == 768)
    #expect(body["output_format"]?.stringValue == "jpeg")
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["raw"]?.boolValue == false)
    #expect(body["safety_tolerance"]?.intValue == 6)
    #expect(body["webhook_secret"]?.stringValue == "secret")
    #expect(body["webhook_url"]?.stringValue == "https://hooks.example.com/bfl")
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)
}

@Test func blackForestLabsProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.blackForestLabs", message: "Black Forest Labs provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid namespace",
            providerOptions: ["blackForestLabs": .string("bad")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid strength",
            providerOptions: ["blackForestLabs": .object(["imagePromptStrength": 1.5])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid steps",
            providerOptions: ["blackForestLabs": .object(["steps": 1.5])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid width",
            providerOptions: ["blackForestLabs": .object(["width": 128])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid output format",
            providerOptions: ["blackForestLabs": .object(["outputFormat": "webp"])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid raw",
            providerOptions: ["blackForestLabs": .object(["raw": "false"])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid webhook",
            providerOptions: ["blackForestLabs": .object(["webhookUrl": "not-a-url"])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "invalid polling",
            providerOptions: ["blackForestLabs": .object(["pollIntervalMillis": 0])]
        ))
    }
}

@Test func blackForestLabsProviderOptionsNullNamespaceKeepsExtraBodyDefaults() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-null-namespace","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/null-namespace.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: ["blackForestLabs": .null],
        extraBody: [
            "blackForestLabs": .object([
                "promptUpsampling": true,
                "outputFormat": "png",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "png")
}

@Test func blackForestLabsImageMapsFilesMaskAndLegacyNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-fill-1","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/fill.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fill-png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.0-fill")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "replace background",
        size: "1280x720",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([9, 8, 7]), mediaType: "image/png"),
        extraBody: [
            "blackForestLabs": .object([
                "width": 640,
                "height": 360,
                "seed": 123,
                "guidance": 2.5,
                "promptUpsampling": true,
                "outputFormat": "jpeg",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ])
        ]
    ))

    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "replace background")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["width"]?.intValue == 640)
    #expect(body["height"]?.intValue == 360)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["guidance"]?.doubleValue == 2.5)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "jpeg")
    #expect(body["image"]?.stringValue == "https://example.com/input.png")
    #expect(body["image_2"]?.stringValue == Data([1, 2, 3]).base64EncodedString())
    #expect(body["mask"]?.stringValue == Data([9, 8, 7]).base64EncodedString())
    #expect(body["blackForestLabs"] == nil)
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)
}

@Test func blackForestLabsImageWarnsWhenSizeAndAspectRatioAreBothProvided() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-2","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"state":"Ready","result":{"sample":"https://bfl.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1920x1080",
        aspectRatio: "1:1"
    ))

    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "size",
            message: "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
        )
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["width"]?.intValue == 1920)
    #expect(body["height"]?.intValue == 1080)
}

@Test func blackForestLabsImageRejectsTooManyInputImages() async throws {
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "too many",
            files: (0..<11).map { ImageInputFile(url: "https://example.com/\($0).png") }
        ))
    }
}

@Test func blackForestLabsImageThrowsForMissingSubmitFields() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"bfl-missing"}"#))
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidResponse(provider: "black-forest-labs.image", message: "Black Forest Labs submit response did not contain id and polling_url.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func blackForestLabsImageThrowsWhenReadyPollHasNoSample() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-empty","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":null}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidResponse(provider: "black-forest-labs.image", message: "Black Forest Labs poll response is Ready but missing result.sample")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func blackForestLabsImageThrowsWhenPollStatusIsMissingLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-missing-status","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"result":{"sample":"https://bfl.example.com/image.png"}}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidResponse(provider: "black-forest-labs.image", message: "Missing status in Black Forest Labs poll response")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func blackForestLabsImageThrowsWhenPollFails() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-failed","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Failed"}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidResponse(provider: "black-forest-labs.image", message: "Black Forest Labs generation failed.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func blackForestLabsImageTimesOutAfterUpstreamPollAttemptCount() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-timeout","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Pending"}"#)
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    await #expect(throws: AIError.invalidResponse(provider: "black-forest-labs.image", message: "Black Forest Labs generation timed out.")) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            providerOptions: [
                "blackForestLabs": .object([
                    "pollIntervalMillis": 1,
                    "pollTimeoutMillis": 3
                ])
            ]
        ))
    }

    let requests = await transport.requests()
    #expect(requests.count == 4)
    #expect(requests[0].method == "POST")
    let pollRequests = requests.dropFirst()
    #expect(pollRequests.allSatisfy { $0.method == "GET" })
    #expect(pollRequests.allSatisfy { $0.url.absoluteString == "https://api.bfl.ai/v1/get_result?id=bfl-timeout" })
}
