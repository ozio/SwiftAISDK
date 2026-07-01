import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicStreamUsageUsesMessageDeltaInputTokensLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_usage","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":43,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":61,"output_tokens":2}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    var finishUsage: TokenUsage?
    var finishMetadataUsage: TokenUsage?
    var providerMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .finish(_, usage):
            finishUsage = usage
        case let .finishMetadata(_, usage, metadata):
            finishMetadataUsage = usage
            providerMetadata = metadata
        default:
            break
        }
    }

    #expect(finishUsage?.inputTokens == 61)
    #expect(finishUsage?.inputTokensNoCache == 61)
    #expect(finishUsage?.outputTokens == 2)
    #expect(finishMetadataUsage?.inputTokens == 61)
    #expect(finishMetadataUsage?.outputTokens == 2)
    #expect(providerMetadata["anthropic"]?["usage"]?["input_tokens"]?.intValue == 61)
    #expect(providerMetadata["anthropic"]?["usage"]?["output_tokens"]?.intValue == 2)
}

@Test func anthropicStreamCacheTokensFromMessageDeltaLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_cache","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}

    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    var finishUsage: TokenUsage?
    var finishMetadataUsage: TokenUsage?
    var providerMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .finish(_, usage):
            finishUsage = usage
        case let .finishMetadata(_, usage, metadata):
            finishMetadataUsage = usage
            providerMetadata = metadata
        default:
            break
        }
    }

    #expect(finishUsage?.inputTokens == 32)
    #expect(finishUsage?.inputTokensNoCache == 17)
    #expect(finishUsage?.inputTokensCacheRead == 5)
    #expect(finishUsage?.inputTokensCacheWrite == 10)
    #expect(finishUsage?.outputTokens == 227)
    #expect(finishMetadataUsage?.inputTokens == 32)
    #expect(finishMetadataUsage?.outputTokens == 227)
    #expect(providerMetadata["anthropic"]?["usage"]?["input_tokens"]?.intValue == 17)
    #expect(providerMetadata["anthropic"]?["usage"]?["cache_creation_input_tokens"]?.intValue == 10)
    #expect(providerMetadata["anthropic"]?["usage"]?["cache_read_input_tokens"]?.intValue == 5)
    #expect(providerMetadata["anthropic"]?["usage"]?["output_tokens"]?.intValue == 227)
}

@Test func anthropicStreamPauseTurnAndStopSequenceMetadataLikeUpstream() async throws {
    let pauseTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_pause","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"pause_turn","stop_sequence":null},"usage":{"output_tokens":227}}

    data: {"type":"message_stop"}

    """))
    let pauseProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: pauseTransport))
    let pauseModel = try pauseProvider.languageModel("claude-3-haiku-20240307")

    var pauseFinishReason: String?
    for try await part in pauseModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        if case let .finish(reason, _) = part {
            pauseFinishReason = reason
        }
    }

    let stopTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_stop","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"stop_sequence","stop_sequence":"STOP"},"usage":{"output_tokens":227}}

    data: {"type":"message_stop"}

    """))
    let stopProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: stopTransport))
    let stopModel = try stopProvider.languageModel("claude-3-haiku-20240307")

    var stopFinishReason: String?
    var stopMetadata: [String: JSONValue] = [:]
    for try await part in stopModel.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        stopSequences: ["STOP"]
    )) {
        switch part {
        case let .finish(reason, _):
            stopFinishReason = reason
        case let .finishMetadata(_, _, metadata):
            stopMetadata = metadata
        default:
            break
        }
    }

    #expect(pauseFinishReason == "stop")
    #expect(stopFinishReason == "stop")
    #expect(stopMetadata["anthropic"]?["stopSequence"]?.stringValue == "STOP")
}

@Test func anthropicStreamRawChunksOnlyWhenRequestedLikeUpstream() async throws {
    let response = sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_raw","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":227}}

    data: {"type":"message_stop"}

    """)

    let defaultProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: RecordingTransport(response: response)))
    let defaultModel = try defaultProvider.languageModel("claude-3-haiku-20240307")
    var defaultRawTypes: [String] = []
    for try await part in defaultModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        if case let .raw(raw) = part {
            defaultRawTypes.append(raw["type"]?.stringValue ?? "")
        }
    }

    let rawProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: RecordingTransport(response: response)))
    let rawModel = try rawProvider.languageModel("claude-3-haiku-20240307")
    var rawTypes: [String] = []
    var rawTextDelta: String?
    for try await part in rawModel.stream(LanguageModelRequest(messages: [.user("Hello")], includeRawChunks: true)) {
        if case let .raw(raw) = part {
            rawTypes.append(raw["type"]?.stringValue ?? "")
            rawTextDelta = raw["delta"]?["text"]?.stringValue ?? rawTextDelta
        }
    }

    #expect(defaultRawTypes.isEmpty)
    #expect(rawTypes == [
        "message_start",
        "content_block_start",
        "content_block_delta",
        "content_block_stop",
        "message_delta",
        "message_stop"
    ])
    #expect(rawTextDelta == "Hello")
}

@Test func anthropicStreamOverloadedErrorChunksLikeUpstream() async throws {
    let firstErrorTransport = RecordingTransport(response: sseResponse("""
    event: error
    data: {"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}

    """))
    let firstErrorProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: firstErrorTransport))
    let firstErrorModel = try firstErrorProvider.languageModel("claude-3-haiku-20240307")

    await #expect(throws: AIError.apiCall(
        provider: "anthropic.messages",
        statusCode: 529,
        body: "Overloaded",
        headers: ["content-type": "text/event-stream"]
    )) {
        for try await _ in firstErrorModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {}
    }

    let midStreamTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_error","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":17,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    event: error
    data: {"type":"error","error":{"details":null,"type":"overloaded_error","message":"Overloaded"}}

    """))
    let midStreamProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: midStreamTransport))
    let midStreamModel = try midStreamProvider.languageModel("claude-3-haiku-20240307")

    var textDeltas: [String] = []
    var errors: [(String, JSONValue?)] = []
    var finishCount = 0
    for try await part in midStreamModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .textDelta(delta):
            textDeltas.append(delta)
        case let .error(message, rawValue):
            errors.append((message, rawValue))
        case .finish, .finishMetadata:
            finishCount += 1
        default:
            break
        }
    }

    #expect(textDeltas == ["Hello"])
    #expect(errors.count == 1)
    #expect(errors.first?.0 == "Overloaded")
    #expect(errors.first?.1?["error"]?["type"]?.stringValue == "overloaded_error")
    #expect(finishCount == 0)
}

