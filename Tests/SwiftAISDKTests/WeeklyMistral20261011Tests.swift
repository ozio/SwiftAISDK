import Foundation
import Testing
@testable import SwiftAISDK

private let weeklyMistralConversationAnswer = #"{"conversation_id":"c1","outputs":[{"type":"tool.execution","id":"s1","name":"web_search_premium","arguments":"news","function":"web_search","info":{"result":"search context"}},{"type":"message.output","model":"mistral-small-latest","content":[{"type":"thinking","thinking":[{"type":"text","text":"think"}]},{"type":"text","text":"Answer"},{"type":"tool_reference","url":"https://example.org/news","title":"News"},{"type":"tool_reference","url":"https://example.org/news"}]}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30,"num_cached_tokens":4}}"#

@Test func WeeklyMistral20261011ConversationsMapsToolsReferencesUsageAndStatelessReplay() async throws {
    let transport = RecordingTransport(response: jsonResponse(weeklyMistralConversationAnswer))
    let provider = try AIProviders.mistral(settings: .init(apiKey: "key", transport: transport))
    let model = try provider.conversation("mistral-small-latest")
    let tools = ["news": MistralTools.webSearchPremium()]
    let result = try await model.generate(.init(messages: [.user("News?")], tools: tools))
    #expect(result.text == "Answer")
    #expect(result.reasoning == "think")
    #expect(result.toolCalls.first?.name == "news")
    #expect(result.toolCalls.first?.providerExecuted == true)
    #expect(result.toolCalls.first?.providerMetadata["mistral"]?["function"] == "web_search")
    #expect(result.toolResults.first?.result["info"]?["result"] == "search context")
    #expect(result.sources.count == 1)
    #expect(result.sources.first?.title == "News")
    #expect(result.usage?.inputTokensNoCache == 6)
    #expect(result.finishReason == "stop")
    #expect(result.responseMetadata.id == "c1")
    let firstBody = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(firstBody["store"] == false)
    #expect(firstBody["tools"] == [["type": "web_search_premium"]])
    #expect(await transport.requests().first?.url.path == "/v1/conversations")
    let history = AIMessage(role: .assistant, content: [.toolCall(try #require(result.toolCalls.first)), .toolResult(try #require(result.toolResults.first)), .text(result.text)])
    _ = try await model.generate(.init(messages: [.user("News?"), history, .user("More?")]))
    let replay = try decodeJSONBody(try #require(await transport.requests().last?.body))
    #expect(replay["inputs"]?[1] == ["type": "function.call", "tool_call_id": "s1", "name": "web_search", "arguments": "news"])
    #expect(replay["inputs"]?[2] == ["type": "function.result", "tool_call_id": "s1", "result": "search context"])
    #expect(replay["inputs"]?.arrayValue?.allSatisfy { $0["id"] == nil } == true)
    _ = try await model.generate(.init(messages: [.user("new")]))
    let fresh = try decodeJSONBody(try #require(await transport.requests().last?.body))
    #expect(fresh["inputs"]?.arrayValue?.count == 1)
}

@Test(arguments: ["news", "weather"])
func WeeklyMistral20261011ForcesRenamedSearchOrFunctionsAndNestsCompletionOptions(_ chosen: String) async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"conversation_id":"c","outputs":[{"type":"message.output","content":"{}"}]}"#))
    let model = try AIProviders.mistral(settings: .init(apiKey: "key", transport: transport)).conversation("mistral-large-4")
    let result = try await model.generate(.init(messages: [.system("one"), .system("two"), .user("answer")], temperature: 0.3, topP: 0.9,
                                               topK: 5, presencePenalty: 0.2, frequencyPenalty: 0.1, seed: 1, maxOutputTokens: 100,
                                               stopSequences: ["END"], responseFormat: .json(schema: ["type": "object"]), reasoning: "max",
                                               tools: ["search": MistralTools.webSearch(), "news": MistralTools.webSearchPremium(), "weather": ["type": "object"]],
                                               toolChoice: ["type": "tool", "toolName": .string(chosen)],
                                               providerOptions: ["mistral": ["safePrompt": true, "documentImageLimit": 1, "documentPageLimit": 2, "parallelToolCalls": false, "promptCacheKey": "cache"]]))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["instructions"] == "one\n\ntwo")
    #expect(body["completion_args"]?["reasoning_effort"] == "high")
    #expect(body["completion_args"]?["max_tokens"] == 100)
    #expect(body["completion_args"]?["tool_choice"] == "any")
    #expect(body["completion_args"]?["response_format"]?["json_schema"]?["strict"] == false)
    #expect(body["tools"]?.arrayValue?.count == 1)
    if chosen == "news" { #expect(body["tools"]?[0] == ["type": "web_search_premium"]) }
    else { #expect(body["tools"]?[0]?["function"]?["name"] == "weather") }
    #expect(body["completion_args"]?["parallel_tool_calls"] == nil)
    #expect(Set(result.warnings.compactMap(\.feature)).isSuperset(of: ["safePrompt", "documentImageLimit", "documentPageLimit", "parallelToolCalls", "promptCacheKey", "topK"]))
}

@Test func WeeklyMistral20261011ReplayKeepsMessageOrderingReasoningAndNativeFunctionResults() throws {
    let call = AIToolCall(id: "f1", name: "weather", arguments: #"{"city":"Paris"}"#)
    let history = [AIMessage(role: .assistant, content: [.text("before"), .reasoning("think"), .toolCall(call), .toolResult(.init(toolCallID: "f1", toolName: "weather", result: ["type": "text", "value": "sunny"])), .text("after")])]
    let converted = try mistralConversationInputs(history, mapping: .init(tools: [:]))
    #expect(converted.inputs.count == 4)
    #expect(converted.inputs[0]["content"]?[1]?["type"] == "thinking")
    #expect(converted.inputs[1]["arguments"] == .string(call.arguments))
    #expect(converted.inputs[2]["result"] == "sunny")
    #expect(converted.inputs[3]["content"]?[0]?["text"] == "after")
    #expect(throws: AIError.self) { try mistralConversationInputs([AIMessage(role: .assistant, content: [.imageURL("https://example.org/image")])], mapping: .init(tools: [:])) }
    let files = try mistralConversationInputs([AIMessage(role: .user, content: [.imageURL("https://example.org/image.png"), .providerReference(mimeType: "application/pdf", reference: ["mistral": "https://example.org/document.pdf"])])], mapping: .init(tools: [:]))
    #expect(files.inputs[0]["content"]?[0]?["image_url"] == "https://example.org/image.png")
    #expect(files.inputs[0]["content"]?[1]?["document_url"] == "https://example.org/document.pdf")
}

@Test func WeeklyMistral20261011StreamingMapsSearchThinkingSourcesAndFunctionDeltas() async throws {
    let events: [JSONValue] = [
        ["type": "conversation.response.started", "conversation_id": "c", "created_at": "2026-10-06T00:00:00Z"],
        ["type": "tool.execution.started", "id": "s", "name": "web_search", "arguments": "latest"],
        ["type": "tool.execution.delta", "id": "s", "name": "web_search", "arguments": " news"],
        ["type": "tool.execution.done", "id": "s", "name": "web_search", "info": ["result": "context"]],
        ["type": "message.output.delta", "id": "m", "model": "mistral-large-4", "content": ["type": "thinking", "thinking": [["type": "text", "text": "think"]]]],
        ["type": "message.output.delta", "id": "m", "content": "Answer"],
        ["type": "message.output.delta", "id": "m", "content": ["type": "tool_reference", "url": "https://example.org"]],
        ["type": "message.output.delta", "id": "m", "content": ["type": "tool_reference", "url": "https://example.org", "title": "duplicate"]],
        ["type": "function.call.delta", "tool_call_id": "f", "name": "weather", "arguments": "{\"city\":", "output_index": 3],
        ["type": "function.call.delta", "tool_call_id": "f", "name": "weather", "arguments": "\"Paris\"}", "output_index": 3],
        ["type": "conversation.response.done", "usage": ["prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30]]
    ]
    let sse = try events.map { "data: \(String(decoding: try encodeJSONBody($0), as: UTF8.self))\n\n" }.joined()
    let transport = RecordingTransport(response: sseResponse(sse))
    let model = try AIProviders.mistral(settings: .init(apiKey: "key", transport: transport)).conversation("mistral-large-4")
    let parts = try await weeklyMediumCollect(model.stream(.init(messages: [.user("News")], tools: ["search": MistralTools.webSearch()], includeRawChunks: true)))
    #expect(parts.contains(.reasoningStart(id: "m-0")))
    #expect(parts.contains(.reasoningEnd(id: "m-0")))
    #expect(parts.contains(.textStart(id: "m-0")))
    #expect(parts.contains(.textEnd(id: "m-0")))
    let calls = parts.compactMap { if case let .toolCall(call) = $0 { call } else { nil } }
    #expect(calls.count == 2)
    #expect(calls.first?.arguments == #"{"arguments":"latest news"}"#)
    #expect(calls.last?.arguments == #"{"city":"Paris"}"#)
    #expect(parts.filter { if case .source = $0 { true } else { false } }.count == 1)
    #expect(parts.filter { if case .raw = $0 { true } else { false } }.count == events.count)
    if case let .finishMetadata(reason, usage, _) = parts.last { #expect(reason == "tool-calls"); #expect(usage?.totalTokens == 30) }
    else { Issue.record("Missing finish") }
}

@Test(arguments: [#"{"type":"conversation.response.error","message":"failed","code":500}"#, #"{"type":"message.output.delta","id":"m","content":42}"#, #"{"type":"message.output.delta","id":"m","content":"truncated"}"#, #"{"type":"tool.execution.started","id":"s","name":"web_search","arguments":""}"#])
func WeeklyMistral20261011IncompleteAndInvalidStreamsFinishWithError(_ event: String) async throws {
    let model = try AIProviders.mistral(settings: .init(apiKey: "key", transport: RecordingTransport(response: sseResponse("data: \(event)\n\n")))).conversation("mistral-small-latest")
    let parts = try await weeklyMediumCollect(model.stream(.init(messages: [.user("Hi")])))
    if case let .finishMetadata(reason, _, _) = parts.last { #expect(reason == "error") } else { Issue.record("Missing finish") }
}

@Test(arguments: ["mistral-large-4", "mistral-large-4-0"])
func WeeklyMistral20261011Large4ChatSupportsMaxReasoning(_ modelID: String) async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let result = try await AIProviders.mistral(settings: .init(apiKey: "key", transport: transport)).languageModel(modelID).generate(.init(messages: [.user("Hi")], reasoning: "max"))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["reasoning_effort"] == "high")
    #expect(!result.warnings.contains { $0.type == "unsupported" && $0.feature == "reasoning" })
}

@Test func WeeklyMistral20261011EmbeddingUsesSharedDimensionsAndProviderOverride() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[1,2]}]}"#))
    let model = try AIProviders.mistral(settings: .init(apiKey: "key", transport: transport)).embedding("mistral-embed")
    _ = try await model.embed(.init(values: ["text"], dimensions: 256))
    #expect(try decodeJSONBody(try #require(await transport.requests().last?.body))["output_dimension"] == 256)
    _ = try await model.embed(.init(values: ["text"], dimensions: 256, providerOptions: ["mistral": ["outputDimension": 512]]))
    #expect(try decodeJSONBody(try #require(await transport.requests().last?.body))["output_dimension"] == 512)
}
