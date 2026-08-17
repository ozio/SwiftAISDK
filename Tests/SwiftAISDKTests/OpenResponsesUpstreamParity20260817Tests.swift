import Foundation
import Testing
@testable import SwiftAISDK

@Test func openResponsesReplaysAssistantItemsInOrderWithIDsAndMetadataLikeUpstream() throws {
    let message = AIMessage(role: .assistant, content: [
        .text("Before", providerMetadata: ["open-responses": [
            "itemId": "msg_before",
            "annotations": [[
                "type": "url_citation",
                "start_index": 0,
                "end_index": 6,
                "url": "https://example.com/before",
                "title": "Before"
            ]]
        ]]),
        .reasoning("fallback", providerMetadata: ["open-responses": [
            "itemId": "rs_1",
            "reasoningSummary": [["type": "summary_text", "text": "Summary"]],
            "reasoningContent": [["type": "reasoning_text", "text": "First"]],
            "reasoningEncryptedContent": "encrypted"
        ]]),
        .reasoning("ignored fallback", providerMetadata: ["open-responses": [
            "itemId": "rs_1",
            "reasoningContent": [["type": "reasoning_text", "text": "Second"]]
        ]]),
        .toolCall(AIToolCall(
            id: "call_1",
            name: "lookup",
            arguments: #"{"query":"swift"}"#,
            providerMetadata: ["open-responses": ["itemId": "fc_1"]]
        )),
        .text("After", providerMetadata: ["open-responses": ["itemId": "msg_after"]])
    ])

    let prepared = openResponsesInput(
        from: [message],
        providerID: "open-responses.responses",
        providerOptionsName: "open-responses"
    )
    let input = try #require(prepared.input.arrayValue)

    #expect(input.map { $0["type"]?.stringValue } == [
        "message", "reasoning", "function_call", "message"
    ])
    #expect(input[0]["id"]?.stringValue == "msg_before")
    #expect(input[0]["content"]?[0]?["annotations"]?[0]?["url"]?.stringValue == "https://example.com/before")
    #expect(input[1]["id"]?.stringValue == "rs_1")
    #expect(input[1]["content"]?.arrayValue?.map { $0["text"]?.stringValue } == ["First", "Second"])
    #expect(input[1]["encrypted_content"]?.stringValue == "encrypted")
    #expect(input[2]["id"]?.stringValue == "fc_1")
    #expect(input[2]["call_id"]?.stringValue == "call_1")
    #expect(input[3]["id"]?.stringValue == "msg_after")
}

@Test func openResponsesPreservesStructuredReasoningForManualReplayLikeUpstream() throws {
    let item: JSONValue = [
        "type": "reasoning",
        "id": "rs_structured",
        "summary": [["type": "summary_text", "text": "Summary"]],
        "content": [
            ["type": "reasoning_text", "text": "First"],
            ["type": "reasoning_text", "text": "Second"]
        ],
        "encrypted_content": "encrypted-state"
    ]
    let parts = openAIResponsesOutputContentItem(
        from: item,
        providerID: "open-responses.responses",
        mode: .openResponses(providerOptionsName: "open-responses")
    )

    #expect(parts.count == 2)
    guard case let .reasoning(firstText, firstMetadata) = parts[0],
          case let .reasoning(secondText, secondMetadata) = parts[1] else {
        Issue.record("Expected two reasoning content parts")
        return
    }
    #expect(firstText == "First")
    #expect(secondText == "Second")
    #expect(firstMetadata["open-responses"]?["itemId"]?.stringValue == "rs_structured")
    #expect(firstMetadata["open-responses"]?["reasoningSummary"]?[0]?["text"]?.stringValue == "Summary")
    #expect(firstMetadata["open-responses"]?["reasoningContent"]?[0]?["text"]?.stringValue == "First")
    #expect(secondMetadata["open-responses"]?["reasoningContent"]?[0]?["text"]?.stringValue == "Second")
    #expect(firstMetadata["open-responses"]?["reasoningEncryptedContent"]?.stringValue == "encrypted-state")
}

@Test func openResponsesNativeReasoningEffortWinsAndProviderToolsWarnLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        reasoning: "high",
        tools: [
            "search": ["type": "provider", "id": "vendor.search"],
            "browser": ["type": "provider", "id": "vendor.browser"],
            "lookup": ["type": "object", "properties": [:]]
        ],
        providerOptions: ["open-responses": [
            "reasoningEffort": "vendor-ultra",
            "reasoningSummary": "auto"
        ]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "vendor-ultra")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["tools"]?.arrayValue?.count == 1)
    #expect(Set(result.warnings.compactMap(\.feature)) == Set([
        "provider-defined tool vendor.search",
        "provider-defined tool vendor.browser"
    ]))
}

