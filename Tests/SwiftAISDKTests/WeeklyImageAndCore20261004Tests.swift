import Foundation
import Testing
@testable import SwiftAISDK

@Test func Weekly20261004ImageInputCapabilitiesAreTriStateAcrossProviders() async throws {
    let config = ModelHTTPConfig(providerID: "openai.image", baseURL: "https://example.com", headers: [:], transport: RecordingTransport(response: jsonResponse("{}")))
    let cases: [(any ImageModel, Bool?, Bool?)] = [
        (OpenAICompatibleImageModel(modelID: "gpt-image-2", config: config), true, true),
        (OpenAICompatibleImageModel(modelID: "dall-e-3", config: config), false, false),
        (OpenAICompatibleImageModel(modelID: "future-image", config: config), nil, nil),
        (OpenAICompatibleImageModel(modelID: "gpt-image-2", config: config.withProviderID("azure.image")), nil, nil),
        (OpenAICompatibleImageModel(modelID: "gpt-image-2", config: config.withProviderID("custom.image")), nil, nil),
        (BlackForestLabsImageModel(modelID: "flux-pro-1.0-fill", config: config), true, true),
        (BlackForestLabsImageModel(modelID: "flux-kontext-max", config: config), true, false),
        (BlackForestLabsImageModel(modelID: "flux-pro-1.1", config: config), false, false),
        (DeepInfraImageModel(modelID: "Qwen/Qwen-Image-Edit", config: config), true, true),
        (DeepInfraImageModel(modelID: "unknown", config: config), nil, nil),
        (FalImageModel(modelID: "fal-ai/flux-general/inpainting", config: config), true, true),
        (FalImageModel(modelID: "fal-ai/flux-2/edit", config: config), true, false),
        (FalImageModel(modelID: "fal-ai/recraft/v3/text-to-image", config: config), false, false),
        (FireworksImageModel(modelID: "accounts/fireworks/models/flux-kontext-pro", config: config), true, false),
        (FireworksImageModel(modelID: "accounts/fireworks/models/flux-1-dev-fp8", config: config), false, false),
        (LumaImageModel(modelID: "photon-flash-1", config: config), true, false),
        (QuiverAIImageModel(modelID: "arrow-2-telos", config: config), true, false),
        (ReplicateImageModel(modelID: "black-forest-labs/flux-fill-dev", config: config), true, true),
        (ReplicateImageModel(modelID: "black-forest-labs/flux-2-pro", config: config), true, false),
        (TogetherAIImageModel(modelID: "black-forest-labs/FLUX.2-pro", config: config), true, false),
        (TogetherAIImageModel(modelID: "black-forest-labs/FLUX.2-dev", config: config), false, false),
        (XAIImageModel(modelID: "grok-imagine-image-pro", config: config), true, false),
        (GoogleImageGenerationModel(modelID: "gemini-3.1-flash-image-preview", config: config), true, false),
        (GoogleImageGenerationModel(modelID: "imagen-4.0-generate-001", config: config), nil, nil),
        (ProdiaImageModel(modelID: "any", config: config), false, false)
    ]
    for (model, files, masks) in cases {
        #expect(await model.supportsFileInputs == files, "\(model.modelID)")
        #expect(await model.supportsMaskInputs == masks, "\(model.modelID)")
    }
    let bedrock = try AmazonBedrockProvider(settings: .init(apiKey: "test"))
    #expect(await (try bedrock.imageModel("amazon.nova-canvas-v1:0")).supportsMaskInputs == true)
    #expect(await (try bedrock.imageModel("unknown")).supportsFileInputs == nil)
    let vertex = try GoogleVertexProvider(settings: .init(apiKey: "test"))
    #expect(await (try vertex.imageModel("gemini-2.5-flash-image")).supportsFileInputs == true)
}

