import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesComputerV4ParsesOrderedActionsAndSafetyChecksLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id":"resp_computer_test",
      "status":"completed",
      "model":"gpt-5.4",
      "output":[{
        "type":"computer_call",
        "id":"computer_item_123",
        "call_id":"computer_call_123",
        "status":"completed",
        "pending_safety_checks":[{"id":"safety_123","code":"confirm_action","message":"Confirm this action."}],
        "actions":[
          {"type":"click","button":"left","x":100,"y":200,"keys":["CTRL"]},
          {"type":"double_click","x":110,"y":210,"keys":null},
          {"type":"drag","path":[{"x":10,"y":20},{"x":30,"y":40}]},
          {"type":"keypress","keys":["CTRL","L"]},
          {"type":"move","x":120,"y":220},
          {"type":"screenshot"},
          {"type":"scroll","x":130,"y":230,"scroll_x":0,"scroll_y":500},
          {"type":"type","text":"hello"},
          {"type":"wait"}
        ]
      }],
      "usage":{"input_tokens":100,"output_tokens":50}
    }
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.languageModel("gpt-5.4").generate(LanguageModelRequest(
        messages: [.user("Use it.")],
        tools: ["computer": OpenAITools.computer()]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"]?[0] == .object(["type": .string("computer")]))
    let call = try #require(result.toolCalls.first)
    #expect(call.id == "computer_call_123")
    #expect(call.name == "computer")
    #expect(call.providerExecuted == false)
    #expect(call.providerMetadata["openai"]?["itemId"]?.stringValue == "computer_item_123")
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    let actions = try #require(input["actions"]?.arrayValue)
    #expect(actions.map { $0["type"]?.stringValue } == [
        "click", "double_click", "drag", "keypress", "move", "screenshot", "scroll", "type", "wait"
    ])
    #expect(actions[0]["keys"]?[0]?.stringValue == "CTRL")
    #expect(actions[1]["keys"] == nil)
    #expect(actions[2]["path"]?[1]?["x"]?.intValue == 30)
    #expect(actions[6]["scrollX"]?.intValue == 0)
    #expect(actions[6]["scrollY"]?.intValue == 500)
    #expect(input["pendingSafetyChecks"]?[0]?["id"]?.stringValue == "safety_123")
    #expect(input["pendingSafetyChecks"]?[0]?["code"]?.stringValue == "confirm_action")
    #expect(input["pendingSafetyChecks"]?[0]?["message"]?.stringValue == "Confirm this action.")
    #expect(input["status"]?.stringValue == "completed")
    #expect(result.toolResults.isEmpty)
    #expect(result.finishReason == "tool-calls")
}

@Test func openAIResponsesComputerV4StreamsInputLifecycleAndToolCallLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_computer_test","created_at":1741630255,"model":"gpt-5.4"}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"computer_call","id":"computer_item_123","call_id":"computer_call_123","status":"in_progress"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"computer_call","id":"computer_item_123","call_id":"computer_call_123","status":"completed","pending_safety_checks":[{"id":"safety_123","code":"confirm_action","message":"Confirm this action."}],"actions":[{"type":"scroll","x":130,"y":230,"scroll_x":0,"scroll_y":500}]}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":100,"output_tokens":50}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var lifecycle: [String] = []
    var deltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use it.")],
        tools: ["computer": OpenAITools.computer()]
    )) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            deltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .finishMetadata(reason, _, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(lifecycle == [
        "start:computer_call_123:computer:false",
        "delta:computer_call_123",
        "end:computer_call_123"
    ])
    let streamedInput = try decodeJSONBody(Data(deltas.joined().utf8))
    #expect(streamedInput["actions"]?[0]?["type"]?.stringValue == "scroll")
    #expect(streamedInput["actions"]?[0]?["scrollY"]?.intValue == 500)
    #expect(streamedInput["pendingSafetyChecks"]?[0]?["id"]?.stringValue == "safety_123")
    #expect(toolCall?.id == "computer_call_123")
    #expect(toolCall?.name == "computer")
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "computer_item_123")
    #expect(toolCall?.arguments == deltas.joined())
    #expect(finishReason == "tool-calls")
}

