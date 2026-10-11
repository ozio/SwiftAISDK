import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyOpenAI20261011")
struct WeeklyOpenAI20261011Tests {
    private let response = jsonResponse(#"{"id":"resp","status":"completed","output_text":"ok"}"#)

    @Test(arguments: ["error-text", "error-json"])
    func chatAndResponsesWrapToolErrorsInJSON(_ type: String) async throws {
        let value: JSONValue = type == "error-text" ? "E42" : ["code": "E42"]
        let output: JSONValue = ["type": .string(type), "value": value]
        let message = AIMessage(role: .tool, content: [.toolResult(AIToolResult(toolCallID: "call", toolName: "deploy", result: output))])
        let chatTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
        let chat = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: chatTransport)).chat("gpt-4o")
        _ = try await chat.generate(LanguageModelRequest(messages: [message]))
        let chatBody = try decodeJSONBody(try #require(await chatTransport.requests().first?.body))
        let chatOutput = try #require(chatBody["messages"]?[0]?["content"]?.stringValue)
        #expect(try decodeJSONBody(Data(chatOutput.utf8)) == .object(["error": value]))
        for custom in [false, true] {
            let transport = RecordingTransport(response: response)
            let model = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gpt-4o")
            _ = try await model.generate(LanguageModelRequest(messages: [message], tools: custom ? ["deploy": OpenAITools.customTool(name: "deploy")] : [:]))
            let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
            let item = try #require(body["input"]?[0])
            #expect(item["type"] == (custom ? "custom_tool_call_output" : "function_call_output"))
            #expect(try decodeJSONBody(Data(try #require(item["output"]?.stringValue).utf8)) == .object(["error": value]))
        }
    }

    @Test func storedAssistantTextPartsUseOneReferencePerMessage() async throws {
        let transport = RecordingTransport(response: response)
        let model = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel("gpt-4o")
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello"), AIMessage(role: .assistant, content: [.text("First", providerMetadata: ["openai": ["itemId": "msg_1"]]), .text("Second", providerMetadata: ["openai": ["itemId": "msg_1"]])]), .user("Continue")]))
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        let references = body["input"]?.arrayValue?.filter { $0["type"] == "item_reference" }
        #expect(references == [["type": "item_reference", "id": "msg_1"]])
    }

