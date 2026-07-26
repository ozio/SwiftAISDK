import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesPreparesProgrammaticToolCallingLikeUpstream() async throws {
    let body = try await recordedOpenAIResponsesBody(
        modelID: "gpt-5.6",
        tools: [
            "program": OpenAITools.programmaticToolCalling(name: "program"),
            "get_inventory": [
                "type": "object",
                "description": "Get inventory",
                "properties": ["sku": ["type": "string"]],
                "required": ["sku"],
                "additionalProperties": false,
                "providerOptions": [
                    "openai": [
                        "allowedCallers": ["programmatic"],
                        "outputSchema": [
                            "type": "object",
                            "properties": ["availableUnits": ["type": "number"]],
                            "required": ["availableUnits"],
                            "additionalProperties": false
                        ]
                    ]
                ]
            ]
        ],
        toolChoice: ["type": "tool", "toolName": "program"]
    )

    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "programmatic_tool_calling" })
    let function = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(function["allowed_callers"]?[0]?.stringValue == "programmatic")
    #expect(function["output_schema"]?["properties"]?["availableUnits"]?["type"]?.stringValue == "number")
    #expect(function["parameters"]?["providerOptions"] == nil)
    #expect(body["tool_choice"]?["type"]?.stringValue == "programmatic_tool_calling")
}

@Test func openAIResponsesMapsProgrammaticCallsOutputsAndCallerMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id":"resp-program",
      "status":"completed",
      "output":[
        {
          "type":"program",
          "id":"program_item_1",
          "call_id":"program_call_1",
          "code":"const value = await tools.get_inventory({ sku: \\"A\\" });",
          "fingerprint":"fingerprint_1"
        },
        {
          "type":"function_call",
          "id":"function_item_1",
          "call_id":"function_call_1",
          "name":"get_inventory",
          "arguments":"{\\"sku\\":\\"A\\"}",
          "caller":{"type":"program","caller_id":"program_call_1"}
        },
        {
          "type":"program_output",
          "id":"program_output_item_1",
          "call_id":"program_call_1",
          "result":"{\\"availableUnits\\":42}",
          "status":"completed"
        }
      ],
      "usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}
    }
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.6")
    let tools: [String: JSONValue] = [
        "program": OpenAITools.programmaticToolCalling(name: "program"),
        "get_inventory": ["type": "object", "properties": ["sku": ["type": "string"]]]
    ]

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Check inventory.")],
        tools: tools
    ))

    let program = try #require(result.toolCalls.first { $0.name == "program" })
    #expect(program.id == "program_call_1")
    #expect(program.providerExecuted)
    #expect(program.providerMetadata["openai"]?["itemId"]?.stringValue == "program_item_1")
    #expect(program.arguments.contains("fingerprint_1"))
    let function = try #require(result.toolCalls.first { $0.name == "get_inventory" })
    #expect(function.providerMetadata["openai"]?["caller"]?["type"]?.stringValue == "program")
    #expect(function.providerMetadata["openai"]?["caller"]?["callerId"]?.stringValue == "program_call_1")
    let output = try #require(result.toolResults.first { $0.toolName == "program" })
    #expect(output.result["status"]?.stringValue == "completed")
    #expect(output.providerMetadata["openai"]?["itemId"]?.stringValue == "program_output_item_1")

    let replayTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-replay","status":"completed","output_text":"done"}"#))
    let replayProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: replayTransport))
    _ = try await replayProvider.languageModel("gpt-5.6").generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .toolCall(program),
                .toolCall(function)
            ]),
            AIMessage(role: .tool, content: [
                .toolResult(AIToolResult(
                    toolCallID: "function_call_1",
                    toolName: "get_inventory",
                    result: ["sku": "A", "availableUnits": 42],
                    providerMetadata: [
                        "openai": [
                            "caller": ["type": "program", "callerId": "program_call_1"]
                        ]
                    ]
                ))
            ]),
            AIMessage(role: .assistant, content: [.toolResult(output)])
        ],
        tools: tools,
        extraBody: ["store": false]
    ))

    let replayBody = try decodeJSONBody(try #require((await replayTransport.requests()).first?.body))
    let input = try #require(replayBody["input"]?.arrayValue)
    #expect(input[0]["type"]?.stringValue == "program")
    #expect(input[0]["id"]?.stringValue == "program_item_1")
    #expect(input[1]["caller"]?["caller_id"]?.stringValue == "program_call_1")
    #expect(input[2]["type"]?.stringValue == "function_call_output")
    #expect(input[2]["caller"]?["caller_id"]?.stringValue == "program_call_1")
    #expect(input[3]["type"]?.stringValue == "program_output")
    #expect(input[3]["id"]?.stringValue == "program_output_item_1")
}