@Test func openAIResponsesComputerV4ReplaysCallAndScreenshotForStorageModesLikeUpstream() async throws {
    let cases: [(store: Bool, previousResponseID: String?, expectedCallType: String?)] = [
        (true, nil, "item_reference"),
        (false, nil, "computer_call"),
        (true, "resp_previous", nil)
    ]

    for testCase in cases {
        let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
        let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
        var options: [String: JSONValue] = ["store": .bool(testCase.store)]
        if let previousResponseID = testCase.previousResponseID {
            options["previousResponseId"] = .string(previousResponseID)
        }
        let call = AIToolCall(
            id: "computer_call_123",
            name: "computer",
            arguments: #"{"actions":[{"type":"scroll","x":10,"y":20,"scrollX":0,"scrollY":100}],"pendingSafetyChecks":[{"id":"safety_123","code":"confirm_action"}],"status":"completed"}"#,
            providerMetadata: ["openai": ["itemId": "computer_item_123"]]
        )
        let screenshot = AIToolResult(
            toolCallID: "computer_call_123",
            toolName: "computer",
            result: [
                "type": "json",
                "value": [
                    "output": [
                        "type": "computer_screenshot",
                        "imageUrl": "data:image/png;base64,c2NyZWVuc2hvdA==",
                        "detail": "original"
                    ],
                    "acknowledgedSafetyChecks": [[
                        "id": "safety_123",
                        "code": "confirm_action"
                    ]]
                ]
            ]
        )

        _ = try await provider.languageModel("gpt-5.4").generate(LanguageModelRequest(
            messages: [
                AIMessage(role: .assistant, content: [.toolCall(call)]),
                .toolResult(screenshot)
            ],
            tools: ["computer": OpenAITools.computer()],
            providerOptions: ["openai": .object(options)]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        let input = try #require(body["input"]?.arrayValue)
        let output = try #require(input.last)
        #expect(input.count == (testCase.expectedCallType == nil ? 1 : 2))
        if let expectedCallType = testCase.expectedCallType {
            let replayedCall = try #require(input.first)
            #expect(replayedCall["type"]?.stringValue == expectedCallType)
            #expect(replayedCall["id"]?.stringValue == "computer_item_123")
            if expectedCallType == "computer_call" {
                #expect(replayedCall["call_id"]?.stringValue == "computer_call_123")
                #expect(replayedCall["actions"]?[0]?["scroll_x"]?.intValue == 0)
                #expect(replayedCall["actions"]?[0]?["scroll_y"]?.intValue == 100)
                #expect(replayedCall["pending_safety_checks"]?[0]?["id"]?.stringValue == "safety_123")
            }
        }
        #expect(output["type"]?.stringValue == "computer_call_output")
        #expect(output["call_id"]?.stringValue == "computer_call_123")
        #expect(output["output"]?["type"]?.stringValue == "computer_screenshot")
        #expect(output["output"]?["image_url"]?.stringValue == "data:image/png;base64,c2NyZWVuc2hvdA==")
        #expect(output["output"]?["detail"]?.stringValue == "original")
        #expect(output["acknowledged_safety_checks"]?[0]?["id"]?.stringValue == "safety_123")
        #expect(output["acknowledged_safety_checks"]?[0]?["code"]?.stringValue == "confirm_action")
    }
}

@Test func openAIResponsesComputerV4SerializesFileIDScreenshotLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let screenshot = AIToolResult(
        toolCallID: "computer_call_123",
        toolName: "computer",
        result: [
            "type": "json",
            "value": [
                "output": [
                    "type": "computer_screenshot",
                    "fileId": "file_screenshot_123"
                ]
            ]
        ]
    )

    _ = try await provider.languageModel("gpt-5.4").generate(LanguageModelRequest(
        messages: [.toolResult(screenshot)],
        tools: ["computer": OpenAITools.computer()]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let output = try #require(body["input"]?[0])
    #expect(output["type"]?.stringValue == "computer_call_output")
    #expect(output["call_id"]?.stringValue == "computer_call_123")
    #expect(output["output"]?["type"]?.stringValue == "computer_screenshot")
    #expect(output["output"]?["file_id"]?.stringValue == "file_screenshot_123")
    #expect(output["output"]?["image_url"] == nil)
    #expect(output["output"]?["detail"] == nil)
    #expect(output["acknowledged_safety_checks"] == nil)
}
