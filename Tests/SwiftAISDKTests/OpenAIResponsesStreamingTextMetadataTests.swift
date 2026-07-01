import Foundation
import Testing
@testable import SwiftAISDK

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

@Test func openAIResponsesStreamsTextDeltasLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_67c9a81dea8c8190b79651a2b3adf91e","type":"message","status":"in_progress","role":"assistant","content":[]}}

    data: {"type":"response.content_part.added","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[],"logprobs":[]}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":"Hello,","logprobs":[]}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":" World!","logprobs":[]}

    data: {"type":"response.output_text.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"text":"Hello, World!"}

    data: {"type":"response.content_part.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Hello, World!","annotations":[],"logprobs":[]}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[],"logprobs":[]}]}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a878139c8190aa2e3105411b408b","object":"response","created_at":1741269112,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":543,"input_tokens_details":{"cached_tokens":234},"output_tokens":478,"output_tokens_details":{"reasoning_tokens":123},"total_tokens":512},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var legacyTextDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDelta(delta):
            legacyTextDeltas.append(delta)
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
            finishProviderMetadata = metadata
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "gpt-4o-2024-07-18")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(textStarts.count == 1)
    #expect(textStarts[0].0 == "msg_67c9a81dea8c8190b79651a2b3adf91e")
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_67c9a81dea8c8190b79651a2b3adf91e")
    #expect(legacyTextDeltas == ["Hello,", " World!"])
    #expect(textDeltas.map { $0.0 } == [
        "msg_67c9a81dea8c8190b79651a2b3adf91e",
        "msg_67c9a81dea8c8190b79651a2b3adf91e"
    ])
    #expect(textDeltas.map { $0.1 } == ["Hello,", " World!"])
    #expect(textEnds.count == 1)
    #expect(textEnds[0].0 == "msg_67c9a8787f4c8190b49c858d4c1cf20c")
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_67c9a8787f4c8190b49c858d4c1cf20c")
    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 543)
    #expect(finishUsage?.inputTokensCacheRead == 234)
    #expect(finishUsage?.inputTokensNoCache == 309)
    #expect(finishUsage?.outputTokens == 478)
    #expect(finishUsage?.outputReasoningTokens == 123)
    #expect(finishUsage?.outputTextTokens == 355)
    #expect(finishUsage?.totalTokens == 512)
}

@Test func openAIResponsesUsesAzureProviderMetadataKeyInStreamingFinishWhenProviderIncludesAzureLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_67c9a81dea8c8190b79651a2b3adf91e","type":"message","status":"in_progress","role":"assistant","content":[]}}

    data: {"type":"response.content_part.added","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":"Hello,"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":" World!"}

    data: {"type":"response.output_text.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"text":"Hello, World!"}

    data: {"type":"response.content_part.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Hello, World!","annotations":[]}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[]}]}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a878139c8190aa2e3105411b408b","object":"response","created_at":1741269112,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":543,"input_tokens_details":{"cached_tokens":234},"output_tokens":478,"output_tokens_details":{"reasoning_tokens":123},"total_tokens":512},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var finishProviderMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["openai": ["reasoningSummary": "auto"]]
    )) {
        if case let .finishMetadata(_, _, metadata) = part {
            finishProviderMetadata = metadata
        }
    }

    #expect(finishProviderMetadata["azure"] != nil)
    #expect(finishProviderMetadata["openai"] == nil)
    #expect(finishProviderMetadata["azure"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
}

