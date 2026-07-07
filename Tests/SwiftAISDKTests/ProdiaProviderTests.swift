import Foundation
import Testing
@testable import SwiftAISDK

@Test func prodiaLanguageUsesMultipartJobEndpoint() async throws {
    let imageBytes = Data("png-bytes".utf8)
    let transport = RecordingTransport(response: prodiaMultipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-language","state":{"current":"succeeded"},"config":{"seed":7},"metrics":{"elapsed":1.5,"ips":20},"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:03Z","price":{"product":"nano-banana","dollars":0.01}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("caption text".utf8)),
        (name: "output", contentType: "image/png", body: imageBytes)
    ], headers: ["x-prodia": "language"]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Use short captions."),
            AIMessage(role: .user, content: [.text("Describe this"), .data(mimeType: "image/png", data: imageBytes)])
        ],
        providerOptions: ["prodia": .object(["aspectRatio": "1:1"])]
    ))

    #expect(result.text == "caption text")
    #expect(result.finishReason == "stop")
    #expect(result.providerMetadata["prodia"]?["jobId"]?.stringValue == "job-language")
    #expect(result.providerMetadata["prodia"]?["seed"]?.intValue == 7)
    #expect(result.providerMetadata["prodia"]?["elapsed"]?.doubleValue == 1.5)
    #expect(result.providerMetadata["prodia"]?["iterationsPerSecond"]?.intValue == 20)
    #expect(result.providerMetadata["prodia"]?["createdAt"]?.stringValue == "2025-01-01T00:00:00Z")
    #expect(result.providerMetadata["prodia"]?["updatedAt"]?.stringValue == "2025-01-01T00:00:03Z")
    #expect(result.providerMetadata["prodia"]?["dollars"]?.doubleValue == 0.01)
    #expect(result.responseMetadata.modelID == "inference.nano-banana.img2img.v2")
    #expect(result.responseMetadata.headers["x-prodia"] == "language")
    #expect(result.rawValue["parts"]?.arrayValue?.contains(where: { $0["base64"]?.stringValue == imageBytes.base64EncodedString() }) == true)

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["authorization"] == "Bearer prodia-token")
    #expect(request.headers["user-agent"] == "ai-sdk/prodia/2.0.6")
    #expect(request.headers["Accept"] == "multipart/form-data")
    #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(bodyText.contains(#""type":"inference.nano-banana.img2img.v2""#))
    #expect(bodyText.contains(#""prompt":"Use short captions.\nDescribe this""#))
    #expect(bodyText.contains(#""include_messages":true"#))
    #expect(bodyText.contains(#""aspect_ratio":"1:1""#))
    #expect(bodyText.contains("name=\"input\"; filename=\"input.png\""))
}

@Test func prodiaAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: prodiaMultipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-custom","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("ok".utf8))
    ], headers: [:]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Describe")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer prodia-token")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/prodia/2.0.6")
}

@Test func prodiaModelsUseUpstreamErrorMessageSchema() async throws {
    let languageProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 422,
            headers: ["x-prodia": "bad"],
            body: Data(#"{"detail":"bad prompt"}"#.utf8)
        ))
    ))

    await #expect(throws: AIError.apiCall(
        provider: "prodia.language",
        statusCode: 422,
        body: "bad prompt",
        headers: ["x-prodia": "bad"]
    )) {
        _ = try await languageProvider.languageModel("inference.nano-banana.img2img.v2").generate(LanguageModelRequest(messages: [.user("bad")]))
    }

    let imageProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 500,
            headers: [:],
            body: Data(#"{"error":"image failed"}"#.utf8)
        ))
    ))

    await #expect(throws: AIError.apiCall(provider: "prodia.image", statusCode: 500, body: "image failed")) {
        _ = try await imageProvider.imageModel("sdxl").generateImage(ImageGenerationRequest(prompt: "cat"))
    }

    let videoProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 400,
            headers: [:],
            body: Data(#"{"message":"video failed"}"#.utf8)
        ))
    ))

    await #expect(throws: AIError.apiCall(provider: "prodia.video", statusCode: 400, body: "video failed")) {
        _ = try await videoProvider.videoModel("veo").generateVideo(VideoGenerationRequest(prompt: "cat"))
    }
}

