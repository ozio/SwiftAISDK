import Foundation
import Testing
@testable import SwiftAISDK

@Test func miniMaxProviderDefaultsAndAliasesMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"content":[{"type":"text","text":"callable"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#),
        jsonResponse(#"{"content":[{"type":"text","text":"language"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#),
        jsonResponse(#"{"content":[{"type":"text","text":"chat"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#)
    ])
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        environment: ["MINIMAX_API_KEY": "env-key"],
        transport: transport
    ))
    let callableModel = try provider("minimax-m3")
    let languageModel = try provider.languageModel("minimax-m2.5")
    let chatModel = try provider.chat("minimax-m2.1")

    #expect(provider.providerID == "minimax")
    #expect(provider.supportedCapabilities == [.language])
    #expect(callableModel.providerID == "minimax.messages")
    #expect(languageModel.providerID == "minimax.messages")
    #expect(chatModel.providerID == "minimax.messages")
    #expect(callableModel.supportedURLs.isEmpty)

    _ = try await callableModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await languageModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    _ = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.url.absoluteString == "https://api.minimax.io/anthropic/v1/messages" })
    #expect(requests.allSatisfy { $0.headers["x-api-key"] == "env-key" })
    #expect(requests.allSatisfy { $0.headers["anthropic-version"] == "2023-06-01" })
    #expect(requests.allSatisfy { $0.headers["user-agent"] == "ai-sdk/minimax/3.0.1" })
}

@Test func miniMaxCustomConfigurationMatchesUpstreamHeaderPrecedence() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#
    ))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "settings-key",
        baseURL: "https://minimax.example.com/custom/",
        headers: [
            "X-API-Key": "header-key",
            "Anthropic-Version": "custom-version",
            "User-Agent": "CustomApp/1.0",
            "X-Custom": "custom-value"
        ],
        environment: ["MINIMAX_API_KEY": "env-key"],
        transport: transport
    ))

    _ = try await provider.languageModel("future-minimax-model").generate(
        LanguageModelRequest(messages: [.user("Hi")])
    )

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://minimax.example.com/custom/messages")
    #expect(request.headers["x-api-key"] == "header-key")
    #expect(request.headers["anthropic-version"] == "custom-version")
    #expect(request.headers["x-custom"] == "custom-value")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/minimax/3.0.1")
}

@Test func miniMaxRequiresAPIKeyLikeUpstream() throws {
    #expect(throws: AIError.missingAPIKey(provider: "minimax", environmentVariables: ["MINIMAX_API_KEY"])) {
        _ = try AIProviders.miniMax(settings: MiniMaxProviderSettings(environment: [:]))
    }

    #expect(throws: AIError.missingAPIKey(provider: "minimax", environmentVariables: ["MINIMAX_API_KEY"])) {
        _ = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
            headers: ["x-api-key": "header-only-key"],
            environment: [:]
        ))
    }
}

