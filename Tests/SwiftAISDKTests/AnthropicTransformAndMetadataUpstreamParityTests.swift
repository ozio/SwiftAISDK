import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicTransformRequestBodyGenerateAndStreamLikeUpstream() async throws {
    let transform: @Sendable ([String: JSONValue]) -> [String: JSONValue] = { body in
        var output = body
        output["custom_field"] = "added-by-transform"
        output["transformed_model"] = body["model"]
        output["transformed_stream"] = body["stream"] ?? false
        return output
    }

    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_transform","content":[{"type":"text","text":"Hello!"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":4,"output_tokens":30}}
    """))
    let generateProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: generateTransport,
        transformRequestBody: transform
    ))
    let generateModel = try generateProvider.languageModel("claude-3-haiku-20240307")

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let generateRequest = try #require(await generateTransport.requests().first)
    let generateBody = try decodeJSONBody(try #require(generateRequest.body))
    #expect(generateBody["custom_field"]?.stringValue == "added-by-transform")
    #expect(generateBody["transformed_model"]?.stringValue == "claude-3-haiku-20240307")
    #expect(generateBody["transformed_stream"]?.boolValue == false)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_transform_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":4,"output_tokens":1}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello!"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

    data: {"type":"message_stop"}

    """))
    let streamProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: streamTransport,
        transformRequestBody: transform
    ))
    let streamModel = try streamProvider.languageModel("claude-3-haiku-20240307")

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    let streamBody = try decodeJSONBody(try #require(streamRequest.body))
    #expect(streamBody["custom_field"]?.stringValue == "added-by-transform")
    #expect(streamBody["transformed_model"]?.stringValue == "claude-3-haiku-20240307")
    #expect(streamBody["transformed_stream"]?.boolValue == true)

    let defaultTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_default","content":[{"type":"text","text":"Hello!"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":4,"output_tokens":30}}
    """))
    let defaultProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: defaultTransport))
    let defaultModel = try defaultProvider.languageModel("claude-3-haiku-20240307")

    _ = try await defaultModel.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let defaultRequest = try #require(await defaultTransport.requests().first)
    let defaultBody = try decodeJSONBody(try #require(defaultRequest.body))
    #expect(defaultBody["model"]?.stringValue == "claude-3-haiku-20240307")
    #expect(defaultBody["custom_field"] == nil)
}

@Test func anthropicCustomProviderNameMetadataAndOptionsLikeUpstream() async throws {
    let canonicalTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_custom","content":[{"type":"text","text":"Hello, World!"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":20}}
    """))
    let canonicalProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: canonicalTransport,
        name: "my-custom-anthropic.messages"
    ))
    let canonicalModel = try canonicalProvider.languageModel("claude-3-haiku-20240307")
    let canonicalResult = try await canonicalModel.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["anthropic": ["sendReasoning": true]]
    ))
    #expect(Set(canonicalResult.providerMetadata.keys) == ["anthropic"])

    let customTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_custom","content":[{"type":"text","text":"Hello, World!"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":20}}
    """))
    let customProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: customTransport,
        name: "my-custom-anthropic.messages"
    ))
    let customModel = try customProvider.languageModel("claude-3-haiku-20240307")
    let customResult = try await customModel.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["my-custom-anthropic": ["sendReasoning": true]]
    ))
    #expect(customResult.providerMetadata["anthropic"] != nil)
    #expect(customResult.providerMetadata["my-custom-anthropic"] != nil)

    let noOptionsTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_custom","content":[{"type":"text","text":"Hello, World!"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":20}}
    """))
    let noOptionsProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: noOptionsTransport,
        name: "my-custom-anthropic.messages"
    ))
    let noOptionsModel = try noOptionsProvider.languageModel("claude-3-haiku-20240307")
    let noOptionsResult = try await noOptionsModel.generate(LanguageModelRequest(messages: [.user("Hello")]))
    #expect(Set(noOptionsResult.providerMetadata.keys) == ["anthropic"])

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_custom_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello World!"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}

    data: {"type":"message_stop"}

    """))
    let streamProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: streamTransport,
        name: "my-custom-anthropic.messages"
    ))
    let streamModel = try streamProvider.languageModel("claude-3-haiku-20240307")
    var streamMetadata: [String: JSONValue] = [:]
    for try await part in streamModel.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["my-custom-anthropic": ["sendReasoning": true]]
    )) {
        if case let .finishMetadata(_, _, metadata) = part {
            streamMetadata = metadata
        }
    }
    #expect(streamMetadata["anthropic"] != nil)
    #expect(streamMetadata["my-custom-anthropic"] != nil)

    let generateOptionsTransport = RecordingTransport(response: jsonResponse("""
    {"id":"msg_custom_options","content":[{"type":"text","text":"ok"}],"model":"claude-3-haiku-20240307","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":20}}
    """))
    let generateOptionsProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: generateOptionsTransport,
        name: "my-custom-anthropic.messages"
    ))
    let generateOptionsModel = try generateOptionsProvider.languageModel("claude-3-haiku-20240307")
    _ = try await generateOptionsModel.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: ["testTool": ["type": "object", "properties": [:]]],
        providerOptions: ["my-custom-anthropic": ["disableParallelToolUse": true]]
    ))
    let generateOptionsRequest = try #require(await generateOptionsTransport.requests().first)
    let generateOptionsBody = try decodeJSONBody(try #require(generateOptionsRequest.body))
    #expect(generateOptionsBody["tool_choice"]?["type"]?.stringValue == "auto")
    #expect(generateOptionsBody["tool_choice"]?["disable_parallel_tool_use"]?.boolValue == true)

    let streamOptionsTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg_custom_options_stream","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}

    data: {"type":"message_stop"}

    """))
    let streamOptionsProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: streamOptionsTransport,
        name: "my-custom-anthropic.messages"
    ))
    let streamOptionsModel = try streamOptionsProvider.languageModel("claude-3-haiku-20240307")
    for try await _ in streamOptionsModel.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: ["testTool": ["type": "object", "properties": [:]]],
        providerOptions: ["my-custom-anthropic": ["disableParallelToolUse": true]]
    )) {}
    let streamOptionsRequest = try #require(await streamOptionsTransport.requests().first)
    let streamOptionsBody = try decodeJSONBody(try #require(streamOptionsRequest.body))
    #expect(streamOptionsBody["tool_choice"]?["type"]?.stringValue == "auto")
    #expect(streamOptionsBody["tool_choice"]?["disable_parallel_tool_use"]?.boolValue == true)
}

