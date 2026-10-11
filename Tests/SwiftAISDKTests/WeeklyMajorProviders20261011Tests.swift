import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyMajorProviders20261011")
struct WeeklyMajorProviders20261011Tests {
    private let anthropicResponse = jsonResponse(#"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#)
    private let bedrockResponse = jsonResponse(#"{"output":{"message":{"content":[{"text":"ok"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1}}"#)

    @Test func haiku55UsesAdaptiveThinkingAndRejectsBudgetSampling() async throws {
        let transport = RecordingTransport(response: anthropicResponse)
        let model = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("claude-haiku-5-5")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], temperature: 0.2, topP: 0.5, reasoning: "max", providerOptions: ["anthropic": ["thinking": ["type": "enabled", "budgetTokens": 2048]]]))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["max_tokens"] == 128_000)
        #expect(body["thinking"] == ["type": "adaptive"])
        #expect(body["output_config"]?["effort"] == "max")
        #expect(body["temperature"] == nil && body["top_p"] == nil)
        #expect(result.warnings.contains { $0.feature == "providerOptions.anthropic.thinking" })
    }

    @Test func haiku55AllowsDisabledThinkingButCapsXhighEffort() async throws {
        let transport = RecordingTransport(response: anthropicResponse)
        let model = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("claude-haiku-5-5")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], providerOptions: ["anthropic": ["thinking": ["type": "disabled"], "effort": "xhigh"]]))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["thinking"] == ["type": "disabled"])
        #expect(body["output_config"]?["effort"] == "high")
        #expect(result.warnings.contains { $0.feature == "providerOptions.anthropic.effort" })
    }

    @Test func explicitFalseStrictDoesNotWarnOnUnsupportedModels() async throws {
        let tools: [String: JSONValue] = ["lookup": ["type": "object", "properties": [:], "strict": false]]
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: RecordingTransport(response: anthropicResponse)))
        let result = try await anthropic.languageModel("claude-3-haiku-20240307").generate(LanguageModelRequest(messages: [.user("Hello")], tools: tools))
        #expect(!result.warnings.contains { $0.feature?.contains("strict") == true })
        let bedrock = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(region: "us-east-1", apiKey: "key", transport: RecordingTransport(response: bedrockResponse)))
        let bedrockResult = try await bedrock.languageModel("anthropic.claude-haiku-5-5").generate(LanguageModelRequest(messages: [.user("Hello")], tools: tools))
        #expect(!bedrockResult.warnings.contains { $0.feature?.contains("strict") == true })
    }

    @Test func bedrockHaiku55UsesJSONToolFallback() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"output":{"message":{"content":[{"toolUse":{"toolUseId":"json-tool","name":"json","input":{"name":"Test"}}}]}},"stopReason":"tool_use","usage":{"inputTokens":4,"outputTokens":10,"totalTokens":14}}"#))
        let model = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(region: "us-east-1", apiKey: "key", transport: transport)).languageModel("us.anthropic.claude-haiku-5-5")
        let schema: JSONValue = ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]]
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Generate a name")], responseFormat: .json(schema: schema)))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"] == "json")
        #expect(body["additionalModelRequestFields"]?["output_config"] == nil)
        #expect(try decodeJSONBody(Data(result.text.utf8)) == ["name": "Test"])
        #expect(result.toolCalls.isEmpty && result.finishReason == "stop")
    }

    @Test func anthropicEmitsRawMessageStartUsageAndFallbackReplayBeta() async throws {
        let stream = sseResponse("""
        data: {"type":"message_start","message":{"id":"msg_start","model":"claude-haiku-5-5","usage":{"input_tokens":17,"output_tokens":2}}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":4}}

        data: {"type":"message_stop"}
        """)
        let transport = RecordingTransport(response: stream)
        let model = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("claude-haiku-5-5")
        var start: JSONValue?
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
            if case let .custom(value, metadata) = part, value["kind"] == "anthropic.message_start" { start = metadata["anthropic"] }
        }
        #expect(start?["id"] == "msg_start")
        #expect(start?["model"] == "claude-haiku-5-5")
        #expect(start?["usage"]?["input_tokens"] == 17)
        #expect(start?["usage"]?["output_tokens"] == 2)
        let replay = RecordingTransport(response: anthropicResponse)
        let replayModel = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: replay)).languageModel("claude-haiku-5-5")
        _ = try await replayModel.generate(LanguageModelRequest(messages: [.user("Hello"), AIMessage(role: .assistant, content: [.custom(["kind": "anthropic.fallback"], providerMetadata: ["anthropic": ["type": "fallback", "from": ["model": "source"], "to": ["model": "target"]]])])]))
        #expect(await replay.requests().first?.headers["anthropic-beta"]?.contains("server-side-fallback-2026-06-01") == true)
    }

    @Test func sigV4PreservesUnicodeHeadersWithoutSigningThem() throws {
        let request = AIHTTPRequest(method: "POST", url: URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/test/invoke")!, headers: ["x-title": "Example · App", "x-ascii": "safe"], body: Data("{}".utf8))
        let signed = try AWSSigV4.sign(request: request, body: Data("{}".utf8), credentials: AWSCredentials(accessKeyID: "access", secretAccessKey: "secret", sessionToken: nil), region: "us-east-1", service: "bedrock", date: Date(timeIntervalSince1970: 0))
        #expect(signed.headers["x-title"] == "Example · App")
        let authorization = try #require(signed.headers["authorization"])
        #expect(authorization.contains("x-ascii"))
        #expect(!authorization.contains("x-title"))
    }

    @Test func anthropicAWSSigningUsesSharedUnicodeFix() async throws {
        let transport = RecordingTransport(response: anthropicResponse)
        let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(region: "us-east-1", workspaceID: "workspace", accessKeyID: "access", secretAccessKey: "secret", headers: ["x-title": "Example · App", "x-ascii": "safe"], transport: transport))
        _ = try await provider.languageModel("claude-haiku-5-5").generate(LanguageModelRequest(messages: [.user("Hello")]))
        let request = try #require(await transport.requests().first)
        #expect(request.headers["x-title"] == "Example · App")
        #expect(request.headers["authorization"]?.contains("x-ascii") == true)
        #expect(request.headers["authorization"]?.contains("x-title") == false)
    }

    @Test func bedrockDisabledAndExplicitReasoningAvoidUnusedWarnings() {
        var options: [String: JSONValue] = ["reasoningConfig": ["type": "disabled", "budgetTokens": 1234, "maxReasoningEffort": "high"]]
        var warnings: [AIWarning] = []
        bedrockApplyTopLevelReasoning("max", modelID: "amazon.nova-2-lite-v1:0", maxOutputTokens: nil, providerOptions: &options, warnings: &warnings)
        #expect(options["reasoningConfig"] == ["type": "disabled"])
        #expect(warnings.isEmpty)
        options = ["reasoningConfig": ["maxReasoningEffort": "low"]]
        bedrockApplyTopLevelReasoning("max", modelID: "amazon.nova-2-lite-v1:0", maxOutputTokens: nil, providerOptions: &options, warnings: &warnings)
        #expect(options["reasoningConfig"] == ["type": "enabled", "maxReasoningEffort": "low"])
        #expect(warnings.isEmpty)
        options = [:]
        bedrockApplyTopLevelReasoning("max", modelID: "amazon.nova-2-lite-v1:0", maxOutputTokens: nil, providerOptions: &options, warnings: &warnings)
        #expect(options["reasoningConfig"]?["maxReasoningEffort"] == "high")
        #expect(warnings.contains { $0.type == "compatibility" && $0.feature == "reasoning" })
    }

    @Test(arguments: ["amazon.titan-embed-text-v2:0", "cohere.embed-english-v3", "amazon.nova-2-multimodal-embeddings-v1:0"])
    func bedrockTopLevelEmbeddingDimensionsAndProviderPrecedence(_ modelID: String) async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"embedding":[0.1,0.2],"embeddings":[[0.1,0.2]]}"#))
        let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(region: "us-east-1", apiKey: "key", transport: transport))
        let model = try provider.embeddingModel(modelID)
        let option = modelID.hasPrefix("cohere") ? "outputDimension" : modelID.contains("nova") ? "embeddingDimension" : "dimensions"
        for override in [false, true] {
            _ = try await model.embed(EmbeddingRequest(values: ["text"], dimensions: 256, providerOptions: override ? ["bedrock": .object([option: 1024])] : [:]))
        }
        let bodies = try await transport.requests().map { try decodeJSONBody(try #require($0.body)) }
        for (index, body) in bodies.enumerated() {
            let dimension = modelID.contains("nova") ? body["singleEmbeddingParams"]?["embeddingDimension"] : body[option == "outputDimension" ? "output_dimension" : "dimensions"]
            #expect(dimension == (index == 0 ? 256 : 1024))
        }
    }

    @Test func jsonLinesBoundCountsUTF8BytesAcrossChunksAndKeepsCRLFAndBOM() async throws {
        let chunks = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0xef, 0xbb]))
            continuation.yield(Data([0xbf] + Array("{}\r\n\n{\"é\":1}".utf8)))
            continuation.finish()
        }
        var rows: [Data] = []
        try await aiForEachBatchResultLine(chunks, url: "https://example.test/results", maxLineBytes: 10, abortSignal: nil) { rows.append($0) }
        #expect(rows == [Data("{}".utf8), Data(), Data("{\"é\":1}".utf8)])
        let oversized = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("é".utf8)); continuation.yield(Data("é".utf8)); continuation.finish()
        }
        await #expect(throws: AIDownloadError.self) {
            try await aiForEachBatchResultLine(oversized, url: "https://example.test/results", maxLineBytes: 3, abortSignal: nil) { _ in }
        }
        #expect(throws: AIError.self) { try aiBatchResultLineLimit(0) }
        #expect(throws: AIError.invalidArgument(argument: "maxLineBytes", message: "maxLineBytes must be a positive safe integer.")) { try aiBatchResultLineLimit(9_007_199_254_740_992) }
        #expect(try aiBatchResultLineLimit(9_007_199_254_740_991) == 9_007_199_254_740_991)
    }

    @Test func anthropicBatchDownloadHonorsProviderLineLimit() async throws {
        let status = jsonResponse(#"{"id":"batch","type":"message_batch","processing_status":"ended","request_counts":{"processing":0,"succeeded":1,"errored":0,"canceled":0,"expired":0},"created_at":"2026-10-11T00:00:00Z","expires_at":"2026-10-12T00:00:00Z","results_url":"https://api.anthropic.com/v1/messages/batches/batch/results"}"#)
        let row = #"{"custom_id":"item","result":{"type":"succeeded","message":{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"output_tokens":1}}}}"#
        let transport = RecordingTransport(responses: [status, jsonResponse(row)])
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = AIBatchResultDownloadSettings(maxLineBytes: 16)
        let stream = try await AIProviders.anthropic(settings: settings).experimentalBatch().getBatchResults(AIBatchOperationOptions(batchID: "batch"))
        await #expect(throws: AIDownloadError.self) { for try await _ in stream {} }
    }

    @Test(arguments: ["anthropic", "google", "openai"])
    func oversizedBatchRowsCancelResponseProduction(_ providerID: String) async throws {
        let status: AIHTTPResponse
        switch providerID {
        case "anthropic":
            status = jsonResponse(#"{"id":"batch","type":"message_batch","processing_status":"ended","request_counts":{"processing":0,"succeeded":1,"errored":0,"canceled":0,"expired":0},"created_at":"2026-10-11T00:00:00Z","expires_at":"2026-10-12T00:00:00Z","results_url":"https://api.anthropic.com/v1/messages/batches/batch/results"}"#)
        case "google":
            status = jsonResponse(#"{"name":"batches/batch","done":true,"metadata":{"state":"BATCH_STATE_SUCCEEDED","output":{"responsesFile":"files/output"}}}"#)
        default:
            status = jsonResponse(#"{"id":"batch","status":"completed","output_file_id":"file","request_counts":{"total":1,"completed":1,"failed":0},"endpoint":"/v1/responses","created_at":1,"input_file_id":"input","completion_window":"24h"}"#)
        }
        let transport = WeeklyBatchResponseCancellationTransport(status: status)
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = AIBatchResultDownloadSettings(maxLineBytes: 16)
        let model: any BatchLanguageModel
        switch providerID {
        case "anthropic": model = try AIProviders.anthropic(settings: settings).batchLanguageModel("claude-haiku-5-5")
        case "google": model = try AIProviders.google(settings: settings).batchLanguageModel("gemini-2.5-flash")
        default: model = try AIProviders.openAI(settings: settings).batchLanguageModel("gpt-6-sol")
        }
        let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: providerID == "google" ? "batches/batch" : "batch"))
        await #expect(throws: AIDownloadError.self) { for try await _ in stream {} }
        #expect(transport.cancellations.count == 1)
    }

    @Test func compatibleTransformCanAppendWarningsDuringGenerateAndStream() async throws {
        let transport = RecordingTransport(responses: [jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#), sseResponse(#"data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}"#)])
        let provider = try AIProviders.openAICompatible(
            name: "proxy", baseURL: "https://compatible.test/v1", apiKey: "key", transport: transport,
            transformRequestBody: { body in var body = body; body["legacy"] = true; return body },
            transformRequestBodyWithWarnings: { body, warnings in
                var body = body; body["modern"] = true
                warnings.append(AIWarning(type: "compatibility", feature: "proxy", message: "Converted proxy request."))
                return body
            }
        )
        let model = try provider.chat("model")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        #expect(result.warnings.contains { $0.feature == "proxy" })
        var streamWarnings: [AIWarning] = []
        for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
            if case let .streamStart(warnings) = part { streamWarnings = warnings }
        }
        #expect(streamWarnings.contains { $0.feature == "proxy" })
        for request in await transport.requests() {
            let body = try decodeJSONBody(try #require(request.body))
            #expect(body["legacy"] == true && body["modern"] == true)
        }
    }

    @Test func portableMaxReasoningMapsAcrossCompatibleHelpers() throws {
        var warnings: [AIWarning] = []
        let fireworks = fireworksChatBody(from: ["reasoning_effort": "max"], warnings: &warnings)
        #expect(fireworks["reasoning_effort"] == "high")
        #expect(warnings.contains { $0.type == "compatibility" && $0.feature == "reasoning" })
        let moonshot = try moonshotChatBody(from: [:], request: LanguageModelRequest(messages: [.user("Hello")], reasoning: "max"), modelID: "kimi-k3", warnings: &warnings)
        #expect(moonshot["reasoning_effort"] == "max")
        #expect(xaiReasoningEffort("max", modelID: "grok-4.6", warnings: &warnings) == "xhigh")
    }

    @Test func nativeMultipartUploadsPreserveDataSliceByteRange() async throws {
        let storage = Data([9, 8, 0, 1, 2, 3, 7, 6])
        let payload = storage[2..<6]
        let factories: [(RecordingTransport) throws -> any AIFileClient] = [
            { try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: $0)).files() },
            { try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: $0)).files() },
            { try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "key", transport: $0)).files() },
            { try AIProviders.xAI(settings: ProviderSettings(apiKey: "key", transport: $0)).files() }
        ]
        for factory in factories {
            let transport = RecordingTransport(response: jsonResponse(#"{"id":"file","object":"file"}"#))
            _ = try await factory(transport).uploadFile(FileUploadRequest(data: payload, mediaType: "image/png", filename: "test.png"))
            let body = try #require(await transport.requests().first?.body)
            #expect(body.range(of: Data([0, 1, 2, 3])) != nil)
            #expect(body.range(of: Data([9, 8, 0, 1, 2, 3, 7, 6])) == nil)
        }
    }
}

private final class WeeklyBatchCancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private actor WeeklyBatchResponseCancellationTransport: AIStreamingTransport {
    let status: AIHTTPResponse
    nonisolated let cancellations = WeeklyBatchCancellationCounter()

    init(status: AIHTTPResponse) { self.status = status }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse { status }
    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        AIHTTPStreamResponse(statusCode: 200, body: AsyncThrowingStream { continuation in
            continuation.yield(Data(repeating: 0x61, count: 17))
            continuation.finish()
        }, cancelBody: { [cancellations] in cancellations.increment() })
    }
}