@Test func miniMaxUnsupportedModelFamiliesMatchUpstream() throws {
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(apiKey: "test-key"))

    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .embedding, modelID: "embed")) {
        _ = try provider.textEmbeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "minimax", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func miniMaxReasoningRequestAndResponseMatchUpstreamFixture() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id": "msg_minimax_reasoning",
      "type": "message",
      "role": "assistant",
      "model": "minimax-m3",
      "content": [
        {
          "type": "thinking",
          "thinking": "Counting the letters...",
          "signature": "sig_123"
        },
        {"type": "text", "text": "There are 3 \\\"r\\\"s."}
      ],
      "stop_reason": "end_turn",
      "stop_sequence": null,
      "usage": {"input_tokens": 4, "output_tokens": 30}
    }
    """))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))
    let model = try provider("minimax-m3")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "minimax": [
                "thinking": ["type": "adaptive"]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.minimax.io/anthropic/v1/messages")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "minimax-m3")
    #expect(body["thinking"] == ["type": "adaptive"])

    #expect(result.text == "There are 3 \"r\"s.")
    #expect(result.reasoning == "Counting the letters...")
    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, metadata) = result.content[0] else {
        Issue.record("Expected reasoning content first")
        return
    }
    #expect(reasoning == "Counting the letters...")
    #expect(metadata["anthropic"]?["signature"]?.stringValue == "sig_123")
    guard case let .text(text, _) = result.content[1] else {
        Issue.record("Expected text content second")
        return
    }
    #expect(text == "There are 3 \"r\"s.")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 4)
    #expect(result.usage?.outputTokens == 30)
    #expect(result.responseMetadata.id == "msg_minimax_reasoning")
    #expect(result.providerMetadata["minimax"]?["usage"]?["output_tokens"]?.intValue == 30)
}

@Test func miniMaxStreamingReasoningUsesSharedAnthropicLifecycle() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data("""
        data: {"type":"message_start","message":{"id":"msg_stream","model":"minimax-m3","usage":{"input_tokens":4,"output_tokens":0}}}

        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Think"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"signed"}}

        data: {"type":"content_block_stop","index":0}

        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Done"}}

        data: {"type":"content_block_stop","index":1}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":2}}

        data: {"type":"message_stop"}

        """.utf8)
    ))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))

    var parts: [LanguageStreamPart] = []
    for try await part in try provider("minimax-m3").stream(
        LanguageModelRequest(
            messages: [.user("Think")],
            providerOptions: ["minimax": ["thinking": ["type": "adaptive"]]]
        )
    ) {
        parts.append(part)
    }

    #expect(parts.contains(.reasoningDelta("Think")))
    #expect(parts.contains(.textDelta("Done")))
    #expect(parts.contains { part in
        guard case let .reasoningDeltaPart(_, _, metadata) = part else { return false }
        return metadata["anthropic"]?["signature"]?.stringValue == "signed"
    })
    #expect(parts.contains { part in
        guard case let .finish(reason, usage) = part else { return false }
        return reason == "stop" && usage?.inputTokens == 4 && usage?.outputTokens == 2
    })
}

@Test func miniMaxDisabledThinkingAndMixedContentPreserveUpstreamOrder() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id": "msg_minimax_mixed",
      "model": "minimax-m3",
      "content": [
        {
          "type": "server_tool_use",
          "id": "search_1",
          "name": "web_search",
          "input": {"query": "MiniMax"}
        },
        {"type": "redacted_thinking", "data": "encrypted_reasoning"},
        {"type": "thinking", "thinking": "Plan", "signature": "sig_mixed"},
        {
          "type": "web_search_tool_result",
          "tool_use_id": "search_1",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/result",
              "title": "Search result",
              "page_age": "1 day",
              "encrypted_content": "encrypted_result"
            }
          ]
        },
        {
          "type": "text",
          "text": "Answer",
          "citations": [
            {
              "type": "web_search_result_location",
              "url": "https://example.com/citation",
              "title": "Citation",
              "cited_text": "Answer",
              "encrypted_index": "encrypted_index"
            }
          ]
        },
        {"type": "compaction", "content": "Compact context"}
      ],
      "stop_reason": "tool_use",
      "usage": {"input_tokens": 3, "output_tokens": 8}
    }
    """))
    let provider = try AIProviders.miniMax(settings: MiniMaxProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))

    let result = try await provider("minimax-m3").generate(LanguageModelRequest(
        messages: [.user("Use tools")],
        providerOptions: ["minimax": ["thinking": ["type": "disabled"]]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["thinking"] == ["type": "disabled"])

    #expect(result.text == "AnswerCompact context")
    #expect(result.reasoning == "Plan")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.map(\.id) == ["search_1"])
    #expect(result.toolResults.map(\.toolCallID) == ["search_1"])
    #expect(result.sources.map(\.url) == [
        "https://example.com/result",
        "https://example.com/citation"
    ])
    #expect(result.content.count == 8)

    guard case let .toolCall(toolCall) = result.content[0] else {
        Issue.record("Expected provider tool call first")
        return
    }
    #expect(toolCall.id == "search_1")
    guard case let .reasoning(redacted, redactedMetadata) = result.content[1] else {
        Issue.record("Expected redacted reasoning second")
        return
    }
    #expect(redacted.isEmpty)
    #expect(redactedMetadata["anthropic"]?["redactedData"]?.stringValue == "encrypted_reasoning")
    guard case let .reasoning(thinking, thinkingMetadata) = result.content[2] else {
        Issue.record("Expected signed reasoning third")
        return
    }
    #expect(thinking == "Plan")
    #expect(thinkingMetadata["anthropic"]?["signature"]?.stringValue == "sig_mixed")
    guard case let .toolResult(toolResult) = result.content[3] else {
        Issue.record("Expected provider tool result fourth")
        return
    }
    #expect(toolResult.toolCallID == "search_1")
    guard case let .source(searchSource) = result.content[4] else {
        Issue.record("Expected search-result source after its tool result")
        return
    }
    #expect(searchSource.url == "https://example.com/result")
    guard case let .text(answer, answerMetadata) = result.content[5] else {
        Issue.record("Expected cited text after the search result")
        return
    }
    #expect(answer == "Answer")
    #expect(answerMetadata["anthropic"]?["citations"]?[0]?["url"]?.stringValue == "https://example.com/citation")
    guard case let .source(citationSource) = result.content[6] else {
        Issue.record("Expected citation source immediately after its text")
        return
    }
    #expect(citationSource.url == "https://example.com/citation")
    guard case let .text(compaction, compactionMetadata) = result.content[7] else {
        Issue.record("Expected compaction content last")
        return
    }
    #expect(compaction == "Compact context")
    #expect(compactionMetadata["anthropic"]?["type"]?.stringValue == "compaction")
}
