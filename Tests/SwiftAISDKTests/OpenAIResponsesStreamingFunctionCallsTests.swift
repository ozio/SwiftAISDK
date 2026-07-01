import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesSendsStreamingToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67cb13a755c08190acbe3839a49632fc","object":"response","created_at":1741362087,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"function","description":"Get the current location.","name":"currentLocation","parameters":{"type":"object","properties":{},"additionalProperties":false},"strict":true},{"type":"function","description":"Get the weather in a location","name":"weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The location to get the weather for"}},"required":["location"],"additionalProperties":false},"strict":true}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"resp_67cb13a755c08190acbe3839a49632fc","object":"response","created_at":1741362087,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"function","description":"Get the current location.","name":"currentLocation","parameters":{"type":"object","properties":{},"additionalProperties":false},"strict":true},{"type":"function","description":"Get the weather in a location","name":"weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The location to get the weather for"}},"required":["location"],"additionalProperties":false},"strict":true}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_67cb13a838088190be08eb3927c87501","call_id":"call_6KxSghkb4MVnunFH2TxPErLP","name":"currentLocation","arguments":"","status":"completed"}}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a838088190be08eb3927c87501","output_index":0,"delta":"{}"}

    data: {"type":"response.function_call_arguments.done","item_id":"fc_67cb13a838088190be08eb3927c87501","output_index":0,"arguments":"{}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_67cb13a838088190be08eb3927c87501","call_id":"call_pgjcAI4ZegMkP6bsAV7sfrJA","name":"currentLocation","arguments":"{}","status":"completed"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","id":"fc_67cb13a858f081908a600343fa040f47","call_id":"call_Dg6WUmFHNeR5JxX1s53s1G4b","name":"weather","arguments":"","status":"in_progress"}}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"delta":"{"}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"delta":"\\"location"}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"delta":"\\":"}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"delta":"\\"Rome"}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"delta":"\\"}"}

    data: {"type":"response.function_call_arguments.done","item_id":"fc_67cb13a858f081908a600343fa040f47","output_index":1,"arguments":"{\\"location\\":\\"Rome\\"}"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"fc_67cb13a858f081908a600343fa040f47","call_id":"call_X2PAkDJInno9VVnNkDrfhboW","name":"weather","arguments":"{\\"location\\":\\"Rome\\"}","status":"completed"}}

    data: {"type":"response.completed","response":{"id":"resp_67cb13a755c08190acbe3839a49632fc","object":"response","created_at":1741362087,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"type":"function_call","id":"fc_67cb13a838088190be08eb3927c87501","call_id":"call_KsVqaVAf3alAtCCkQe4itE7W","name":"currentLocation","arguments":"{}","status":"completed"},{"type":"function_call","id":"fc_67cb13a858f081908a600343fa040f47","call_id":"call_X2PAkDJInno9VVnNkDrfhboW","name":"weather","arguments":"{\\"location\\":\\"Rome\\"}","status":"completed"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"function","description":"Get the current location.","name":"currentLocation","parameters":{"type":"object","properties":{},"additionalProperties":false},"strict":true},{"type":"function","description":"Get the weather in a location","name":"weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The location to get the weather for"}},"required":["location"],"additionalProperties":false},"strict":true}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":0,"input_tokens_details":{"cached_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var inputStarts: [(String, String)] = []
    var inputDeltas: [(String, String)] = []
    var inputEnds: [String] = []
    var toolCalls: [AIToolCall] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolInputStart(id, name, _, _, _, _):
            inputStarts.append((id, name))
        case let .toolInputDelta(id, delta, _):
            inputDeltas.append((id, delta))
        case let .toolInputEnd(id, _):
            inputEnds.append(id)
        case let .toolCall(call):
            toolCalls.append(call)
        case let .finishMetadata(reason, usage, providerMetadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = providerMetadata
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_67cb13a755c08190acbe3839a49632fc")
    #expect(responseMetadata?.modelID == "gpt-4o-2024-07-18")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_362_087))
    #expect(inputStarts.map { $0.0 } == [
        "call_6KxSghkb4MVnunFH2TxPErLP",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b"
    ])
    #expect(inputStarts.map { $0.1 } == ["currentLocation", "weather"])
    #expect(inputDeltas.map { $0.0 } == [
        "call_6KxSghkb4MVnunFH2TxPErLP",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b",
        "call_Dg6WUmFHNeR5JxX1s53s1G4b"
    ])
    #expect(inputDeltas.map { $0.1 } == ["{}", "{", "\"location", "\":", "\"Rome", "\"}"])
    #expect(inputEnds == [
        "call_pgjcAI4ZegMkP6bsAV7sfrJA",
        "call_X2PAkDJInno9VVnNkDrfhboW"
    ])
    #expect(toolCalls.count == 2)
    #expect(toolCalls[0].id == "call_pgjcAI4ZegMkP6bsAV7sfrJA")
    #expect(toolCalls[0].name == "currentLocation")
    #expect(toolCalls[0].arguments == "{}")
    #expect(toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "fc_67cb13a838088190be08eb3927c87501")
    #expect(toolCalls[1].id == "call_X2PAkDJInno9VVnNkDrfhboW")
    #expect(toolCalls[1].name == "weather")
    #expect(toolCalls[1].arguments == #"{"location":"Rome"}"#)
    #expect(toolCalls[1].providerMetadata["openai"]?["itemId"]?.stringValue == "fc_67cb13a858f081908a600343fa040f47")
    #expect(finishReason == "tool-calls")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_67cb13a755c08190acbe3839a49632fc")
    #expect(finishUsage?.inputTokens == 0)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 0)
    #expect(finishUsage?.outputTokens == 0)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 0)
    #expect(finishUsage?.totalTokens == 0)
}

