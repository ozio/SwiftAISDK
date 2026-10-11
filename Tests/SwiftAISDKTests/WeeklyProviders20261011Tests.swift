import Foundation
import Testing
@testable import SwiftAISDK

@Test(arguments: ["float", "int8", "uint8", "binary", "ubinary"])
func WeeklyProviders20261011CohereSelectedEmbeddingTypePreservesPackedBytes(_ type: String) async throws {
    let raw = "{\"embeddings\":{\"\(type)\":[[-1,2,3]]},\"meta\":{\"billed_units\":{\"input_tokens\":4}}}"
    let transport = RecordingTransport(response: jsonResponse(raw))
    let model = try AIProviders.cohere(settings: .init(apiKey: "key", transport: transport)).embedding("embed-v5.0-fast")
    let result = try await model.embed(.init(values: ["text"], dimensions: 768, providerOptions: ["cohere": ["embeddingType": .string(type), "outputDimension": 2048]]))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["embedding_types"] == [.string(type)])
    #expect(body["output_dimension"] == 2048)
    #expect(body["embeddingType"] == nil)
    #expect(result.embeddings == [[-1, 2, 3]])
    #expect(result.usage?.totalTokens == 4)
}

@Test(arguments: [768, 2048])
func WeeklyProviders20261011CohereDimensionsFallbackAndV5Options(_ dimensions: Int) async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"embeddings":{"float":[[1]]},"meta":{"billed_units":{"input_tokens":1}}}"#))
    let model = try AIProviders.cohere(settings: .init(apiKey: "key", transport: transport)).embedding("embed-v5.0-pro")
    _ = try await model.embed(.init(values: ["text"], dimensions: dimensions))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["output_dimension"]?.intValue == dimensions)
}

