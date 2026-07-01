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

@Test func openAIResponsesStreamsApplyPatchCreateFileFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-apply-patch-tool.1.chunks.txt"
    let events = try openAIResponsesChunksFixtureEvents(fixtureName)
    let firstResponse = try #require(events.first?["response"])
    let addedItem = try #require(events.first {
        $0["type"]?.stringValue == "response.output_item.added" &&
        $0["item"]?["type"]?.stringValue == "apply_patch_call"
    }?["item"])
    let doneItem = try #require(events.first {
        $0["type"]?.stringValue == "response.output_item.done" &&
        $0["item"]?["type"]?.stringValue == "apply_patch_call"
    }?["item"])
    let expectedDiffDeltas = events.compactMap { event -> String? in
        guard event["type"]?.stringValue == "response.apply_patch_call_operation_diff.delta" else {
            return nil
        }
        return event["delta"]?.stringValue
    }
    let finalResponse = try #require(events.last?["response"])

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1-2025-11-13")

    var responseMetadata: AIResponseMetadata?
    var lifecycle: [String] = []
    var inputDeltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Create a shopping checklist.")],
        tools: ["apply_patch": OpenAITools.applyPatch()]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            inputDeltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            finishUsage = usage
        case let .finishMetadata(reason, usage, metadata):
            finishReason = reason
            finishUsage = usage
            finishMetadata = metadata
        default:
            break
        }
    }

    let callID = try #require(addedItem["call_id"]?.stringValue)
    #expect(responseMetadata?.id == firstResponse["id"]?.stringValue)
    #expect(responseMetadata?.modelID == firstResponse["model"]?.stringValue)
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_764_180_467))
    #expect(lifecycle.first == "start:\(callID):apply_patch:false")
    #expect(lifecycle.last == "end:\(callID)")
    #expect(lifecycle.filter { $0 == "delta:\(callID)" }.count == expectedDiffDeltas.count + 2)
    #expect(Array(inputDeltas.dropFirst().dropLast()) == expectedDiffDeltas.map(openAIResponsesEscapeJSONStringFragment))

    let streamedInput = try decodeJSONBody(Data(inputDeltas.joined().utf8))
    #expect(streamedInput["callId"]?.stringValue == callID)
    #expect(streamedInput["operation"]?["type"]?.stringValue == "create_file")
    #expect(streamedInput["operation"]?["path"]?.stringValue == addedItem["operation"]?["path"]?.stringValue)
    #expect(streamedInput["operation"]?["diff"]?.stringValue == doneItem["operation"]?["diff"]?.stringValue)

    let finalInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(toolCall?.id == callID)
    #expect(toolCall?.name == "apply_patch")
    #expect(toolCall?.providerExecuted == false)
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == addedItem["id"]?.stringValue)
    #expect(finalInput == streamedInput)
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == finalResponse["id"]?.stringValue)
    #expect(finishMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 642)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 642)
    #expect(finishUsage?.outputTokens == 67)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 67)
    #expect(finishUsage?.totalTokens == 709)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.1-2025-11-13")
    #expect(body["tools"]?.arrayValue?.first?["type"]?.stringValue == "apply_patch")
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsApplyPatchDeleteFileFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-apply-patch-tool-delete.1.chunks.txt"
    let events = try openAIResponsesChunksFixtureEvents(fixtureName)
    let firstResponse = try #require(events.first?["response"])
    let addedItem = try #require(events.first {
        $0["type"]?.stringValue == "response.output_item.added" &&
        $0["item"]?["type"]?.stringValue == "apply_patch_call"
    }?["item"])
    let finalResponse = try #require(events.last?["response"])

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1-2025-11-13")

    var responseMetadata: AIResponseMetadata?
    var lifecycle: [String] = []
    var inputDeltas: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Delete obsolete.txt.")],
        tools: ["apply_patch": OpenAITools.applyPatch()]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            lifecycle.append("delta:\(id)")
            inputDeltas.append(delta)
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            finishUsage = usage
        case let .finishMetadata(reason, usage, metadata):
            finishReason = reason
            finishUsage = usage
            finishMetadata = metadata
        default:
            break
        }
    }

    let callID = try #require(addedItem["call_id"]?.stringValue)
    #expect(responseMetadata?.id == firstResponse["id"]?.stringValue)
    #expect(responseMetadata?.modelID == firstResponse["model"]?.stringValue)
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_764_180_467))
    #expect(lifecycle == ["start:\(callID):apply_patch:false", "delta:\(callID)", "end:\(callID)"])

    let streamedInput = try decodeJSONBody(Data(inputDeltas.joined().utf8))
    #expect(streamedInput["callId"]?.stringValue == callID)
    #expect(streamedInput["operation"]?["type"]?.stringValue == "delete_file")
    #expect(streamedInput["operation"]?["path"]?.stringValue == addedItem["operation"]?["path"]?.stringValue)

    let finalInput = try decodeJSONBody(Data(try #require(toolCall?.arguments).utf8))
    #expect(toolCall?.id == callID)
    #expect(toolCall?.name == "apply_patch")
    #expect(toolCall?.providerExecuted == false)
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == addedItem["id"]?.stringValue)
    #expect(finalInput == streamedInput)
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == finalResponse["id"]?.stringValue)
    #expect(finishMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 24)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 24)
    #expect(finishUsage?.outputTokens == 0)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 0)
    #expect(finishUsage?.totalTokens == 24)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.1-2025-11-13")
    #expect(body["tools"]?.arrayValue?.first?["type"]?.stringValue == "apply_patch")
    #expect(body["stream"]?.boolValue == true)
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
    #expect(finishReason == "tool-calls")
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

    #expect(toolCall?.id == "id-0")
    #expect(toolCall?.name == "mcp.create_short_url")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolCall?.dynamic == true)
    #expect(approvalRequest?.id == "approval-1")
    #expect(approvalRequest?.toolCallID == "id-0")
    #expect(finishReason == "stop")
}