@Test func openAIResponsesPreservesNamespaceOnStreamingFunctionCallOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_ns","object":"response","created_at":1741362087,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.4","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_ns_1","call_id":"call_ns_1","name":"get_weather","arguments":"","status":"in_progress"}}

    data: {"type":"response.function_call_arguments.delta","item_id":"fc_ns_1","output_index":0,"delta":"{\\"location\\":\\"NYC\\"}"}

    data: {"type":"response.function_call_arguments.done","item_id":"fc_ns_1","output_index":0,"arguments":"{\\"location\\":\\"NYC\\"}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_ns_1","call_id":"call_ns_1","name":"get_weather","arguments":"{\\"location\\":\\"NYC\\"}","status":"completed","namespace":"weather_ns"}}

    data: {"type":"response.completed","response":{"id":"resp_ns","object":"response","created_at":1741362087,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.4","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":0,"input_tokens_details":{"cached_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var toolInputEndMetadata: [String: JSONValue] = [:]
    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    )) {
        switch part {
        case let .toolInputEnd(_, metadata):
            toolInputEndMetadata = metadata
        case let .toolCall(call):
            toolCall = call
        default:
            break
        }
    }

    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "fc_ns_1")
    #expect(toolCall?.providerMetadata["openai"]?["namespace"]?.stringValue == "weather_ns")
    #expect(toolInputEndMetadata["openai"]?["namespace"]?.stringValue == "weather_ns")
}

@Test func openAIResponsesDoesNotSetNamespaceOnStreamingFunctionCallWhenAbsentLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_plain","object":"response","created_at":1741362087,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_plain","call_id":"call_plain","name":"get_weather","arguments":"","status":"in_progress"}}

    data: {"type":"response.function_call_arguments.done","item_id":"fc_plain","output_index":0,"arguments":"{}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_plain","call_id":"call_plain","name":"get_weather","arguments":"{}","status":"completed"}}

    data: {"type":"response.completed","response":{"id":"resp_plain","object":"response","created_at":1741362087,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":0,"input_tokens_details":{"cached_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    )) {
        if case let .toolCall(call) = part {
            toolCall = call
        }
    }

    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == "fc_plain")
    #expect(toolCall?.providerMetadata["openai"]?["namespace"] == nil)
}

