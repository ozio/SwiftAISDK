import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsComputerUseToolResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"in_progress"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"completed"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    var lifecycle: [String] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use the computer.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(lifecycle == [
        "start:computer_67cf2b3051e88190b006770db6fdb13d:computer_use:true",
        "end:computer_67cf2b3051e88190b006770db6fdb13d"
    ])
    #expect(toolCall?.id == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolCall?.name == "computer_use")
    #expect(toolCall?.arguments == "")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolResult?.toolName == "computer_use")
    #expect(toolResult?.result["type"]?.stringValue == "computer_use_tool_result")
    #expect(toolResult?.result["status"]?.stringValue == "completed")
    #expect(finishReason == "stop")
}
@Test func openAIResponsesStreamsCodeInterpreterInputLifecycleLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"code_interpreter_call","id":"ci_1","status":"in_progress","container_id":"cntr_1"}}

    data: {"type":"response.code_interpreter_call_code.delta","output_index":0,"delta":"print(\\\"hi\\\")\\n"}

    data: {"type":"response.code_interpreter_call_code.done","output_index":0,"code":"print(\\\"hi\\\")\\n"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"code_interpreter_call","id":"ci_1","status":"completed","code":"print(\\\"hi\\\")\\n","container_id":"cntr_1","outputs":[{"type":"logs","logs":"hi\\n"}]}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var lifecycle: [String] = []
    var inputDeltas: [String] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Run code.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            inputDeltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        default:
            break
        }
    }

    #expect(lifecycle == ["start:ci_1:code_interpreter:true", "delta:ci_1", "delta:ci_1", "delta:ci_1", "end:ci_1"])
    let streamedInput = try decodeJSONBody(Data(inputDeltas.joined().utf8))
    #expect(streamedInput["containerId"]?.stringValue == "cntr_1")
    #expect(streamedInput["code"]?.stringValue == "print(\"hi\")\n")
    #expect(toolCall?.id == "ci_1")
    #expect(toolCall?.name == "code_interpreter")
    #expect(toolCall?.providerExecuted == true)
    let finalInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(finalInput["containerId"]?.stringValue == "cntr_1")
    #expect(finalInput["code"]?.stringValue == "print(\"hi\")\n")
    #expect(toolResult?.toolCallID == "ci_1")
    #expect(toolResult?.toolName == "code_interpreter")
    #expect(toolResult?.result["outputs"]?[0]?["logs"]?.stringValue == "hi\n")
}
@Test func openAIResponsesStreamsImageGenerationPartialResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"image_generation_call","id":"ig_1","status":"in_progress"}}

    data: {"type":"response.image_generation_call.partial_image","item_id":"ig_1","partial_image_index":0,"partial_image_b64":"partial-image"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"image_generation_call","id":"ig_1","status":"completed","result":"final-image"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-image-1")

    var sawInputLifecycle = false
    var toolCall: AIToolCall?
    var toolResults: [AIToolResult] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Generate an image.")])) {
        switch part {
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResults.append(result)
        default:
            break
        }
    }

    #expect(sawInputLifecycle == false)
    #expect(toolCall?.id == "ig_1")
    #expect(toolCall?.name == "image_generation")
    #expect(toolCall?.arguments == "{}")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResults.count == 2)
    #expect(toolResults[0].toolCallID == "ig_1")
    #expect(toolResults[0].toolName == "image_generation")
    #expect(toolResults[0].preliminary == true)
    #expect(toolResults[0].result["result"]?.stringValue == "partial-image")
    #expect(toolResults[1].preliminary == false)
    #expect(toolResults[1].result["result"]?.stringValue == "final-image")
}
@Test func openAIResponsesStreamsApplyPatchDiffLifecycleLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"apc_1","type":"apply_patch_call","status":"in_progress","call_id":"call_patch_1","operation":{"type":"create_file","path":"shopping.md","diff":""}}}

    data: {"type":"response.apply_patch_call_operation_diff.delta","output_index":0,"delta":"+## Shopping\\n"}

    data: {"type":"response.apply_patch_call_operation_diff.done","output_index":0,"diff":"+## Shopping\\n"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"apc_1","type":"apply_patch_call","status":"completed","call_id":"call_patch_1","operation":{"type":"create_file","path":"shopping.md","diff":"+## Shopping\\n"}}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var lifecycle: [String] = []
    var inputDeltas: [String] = []
    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Patch a file.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            inputDeltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        default:
            break
        }
    }

    #expect(lifecycle == ["start:call_patch_1:apply_patch:false", "delta:call_patch_1", "delta:call_patch_1", "delta:call_patch_1", "end:call_patch_1"])
    let streamedInput = try decodeJSONBody(Data(inputDeltas.joined().utf8))
    #expect(streamedInput["callId"]?.stringValue == "call_patch_1")
    #expect(streamedInput["operation"]?["type"]?.stringValue == "create_file")
    #expect(streamedInput["operation"]?["path"]?.stringValue == "shopping.md")
    #expect(streamedInput["operation"]?["diff"]?.stringValue == "+## Shopping\n")
    let finalInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(finalInput["callId"]?.stringValue == "call_patch_1")
    #expect(finalInput["operation"]?["diff"]?.stringValue == "+## Shopping\n")
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "apc_1")
}
@Test func openAIResponsesStreamsApplyPatchDeleteFileLifecycleLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"apc_delete_1","type":"apply_patch_call","status":"in_progress","call_id":"call_delete_1","operation":{"type":"delete_file","path":"obsolete.txt"}}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"apc_delete_1","type":"apply_patch_call","status":"completed","call_id":"call_delete_1","operation":{"type":"delete_file","path":"obsolete.txt"}}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var lifecycle: [String] = []
    var inputDeltas: [String] = []
    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Delete a file.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            inputDeltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        default:
            break
        }
    }

    #expect(lifecycle == ["start:call_delete_1:apply_patch:false", "delta:call_delete_1", "end:call_delete_1"])
    let streamedInput = try decodeJSONBody(Data(inputDeltas.joined().utf8))
    #expect(streamedInput["callId"]?.stringValue == "call_delete_1")
    #expect(streamedInput["operation"]?["type"]?.stringValue == "delete_file")
    #expect(streamedInput["operation"]?["path"]?.stringValue == "obsolete.txt")
    let finalInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(finalInput["operation"]?["type"]?.stringValue == "delete_file")
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "apc_delete_1")
}
@Test func openAIResponsesStreamsToolSearchOutputWithFinalCallIDLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"tool_search_call","id":"tsc_client_1","execution":"client","call_id":"call_provisional","status":"completed","arguments":{"goal":"Find the weather tool"}}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"tool_search_call","id":"tsc_client_1","execution":"client","call_id":"call_final","status":"completed","arguments":{"goal":"Find the weather tool"}}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"type":"tool_search_output","id":"tso_client_1","execution":"client","call_id":"call_final","status":"completed","tools":[{"type":"function","name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}}},"strict":true,"defer_loading":true}]}}

    data: {"type":"response.output_item.done","output_index":1,"item":{"type":"tool_search_output","id":"tso_client_1","execution":"client","call_id":"call_final","status":"completed","tools":[{"type":"function","name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}}},"strict":true,"defer_loading":true}]}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var lifecycle: [String] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Search for a tool.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(lifecycle == [
        "start:call_final:tool_search:false",
        "end:call_final"
    ])
    #expect(toolCall?.id == "call_final")
    #expect(toolCall?.name == "tool_search")
    #expect(toolCall?.providerExecuted == false)
    let toolSearchInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(toolSearchInput["arguments"]?["goal"]?.stringValue == "Find the weather tool")
    #expect(toolSearchInput["call_id"]?.stringValue == "call_final")
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_client_1")
    #expect(toolResult?.toolCallID == "call_final")
    #expect(toolResult?.toolName == "tool_search")
    #expect(toolResult?.result["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(toolResult?.providerMetadata["openai"]?["itemId"]?.stringValue == "tso_client_1")
    #expect(finishReason == "stop")
}
@Test func openAIResponsesStreamsMCPCallResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"mcp_call","id":"mcp_1","server_label":"docs","name":"search","arguments":"{\\"query\\":\\"swift\\"}","output":"found docs"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_call","id":"mcp_1","server_label":"docs","name":"search","arguments":"{\\"query\\":\\"swift\\"}","output":"found docs"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var sawInputLifecycle = false
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use MCP.")])) {
        switch part {
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        default:
            break
        }
    }

    #expect(sawInputLifecycle == false)
    #expect(toolCall?.id == "mcp_1")
    #expect(toolCall?.name == "mcp.search")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolCall?.dynamic == true)
    #expect(toolResult?.toolCallID == "mcp_1")
    #expect(toolResult?.toolName == "mcp.search")
    #expect(toolResult?.dynamic == true)
    #expect(toolResult?.result["serverLabel"]?.stringValue == "docs")
    #expect(toolResult?.result["output"]?.stringValue == "found docs")
    #expect(toolResult?.providerMetadata["openai"]?["itemId"]?.stringValue == "mcp_1")
}
@Test func openAIResponsesStreamsMCPApprovalRequests() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_approval_request","id":"mcpr_1","approval_request_id":"approval-1","name":"create_short_url","arguments":"{\\"url\\":\\"https://example.com\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var toolCall: AIToolCall?
    var approvalRequest: AIToolApprovalRequest?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Shorten this.")])) {
        switch part {
        case let .toolCall(call):
            toolCall = call
        case let .toolApprovalRequest(request):
            approvalRequest = request
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(toolCall?.id == "tool-call-approval-1")
    #expect(toolCall?.name == "mcp.create_short_url")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolCall?.dynamic == true)
    #expect(approvalRequest?.id == "approval-1")
    #expect(approvalRequest?.toolCallID == "tool-call-approval-1")
    #expect(finishReason == "stop")
}
@Test func openAIResponsesStreamsTextReasoningAndFinishUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.reasoning_summary_text.delta","delta":"think"}

    data: {"type":"response.output_text.delta","delta":"answer"}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var text: [String] = []
    var reasoning: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(finishReason == "stop")
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
}
@Test func openAIResponsesStreamsTextLifecycleProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_commentary","type":"message","status":"in_progress","content":[],"phase":"commentary","role":"assistant"}}

    data: {"type":"response.output_text.delta","item_id":"msg_commentary","output_index":0,"content_index":0,"delta":"checking"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_commentary","type":"message","status":"completed","content":[{"type":"output_text","text":"checking","annotations":[]}],"phase":"commentary","role":"assistant"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_final","type":"message","status":"in_progress","content":[],"phase":"final_answer","role":"assistant"}}

    data: {"type":"response.output_text.delta","item_id":"msg_final","output_index":1,"content_index":0,"delta":"answer"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_final","type":"message","status":"completed","content":[{"type":"output_text","text":"answer","annotations":[]}],"phase":"final_answer","role":"assistant"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.3-codex")

    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String, [String: JSONValue])] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var legacyText: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDelta(delta):
            legacyText.append(delta)
        case let .textDeltaPart(id, delta, metadata):
            textDeltas.append((id, delta, metadata))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        default:
            break
        }
    }

    #expect(legacyText == ["checking", "answer"])
    #expect(textStarts.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textDeltas.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textDeltas.map { $0.1 } == ["checking", "answer"])
    #expect(textEnds.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_commentary")
    #expect(textStarts[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textDeltas[0].2["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textEnds[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textStarts[1].1["openai"]?["itemId"]?.stringValue == "msg_final")
    #expect(textStarts[1].1["openai"]?["phase"]?.stringValue == "final_answer")
    #expect(textDeltas[1].2["openai"]?["phase"]?.stringValue == "final_answer")
    #expect(textEnds[1].1["openai"]?["phase"]?.stringValue == "final_answer")
}