@Test func prodiaLanguageWarnsAndStreamsGeneratedFiles() async throws {
    let imageBytes = Data("stream-image".utf8)
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-stream","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("stream text".utf8)),
        (name: "output", contentType: "image/png", body: imageBytes)
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    var parts: [LanguageStreamPart] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Describe")],
        temperature: 0.5,
        topP: 0.9,
        topK: 40,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        maxOutputTokens: 100,
        stopSequences: ["stop"],
        responseFormat: .json(),
        reasoning: "medium",
        tools: ["test": .object(["type": "function"])],
        toolChoice: .object(["type": "auto"])
    )) {
        parts.append(part)
    }

    let warningFeatures = parts.compactMap { part -> [String]? in
        if case let .streamStart(warnings) = part {
            return warnings.compactMap(\.feature)
        }
        return nil
    }.flatMap { $0 }
    #expect(warningFeatures.contains("temperature"))
    #expect(warningFeatures.contains("topP"))
    #expect(warningFeatures.contains("topK"))
    #expect(warningFeatures.contains("maxOutputTokens"))
    #expect(warningFeatures.contains("stopSequences"))
    #expect(warningFeatures.contains("presencePenalty"))
    #expect(warningFeatures.contains("frequencyPenalty"))
    #expect(warningFeatures.contains("tools"))
    #expect(warningFeatures.contains("toolChoice"))
    #expect(warningFeatures.contains("responseFormat"))
    #expect(warningFeatures.contains("reasoning"))
    #expect(parts.contains { part in
        if case let .textDeltaPart(_, delta, _) = part {
            return delta == "stream text"
        }
        return false
    })
    #expect(parts.contains { part in
        if case let .file(file) = part {
            return file.mediaType == "image/png" && file.data == imageBytes
        }
        return false
    })
    #expect(parts.contains { part in
        if case let .finishMetadata(reason, _, providerMetadata) = part {
            return reason == "stop" && providerMetadata["prodia"]?["jobId"]?.stringValue == "job-stream"
        }
        return false
    })
}

@Test func prodiaLanguageDoesNotWarnForProviderDefaultReasoningLikeUpstream() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-provider-default","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("ok".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Describe")],
        reasoning: "provider-default"
    ))

    #expect(result.text == "ok")
    #expect(result.warnings.isEmpty)
}

@Test func prodiaLanguageProviderOptionsValidateLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-language","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("caption text".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.languageModel("inference.nano-banana.img2img.v2")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.prodia", message: "Prodia provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Describe")], providerOptions: ["prodia": "bad"]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Describe")], providerOptions: ["prodia": ["aspectRatio": nil]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Describe")], providerOptions: ["prodia": ["aspectRatio": "10:10"]]))
    }

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Describe")],
        providerOptions: ["prodia": ["aspectRatio": "16:9", "unknown": true]]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(bodyText.contains(#""aspect_ratio":"16:9""#))
    #expect(!bodyText.contains("unknown"))
}

@Test func prodiaImageUsesMultipartJobEndpoint() async throws {
    let transport = RecordingTransport(response: prodiaMultipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-1","state":{"current":"succeeded"},"config":{"seed":42},"metrics":{"elapsed":2.5,"ips":10.5},"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:05Z","price":{"product":"flux","dollars":0.0025}}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ], headers: ["x-prodia": "image"]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.imageModel("sdxl")

    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1024x768", seed: 123))

    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    #expect(result.providerMetadata["prodia"]?["images"]?[0]?["jobId"]?.stringValue == "job-1")
    #expect(result.providerMetadata["prodia"]?["images"]?[0]?["seed"]?.intValue == 42)
    #expect(result.providerMetadata["prodia"]?["images"]?[0]?["elapsed"]?.doubleValue == 2.5)
    #expect(result.providerMetadata["prodia"]?["images"]?[0]?["iterationsPerSecond"]?.doubleValue == 10.5)
    #expect(result.providerMetadata["prodia"]?["images"]?[0]?["dollars"]?.doubleValue == 0.0025)
    #expect(result.responseMetadata.modelID == "sdxl")
    #expect(result.responseMetadata.headers["x-prodia"] == "image")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["authorization"] == "Bearer prodia-token")
    #expect(request.headers["user-agent"] == "ai-sdk/prodia/2.0.6")
    #expect(request.headers["Accept"] == "multipart/form-data; image/png")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["values"]?["type"]?.stringValue == "sdxl")
    #expect(body["values"]?["config"]?["prompt"]?.stringValue == "cat")
    #expect(body["values"]?["config"]?["width"]?.intValue == 1024)
    #expect(body["values"]?["config"]?["height"]?.intValue == 768)
    #expect(body["values"]?["config"]?["seed"]?.intValue == 123)
    #expect(body["content"]?.stringValue?.contains(#""type":"sdxl""#) == true)
}

@Test func prodiaImageMapsProviderOptionsAndWarnsForInvalidSize() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-image","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.imageModel("sdxl")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "invalid",
        providerOptions: [
            "prodia": .object([
                "width": 512,
                "height": 512,
                "steps": 4,
                "stylePreset": "cinematic",
                "loras": ["detail", "light"],
                "progressive": true,
                "seed": 999,
                "ignoredProviderOption": true
            ])
        ],
        extraBody: ["prodia": .object(["width": 256, "ignored": true])]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "size", message: "Invalid size format: invalid. Expected format: WIDTHxHEIGHT (e.g., 1024x1024)")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["values"]?["config"]?["width"]?.intValue == 512)
    #expect(body["values"]?["config"]?["height"]?.intValue == 512)
    #expect(body["values"]?["config"]?["steps"]?.intValue == 4)
    #expect(body["values"]?["config"]?["style_preset"]?.stringValue == "cinematic")
    #expect(body["values"]?["config"]?["loras"]?[0]?.stringValue == "detail")
    #expect(body["values"]?["config"]?["progressive"]?.boolValue == true)
    #expect(body["values"]?["config"]?["seed"] == nil)
    #expect(body["values"]?["config"]?["stylePreset"] == nil)
    #expect(body["values"]?["config"]?["prodia"] == nil)
    #expect(body["values"]?["config"]?["ignored"] == nil)
    #expect(body["values"]?["config"]?["ignoredProviderOption"] == nil)
}