@Test func openAIResponsesStreamingHandlesServiceTierLikeUpstream() async throws {
    let responseID = "resp_68b08bfa71908196889e9ae5668b2ae40cd677a623b867d5"
    let reasoningID = "rs_68b08bfb9f3c819682c5cff6edee6e4d0cd677a623b867d5"
    let messageID = "msg_68b08bfc9a548196b15465b6020b04e40cd677a623b867d5"
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.created","sequence_number":0,"response":{"id":"\(responseID)","object":"response","created_at":1756400634,"status":"in_progress","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-nano-2025-08-07","output":[],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"flex","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.in_progress","sequence_number":1,"response":{"id":"\(responseID)","object":"response","created_at":1756400634,"status":"in_progress","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-nano-2025-08-07","output":[],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"flex","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"id":"\(reasoningID)","type":"reasoning","summary":[]}}

    data:{"type":"response.output_item.done","sequence_number":3,"output_index":0,"item":{"id":"\(reasoningID)","type":"reasoning","summary":[]}}

    data:{"type":"response.output_item.added","sequence_number":4,"output_index":1,"item":{"id":"\(messageID)","type":"message","status":"in_progress","content":[],"role":"assistant"}}

    data:{"type":"response.content_part.added","sequence_number":5,"item_id":"\(messageID)","output_index":1,"content_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""}}

    data:{"type":"response.output_text.delta","sequence_number":6,"item_id":"\(messageID)","output_index":1,"content_index":0,"delta":"blue","logprobs":[],"obfuscation":"A3q16QVxivdK"}

    data:{"type":"response.output_text.done","sequence_number":7,"item_id":"\(messageID)","output_index":1,"content_index":0,"text":"blue","logprobs":[]}

    data:{"type":"response.content_part.done","sequence_number":8,"item_id":"\(messageID)","output_index":1,"content_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"blue"}}

    data:{"type":"response.output_item.done","sequence_number":9,"output_index":1,"item":{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"blue"}],"role":"assistant"}}

    data:{"type":"response.completed","sequence_number":10,"response":{"id":"\(responseID)","object":"response","created_at":1756400634,"status":"completed","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-nano-2025-08-07","output":[{"id":"\(reasoningID)","type":"reasoning","summary":[]},{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"blue"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"flex","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":15,"input_tokens_details":{"cached_tokens":0},"output_tokens":263,"output_tokens_details":{"reasoning_tokens":256},"total_tokens":278},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        extraBody: ["serviceTier": "flex"]
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .finishMetadata(reason, usage, providerMetadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = providerMetadata
        default:
            break
        }
    }

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["service_tier"]?.stringValue == "flex")

    #expect(streamStarted)
    #expect(responseMetadata?.id == responseID)
    #expect(responseMetadata?.modelID == "gpt-5-nano-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_756_400_634))

    #expect(reasoningStarts.map { $0.0 } == ["\(reasoningID):0"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == reasoningID)
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(reasoningEnds.map { $0.0 } == ["\(reasoningID):0"])
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == reasoningID)
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == .null)

    #expect(textStarts.map { $0.0 } == [messageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == messageID)
    #expect(textDeltas.map { $0.0 } == [messageID])
    #expect(textDeltas.map { $0.1 } == ["blue"])
    #expect(textEnds.map { $0.0 } == [messageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == messageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == responseID)
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "flex")
    #expect(finishUsage?.inputTokens == 15)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 15)
    #expect(finishUsage?.outputTokens == 263)
    #expect(finishUsage?.outputReasoningTokens == 256)
    #expect(finishUsage?.outputTextTokens == 7)
    #expect(finishUsage?.totalTokens == 278)
}