@Test func openResponsesSurfacesSuccessfulBodyErrorBeforeNoOutputFallbackLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"id":"resp-error","status":"failed","error":{"code":"server_error","message":"The upstream provider failed to generate a response."}}"#,
        headers: ["x-request-id": "request-error"]
    ))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    do {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        Issue.record("Expected the embedded successful-body error to be surfaced.")
    } catch let AIError.apiCall(error) {
        #expect(error.provider == "open-responses.responses")
        #expect(error.statusCode == 400)
        #expect(error.responseHeaders["x-request-id"] == "request-error")
        #expect(error.responseBody == "The upstream provider failed to generate a response.")
        #expect(error.isRetryable == false)
    }
}

@Test func openResponsesThrowsDescriptiveNonRetryableErrorWhenSuccessfulBodyHasNoOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"id":"resp-no-output","status":"incomplete","incomplete_details":{"reason":"content_filter"},"output":null}"#,
        headers: ["x-request-id": "request-no-output"]
    ))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    do {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        Issue.record("Expected a missing output error.")
    } catch let AIError.apiCall(error) {
        #expect(error.provider == "open-responses.responses")
        #expect(error.statusCode == 500)
        #expect(error.responseHeaders["x-request-id"] == "request-no-output")
        #expect(error.responseBody == "Responses API returned no output (content_filter)")
        #expect(error.isRetryable == false)
    }
}

@Test func openResponsesAcceptsReasoningOnlySuccessfulBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "id":"resp-reasoning-only",
      "status":"completed",
      "output":[{
        "id":"rs-only",
        "type":"reasoning",
        "status":"completed",
        "summary":[{"type":"summary_text","text":"safe summary"}],
        "encrypted_content":"opaque-provider-state"
      }]
    }
    """#))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Think")]))

    #expect(result.text == "")
    #expect(result.content.count == 1)
    guard case let .reasoning(text, metadata) = result.content[0] else {
        Issue.record("Expected reasoning-only output content.")
        return
    }
    #expect(text == "safe summary")
    #expect(metadata["open-responses"]?["itemId"]?.stringValue == "rs-only")
    #expect(metadata["open-responses"]?["reasoningSummary"]?[0]?["text"]?.stringValue == "safe summary")
    #expect(metadata["open-responses"]?["reasoningEncryptedContent"]?.stringValue == "opaque-provider-state")
}

@Test func openResponsesStreamIgnoresReasoningSummaryTextDeltasLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs-original","summary":[]}}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs-original","output_index":0,"summary_index":0,"delta":"safe summary"}

    data: {"type":"response.reasoning_text.delta","item_id":"rs-original","output_index":0,"content_index":0,"delta":"private reasoning"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs-original","status":"completed","summary":[{"type":"summary_text","text":"safe summary"}],"content":[{"type":"reasoning_text","text":"private reasoning"}]}}
    """))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    var starts: [String] = []
    var deltas: [(String, String)] = []
    var ends: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Think")])) {
        switch part {
        case let .reasoningStart(id, _): starts.append(id)
        case let .reasoningDeltaPart(id, delta, _): deltas.append((id, delta))
        case let .reasoningEnd(id, _): ends.append(id)
        default: break
        }
    }

    #expect(starts == ["rs-original"])
    #expect(deltas.count == 1)
    #expect(deltas.first?.0 == "rs-original")
    #expect(deltas.first?.1 == "private reasoning")
    #expect(ends == ["rs-original"])
}

@Test func openResponsesStreamUsesOriginalReasoningIDAndClosesItAtEOFLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_original","summary":[]}}

    data: {"type":"response.reasoning_text.delta","item_id":"rs_original","delta":"thinking"}

    """))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    var starts: [String] = []
    var deltas: [(String, String)] = []
    var ends: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Think")])) {
        switch part {
        case let .reasoningStart(id, _): starts.append(id)
        case let .reasoningDeltaPart(id, delta, _): deltas.append((id, delta))
        case let .reasoningEnd(id, _): ends.append(id)
        default: break
        }
    }

    #expect(starts == ["rs_original"])
    #expect(deltas.count == 1)
    #expect(deltas.first?.0 == "rs_original")
    #expect(deltas.first?.1 == "thinking")
    #expect(ends == ["rs_original"])
}