@Test func prodiaImageProviderOptionsValidateAndStripLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-image","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.imageModel("sdxl")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.prodia", message: "Prodia provider options must be an object.")) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": false]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["steps": 5]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["width": 255]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["height": 512.5]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["stylePreset": "oil"]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["loras": ["a", "b", "c", "d"]]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["progressive": "true"]]))
    }

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: [
            "prodia": [
                "steps": 4,
                "width": 512,
                "height": 768,
                "stylePreset": "anime",
                "loras": ["detail"],
                "progressive": false,
                "unknown": "stripped"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["values"]?["config"]?["steps"]?.intValue == 4)
    #expect(body["values"]?["config"]?["width"]?.intValue == 512)
    #expect(body["values"]?["config"]?["height"]?.intValue == 768)
    #expect(body["values"]?["config"]?["style_preset"]?.stringValue == "anime")
    #expect(body["values"]?["config"]?["loras"]?[0]?.stringValue == "detail")
    #expect(body["values"]?["config"]?["progressive"]?.boolValue == false)
    #expect(body["values"]?["config"]?["unknown"] == nil)
}

@Test func prodiaImageUsesUpstreamMultipartValidationMessages() async throws {
    let missingJobProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: multipartResponse(parts: [
            (name: "output", contentType: "image/png", body: Data("png".utf8))
        ]))
    ))

    await #expect(throws: AIError.invalidResponse(provider: "prodia.image", message: "Prodia multipart response missing job part")) {
        _ = try await missingJobProvider.imageModel("sdxl").generateImage(ImageGenerationRequest(prompt: "cat"))
    }

    let missingOutputProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: multipartResponse(parts: [
            (name: "job", contentType: "application/json", body: Data(#"{"id":"job-image"}"#.utf8))
        ]))
    ))

    await #expect(throws: AIError.invalidResponse(provider: "prodia.image", message: "Prodia multipart response missing output image")) {
        _ = try await missingOutputProvider.imageModel("sdxl").generateImage(ImageGenerationRequest(prompt: "cat"))
    }
}