    @Test(arguments: ["error-text", "error-json"])
    func sharedResponsesPreservesNonOpenAIErrorEncoding(_ type: String) throws {
        let value: JSONValue = type == "error-text" ? "E42" : ["code": "E42"]
        let result = AIToolResult(toolCallID: "call", toolName: "deploy", result: ["type": .string(type), "value": value])
        for providerID in ["xai.responses", "open-responses", "quiverai.responses"] {
            var warnings: [AIWarning] = []
            let encoded = openResponsesToolResultOutput(result, providerID: providerID, warnings: &warnings)
            if type == "error-text" { #expect(encoded == value) }
            else { #expect(try decodeJSONBody(Data(try #require(encoded.stringValue).utf8)) == value) }
        }
        var warnings: [AIWarning] = []
        let backed = openResponsesToolResultOutput(result, providerID: "custom.responses", wrapToolErrors: true, warnings: &warnings)
        #expect(try decodeJSONBody(Data(try #require(backed.stringValue).utf8)) == ["error": value])
    }

    @Test(arguments: ["gpt-6-sol", "gpt-6-luna"])
    func lastConfigurationUpdateControlsSamplingAndLogprobs(_ modelID: String) async throws {
        func update(_ effort: String) -> AIMessage {
            AIMessage(role: .system, content: [.text("")], providerMetadata: ["openai": ["reasoningEffortUpdate": .string(effort)]])
        }
        let cases: [([AIMessage], JSONValue, Bool)] = [
            ([.user("Hello")], ["reasoningEffort": "none", "reasoningEffortUpdate": "low"], false),
            ([.user("Hello")], ["reasoningEffort": "low", "reasoningEffortUpdate": "none"], true),
            ([.user("Hello"), update("low"), .user("Again")], ["reasoningEffort": "none"], false),
            ([.user("Hello"), update("low"), .user("Again"), update("none"), .user("Finally")], ["reasoningEffort": "none"], true),
            ([.user("Hello"), update("low"), .user("Again")], ["reasoningEffort": "low", "reasoningEffortUpdate": "none"], false),
            ([update("none"), .user("Hello")], [:], true)
        ]
        for (messages, options, supported) in cases {
            for streaming in [false, true] {
                let transport = RecordingTransport(response: streaming ? sseResponse(#"data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":1}}}"#) : response)
                let model = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: transport)).languageModel(modelID)
                var providerOptions = options.objectValue ?? [:]
                providerOptions["reasoningSummary"] = .null
                providerOptions["logprobs"] = 2
                providerOptions["include"] = ["message.output_text.logprobs", "reasoning.encrypted_content"]
                let request = LanguageModelRequest(messages: messages, temperature: 0, topP: 0.9, providerOptions: ["openai": .object(providerOptions)])
                var warnings: [AIWarning] = []
                if streaming {
                    for try await part in model.stream(request) { if case let .streamStart(value) = part { warnings = value } }
                } else { warnings = try await model.generate(request).warnings }
                let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
                #expect(body["temperature"] == (supported ? 0 : nil))
                #expect(body["top_p"] == (supported ? 0.9 : nil))
                #expect(body["top_logprobs"] == (supported ? 2 : nil))
                #expect(body["reasoning"]?["effort"] == options["reasoningEffort"])
                #expect(body["include"]?.arrayValue?.contains("message.output_text.logprobs") == supported)
                #expect(warnings.filter { ["temperature", "topP", "logprobs"].contains($0.feature ?? "") }.count == (supported ? 0 : 3))
            }
        }
    }

    @Test func chatWarnsWhenReasoningSummaryOnlyWorksInResponses() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
        let model = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: transport)).chat("gpt-6-sol")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")], providerOptions: ["openai": ["reasoningSummary": "auto"]]))
        #expect(result.warnings.contains { $0.feature == "reasoningSummary" && $0.message?.contains("Responses API") == true })
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["reasoning_summary"] == nil)
    }

    @Test(arguments: ["failed", "incomplete"])
    func failedWebSearchReturnsErrorToolResultsInGenerateStreamAndBatch(_ status: String) async throws {
        let item: JSONValue = ["type": "web_search_call", "id": "search", "status": .string(status)]
        let raw: JSONValue = ["id": "resp", "status": "completed", "output": .array([item]), "usage": ["input_tokens": 1, "output_tokens": 1]]
        let generated = RecordingTransport(response: AIHTTPResponse(statusCode: 200, body: try encodeJSONBody(raw)))
        let model = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: generated)).languageModel("gpt-4o")
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Search")]))
        #expect(result.toolResults.first?.isError == true)
        #expect(result.toolResults.first?.result == ["status": .string(status)])
        let itemText = String(decoding: try encodeJSONBody(item), as: UTF8.self)
        let streamTransport = RecordingTransport(response: sseResponse("data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":\(itemText)}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}"))
        let streamingModel = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: streamTransport)).languageModel("gpt-4o")
        var streamedResult: AIToolResult?
        for try await part in streamingModel.stream(LanguageModelRequest(messages: [.user("Search")])) { if case let .toolResult(result) = part { streamedResult = result } }
        #expect(streamedResult?.isError == true)
        #expect(streamedResult?.result == ["status": .string(status)])
        let row: JSONValue = ["custom_id": "item", "response": ["status_code": 200, "body": raw]]
        let batchTransport = RecordingTransport(responses: [jsonResponse(#"{"id":"batch","status":"completed","output_file_id":"output","request_counts":{"total":1,"completed":1,"failed":0}}"#), AIHTTPResponse(statusCode: 200, body: try encodeJSONBody(row))])
        let batch = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: batchTransport)).batchLanguageModel("gpt-4o")
        let results = try await batch.getBatchResults(AIBatchOperationOptions(batchID: "batch"))
        var batchResult: TextGenerationResult?
        for try await result in results { if case let .succeeded(_, value) = result { batchResult = value } }
        #expect(batchResult?.toolResults.first?.isError == true)
        #expect(batchResult?.toolResults.first?.result == ["status": .string(status)])
    }

    @Test func openAIBatchDownloadHonorsProviderLineLimit() async throws {
        let transport = RecordingTransport(responses: [jsonResponse(#"{"id":"batch","status":"completed","output_file_id":"output","request_counts":{"total":1,"completed":1,"failed":0}}"#), jsonResponse(#"{"custom_id":"item","response":{"status_code":200,"body":{"id":"resp","status":"completed","output_text":"ok"}}}"#)])
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = AIBatchResultDownloadSettings(maxLineBytes: 16)
        let stream = try await AIProviders.openAI(settings: settings).batchLanguageModel("gpt-4o").getBatchResults(AIBatchOperationOptions(batchID: "batch"))
        await #expect(throws: AIDownloadError.self) { for try await _ in stream {} }
    }

    @Test func openAIAndCompatibleEmbeddingDimensionsKeepProviderPrecedence() async throws {
        for native in [false, true] {
            let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1],"index":0}],"usage":{"prompt_tokens":1,"total_tokens":1}}"#))
            let provider = native ? try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: transport)) : try AIProviders.openAICompatible(name: "proxy", baseURL: "https://proxy.test/v1", transport: transport)
            let model = try provider.embeddingModel("text-embedding-3-small")
            _ = try await model.embed(EmbeddingRequest(values: ["text"], dimensions: 128))
            _ = try await model.embed(EmbeddingRequest(values: ["text"], dimensions: 128, providerOptions: [native ? "openai" : "proxy": ["dimensions": 256]]))
            let requests = await transport.requests()
            #expect(try decodeJSONBody(try #require(requests[0].body))["dimensions"] == 128)
            #expect(try decodeJSONBody(try #require(requests[1].body))["dimensions"] == 256)
        }
    }

    @Test func openResponsesPortableMaxEffortIsForwarded() async throws {
        let transport = RecordingTransport(response: response)
        let provider = try AIProviders.openResponses(name: "open-responses", url: "https://proxy.test/v1/responses", settings: ProviderSettings(transport: transport))
        _ = try await provider.responses("model").generate(LanguageModelRequest(messages: [.user("Hello")], reasoning: "max"))
        #expect(try decodeJSONBody(try #require(await transport.requests().first?.body))["reasoning"]?["effort"] == "max")
    }
}
