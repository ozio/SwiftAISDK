import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicJSONToolResponseParsesAsTextStopLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"tool_use","id":"toolu_json","name":"json","input":{"name":"Alice"}}],"stop_reason":"tool_use","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: [
            "type": "object",
            "properties": ["name": ["type": "string"]],
            "required": ["name"]
        ])
    ))

    #expect(try decodeJSONBody(Data(result.text.utf8))["name"]?.stringValue == "Alice")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.isEmpty)
}

@Test func anthropicStructuredOutputStreamsJSONToolAsTextLikeUpstream() async throws {
    let schema: JSONValue = [
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"],
        "additionalProperties": false
    ]
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_json","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":849,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":10,"service_tier":"standard"}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_json","name":"json","input":{}}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}}

    data: {"type":"ping"}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"elements\\": [{\\"location\\": \\"San Francisco\\", \\"temperature\\": 58, \\"condition\\": \\"sunny\\"}]"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"}"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":849,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":47}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    var textIDs: [String] = []
    var textDeltas: [String] = []
    var toolCalls: [AIToolCall] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: schema)
    )) {
        switch part {
        case let .textStart(id, _):
            textIDs.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textIDs.append("delta:\(id)")
            textDeltas.append(delta)
        case let .textEnd(id, _):
            textIDs.append("end:\(id)")
        case let .toolCall(call):
            toolCalls.append(call)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"]?.boolValue == true)
    #expect(body["tools"]?[0]?["name"]?.stringValue == "json")
    #expect(body["tools"]?[0]?["eager_input_streaming"]?.boolValue == true)
    #expect(body["tool_choice"]?["type"]?.stringValue == "any")
    #expect(textIDs == ["start:0", "delta:0", "delta:0", "end:0"])
    #expect(textDeltas.joined() == "{\"elements\": [{\"location\": \"San Francisco\", \"temperature\": 58, \"condition\": \"sunny\"}]}")
    #expect(finishReason == "stop")
    #expect(toolCalls.isEmpty)
}

@Test func anthropicStructuredOutputStreamSuppressesJSONToolTextPrefixLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_json","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":849,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":10,"service_tier":"standard"}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I'll invoke"}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" the JSON response tool."}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_json","name":"json","input":{}}}

    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}

    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"elements\\": [{\\"location\\": \\"San Francisco\\", \\"temperature\\": 58, \\"condition\\": \\"sunny\\"}]"}}

    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"}"}}

    data: {"type":"content_block_stop","index":1}

    data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":849,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":47}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    var textIDs: [String] = []
    var textDeltas: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: [
            "type": "object",
            "properties": ["name": ["type": "string"]],
            "required": ["name"]
        ])
    )) {
        switch part {
        case let .textStart(id, _):
            textIDs.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textIDs.append("delta:\(id)")
            textDeltas.append(delta)
        case let .textEnd(id, _):
            textIDs.append("end:\(id)")
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(textIDs == ["start:1", "delta:1", "delta:1", "end:1"])
    #expect(!textDeltas.joined().contains("I'll invoke"))
    #expect(textDeltas.joined() == "{\"elements\": [{\"location\": \"San Francisco\", \"temperature\": 58, \"condition\": \"sunny\"}]}")
    #expect(finishReason == "stop")
}