@Test func openAIResponsesStreamingHandlesLogprobsLikeUpstream() async throws {
    let responseID = "resp_689cec4cf608819583c56813ccb0f5040f92af1765dd5aad"
    let messageID = "msg_689cec4d46448195905a27fb9e12ff670f92af1765dd5aad"
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.created","sequence_number":0,"response":{"id":"\(responseID)","object":"response","created_at":1755114572,"status":"in_progress","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":1024,"max_tool_calls":null,"model":"gpt-4.1-nano-2025-04-14","output":[],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":5,"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.in_progress","sequence_number":1,"response":{"id":"\(responseID)","object":"response","created_at":1755114572,"status":"in_progress","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":1024,"max_tool_calls":null,"model":"gpt-4.1-nano-2025-04-14","output":[],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":5,"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"id":"\(messageID)","type":"message","status":"in_progress","content":[],"role":"assistant"}}

    data:{"type":"response.content_part.added","sequence_number":3,"item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""}}

    data:{"type":"response.output_text.delta","sequence_number":4,"item_id":"\(messageID)","output_index":0,"content_index":0,"delta":"N","logprobs":[{"bytes":[78],"logprob":-2.9266366958618164,"token":"N","top_logprobs":[{"bytes":[80,108,101,97,115,101],"logprob":-0.5516367554664612,"token":"Please"},{"bytes":[89],"logprob":-1.0516366958618164,"token":"Y"},{"bytes":[78],"logprob":-2.9266366958618164,"token":"N"},{"bytes":[83,117,114,101],"logprob":-4.551636695861816,"token":"Sure"},{"bytes":[67,111,117,108,100],"logprob":-5.176636695861816,"token":"Could"}]}],"obfuscation":"t9egcKewVOXiQ6N"}

    data:{"type":"response.output_text.done","sequence_number":5,"item_id":"\(messageID)","output_index":0,"content_index":0,"text":"N","logprobs":[{"bytes":[78],"logprob":-2.9266366958618164,"token":"N","top_logprobs":[{"bytes":[80,108,101,97,115,101],"logprob":-0.5516367554664612,"token":"Please"},{"bytes":[89],"logprob":-1.0516366958618164,"token":"Y"},{"bytes":[78],"logprob":-2.9266366958618164,"token":"N"},{"bytes":[83,117,114,101],"logprob":-4.551636695861816,"token":"Sure"},{"bytes":[67,111,117,108,100],"logprob":-5.176636695861816,"token":"Could"}]}]}

    data:{"type":"response.content_part.done","sequence_number":6,"item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"N"}}

    data:{"type":"response.output_item.done","sequence_number":7,"output_index":0,"item":{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[{"bytes":[78],"logprob":-2.926637,"token":"N","top_logprobs":[{"bytes":[80,108,101,97,115,101],"logprob":-0.551637,"token":"Please"},{"bytes":[89],"logprob":-1.051637,"token":"Y"},{"bytes":[78],"logprob":-2.926637,"token":"N"},{"bytes":[83,117,114,101],"logprob":-4.551637,"token":"Sure"},{"bytes":[67,111,117,108,100],"logprob":-5.176637,"token":"Could"}]}],"text":"N"}],"role":"assistant"}}

    data:{"type":"response.completed","sequence_number":8,"response":{"id":"\(responseID)","object":"response","created_at":1755114572,"status":"completed","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":1024,"max_tool_calls":null,"model":"gpt-4.1-nano-2025-04-14","output":[{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[{"bytes":[78],"logprob":-2.926637,"token":"N","top_logprobs":[{"bytes":[80,108,101,97,115,101],"logprob":-0.551637,"token":"Please"},{"bytes":[89],"logprob":-1.051637,"token":"Y"},{"bytes":[78],"logprob":-2.926637,"token":"N"},{"bytes":[83,117,114,101],"logprob":-4.551637,"token":"Sure"},{"bytes":[67,111,117,108,100],"logprob":-5.176637,"token":"Could"}]}],"text":"N"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":5,"top_p":1,"truncation":"disabled","usage":{"input_tokens":12,"input_tokens_details":{"cached_tokens":0},"output_tokens":2,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":14},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["logprobs": 1]]
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .finishMetadata(reason, usage, providerMetadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = providerMetadata
        default:
            break
        }
    }

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["top_logprobs"]?.intValue == 1)
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["message.output_text.logprobs"])

    #expect(streamStarted)
    #expect(responseMetadata?.id == responseID)
    #expect(responseMetadata?.modelID == "gpt-4.1-nano-2025-04-14")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_755_114_572))
    #expect(textStarts.map { $0.0 } == [messageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == messageID)
    #expect(textDeltas.map { $0.0 } == [messageID])
    #expect(textDeltas.map { $0.1 } == ["N"])
    #expect(textEnds.map { $0.0 } == [messageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == messageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == responseID)
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    let logprobs = try #require(finishProviderMetadata["openai"]?["logprobs"]?.arrayValue)
    #expect(logprobs.count == 1)
    #expect(logprobs[0][0]?["token"]?.stringValue == "N")
    #expect(logprobs[0][0]?["logprob"]?.doubleValue == -2.9266366958618164)
    #expect(logprobs[0][0]?["top_logprobs"]?[0]?["token"]?.stringValue == "Please")
    #expect(logprobs[0][0]?["top_logprobs"]?[0]?["logprob"]?.doubleValue == -0.5516367554664612)
    #expect(logprobs[0][0]?["top_logprobs"]?[4]?["token"]?.stringValue == "Could")
    #expect(logprobs[0][0]?["top_logprobs"]?[4]?["logprob"]?.doubleValue == -5.176636695861816)
    #expect(finishUsage?.inputTokens == 12)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 12)
    #expect(finishUsage?.outputTokens == 2)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 2)
    #expect(finishUsage?.totalTokens == 14)
}