@Test func Weekly20261004ImageMiddlewarePreservesAsyncUnknownOverrides() async throws {
    let model = try AIProviders.openAI(settings: .init(apiKey: "test")).imageModel("gpt-image-2")
    let passthrough = wrapImageModel(model, middleware: AIImageModelMiddleware())
    #expect(await passthrough.supportsFileInputs == true)
    let unknown = wrapImageModel(model, middleware: .init(overrideSupportsFileInputs: { _ in nil }, overrideSupportsMaskInputs: { _ in false }))
    #expect(await unknown.supportsFileInputs == nil)
    #expect(await unknown.supportsMaskInputs == false)
}

@Test(arguments: ["evil.example.com/#", "user@internal:8080/#", "us-east-1/../..", "us east 1", "", "region\n", "-region", "region-", "東京", String(repeating: "a", count: 64)])
func Weekly20261004GeneratedHostValidationRejectsCompleteInvalidLabels(_ value: String) throws {
    #expect(!isValidHostnamePart(value))
    #expect(throws: AIError.self) { try AzureOpenAIProvider(resourceName: value, settings: .init(apiKey: "test")) }
    #expect(throws: AIError.self) { try AmazonBedrockProvider(settings: .init(region: value, apiKey: "test")) }
    #expect(throws: AIError.self) { try AnthropicAWSProvider(settings: .init(region: value, apiKey: "test")) }
    #expect(throws: AIError.self) { try GoogleVertexProvider(settings: .init(project: "test", location: value, accessToken: "test")) }
    #expect(throws: AIError.self) { try AIProviders.googleVertexMaaS(project: "test", location: value, settings: .init(apiKey: "test")) }
}

@Test func Weekly20261004CustomHostsBypassUnusedLabelsAndExpressModeDoesToo() throws {
    #expect(isValidHostnamePart("US-east-1"))
    #expect(isValidHostnamePart(String(repeating: "a", count: 63)))
    _ = try AzureOpenAIProvider(resourceName: "unused/invalid", settings: .init(apiKey: "test", baseURL: "https://proxy.example/v1"))
    _ = try AmazonBedrockProvider(settings: .init(region: "unused/invalid", apiKey: "test", baseURL: "https://proxy.example"))
    _ = try AnthropicAWSProvider(settings: .init(region: "unused/invalid", workspaceID: "test", apiKey: "test", baseURL: "https://proxy.example"))
    _ = try GoogleVertexProvider(settings: .init(project: "test", location: "unused/invalid", accessToken: "test", baseURL: "https://proxy.example"))
    _ = try AIProviders.googleVertexMaaS(location: "unused/invalid", settings: .init(apiKey: "test", baseURL: "https://proxy.example"))
    _ = try AIProviders.googleVertexAnthropic(location: "unused/invalid", settings: .init(apiKey: "test", baseURL: "https://proxy.example"))
    _ = try GoogleVertexProvider(settings: .init(location: "unused/invalid", apiKey: "test"))
}

@Test func Weekly20261004OpenAIRecursiveSchemasNormalizeWithoutChangingIntersections() throws {
    let schema: JSONValue = ["allOf": [["$ref": "#/$defs/a~1b~0c"]], "description": "root", "$defs": ["a/b~c": ["type": "object", "properties": ["next": ["allOf": [["$ref": "#/$defs/a~1b~0c"]], "description": "node"]]]]]
    let normalized = try normalizeOpenAIJSONSchema(schema)
    #expect(normalized.schema["type"] == "object")
    #expect(normalized.schema["description"] == "root")
    #expect(normalized.schema["allOf"] == nil)
    #expect(normalized.schema["properties"]?["next"]?["$ref"] == "#/$defs/a~1b~0c")
    #expect(normalized.schema["properties"]?["next"]?["description"] == "node")
    let intersection: JSONValue = ["allOf": [["$ref": "#/$defs/a"], ["$ref": "#/$defs/b"]]]
    #expect(try normalizeOpenAIJSONSchema(intersection).schema == intersection)
}