@Test func openAIResponsesUsesOpenAIProviderMetadataKeyInStreamingFinishWhenProviderDoesNotIncludeAzureLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_67c9a81dea8c8190b79651a2b3adf91e","type":"message","status":"in_progress","role":"assistant","content":[]}}

    data: {"type":"response.content_part.added","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":"Hello,"}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":" World!"}

    data: {"type":"response.output_text.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"text":"Hello, World!"}

    data: {"type":"response.content_part.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Hello, World!","annotations":[]}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[]}]}}

    data: {"type":"response.completed","response":{"id":"resp_67c9a878139c8190aa2e3105411b408b","object":"response","created_at":1741269112,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello, World!","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":543,"input_tokens_details":{"cached_tokens":234},"output_tokens":478,"output_tokens_details":{"reasoning_tokens":123},"total_tokens":512},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var finishProviderMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finishMetadata(_, _, metadata) = part {
            finishProviderMetadata = metadata
        }
    }

    #expect(finishProviderMetadata["openai"] != nil)
    #expect(finishProviderMetadata["azure"] == nil)
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
}

@Test func openAIResponsesUsesAzureProviderMetadataKeyInStreamingReasoningEventsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_reasoning","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_reasoning_item","type":"reasoning"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning_item","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning_item","summary_index":0,"delta":"thinking through the steps"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning_item","summary_index":0}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_reasoning_item","type":"reasoning","summary":[{"type":"summary_text","text":"thinking through the steps"}]}}

    data: {"type":"response.completed","response":{"id":"resp_reasoning","object":"response","created_at":1741269019,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"o3-mini-2025-01-31","output":[{"id":"rs_reasoning_item","type":"reasoning","summary":[{"type":"summary_text","text":"thinking through the steps"}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"low","summary":"auto"},"store":true,"temperature":null,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":null,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":20,"output_tokens_details":{"reasoning_tokens":20},"total_tokens":30},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var reasoningStartMetadata: [String: JSONValue] = [:]
    var reasoningDeltaMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningStart(_, metadata):
            reasoningStartMetadata = metadata
        case let .reasoningDeltaPart(_, _, metadata):
            reasoningDeltaMetadata = metadata
        default:
            break
        }
    }

    #expect(reasoningStartMetadata["azure"] != nil)
    #expect(reasoningStartMetadata["openai"] == nil)
    #expect(reasoningStartMetadata["azure"]?["itemId"]?.stringValue == "rs_reasoning_item")
    #expect(reasoningStartMetadata["azure"]?["reasoningEncryptedContent"] == .null)
    #expect(reasoningDeltaMetadata["azure"] != nil)
    #expect(reasoningDeltaMetadata["openai"] == nil)
    #expect(reasoningDeltaMetadata["azure"]?["itemId"]?.stringValue == "rs_reasoning_item")
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

@Test func openAIResponsesIncludesPhaseInProviderMetadataForStreamedMessageItemsLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-phase.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.3-codex")

    var textStartParts: [(String, [String: JSONValue])] = []
    var textEndParts: [(String, [String: JSONValue])] = []

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        includeRawChunks: false
    )) {
        switch part {
        case let .textStart(id, providerMetadata):
            textStartParts.append((id, providerMetadata))
        case let .textEnd(id, providerMetadata):
            textEndParts.append((id, providerMetadata))
        default:
            break
        }
    }

    #expect(textStartParts.count == 2)
    #expect(textStartParts[0].1["openai"]?["itemId"]?.stringValue == "msg_0a63f40a2632b74300699f8819a5e08196ac270722d369af5a")
    #expect(textStartParts[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textStartParts[1].1["openai"]?["itemId"]?.stringValue == "msg_0a63f40a2632b74300699f881bfbc88196aec38f30c3dd24b0")
    #expect(textStartParts[1].1["openai"]?["phase"]?.stringValue == "final_answer")

    #expect(textEndParts.count == 2)
    #expect(textEndParts[0].1["openai"]?["itemId"]?.stringValue == "msg_0a63f40a2632b74300699f8819a5e08196ac270722d369af5a")
    #expect(textEndParts[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textEndParts[1].1["openai"]?["itemId"]?.stringValue == "msg_0a63f40a2632b74300699f881bfbc88196aec38f30c3dd24b0")
    #expect(textEndParts[1].1["openai"]?["phase"]?.stringValue == "final_answer")
}