@Test(arguments: [#"{"embeddings":{"float":[[1]]},"meta":{"billed_units":{"input_tokens":1}}}"#, #"{"embeddings":{"int8":[["bad"]]},"meta":{"billed_units":{"input_tokens":1}}}"#])
func WeeklyProviders20261011CohereRejectsWrongSelectedEmbeddingResponse(_ raw: String) async throws {
    let model = try AIProviders.cohere(settings: .init(apiKey: "key", transport: RecordingTransport(response: jsonResponse(raw)))).embedding("embed-v5.0-pro")
    await #expect(throws: AIError.self) { try await model.embed(.init(values: ["text"], providerOptions: ["cohere": ["embeddingType": "int8"]])) }
}

@Test func WeeklyProviders20261011CohereCachedTokensAppearInGenerateAndStreamUsage() async throws {
    let raw = #"{"message":{"content":[{"type":"text","text":"answer"}]},"usage":{"tokens":{"input_tokens":10,"output_tokens":20},"cached_tokens":4}}"#
    let generate = try AIProviders.cohere(settings: .init(apiKey: "key", transport: RecordingTransport(response: jsonResponse(raw)))).languageModel("command-a")
    let result = try await generate.generate(.init(messages: [.user("Hi")]))
    #expect(result.usage?.inputTokensNoCache == 6)
    #expect(result.usage?.inputTokensCacheRead == 4)
    #expect(result.usage?.totalTokens == 30)
    let streamModel = try AIProviders.cohere(settings: .init(apiKey: "key", transport: RecordingTransport(response: sseResponse("data: {\"type\":\"message-end\",\"delta\":\(raw)}\n\n")))).languageModel("command-a")
    for try await part in streamModel.stream(.init(messages: [.user("Hi")])) {
        if case let .finishMetadata(_, usage, _) = part { #expect(usage?.inputTokensNoCache == 6); #expect(usage?.inputTokensCacheRead == 4) }
    }
}

@Test(arguments: ["required", "none", "named"])
func WeeklyProviders20261011GroqStructuredOutputUsesJSONToolAlongsideFunctions(_ choice: String) async throws {
    let jsonName = "json_2"
    let transport = RecordingTransport(response: jsonResponse("{\"choices\":[{\"message\":{\"content\":\"suppressed\",\"tool_calls\":[{\"id\":\"j\",\"function\":{\"name\":\"\(jsonName)\",\"arguments\":\"{\\\"date\\\":\\\"2031-06-17\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":8}}"))
    let model = try AIProviders.groq(settings: .init(apiKey: "key", transport: transport)).languageModel("openai/gpt-oss-120b")
    let toolChoice: JSONValue = choice == "named" ? ["type": "tool", "toolName": "weather"] : .string(choice)
    let result = try await model.generate(.init(messages: [.user("Date")], responseFormat: .json(schema: ["type": "object"]),
                                                 tools: ["weather": ["type": "object"], "json": ["type": "object"], "json_1": ["type": "object"]], toolChoice: toolChoice, providerOptions: ["groq": ["parallelToolCalls": true, "structuredOutputs": false]]))
    let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
    #expect(body["response_format"] == nil)
    #expect(body["parallel_tool_calls"] == false)
    #expect(body["tools"]?.arrayValue?.contains { $0["function"]?["name"] == .string(jsonName) } == true)
    if choice == "required" { #expect(body["tool_choice"] == "required") }
    else { #expect(body["tool_choice"]?["function"]?["name"] == .string(choice == "none" ? jsonName : "weather")) }
    #expect(result.text == #"{"date":"2031-06-17"}"#)
    #expect(result.toolCalls.isEmpty)
    #expect(result.finishReason == "stop")
    #expect(!result.warnings.contains { $0.feature == "responseFormat" })
}

@Test func WeeklyProviders20261011GroqStreamsJSONToolArgumentsAsTextAndKeepsApplicationCalls() async throws {
    let events = [
        #"{"choices":[{"delta":{"content":"omit","tool_calls":[{"index":0,"id":"j","function":{"name":"json","arguments":"{\"date\":"}}]}}]}"#,
        #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"2031-06-17\"}"}}]},"finish_reason":"tool_calls"}],"x_groq":{"usage":{"prompt_tokens":4,"completion_tokens":8}}}"#
    ]
    let transport = RecordingTransport(response: sseResponse(events.map { "data: \($0)\n\n" }.joined() + "data: [DONE]\n\n"))
    let model = try AIProviders.groq(settings: .init(apiKey: "key", transport: transport)).languageModel("llama-3.3-70b-versatile")
    let parts = try await weeklyMediumCollect(model.stream(.init(messages: [.user("Date")], responseFormat: .json(schema: ["type": "object"]), tools: ["weather": ["type": "object"]])))
    #expect(parts.contains(.textStart(id: "j")))
    #expect(parts.contains(.textEnd(id: "j")))
    #expect(parts.compactMap { if case let .textDeltaPart(_, text, _) = $0 { text } else { nil } }.joined() == #"{"date":"2031-06-17"}"#)
    #expect(!parts.contains { switch $0 { case .toolCall, .toolCallDelta, .toolInputStart, .toolInputDelta, .toolInputEnd: true; default: false } })
    if case let .finishMetadata(reason, usage, _) = parts.last { #expect(reason == "stop"); #expect(usage?.outputTokens == 8) }
    else { Issue.record("Missing finish") }
    let ordinary = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"omit","tool_calls":[{"id":"w","function":{"name":"weather","arguments":"{}"}}]},"finish_reason":"length"}]}"#))
    let result = try await AIProviders.groq(settings: .init(apiKey: "key", transport: ordinary)).languageModel("llama-3.3-70b-versatile").generate(.init(messages: [.user("Date")], responseFormat: .json(schema: ["type": "object"]), tools: ["weather": ["type": "object"]]))
    #expect(result.text.isEmpty)
    #expect(result.toolCalls.first?.name == "weather")
    #expect(result.finishReason == "length")
}

func weeklyMediumCollect<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var parts: [T] = []
    for try await part in stream { parts.append(part) }
    return parts
}