@Test func prodiaVideoUsesMultipartJobEndpoint() async throws {
    let transport = RecordingTransport(response: prodiaMultipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-video","state":{"current":"succeeded"},"config":{"seed":99},"metrics":{"elapsed":5,"ips":3.2},"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:10Z","price":{"product":"wan","dollars":0.05}}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ], headers: ["x-prodia": "video"]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.videoModel("veo")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        seed: 42,
        providerOptions: ["prodia": .object(["resolution": "720p"])]
    ))

    #expect(result.operationID == "job-video")
    #expect(result.providerMetadata["prodia"]?["videos"]?[0]?["jobId"]?.stringValue == "job-video")
    #expect(result.providerMetadata["prodia"]?["videos"]?[0]?["seed"]?.intValue == 99)
    #expect(result.providerMetadata["prodia"]?["videos"]?[0]?["elapsed"]?.intValue == 5)
    #expect(result.providerMetadata["prodia"]?["videos"]?[0]?["iterationsPerSecond"]?.doubleValue == 3.2)
    #expect(result.providerMetadata["prodia"]?["videos"]?[0]?["dollars"]?.doubleValue == 0.05)
    #expect(result.responseMetadata.modelID == "veo")
    #expect(result.responseMetadata.headers["x-prodia"] == "video")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.prodia.com/v2/job?price=true")
    #expect(request.headers["authorization"] == "Bearer prodia-token")
    #expect(request.headers["user-agent"] == "ai-sdk/prodia/2.0.6")
    #expect(request.headers["Accept"] == "multipart/form-data; video/mp4")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["values"]?["type"]?.stringValue == "veo")
    #expect(body["values"]?["config"]?["prompt"]?.stringValue == "cat running")
    #expect(body["values"]?["config"]?["seed"]?.intValue == 42)
    #expect(body["values"]?["config"]?["resolution"]?.stringValue == "720p")
    #expect(body["content"]?.stringValue?.contains(#""type":"veo""#) == true)
}

@Test func prodiaVideoUsesMultipartForImageInputAndMergesProviderOptions() async throws {
    let imageBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-img2vid","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "video/webm", body: Data("webm".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.videoModel("inference.wan2-2.lightning.img2vid.v0")

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(data: imageBytes, mediaType: "image"),
        providerOptions: ["prodia": .object(["resolution": "720p", "seed": 999, "ignoredProviderOption": true])],
        extraBody: ["prodia": .object(["resolution": "480p", "seed": 7, "ignored": true])]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(bodyText.contains("name=\"input\"; filename=\"input.png\""))
    #expect(bodyText.contains("Content-Type: image/png"))
    #expect(bodyText.contains(#""resolution":"720p""#))
    #expect(bodyText.contains(#""seed":7"#))
    #expect(!bodyText.contains(#""ignored""#))
    #expect(!bodyText.contains(#""ignoredProviderOption""#))
    #expect(!bodyText.contains(#""seed":999"#))
}

@Test func prodiaVideoRejectsPrivateImageURLsBeforeFetchingLikeUpstream() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-img2vid"}"#.utf8)),
        (name: "output", contentType: "video/webm", body: Data("webm".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.videoModel("inference.wan2-2.lightning.img2vid.v0")

    await #expect(throws: AIError.invalidArgument(argument: "url", message: "URL with IP address 127.0.0.1 is not allowed.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "cat running",
            image: ImageInputFile(url: "http://127.0.0.1/latest/meta-data", mediaType: "image/png")
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func prodiaVideoProviderOptionsValidateAndStripLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"job-video","state":{"current":"succeeded"}}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ]))
    let provider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-token", transport: transport))
    let model = try provider.videoModel("veo")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.prodia", message: "Prodia provider options must be an object.")) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["prodia": 42]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["resolution": nil]]))
    }
    await #expect(throws: AIError.self) {
        _ = try await model.generateVideo(VideoGenerationRequest(prompt: "cat", providerOptions: ["prodia": ["resolution": 720]]))
    }

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["prodia": ["resolution": "720p", "unknown": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["values"]?["config"]?["resolution"]?.stringValue == "720p")
    #expect(body["values"]?["config"]?["unknown"] == nil)
}

@Test func prodiaVideoUsesUpstreamMultipartValidationMessages() async throws {
    let missingOutputProvider = try AIProviders.prodia(settings: ProviderSettings(
        apiKey: "prodia-token",
        transport: RecordingTransport(response: multipartResponse(parts: [
            (name: "job", contentType: "application/json", body: Data(#"{"id":"job-video"}"#.utf8))
        ]))
    ))

    await #expect(throws: AIError.invalidResponse(provider: "prodia.video", message: "Prodia multipart response missing output video")) {
        _ = try await missingOutputProvider.videoModel("veo").generateVideo(VideoGenerationRequest(prompt: "cat"))
    }
}

private func prodiaMultipartResponse(parts: [(name: String, contentType: String, body: Data)], headers: [String: String]) -> AIHTTPResponse {
    var response = multipartResponse(parts: parts)
    response.headers = response.headers.mergingHeaders(headers)
    return response
}
