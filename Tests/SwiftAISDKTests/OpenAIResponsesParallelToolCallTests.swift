import Foundation
import Testing
@testable import SwiftAISDK

private let parallelWrapperArguments = #"{"tool_uses":[{"recipient_name":"functions.weather","parameters":{"location":"San Francisco"}},{"recipient_name":"functions.cityAttractions","parameters":{"city":"Rome"}}]}"#

private func parallelWrapperTools(includeDeclaredParallel: Bool = false) -> [String: JSONValue] {
    var tools: [String: JSONValue] = [
        "weather": ["type": "object", "properties": ["location": ["type": "string"]]],
        "cityAttractions": ["type": "object", "properties": ["city": ["type": "string"]]]
    ]
    if includeDeclaredParallel {
        tools["parallel"] = ["type": "object"]
    }
    return tools
}

private func parallelWrapperMetadata(index: Int) -> [String: JSONValue] {
    [
        "openai": [
            "parallelToolCall": [
                "itemId": "fc_parallel",
                "toolCallId": "call_parallel",
                "toolName": "parallel",
                "input": .string(parallelWrapperArguments),
                "index": .number(Double(index)),
                "count": 2
            ]
        ]
    ]
}

@Test func openAIResponsesExpandsUndeclaredParallelToolCallWrappers() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_parallel","status":"completed","output":[{"type":"function_call","id":"fc_parallel","call_id":"call_parallel","name":"parallel","arguments":"{\\"tool_uses\\":[{\\"recipient_name\\":\\"functions.weather\\",\\"parameters\\":{\\"location\\":\\"San Francisco\\"}},{\\"recipient_name\\":\\"functions.cityAttractions\\",\\"parameters\\":{\\"city\\":\\"Rome\\"}}]}","status":"completed"}],"usage":{"input_tokens":34,"output_tokens":28,"total_tokens":62}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Plan both cities")],
        tools: parallelWrapperTools()
    ))

    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.map(\.id) == ["call_parallel_0", "call_parallel_1"])
    #expect(result.toolCalls.map(\.name) == ["weather", "cityAttractions"])
    #expect(result.toolCalls.map(\.arguments) == [#"{"location":"San Francisco"}"#, #"{"city":"Rome"}"#])
    #expect(result.toolCalls[0].providerMetadata["openai"]?["parallelToolCall"]?["itemId"]?.stringValue == "fc_parallel")
    #expect(result.toolCalls[0].providerMetadata["openai"]?["parallelToolCall"]?["input"]?.stringValue == parallelWrapperArguments)
    #expect(result.toolCalls[1].providerMetadata["openai"]?["parallelToolCall"]?["index"]?.intValue == 1)
    #expect(result.toolCalls[1].providerMetadata["openai"]?["parallelToolCall"]?["count"]?.intValue == 2)
}

@Test func openAIResponsesKeepsDeclaredParallelToolsUnexpanded() async throws {
    let call = AIToolCall(id: "call_parallel", name: "parallel", arguments: parallelWrapperArguments)
    let expanded = openAIResponsesExpandedParallelToolCalls(
        from: call,
        itemID: "fc_parallel",
        providerID: "openai.responses",
        functionToolNames: openAIResponsesFunctionToolNames(from: parallelWrapperTools(includeDeclaredParallel: true))
    )

    #expect(expanded == nil)
}

