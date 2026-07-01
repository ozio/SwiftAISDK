import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsReasoningDeltaPartsFromEncryptedFixtureLikeUpstream() async throws {
    let fixtureName = "openai-reasoning-encrypted-content.1.chunks.txt"
    let events = try openAIResponsesChunksFixtureEvents(fixtureName)
    let firstResponse = try #require(events.first?["response"])
    let reasoningAddedItem = try #require(events.first {
        $0["type"]?.stringValue == "response.output_item.added" &&
        $0["item"]?["type"]?.stringValue == "reasoning"
    }?["item"])
    let reasoningDoneItem = try #require(events.first {
        $0["type"]?.stringValue == "response.output_item.done" &&
        $0["item"]?["type"]?.stringValue == "reasoning"
    }?["item"])
    let expectedReasoningDeltas = events.compactMap { event -> String? in
        guard event["type"]?.stringValue == "response.reasoning_summary_text.delta" else { return nil }
        return event["delta"]?.stringValue
    }
    let expectedToolItems = events.compactMap { event -> JSONValue? in
        guard event["type"]?.stringValue == "response.output_item.done",
              event["item"]?["type"]?.stringValue == "function_call" else {
            return nil
        }
        return event["item"]
    }
    let expectedTextDeltas = events.compactMap { event -> String? in
        guard event["type"]?.stringValue == "response.output_text.delta" else { return nil }
        return event["delta"]?.stringValue
    }
    let expectedFinalResponseID = try #require(events.last?["response"]?["id"]?.stringValue)

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1-codex-max")

    var responseMetadata: [AIResponseMetadata] = []
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolCalls: [AIToolCall] = []
    var textDeltas: [String] = []
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesCalculatorTool(),
        providerOptions: [
            "openai": [
                "reasoningEffort": "high",
                "maxCompletionTokens": 32_000,
                "store": false,
                "include": ["reasoning.encrypted_content"],
                "reasoningSummary": "auto",
                "forceReasoning": true
            ]
        ]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata.append(metadata)
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .toolCall(toolCall):
            toolCalls.append(toolCall)
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
        case let .finishMetadata(_, _, metadata):
            finishMetadata = metadata
        default:
            break
        }
    }

    #expect(responseMetadata.first?.id == firstResponse["id"]?.stringValue)
    #expect(responseMetadata.first?.modelID == firstResponse["model"]?.stringValue)
    #expect(responseMetadata.first?.timestamp == Date(timeIntervalSince1970: 1_765_552_659))
    #expect(reasoningStarts.map { $0.0 } == ["\(try #require(reasoningAddedItem["id"]?.stringValue)):0"])
    #expect(reasoningStarts.first?.1["openai"]?["itemId"]?.stringValue == reasoningAddedItem["id"]?.stringValue)
    #expect(reasoningStarts.first?.1["openai"]?["reasoningEncryptedContent"]?.stringValue == reasoningAddedItem["encrypted_content"]?.stringValue)
    #expect(reasoningDeltas.map { $0.1 } == expectedReasoningDeltas)
    #expect(reasoningDeltas.count > 10)
    #expect(Set(reasoningDeltas.map { $0.0 }) == ["\(try #require(reasoningAddedItem["id"]?.stringValue)):0"])
    #expect(reasoningDeltas.allSatisfy {
        $0.2["openai"]?["itemId"]?.stringValue == reasoningAddedItem["id"]?.stringValue
    })
    #expect(reasoningEnds.map { $0.0 } == ["\(try #require(reasoningAddedItem["id"]?.stringValue)):0"])
    #expect(reasoningEnds.first?.1["openai"]?["reasoningEncryptedContent"]?.stringValue == reasoningDoneItem["encrypted_content"]?.stringValue)
    #expect(toolCalls.map(\.id) == expectedToolItems.compactMap { $0["call_id"]?.stringValue })
    #expect(toolCalls.map(\.name) == expectedToolItems.compactMap { $0["name"]?.stringValue })
    #expect(toolCalls.map(\.arguments) == expectedToolItems.compactMap { $0["arguments"]?.stringValue })
    #expect(textDeltas == expectedTextDeltas)
    #expect(textDeltas.joined() == "The final result is **570**.")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == expectedFinalResponseID)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.1-codex-max")
    #expect(body["reasoning"]?["effort"]?.stringValue == "high")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])
    #expect(body["store"]?.boolValue == false)
    #expect(body["max_output_tokens"]?.intValue == 32_000)
    #expect(body["forceReasoning"] == nil)
    #expect(body["stream"]?.boolValue == true)
    #expect(body["tools"]?.arrayValue?.first?["name"]?.stringValue == "calculator")
}