@Test func openAIResponsesStreamsCustomToolCallLikeUpstream() async throws {
    let responseID = "resp_custom_tool_test_001"
    let itemID = "ct_abc123def456"
    let callID = "call_custom_sql_001"
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"\(responseID)","object":"response","created_at":1741257730,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.2-codex","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"required","tools":[{"type":"custom","name":"write_sql","description":"Write a SQL SELECT query to answer the user question.","format":{"type":"grammar","syntax":"regex","definition":"SELECT .+"}}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"\(responseID)","object":"response","created_at":1741257730,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.2-codex","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"required","tools":[{"type":"custom","name":"write_sql","description":"Write a SQL SELECT query to answer the user question.","format":{"type":"grammar","syntax":"regex","definition":"SELECT .+"}}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"custom_tool_call","id":"\(itemID)","call_id":"\(callID)","name":"write_sql","input":""}}

    data: {"type":"response.custom_tool_call_input.delta","item_id":"\(itemID)","output_index":0,"delta":"SELECT * "}

    data: {"type":"response.custom_tool_call_input.delta","item_id":"\(itemID)","output_index":0,"delta":"FROM users "}

    data: {"type":"response.custom_tool_call_input.delta","item_id":"\(itemID)","output_index":0,"delta":"WHERE age > 25"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"custom_tool_call","id":"\(itemID)","call_id":"\(callID)","name":"write_sql","input":"SELECT * FROM users WHERE age > 25","status":"completed"}}

    data: {"type":"response.completed","response":{"id":"\(responseID)","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.2-codex","output":[{"type":"custom_tool_call","id":"\(itemID)","call_id":"\(callID)","name":"write_sql","input":"SELECT * FROM users WHERE age > 25","status":"completed"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"required","tools":[{"type":"custom","name":"write_sql","description":"Write a SQL SELECT query to answer the user question.","format":{"type":"grammar","syntax":"regex","definition":"SELECT .+"}}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":20,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":70},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2-codex")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var inputStarts: [(String, String, [String: JSONValue])] = []
    var inputDeltas: [(String, String)] = []
    var inputEnds: [(String, [String: JSONValue])] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "write_sql": OpenAITools.customTool(
                name: "write_sql",
                description: "Write a SQL SELECT query to answer the user question.",
                format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
            )
        ]
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolInputStart(id, name, _, _, _, providerMetadata):
            inputStarts.append((id, name, providerMetadata))
        case let .toolInputDelta(id, delta, _):
            inputDeltas.append((id, delta))
        case let .toolInputEnd(id, providerMetadata):
            inputEnds.append((id, providerMetadata))
        case let .toolCall(call):
            toolCall = call
        case let .finishMetadata(reason, usage, providerMetadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = providerMetadata
        default:
            break
        }
    }

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"]?[0]?["type"]?.stringValue == "custom")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "write_sql")
    #expect(body["tools"]?[0]?["format"]?["definition"]?.stringValue == "SELECT .+")

    #expect(streamStarted)
    #expect(responseMetadata?.id == responseID)
    #expect(responseMetadata?.modelID == "gpt-5.2-codex")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_257_730))
    #expect(inputStarts.map { $0.0 } == [callID])
    #expect(inputStarts.map { $0.1 } == ["write_sql"])
    #expect(inputStarts[0].2.isEmpty)
    #expect(inputDeltas.map { $0.0 } == [callID, callID, callID])
    #expect(inputDeltas.map { $0.1 } == ["SELECT * ", "FROM users ", "WHERE age > 25"])
    #expect(inputEnds.map { $0.0 } == [callID])
    #expect(inputEnds[0].1.isEmpty)
    #expect(toolCall?.id == callID)
    #expect(toolCall?.name == "write_sql")
    #expect(toolCall?.arguments == "\"SELECT * FROM users WHERE age > 25\"")
    #expect(toolCall?.providerMetadata["openai"]?["itemId"]?.stringValue == itemID)
    #expect(finishReason == "tool-calls")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == responseID)
    #expect(finishUsage?.inputTokens == 50)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 50)
    #expect(finishUsage?.outputTokens == 20)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 20)
    #expect(finishUsage?.totalTokens == 70)
}
@Test func openAIResponsesStreamsPrototypeNamedFunctionItemsSafely() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"__proto__","call_id":"call_proto","name":"lookup","arguments":""}}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"__proto__","delta":"{\\"query\\":"}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"__proto__","delta":"\\"weather\\"}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"__proto__","call_id":"call_proto","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(headers: ["Authorization": "Bearer custom-key"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        if case let .toolCall(call) = part {
            toolCall = call
        }
    }

    #expect(toolCall?.id == "call_proto")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(toolCall?.providerMetadata["open-responses"]?["itemId"]?.stringValue == "__proto__")
}