@Test func openAIResponsesStreamsExpandedParallelToolCallWrappers() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_parallel","status":"in_progress","model":"gpt-5.4","output":[]}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_parallel","call_id":"call_parallel","name":"parallel","arguments":"","status":"in_progress"}}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_parallel","output_index":0,"delta":"{\\"tool_uses\\":[{\\"recipient_name\\":\\"functions.weather\\",\\"parameters\\":{\\"location\\":\\"San Francisco\\"}},{\\"recipient_name\\":\\"functions.cityAttractions\\",\\"parameters\\":{\\"city\\":\\"Rome\\"}}]}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_parallel","call_id":"call_parallel","name":"parallel","arguments":"{\\"tool_uses\\":[{\\"recipient_name\\":\\"functions.weather\\",\\"parameters\\":{\\"location\\":\\"San Francisco\\"}},{\\"recipient_name\\":\\"functions.cityAttractions\\",\\"parameters\\":{\\"city\\":\\"Rome\\"}}]}","status":"completed"}}

    data: {"type":"response.completed","response":{"id":"resp_parallel","status":"completed","output":[],"usage":{"input_tokens":34,"output_tokens":28,"total_tokens":62}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var starts: [(String, String)] = []
    var deltas: [(String, String)] = []
    var ends: [String] = []
    var calls: [AIToolCall] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Plan both cities")],
        tools: parallelWrapperTools()
    )) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _): starts.append((id, name))
        case let .toolInputDelta(id, delta, _): deltas.append((id, delta))
        case let .toolInputEnd(id, _): ends.append(id)
        case let .toolCall(call): calls.append(call)
        default: break
        }
    }

    #expect(starts.map(\.0) == ["call_parallel_0", "call_parallel_1"])
    #expect(starts.map(\.1) == ["weather", "cityAttractions"])
    #expect(deltas.map(\.1) == [#"{"location":"San Francisco"}"#, #"{"city":"Rome"}"#])
    #expect(ends == ["call_parallel_0", "call_parallel_1"])
    #expect(calls.map(\.name) == ["weather", "cityAttractions"])
}

@Test func openAIResponsesParallelStreamFallbackUsesDoneArgumentsWhenNoDeltasArrive() {
    var tracker = OpenAIResponsesStreamingToolCalls(
        providerID: "openai.responses",
        functionToolNames: ["weather"]
    )
    let added: JSONValue = [
        "type": "response.output_item.added",
        "output_index": 0,
        "item": [
            "type": "function_call",
            "id": "fc_parallel",
            "call_id": "call_parallel",
            "name": "parallel",
            "arguments": "",
            "status": "in_progress"
        ]
    ]
    let invalidArguments = #"{"tool_uses":[{"recipient_name":"functions.unknown","parameters":{}}]}"#
    let done: JSONValue = [
        "type": "response.output_item.done",
        "output_index": 0,
        "item": [
            "type": "function_call",
            "id": "fc_parallel",
            "call_id": "call_parallel",
            "name": "parallel",
            "arguments": .string(invalidArguments),
            "status": "completed"
        ]
    ]

    #expect(tracker.apply(event: added).isEmpty)
    let parts = tracker.apply(event: done)
    let deltas = parts.compactMap { part -> String? in
        if case let .toolInputDelta(_, delta, _) = part { delta } else { nil }
    }
    let calls = parts.compactMap { part -> AIToolCall? in
        if case let .toolCall(call) = part { call } else { nil }
    }
    #expect(deltas == [invalidArguments])
    #expect(calls.map(\.name) == ["parallel"])
    #expect(calls.map(\.arguments) == [invalidArguments])
}

@Test func openAIResponsesReconstructsParallelWrapperAndJoinsChildResults() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-next","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Plan both cities"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_parallel_0",
                    name: "weather",
                    arguments: #"{"location":"San Francisco"}"#,
                    providerMetadata: parallelWrapperMetadata(index: 0)
                )),
                .toolCall(AIToolCall(
                    id: "call_parallel_1",
                    name: "cityAttractions",
                    arguments: #"{"city":"Rome"}"#,
                    providerMetadata: parallelWrapperMetadata(index: 1)
                ))
            ]),
            .toolResponses(toolResults: [
                AIToolResult(
                    toolCallID: "call_parallel_0",
                    toolName: "weather",
                    result: ["temperature": 72],
                    providerMetadata: parallelWrapperMetadata(index: 0)
                ),
                AIToolResult(
                    toolCallID: "call_parallel_1",
                    toolName: "cityAttractions",
                    result: "Colosseum",
                    providerMetadata: parallelWrapperMetadata(index: 1)
                )
            ])
        ],
        tools: parallelWrapperTools(),
        providerOptions: ["openai": ["previousResponseId": "resp_parallel", "store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.count == 3)
    #expect(input[1]["type"]?.stringValue == "function_call")
    #expect(input[1]["call_id"]?.stringValue == "call_parallel")
    #expect(input[1]["name"]?.stringValue == "parallel")
    #expect(input[1]["arguments"]?.stringValue == parallelWrapperArguments)
    #expect(input[2]["type"]?.stringValue == "function_call_output")
    #expect(input[2]["call_id"]?.stringValue == "call_parallel")
    #expect(input[2]["output"]?.stringValue == "{\"temperature\":72}\nColosseum")
}