@Test func anthropicWebFetchToolResultsAcceptNullTitleAndPDFSourceLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[
      {"type":"web_fetch_tool_result","tool_use_id":"srv_fetch_1","content":{"type":"web_fetch_result","url":"https://test.com","retrieved_at":"2025-12-08T20:46:31.114158","content":{"type":"document","title":null,"source":{"type":"base64","media_type":"application/pdf","data":"JVBERi0xLjcNJeLjz9MNC"}}}},
      {"type":"text","text":"fetched"}
    ],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Fetch.")]))

    let toolResult = try #require(result.toolResults.first)
    #expect(toolResult.toolName == "web_fetch")
    #expect(toolResult.result["type"]?.stringValue == "web_fetch_result")
    #expect(toolResult.result["url"]?.stringValue == "https://test.com")
    #expect(toolResult.result["content"]?["title"] == .null)
    #expect(toolResult.result["content"]?["source"]?["type"]?.stringValue == "base64")
    #expect(toolResult.result["content"]?["source"]?["mediaType"]?.stringValue == "application/pdf")
}

@Test func anthropicWebSearchToolResultsAcceptNullTitleLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[
      {"type":"web_search_tool_result","tool_use_id":"srv_search_1","content":[{"type":"web_search_result","url":"https://test.com","title":null,"encrypted_content":"encrypted","page_age":"April 30, 2025"}]},
      {"type":"text","text":"searched"}
    ],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Search.")]))

    let toolResult = try #require(result.toolResults.first)
    #expect(toolResult.toolName == "web_search")
    #expect(toolResult.result[0]?["title"] == .null)
    #expect(toolResult.result[0]?["pageAge"]?.stringValue == "April 30, 2025")
    #expect(toolResult.result[0]?["encryptedContent"]?.stringValue == "encrypted")
}

@Test func anthropicStreamWebFetchToolResultsAcceptTextSourceLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"web_fetch_tool_result","tool_use_id":"srv_fetch_1","content":{"type":"web_fetch_result","url":"https://test.com","retrieved_at":"2025-12-08T20:46:31.114158","content":{"type":"document","title":null,"source":{"type":"text","media_type":"text/plain","data":"content"}}}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"done"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    var toolResults: [AIToolResult] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Fetch.")])) {
        if case let .toolResult(result) = part {
            toolResults.append(result)
        }
    }

    let toolResult = try #require(toolResults.first)
    #expect(toolResult.toolName == "web_fetch")
    #expect(toolResult.result["content"]?["title"] == .null)
    #expect(toolResult.result["content"]?["source"]?["type"]?.stringValue == "text")
    #expect(toolResult.result["content"]?["source"]?["mediaType"]?.stringValue == "text/plain")
}

