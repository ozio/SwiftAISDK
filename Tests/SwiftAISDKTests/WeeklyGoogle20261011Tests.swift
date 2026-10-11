import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyGoogle20261011")
struct WeeklyGoogle20261011Tests {
    private let schema: JSONValue = ["type": "object", "properties": ["date": ["type": "string"]], "required": ["date"], "additionalProperties": false]
    private let tools: [String: JSONValue] = ["resolveDate": ["type": "object", "properties": [:]]]

    @Test(arguments: [false, true])
    func jsonResponseToolWorksForGoogleAndVertex(_ vertex: Bool) async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"text":"Ignore this prose"},{"text":"Thinking","thought":true},{"functionCall":{"name":"resolveDate","id":"app","args":{}}},{"functionCall":{"name":"json","id":"json-call","args":{"date":"2026-10-11"}},"thoughtSignature":"sig"}]},"finishReason":"STOP"}]}"#))
        let model: any LanguageModel = vertex
            ? try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "key", transport: transport)).languageModel("gemini-2.5-flash")
            : try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gemini-2.5-flash")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Date?")], responseFormat: .json(schema: schema), tools: tools))
        #expect(try decodeJSONBody(Data(result.text.utf8)) == ["date": "2026-10-11"])
        #expect(result.reasoning == "Thinking")
        #expect(result.toolCalls.map(\.name) == ["resolveDate"])
        #expect(result.finishReason == "tool-calls")
        #expect(result.content.contains { if case let .text(_, metadata) = $0 { metadata["google"]?["thoughtSignature"] == "sig" } else { false } })
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["generationConfig"]?["responseMimeType"] == nil)
        #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"] == "ANY")
        let declarations = body["tools"]?[0]?["functionDeclarations"]?.arrayValue ?? []
        #expect(Set(declarations.compactMap { $0["name"]?.stringValue }) == ["json", "resolveDate"])
    }

    @Test func fallbackUsesCollisionFreeNamesAndPreservesToolChoice() throws {
        var request = LanguageModelRequest(messages: [.user("Date?")], responseFormat: .json(schema: schema), tools: tools.merging(["json": ["type": "object"], "json_1": ["type": "object"]]) { _, new in new }, toolChoice: ["type": "none"])
        let prepared = googlePrepareJSONResponseToolRequest(request, modelID: "gemini-2.5-flash")
        #expect(prepared.name == "json_2")
        #expect(prepared.request.toolChoice == ["type": "tool", "toolName": "json_2"])
        request.toolChoice = ["type": "tool", "toolName": "resolveDate"]
        let forced = googlePrepareJSONResponseToolRequest(request, modelID: "gemini-3.8-flash")
        let body = try GoogleGenerativeLanguageModel.generateContentBody(for: forced.request, modelID: "gemini-3.8-flash").body
        #expect(body["toolConfig"]?["functionCallingConfig"]?["allowedFunctionNames"] == ["resolveDate"])
        request.toolChoice = ["type": "auto"]
        #expect(googlePrepareJSONResponseToolRequest(request, modelID: "gemini-3.8-flash").name == nil)
        request.tools = [:]
        #expect(googlePrepareJSONResponseToolRequest(request, modelID: "gemini-2.5-flash").name == nil)
    }

    @Test func jsonResponseToolStreamsTextAndKeepsApplicationCalls() async throws {
        let transport = RecordingTransport(response: sseResponse("""
        data: {"candidates":[{"content":{"parts":[{"text":"Ignore this prose"},{"functionCall":{"name":"resolveDate","id":"app","args":{}}},{"functionCall":{"name":"json","id":"json-call","args":{"date":"2026-10-11"}},"thoughtSignature":"sig"}]},"finishReason":"STOP"}]}
        """))
        let model = try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gemini-2.5-flash")
        var text = ""
        var calls: [String] = []
        var finishReason: String?
        var signature: JSONValue?
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Date?")], responseFormat: .json(schema: schema), tools: tools)) {
            switch part {
            case let .textDeltaPart(_, delta, metadata): text += delta; signature = metadata["google"]?["thoughtSignature"]
            case let .toolCall(call): calls.append(call.name)
            case let .toolInputStart(_, name, _, _, _, _): #expect(name != "json")
            case let .finishMetadata(reason, _, _): finishReason = reason
            default: break
            }
        }
        #expect(try decodeJSONBody(Data(text.utf8)) == ["date": "2026-10-11"])
        #expect(calls == ["resolveDate"])
        #expect(finishReason == "tool-calls")
        #expect(signature == "sig")
    }

    @Test func jsonResponseToolStreamsNestedPartialArgumentsAndClosesJSON() async throws {
        let transport = RecordingTransport(response: sseResponse("""
        data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"json","id":"json-call","willContinue":true},"thoughtSignature":"sig"}]}}]}

        data: {"candidates":[{"content":{"parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.recipe.ingredients[0].name","stringValue":"San ","willContinue":true}],"willContinue":true}}]}}]}

        data: {"candidates":[{"content":{"parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.recipe.ingredients[0].name","stringValue":"Francisco"},{"jsonPath":"$.recipe.quantity","numberValue":2}],"willContinue":false}}]},"finishReason":"STOP"}]}
        """))
        let model = try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gemini-2.5-flash")
        var text = ""
        var finishReason: String?
        var sawEarlyText = false
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Date?")], responseFormat: .json(schema: schema), tools: tools)) {
            if case let .textDeltaPart(_, delta, _) = part { text += delta; if delta.contains("San ") { sawEarlyText = true } }
            if case let .toolCall(call) = part { #expect(call.name != "json") }
            if case let .finishMetadata(reason, _, _) = part { finishReason = reason }
        }
        #expect(sawEarlyText)
        #expect(try decodeJSONBody(Data(text.utf8)) == ["recipe": ["ingredients": [["name": "San Francisco"]], "quantity": 2]])
        #expect(finishReason == "stop")
    }

    @Test func missingResponseToolArgumentsBecomeEmptyJSONObject() throws {
        let raw: JSONValue = ["candidates": [["content": ["parts": [["functionCall": ["name": "json"]]]]]]]
        let converted = googleConvertJSONResponseTool(raw, name: "json")
        #expect(googleGenerateContentText(from: converted) == "{}")
    }

    @Test(arguments: ["error-text", "error-json", "execution-denied"])
    func toolResultsKeepExplicitErrorSemantics(_ type: String) throws {
        let output: JSONValue = type == "execution-denied" ? ["type": .string(type), "reason": "denied"] : ["type": .string(type), "value": type == "error-json" ? ["code": "E42"] : "E42"]
        let request = LanguageModelRequest(messages: [AIMessage(role: .tool, content: [.toolResult(AIToolResult(toolCallID: "call", toolName: "deploy", result: output))])])
        let body = try GoogleGenerativeLanguageModel.generateContentBody(for: request, modelID: "gemini-3.8-flash").body
        let response = try #require(body["contents"]?[0]?["parts"]?[0]?["functionResponse"]?["response"])
        #expect(response["name"] == "deploy")
        #expect(response["error"] == (type == "execution-denied" ? "denied" : type == "error-json" ? ["code": "E42"] : "E42"))
    }

    @Test func errorJSONSchemaReferencesStaySerializedInsideErrorEnvelope() throws {
        let value: JSONValue = ["nested": ["$ref": "#/definitions/Error"]]
        let output: JSONValue = ["type": "error-json", "value": value]
        let request = LanguageModelRequest(messages: [AIMessage(role: .tool, content: [.toolResult(AIToolResult(toolCallID: "call", toolName: "deploy", result: output))])])
        let body = try GoogleGenerativeLanguageModel.generateContentBody(for: request, modelID: "gemini-3.8-flash").body
        let error = try #require(body["contents"]?[0]?["parts"]?[0]?["functionResponse"]?["response"]?["error"]?.stringValue)
        #expect(try decodeJSONBody(Data(error.utf8)) == value)
    }

    @Test func googleEmbeddingDimensionsFallBackAndProviderOptionsWin() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"embedding":{"values":[0.1]},"embeddings":[{"values":[0.1]},{"values":[0.2]}]}"#))
        let model = try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).embeddingModel("gemini-embedding-2")
        for count in [1, 2] {
            _ = try await model.embed(EmbeddingRequest(values: Array(repeating: "text", count: count), dimensions: 128))
            _ = try await model.embed(EmbeddingRequest(values: Array(repeating: "text", count: count), dimensions: 128, providerOptions: ["google": ["outputDimensionality": 256]]))
        }
        for (index, request) in await transport.requests().enumerated() {
            let body = try decodeJSONBody(try #require(request.body))
            let dimension = index < 2 ? body["outputDimensionality"] : body["requests"]?[0]?["outputDimensionality"]
            #expect(dimension == (index % 2 == 0 ? 128 : 256))
        }
    }

    @Test(arguments: ["text-embedding-005", "gemini-embedding-2-preview"])
    func vertexEmbeddingDimensionsMatchBothEndpoints(_ modelID: String) async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"embeddings":{"values":[0.1]}}],"embedding":{"values":[0.1]}}"#))
        let model = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "key", transport: transport)).embeddingModel(modelID)
        _ = try await model.embed(EmbeddingRequest(values: ["text"], dimensions: 128))
        _ = try await model.embed(EmbeddingRequest(values: ["text"], dimensions: 128, providerOptions: ["googleVertex": ["outputDimensionality": 256]]))
        for (index, request) in await transport.requests().enumerated() {
            let body = try decodeJSONBody(try #require(request.body))
            let dimension = modelID.hasPrefix("gemini-") ? body["embedContentConfig"]?["outputDimensionality"] : body["parameters"]?["outputDimensionality"]
            #expect(dimension == (index == 0 ? 128 : 256))
        }
    }

    @Test func retrievedContextCustomMetadataSurvivesAndMaxEffortMapsHigh() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"text":"ok"}]},"groundingMetadata":{"groundingChunks":[{"retrievedContext":{"uri":"https://example.test","customMetadata":[{"key":"category","stringValue":"docs"},{"key":"score","numericValue":3},{"key":"tags","stringListValue":{"values":["swift"]}}]}}]},"finishReason":"STOP"}]}"#))
        let model = try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gemini-3.8-flash")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], reasoning: "max"))
        let custom = result.providerMetadata["google"]?["groundingMetadata"]?["groundingChunks"]?[0]?["retrievedContext"]?["customMetadata"]
        #expect(custom?[0]?["stringValue"] == "docs")
        #expect(custom?[2]?["stringListValue"]?["values"] == ["swift"])
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["generationConfig"]?["thinkingConfig"]?["thinkingLevel"] == "high")
    }

    @Test func googleBatchDownloadHonorsProviderLineLimit() async throws {
        let transport = RecordingTransport(responses: [jsonResponse(#"{"name":"batches/batch","done":true,"metadata":{"state":"BATCH_STATE_SUCCEEDED","output":{"responsesFile":"files/output"}}}"#), jsonResponse(#"{"key":"item","response":{"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}}"#)])
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = AIBatchResultDownloadSettings(maxLineBytes: 16)
        let stream = try await AIProviders.google(settings: settings).batchLanguageModel("gemini-2.5-flash").getBatchResults(AIBatchOperationOptions(batchID: "batches/batch"))
        await #expect(throws: AIDownloadError.self) { for try await _ in stream {} }
    }

    @Test(arguments: [false, true])
    func nanoBananaImageModelUsesGenerateContent(_ vertex: Bool) async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}"#))
        let model: any ImageModel = vertex
            ? try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "key", transport: transport)).imageModel("gemini-nano-banana-2.1")
            : try AIProviders.google(settings: ProviderSettings(apiKey: "key", transport: transport)).imageModel("gemini-nano-banana-2.1")
        let result = try await model.generateImage(ImageGenerationRequest(
            prompt: "A banana", size: "1024x1024", aspectRatio: "4:3", seed: 7,
            files: [ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png"), ImageInputFile(url: "gs://images/reference.png")],
            providerOptions: [vertex ? "googleVertex" : "google": ["imageConfig": ["imageSize": "2K"]]]
        ))
        #expect(result.base64Images.first.flatMap { Data(base64Encoded: $0) } == Data([1, 2, 3]))
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString.contains(":generateContent"))
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["contents"]?[0]?["parts"]?.arrayValue?.contains { $0["inlineData"]?["data"] == "BAUG" && $0["inlineData"]?["mimeType"] == "image/png" } == true)
        #expect(body["contents"]?[0]?["parts"]?.arrayValue?.contains { $0["fileData"]?["fileUri"] == "gs://images/reference.png" && $0["fileData"]?["mimeType"] == "image/*" } == true)
        #expect(body["generationConfig"]?["responseModalities"] == ["IMAGE"])
        #expect(body["generationConfig"]?["imageConfig"]?["aspectRatio"] == "4:3")
        #expect(body["generationConfig"]?["imageConfig"]?["imageSize"] == "2K")
        #expect(body["generationConfig"]?["seed"] == 7)
        #expect(result.warnings.contains { $0.feature == "size" })
        #expect(result.usage?.inputTokens == 1 && result.usage?.outputTokens == 2)
        await #expect(throws: AIError.self) { _ = try await model.generateImage(ImageGenerationRequest(prompt: "Mask", mask: ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png"))) }
        await #expect(throws: AIError.self) { _ = try await model.generateImage(ImageGenerationRequest(prompt: "Multiple", count: 2)) }
        #expect(await transport.requests().count == 1)
        if vertex {
            #expect(result.providerMetadata["googleVertex"]?["images"] == [[:]])
            #expect(result.providerMetadata["vertex"]?["images"] == [[:]])
        }
    }

    @Test func vertexGeminiImageKeepsLegacyExtraBodyImageOptions() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}]}"#))
        let model = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "key", transport: transport)).imageModel("gemini-nano-banana-2.1")
        _ = try await model.generateImage(ImageGenerationRequest(prompt: "A banana", aspectRatio: "4:3", extraBody: ["vertex": ["imageConfig": ["imageSize": "2K", "aspectRatio": "1:1"], "sharedRequestType": "dedicated"]]))
        let request = try #require(await transport.requests().first)
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["generationConfig"]?["imageConfig"] == ["imageSize": "2K", "aspectRatio": "4:3"])
        #expect(body["generationConfig"]?["responseModalities"] == ["IMAGE"])
        #expect(body["vertex"] == nil && body["googleVertex"] == nil)
        #expect(request.headers["X-Vertex-AI-LLM-Shared-Request-Type"] == "dedicated")
    }
}