@Test func Weekly20261004SmoothStreamKeepsMetadataOnEachChunkAndFlushesAtBoundaries() async throws {
    let a: [String: JSONValue] = ["test": ["signature": "A"]]
    let b: [String: JSONValue] = ["test": ["signature": "B"]]
    let input = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        for part in [LanguageStreamPart.textStart(id: "t"), .textDeltaPart(id: "t", delta: "one two tail", providerMetadata: a),
                     .textDeltaPart(id: "t", delta: "", providerMetadata: b), .textDeltaPart(id: "t", delta: "next", providerMetadata: b), .textEnd(id: "t")] { continuation.yield(part) }
        continuation.finish()
    }
    var deltas: [(String, [String: JSONValue])] = []
    for try await part in smoothStream(input, delayNanoseconds: nil) {
        if case let .textDeltaPart(_, delta, metadata) = part { deltas.append((delta, metadata)) }
    }
    #expect(deltas.map(\.0) == ["one ", "two ", "tail", "", "next"])
    #expect(deltas.map(\.1) == [a, a, a, b, b])
}

@Test func Weekly20261004ResumedReducerContinuesPartialArgumentsAndText() throws {
    let original = AIUIMessage.assistant(id: "message", parts: [.text(.init(id: "t", text: "A", state: .streaming)), .toolCall(.init(id: "c", name: "lookup", arguments: "{\"q\":"))])
    var reducer = AIUIMessageStreamReducer(message: original)
    _ = try reducer.consume(.textDeltaPart(id: "t", delta: "B"))
    _ = try reducer.consume(.toolInputDelta(id: "c", delta: "\"value\"}"))
    #expect(reducer.message.text == "AB")
    if case let .toolCall(call) = reducer.message.parts[1] { #expect(call.arguments == "{\"q\":\"value\"}") }
    else { Issue.record("Expected resumed tool call") }
}

@Test func Weekly20261004DataPartConversionPreservesUserContent() throws {
    let message = AIUIMessage(id: "u", role: .user, parts: [.text(.init(text: "Question")), .data(.init(value: ["project": "AI SDK"]))])
    let result = try convertToModelMessages([message], convertDataPart: { part in .text("Project: \(part.value["project"]?.stringValue ?? "")") })
    #expect(result[0].combinedText == "Question\nProject: AI SDK")
    #expect(try convertToModelMessages([message])[0].combinedText == "Question")
}

@Test func Weekly20261004LaterUserMessageSupersedesOnlyUnresolvedApprovals() throws {
    let call = AIToolCall(id: "call", name: "lookup", arguments: "{}")
    let approval = AIToolApprovalRequest(id: "approval", toolName: "lookup", arguments: "{}", toolCallID: "call")
    let pending = AIUIMessage.assistant(id: "pending", parts: [.toolCall(call), .toolApprovalRequest(approval)])
    let latest = AIUIMessage.user("New question")
    let superseded = try convertToModelMessages([.user("Old question"), pending, latest])
    #expect(superseded.allSatisfy { message in message.content.allSatisfy { if case .toolCall = $0 { return false }; return true } })
    let current = try convertToModelMessages([.user("Old question"), pending])
    #expect(current.contains { message in message.content.contains { if case .toolCall = $0 { return true }; return false } })
}

@Test func Weekly20261004ToolTrackerGeneratesUniqueIDsAndRejectsAmbiguousContinuations() throws {
    var tracker = AIStreamingToolCallTracker(generateID: { "generated" })
    _ = try tracker.processDelta(.init(index: 1, id: "repeat", functionName: "fn", arguments: "{\"a\":"))
    _ = try tracker.processDelta(.init(index: 2, id: "repeat", functionName: "fn", arguments: "{\"b\":"))
    #expect(try tracker.processDelta(.init(arguments: "ambiguous")) == [])
    _ = try tracker.processDelta(.init(index: 1, arguments: "1}"))
    _ = try tracker.processDelta(.init(index: 2, arguments: "2}"))
    _ = try tracker.processDelta(.init(functionName: "missing", arguments: "{}"))
    _ = try tracker.processDelta(.init(functionName: "missing", arguments: "{}"))
    let calls = tracker.flush().compactMap { part -> AIToolCall? in if case let .toolCall(call) = part { return call }; return nil }
    #expect(calls.map(\.id) == ["repeat", "generated", "generated-1", "generated-2"])
    #expect(calls.map(\.arguments) == ["{\"a\":1}", "{\"b\":2}", "{}", "{}"])
}