@Test func openAIResponsesStreamsReasoningWithSummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":"**Exploring burrito origins**\\n\\nThe user is"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":" curious about the debate regarding Taqueria La Cumbre and El Farolito."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":"**Investigating burrito origins**\\n\\nThere's a fascinating debate"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":" about who created the Mission burrito."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":"answer"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":" text"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[{"type":"summary_text","text":"**Exploring burrito origins**\\n\\nThe user is curious about the debate regarding Taqueria La Cumbre and El Farolito."},{"type":"summary_text","text":"**Investigating burrito origins**\\n\\nThere's a fascinating debate about who created the Mission burrito."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "low", "reasoningSummary": "auto"]]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
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

    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "o3-mini-2025-01-31")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(reasoningStarts.map { $0.0 } == [
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1"
    ])
    #expect(reasoningDeltas.map { $0.0 } == [
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1"
    ])
    #expect(reasoningDeltas.map { $0.1 } == [
        "**Exploring burrito origins**\n\nThe user is",
        " curious about the debate regarding Taqueria La Cumbre and El Farolito.",
        "**Investigating burrito origins**\n\nThere's a fascinating debate",
        " about who created the Mission burrito."
    ])
    #expect(reasoningEnds.map { $0.0 } == [
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1"
    ])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(reasoningDeltas[0].2["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(textStarts.map { $0.0 } == ["msg_67c97c02656c81908e080dfdf4a03cd1"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")
    #expect(textDeltas.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_67c97c02656c81908e080dfdf4a03cd1"
    ])
    #expect(textDeltas.map { $0.1 } == ["answer", " text"])
    #expect(textEnds.map { $0.0 } == ["msg_67c97c02656c81908e080dfdf4a03cd1"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 34)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 34)
    #expect(finishUsage?.outputTokens == 538)
    #expect(finishUsage?.outputReasoningTokens == 320)
    #expect(finishUsage?.outputTextTokens == 218)
    #expect(finishUsage?.totalTokens == 572)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "o3-mini")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsReasoningWithEmptySummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":"answer"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":" text"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "low", "reasoningSummary": .null]]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case .reasoningDeltaPart:
            Issue.record("Empty upstream reasoning summary should not emit reasoning deltas.")
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
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

    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "o3-mini-2025-01-31")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(reasoningStarts.map { $0.0 } == ["rs_6808709f6fcc8191ad2e2fdd784017b3:0"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(reasoningEnds.map { $0.0 } == ["rs_6808709f6fcc8191ad2e2fdd784017b3:0"])
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(textDeltas.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_67c97c02656c81908e080dfdf4a03cd1"
    ])
    #expect(textDeltas.map { $0.1 } == ["answer", " text"])
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 34)
    #expect(finishUsage?.outputTokens == 538)
    #expect(finishUsage?.outputReasoningTokens == 320)
    #expect(finishUsage?.outputTextTokens == 218)
    #expect(finishUsage?.totalTokens == 572)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "o3-mini")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"] == nil)
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsEncryptedReasoningWithEmptySummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_abc123"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final_def456"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":"answer"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":" text"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final_def456","summary":[]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "reasoningEffort": "low",
                "reasoningSummary": .null,
                "include": ["reasoning.encrypted_content"]
            ]
        ]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case .reasoningDeltaPart:
            Issue.record("Empty upstream reasoning summary should not emit reasoning deltas.")
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
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

    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "o3-mini-2025-01-31")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(reasoningStarts.map { $0.0 } == ["rs_6808709f6fcc8191ad2e2fdd784017b3:0"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_abc123")
    #expect(reasoningEnds.map { $0.0 } == ["rs_6808709f6fcc8191ad2e2fdd784017b3:0"])
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_final_def456")
    #expect(textDeltas.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_67c97c02656c81908e080dfdf4a03cd1"
    ])
    #expect(textDeltas.map { $0.1 } == ["answer", " text"])
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 34)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 34)
    #expect(finishUsage?.outputTokens == 538)
    #expect(finishUsage?.outputReasoningTokens == 320)
    #expect(finishUsage?.outputTextTokens == 218)
    #expect(finishUsage?.totalTokens == 572)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "o3-mini")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"] == nil)
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsEncryptedReasoningWithSummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_abc123"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":"**Exploring burrito origins**\\n\\nThe user is"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":" curious about the debate regarding Taqueria La Cumbre and El Farolito."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":"**Investigating burrito origins**\\n\\nThere's a fascinating debate"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":" about who created the Mission burrito."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final_def456"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":"answer"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":" text"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final_def456","summary":[{"type":"summary_text","text":"**Exploring burrito origins**\\n\\nThe user is curious about the debate regarding Taqueria La Cumbre and El Farolito."},{"type":"summary_text","text":"**Investigating burrito origins**\\n\\nThere's a fascinating debate about who created the Mission burrito."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String)] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var finishReason: String?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "reasoningEffort": "low",
                "reasoningSummary": "auto",
                "include": ["reasoning.encrypted_content"]
            ]
        ]
    )) {
        switch part {
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDeltaPart(id, delta, _):
            reasoningDeltas.append((id, delta))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
        case let .finish(reason, _):
            finishReason = reason
        case let .finishMetadata(reason, _, metadata):
            finishReason = reason
            finishMetadata = metadata
        default:
            break
        }
    }

    #expect(reasoningStarts.map { $0.0 } == [
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1"
    ])
    #expect(reasoningStarts.map { $0.1["openai"]?["reasoningEncryptedContent"]?.stringValue } == [
        "encrypted_reasoning_data_abc123",
        "encrypted_reasoning_data_abc123"
    ])
    #expect(reasoningDeltas.map { $0.1 } == [
        "**Exploring burrito origins**\n\nThe user is",
        " curious about the debate regarding Taqueria La Cumbre and El Farolito.",
        "**Investigating burrito origins**\n\nThere's a fascinating debate",
        " about who created the Mission burrito."
    ])
    #expect(reasoningEnds.map { $0.0 } == [
        "rs_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_6808709f6fcc8191ad2e2fdd784017b3:1"
    ])
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_final_def456")
    #expect(textDeltas == ["answer", " text"])
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "o3-mini")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsMultipleReasoningBlocksLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":"**Initial analysis**\\n\\nFirst reasoning block:"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0,"delta":" analyzing the problem structure."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":"**Deeper consideration**\\n\\nLet me think about"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1,"delta":" the various approaches available."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":"Let me think about"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c97c02656c81908e080dfdf4a03cd1","delta":" this step by step."}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message"}}

    data: {"type":"response.output_item.added","output_index":2,"item":{"id":"rs_second_7908809g7gcc9291be3e3fee895028c4","type":"reasoning"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_second_7908809g7gcc9291be3e3fee895028c4","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_second_7908809g7gcc9291be3e3fee895028c4","summary_index":0,"delta":"Second reasoning block:"}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_second_7908809g7gcc9291be3e3fee895028c4","summary_index":0,"delta":" considering alternative approaches."}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_second_7908809g7gcc9291be3e3fee895028c4","summary_index":0}

    data: {"type":"response.output_item.done","output_index":2,"item":{"id":"rs_second_7908809g7gcc9291be3e3fee895028c4","type":"reasoning"}}

    data: {"type":"response.output_item.added","output_index":3,"item":{"id":"msg_final_78d08d03767d92908f25523f5ge51e77","type":"message"}}

    data: {"type":"response.output_text.delta","item_id":"msg_final_78d08d03767d92908f25523f5ge51e77","delta":"Based on my analysis,"}

    data: {"type":"response.output_text.delta","item_id":"msg_final_78d08d03767d92908f25523f5ge51e77","delta":" here is the solution."}

    data: {"type":"response.output_item.done","output_index":3,"item":{"id":"msg_final_78d08d03767d92908f25523f5ge51e77","type":"message"}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[{"type":"summary_text","text":"**Initial analysis**\\n\\nFirst reasoning block: analyzing the problem structure."},{"type":"summary_text","text":"**Deeper consideration**\\n\\nLet me think about the various approaches available."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Let me think about this step by step.","annotations":[]}]},{"id":"rs_second_7908809g7gcc9291be3e3fee895028c4","type":"reasoning","summary":[{"type":"summary_text","text":"Second reasoning block: considering alternative approaches."}]},{"id":"msg_final_78d08d03767d92908f25523f5ge51e77","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on my analysis, here is the solution.","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":45,"input_tokens_details":{"cached_tokens":0},"output_tokens":628,"output_tokens_details":{"reasoning_tokens":420},"total_tokens":673},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "medium", "reasoningSummary": "auto"]]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
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

    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "o3-mini-2025-01-31")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(reasoningStarts.map { $0.0 } == [
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:1",
        "rs_second_7908809g7gcc9291be3e3fee895028c4:0"
    ])
    #expect(reasoningDeltas.map { $0.0 } == [
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:1",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:1",
        "rs_second_7908809g7gcc9291be3e3fee895028c4:0",
        "rs_second_7908809g7gcc9291be3e3fee895028c4:0"
    ])
    #expect(reasoningDeltas.map { $0.1 } == [
        "**Initial analysis**\n\nFirst reasoning block:",
        " analyzing the problem structure.",
        "**Deeper consideration**\n\nLet me think about",
        " the various approaches available.",
        "Second reasoning block:",
        " considering alternative approaches."
    ])
    #expect(reasoningEnds.map { $0.0 } == [
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:0",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3:1",
        "rs_second_7908809g7gcc9291be3e3fee895028c4:0"
    ])
    #expect(reasoningStarts.map { $0.1["openai"]?["itemId"]?.stringValue } == [
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_second_7908809g7gcc9291be3e3fee895028c4"
    ])
    #expect(reasoningStarts.allSatisfy { $0.1["openai"]?["reasoningEncryptedContent"] == .null })
    #expect(reasoningDeltas.map { $0.2["openai"]?["itemId"]?.stringValue } == [
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_first_6808709f6fcc8191ad2e2fdd784017b3",
        "rs_second_7908809g7gcc9291be3e3fee895028c4",
        "rs_second_7908809g7gcc9291be3e3fee895028c4"
    ])
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(reasoningEnds[2].1["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(textStarts.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_final_78d08d03767d92908f25523f5ge51e77"
    ])
    #expect(textStarts.map { $0.1["openai"]?["itemId"]?.stringValue } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_final_78d08d03767d92908f25523f5ge51e77"
    ])
    #expect(textDeltas.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_final_78d08d03767d92908f25523f5ge51e77",
        "msg_final_78d08d03767d92908f25523f5ge51e77"
    ])
    #expect(textDeltas.map { $0.1 } == [
        "Let me think about",
        " this step by step.",
        "Based on my analysis,",
        " here is the solution."
    ])
    #expect(textEnds.map { $0.0 } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_final_78d08d03767d92908f25523f5ge51e77"
    ])
    #expect(textEnds.map { $0.1["openai"]?["itemId"]?.stringValue } == [
        "msg_67c97c02656c81908e080dfdf4a03cd1",
        "msg_final_78d08d03767d92908f25523f5ge51e77"
    ])
    #expect(finishReason == "stop")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 45)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 45)
    #expect(finishUsage?.outputTokens == 628)
    #expect(finishUsage?.outputReasoningTokens == 420)
    #expect(finishUsage?.outputTextTokens == 208)
    #expect(finishUsage?.totalTokens == 673)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "o3-mini")
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["stream"]?.boolValue == true)
}

@Test func openAIResponsesStreamsReasoningLifecycleProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_initial"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":0,"delta":"first thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":1,"delta":"second thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var legacyReasoning: [String] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["store": false]
    )) {
        switch part {
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDelta(delta):
            legacyReasoning.append(delta)
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        default:
            break
        }
    }

    #expect(legacyReasoning == ["first thought", "second thought"])
    #expect(reasoningStarts.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.1 } == ["first thought", "second thought"])
    #expect(reasoningEnds.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningDeltas[0].2["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningDeltas[0].2["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningStarts[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_final")
}