@Test func openAIResponsesStreamsProgrammaticItemsOnlyWhenDoneLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"program","id":"program_item_1","call_id":"program_call_1","code":"","fingerprint":""}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"program","id":"program_item_1","call_id":"program_call_1","code":"return 42","fingerprint":"fp"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"type":"program_output","id":"program_output_item_1","call_id":"program_call_1","result":"","status":"incomplete"}}

    data: {"type":"response.output_item.done","output_index":1,"item":{"type":"program_output","id":"program_output_item_1","call_id":"program_call_1","result":"42","status":"completed"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.6")
    var calls: [AIToolCall] = []
    var results: [AIToolResult] = []
    var inputLifecycleCount = 0

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Run it.")],
        tools: ["program": OpenAITools.programmaticToolCalling(name: "program")]
    )) {
        switch part {
        case let .toolCall(call):
            calls.append(call)
        case let .toolResult(result):
            results.append(result)
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            inputLifecycleCount += 1
        default:
            break
        }
    }

    #expect(calls.count == 1)
    #expect(calls[0].name == "program")
    #expect(calls[0].arguments.contains("return 42"))
    #expect(results.count == 1)
    #expect(results[0].result["result"]?.stringValue == "42")
    #expect(inputLifecycleCount == 0)
}

@Test func openAIUsesForwardCompatibleDefaultsForFutureModelFamilies() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":2}}
    """))
    let chatProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: chatTransport))
    _ = try await chatProvider.chatModel("gpt-99").generate(LanguageModelRequest(
        messages: [.system("Follow instructions."), .user("Say ok.")],
        temperature: 0.2,
        topP: 0.8,
        presencePenalty: 0.1,
        frequencyPenalty: 0.1,
        maxOutputTokens: 64,
        providerOptions: ["openai": ["logitBias": ["1": 1], "logprobs": 2]]
    ))
    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["messages"]?[0]?["role"]?.stringValue == "developer")
    #expect(chatBody["max_completion_tokens"]?.intValue == 64)
    #expect(chatBody["max_tokens"] == nil)
    #expect(chatBody["temperature"] == nil)
    #expect(chatBody["top_p"] == nil)
    #expect(chatBody["frequency_penalty"] == nil)
    #expect(chatBody["presence_penalty"] == nil)
    #expect(chatBody["logit_bias"] == nil)
    #expect(chatBody["logprobs"] == nil)

    let responsesTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-future","status":"completed","output_text":"ok"}"#))
    let responsesProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: responsesTransport))
    _ = try await responsesProvider.languageModel("gpt-99").generate(LanguageModelRequest(
        messages: [.system("Follow instructions."), .user("Say ok.")],
        temperature: 0.2,
        topP: 0.8,
        providerOptions: ["openai": ["reasoningEffort": "medium"]]
    ))
    let responsesBody = try decodeJSONBody(try #require((await responsesTransport.requests()).first?.body))
    #expect(responsesBody["input"]?[0]?["role"]?.stringValue == "developer")
    #expect(responsesBody["temperature"] == nil)
    #expect(responsesBody["top_p"] == nil)

    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"one"},{"b64_json":"two"}]}"#))
    let imageProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: imageTransport))
    let imageResult = try await imageProvider.imageModel("gpt-image-99").generateImage(
        ImageGenerationRequest(prompt: "A black square.", count: 2)
    )
    #expect(imageResult.base64Images.count == 2)
    let imageBody = try decodeJSONBody(try #require((await imageTransport.requests()).first?.body))
    #expect(imageBody["response_format"] == nil)
}
