import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicBatchV4StartsPreparedRequestsAndCombinesBetasLikeUpstream() async throws {
    let transport = AnthropicBatchScriptedTransport(
        sendResponses: [jsonResponse(anthropicBatchResponse(
            status: "in_progress",
            processing: 2,
            succeeded: 0,
            resultsURL: nil
        ))]
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "test-api-key",
        headers: [
            "Provider-Header": "provider",
            "Anthropic-Beta": "provider-header-beta"
        ],
        transport: transport
    ))
    let model = provider.batchLanguageModel("claude-3-haiku-20240307")

    let result = try await AI.startTextBatch(
        model: model,
        requests: [
            TextBatchRequest(
                id: "france",
                request: LanguageModelRequest(
                    messages: [.user("What is the capital of France?")],
                    frequencyPenalty: 0.5,
                    maxOutputTokens: 100
                )
            ),
            TextBatchRequest(
                id: "germany",
                request: LanguageModelRequest(
                    messages: [.user("What is the capital of Germany?")],
                    maxOutputTokens: 200,
                    providerOptions: [
                        "anthropic": [
                            "fallbacks": [[
                                "model": "claude-sonnet-4-5",
                                "max_tokens": 150
                            ]]
                        ]
                    ]
                )
            )
        ],
        providerOptions: ["anthropic": ["anthropicBeta": ["batch-beta"]]],
        headers: ["Operation-Header": "operation"]
    )

    #expect(result.batch.status.status == .pending)
    #expect(result.batch.status.rawStatus == "in_progress")
    #expect(result.batch.status.requestCounts == AIBatchRequestCounts(
        total: 2,
        pending: 2,
        completed: 0,
        failed: 0
    ))
    #expect(result.warnings.contains {
        $0.requestID == "france"
            && $0.warning.type == "unsupported"
            && $0.warning.feature == "frequencyPenalty"
    })

    let request = try #require(await transport.sendRequests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages/batches")
    #expect(request.headers["x-api-key"] == "test-api-key")
    #expect(request.headers["operation-header"] == "operation")
    #expect(request.headers["user-agent"] == "ai/7.0.68")
    let betaHeader = try #require(request.headers["anthropic-beta"])
    let betas = Set(betaHeader.split(separator: ",").map(String.init))
    #expect(betas.contains("batch-beta"))
    #expect(betas.contains("server-side-fallback-2026-06-01"))
    #expect(!betas.contains("provider-header-beta"))

    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["requests"]?[0]?["custom_id"]?.stringValue == "france")
    #expect(body["requests"]?[0]?["params"]?["model"]?.stringValue == "claude-3-haiku-20240307")
    #expect(body["requests"]?[0]?["params"]?["max_tokens"]?.intValue == 100)
    #expect(body["requests"]?[0]?["params"]?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "What is the capital of France?")
    #expect(body["requests"]?[1]?["params"]?["fallbacks"]?[0]?["model"]?.stringValue == "claude-sonnet-4-5")
}

@Test func anthropicBatchV4ValidatesProviderSpecificInputsBeforeHTTP() async throws {
    let transport = AnthropicBatchScriptedTransport(sendResponses: [jsonResponse("{}")])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let model = provider.batchLanguageModel("claude-3-haiku-20240307")

    await #expect(throws: AIError.self) {
        try await model.startBatch(AIBatchStartOptions(requests: [
            AILanguageModelBatchRequest(
                id: "invalid id",
                request: LanguageModelRequest(messages: [.user("hello")])
            )
        ]))
    }
    await #expect(throws: AIError.self) {
        try await model.startBatch(AIBatchStartOptions(requests: [
            AILanguageModelBatchRequest(
                id: "request-1",
                request: LanguageModelRequest(
                    messages: [.user("hello")],
                    providerOptions: ["anthropic": ["anthropicBeta": ["request-beta"]]]
                )
            )
        ]))
    }
    await #expect(throws: AIError.self) {
        try await model.startBatch(AIBatchStartOptions(requests: [
            AILanguageModelBatchRequest(
                id: "request-1",
                request: LanguageModelRequest(
                    messages: [.user("hello")],
                    providerOptions: ["anthropic": ["speed": "fast"]]
                )
            )
        ]))
    }
    #expect(await transport.sendRequests().isEmpty)
}

@Test func anthropicBatchV4MapsStatusCountsAndAllJSONLItemVariants() async throws {
    let statusResponse = anthropicBatchResponse(
        status: "ended",
        processing: 0,
        succeeded: 2,
        errored: 1,
        cancelled: 1,
        expired: 1,
        resultsURL: "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
    )
    let success = """
    {"custom_id":"france","result":{"type":"succeeded","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":3,"cache_creation_input_tokens":1,"cache_read_input_tokens":2}}}}
    """
    let failed = """
    {"custom_id":"invalid","result":{"type":"errored","error":{"type":"error","error":{"type":"invalid_request_error","message":"Invalid request."},"request_id":"req_123"}}}
    """
    let cancelled = #"{"custom_id":"cancelled","result":{"type":"canceled"}}"#
    let expired = #"{"custom_id":"expired","result":{"type":"expired"}}"#
    let joined = "\(success)\r\n\n\(failed)\n\(cancelled)\r\n\(expired)"
    let data = Data(joined.utf8)
    let splitA = data.index(data.startIndex, offsetBy: 17)
    let splitB = data.index(splitA, offsetBy: 41)
    let chunks = [
        Data(data[..<splitA]),
        Data(data[splitA..<splitB]),
        Data(data[splitB...])
    ]
    let transport = AnthropicBatchScriptedTransport(
        sendResponses: [jsonResponse(statusResponse), jsonResponse(statusResponse)],
        streamChunks: chunks
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let model = provider.batchLanguageModel("claude-3-haiku-20240307")

    let status = try await model.getBatchStatus(AIBatchOperationOptions(batchID: "msgbatch_123"))
    #expect(status.status == .completed)
    #expect(status.rawStatus == "ended")
    #expect(status.requestCounts == AIBatchRequestCounts(
        total: 5,
        pending: 0,
        completed: 2,
        failed: 3
    ))

    let stream = try await model.getBatchResults(AIBatchOperationOptions(
        batchID: "msgbatch_123",
        headers: ["Operation-Header": "operation"]
    ))
    var items: [AIBatchItemResult<TextGenerationResult>] = []
    for try await item in stream {
        items.append(item)
    }

    #expect(items.count == 4)
    guard case let .succeeded(id, result) = items[0] else {
        Issue.record("Expected succeeded result")
        return
    }
    #expect(id == "france")
    #expect(result.text == "Paris")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 13)
    #expect(result.usage?.inputTokensNoCache == 10)
    #expect(result.usage?.inputTokensCacheRead == 2)
    #expect(result.usage?.inputTokensCacheWrite == 1)
    #expect(result.responseMetadata.id == "msg_123")
    guard case let .failed(failedID, error, metadata) = items[1] else {
        Issue.record("Expected failed result")
        return
    }
    #expect(failedID == "invalid")
    #expect(error.type == "invalid_request_error")
    #expect(metadata["anthropic"]?["requestId"]?.stringValue == "req_123")
    guard case .cancelled(id: "cancelled", error: nil, providerMetadata: _) = items[2] else {
        Issue.record("Expected cancelled result")
        return
    }
    guard case .expired(id: "expired", error: nil, providerMetadata: _) = items[3] else {
        Issue.record("Expected expired result")
        return
    }

    let streamRequest = try #require(await transport.streamRequests().first)
    #expect(streamRequest.url.absoluteString == "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results")
    #expect(streamRequest.headers["operation-header"] == "operation")
}

@Test func anthropicBatchV4FailsUnsupportedOrInvalidItemsWithoutEndingTheStream() async throws {
    let statusResponse = anthropicBatchResponse(
        status: "ended",
        resultsURL: "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
    )
    let unsupported = """
    {"custom_id":"tool-call","result":{"type":"succeeded","message":{"id":"msg_tool","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"tool_use","id":"toolu_123","name":"get_weather","input":{"city":"Paris"}}],"stop_reason":"tool_use","usage":{"input_tokens":1,"output_tokens":1}}}}
    """
    let invalid = #"{"custom_id":"invalid","result":{"type":"succeeded","message":{"type":"message"}}}"#
    let valid = """
    {"custom_id":"valid","result":{"type":"succeeded","message":{"id":"msg_valid","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}}
    """
    let transport = AnthropicBatchScriptedTransport(
        sendResponses: [jsonResponse(statusResponse)],
        streamChunks: [Data("\(unsupported)\n\(invalid)\n\(valid)".utf8)]
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let model = provider.batchLanguageModel("claude-3-haiku-20240307")
    let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: "msgbatch_123"))
    var items: [AIBatchItemResult<TextGenerationResult>] = []
    for try await item in stream {
        items.append(item)
    }

    #expect(items.count == 3)
    guard case let .failed(_, toolError, _) = items[0] else {
        Issue.record("Expected unsupported-tool item failure")
        return
    }
    #expect(toolError.code == "unsupported_tool_content")
    #expect(toolError.message.contains("\"tool_use\""))
    guard case let .failed(_, invalidError, _) = items[1] else {
        Issue.record("Expected invalid-response item failure")
        return
    }
    #expect(invalidError.code == "invalid_response")
    guard case let .succeeded(id, result) = items[2] else {
        Issue.record("Expected later valid item")
        return
    }
    #expect(id == "valid")
    #expect(result.text == "Paris")
}

@Test func anthropicBatchV4RejectsIncompleteStatusResponses() async throws {
    let transport = AnthropicBatchScriptedTransport(sendResponses: [jsonResponse("""
    {
      "id": "msgbatch_123",
      "type": "message_batch",
      "processing_status": "ended",
      "archived_at": null,
      "results_url": null
    }
    """)])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))

    await #expect(throws: AIError.invalidResponse(
        provider: "anthropic",
        message: "Invalid Message Batch response."
    )) {
        _ = try await provider.batchLanguageModel("claude-3-haiku-20240307")
            .getBatchStatus(AIBatchOperationOptions(batchID: "msgbatch_123"))
    }
}

@Test func anthropicBatchV4RejectsMalformedUsagePerItemAndContinuesStreaming() async throws {
    let statusResponse = anthropicBatchResponse(
        status: "ended",
        resultsURL: "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
    )
    let malformed = """
    {"custom_id":"malformed","result":{"type":"succeeded","message":{"id":"msg_bad","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"bad usage"}],"stop_reason":"end_turn","usage":{"input_tokens":"1","output_tokens":1}}}}
    """
    let valid = """
    {"custom_id":"valid","result":{"type":"succeeded","message":{"id":"msg_valid","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}}
    """
    let transport = AnthropicBatchScriptedTransport(
        sendResponses: [jsonResponse(statusResponse)],
        streamChunks: [Data("\(malformed)\n\(valid)".utf8)]
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "test-api-key",
        transport: transport
    ))
    let stream = try await provider.batchLanguageModel("claude-3-haiku-20240307")
        .getBatchResults(AIBatchOperationOptions(batchID: "msgbatch_123"))
    var items: [AIBatchItemResult<TextGenerationResult>] = []
    for try await item in stream { items.append(item) }

    #expect(items.count == 2)
    guard case let .failed(id, error, _) = items[0] else {
        Issue.record("Expected malformed usage to produce a per-item failure")
        return
    }
    #expect(id == "malformed")
    #expect(error.code == "invalid_response")
    guard case let .succeeded(id, result) = items[1] else {
        Issue.record("Expected the later valid item to succeed")
        return
    }
    #expect(id == "valid")
    #expect(result.text == "Paris")
}

@Test func anthropicBatchV4AllowsSignedCrossOriginResultsWithoutForwardingCredentials() async throws {
    let resultsURL = "https://results.anthropic-cdn.example/signed/results.jsonl"
    let line = """
    {"custom_id":"valid","result":{"type":"succeeded","message":{"id":"msg_valid","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}}
    """
    let transport = AnthropicBatchRedirectTransport(
        sendResponses: [jsonResponse(anthropicBatchResponse(status: "ended", resultsURL: resultsURL))],
        streamResponses: [AnthropicBatchStreamResponse(
            statusCode: 200,
            headers: ["content-type": "application/jsonl"],
            chunks: [Data(line.utf8)]
        )]
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "test-api-key",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let stream = try await provider.batchLanguageModel("claude-3-haiku-20240307")
        .getBatchResults(AIBatchOperationOptions(
            batchID: "msgbatch_123",
            headers: ["X-Operation-Secret": "operation-secret"]
        ))
    for try await _ in stream {}

    let request = try #require(await transport.streamRequests().first)
    #expect(request.url.absoluteString == resultsURL)
    #expect(request.followRedirects == false)
    #expect(request.headers["x-api-key"] == nil)
    #expect(request.headers["x-provider-secret"] == nil)
    #expect(request.headers["x-operation-secret"] == nil)
    #expect(request.headers.keys.allSatisfy { $0.caseInsensitiveCompare("user-agent") == .orderedSame })
}

@Test func anthropicBatchV4StripsCredentialsWhenResultsRedirectCrossOrigin() async throws {
    let initialURL = "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
    let signedURL = "https://results.anthropic-cdn.example/signed/results.jsonl"
    let line = """
    {"custom_id":"valid","result":{"type":"succeeded","message":{"id":"msg_valid","type":"message","model":"claude-3-haiku-20240307","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}}
    """
    let transport = AnthropicBatchRedirectTransport(
        sendResponses: [jsonResponse(anthropicBatchResponse(status: "ended", resultsURL: initialURL))],
        streamResponses: [
            AnthropicBatchStreamResponse(
                statusCode: 302,
                headers: ["location": signedURL],
                chunks: []
            ),
            AnthropicBatchStreamResponse(
                statusCode: 200,
                headers: ["content-type": "application/jsonl"],
                chunks: [Data(line.utf8)]
            )
        ]
    )
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "test-api-key",
        headers: ["X-Provider-Secret": "provider-secret"],
        transport: transport
    ))
    let stream = try await provider.batchLanguageModel("claude-3-haiku-20240307")
        .getBatchResults(AIBatchOperationOptions(
            batchID: "msgbatch_123",
            headers: ["X-Operation-Secret": "operation-secret"]
        ))
    for try await _ in stream {}

    let requests = await transport.streamRequests()
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { !$0.followRedirects })
    #expect(requests[0].headers["x-api-key"] == "test-api-key")
    #expect(requests[0].headers["x-operation-secret"] == "operation-secret")
    #expect(requests[1].url.absoluteString == signedURL)
    #expect(requests[1].headers["x-api-key"] == nil)
    #expect(requests[1].headers["x-provider-secret"] == nil)
    #expect(requests[1].headers["x-operation-secret"] == nil)
    #expect(requests[1].headers.keys.allSatisfy { $0.caseInsensitiveCompare("user-agent") == .orderedSame })
}

private func anthropicBatchResponse(
    status: String,
    processing: Int = 0,
    succeeded: Int = 1,
    errored: Int = 0,
    cancelled: Int = 0,
    expired: Int = 0,
    resultsURL: String? = "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
) -> String {
    let results = resultsURL.map { #""\#($0)""# } ?? "null"
    return """
    {
      "id": "msgbatch_123",
      "type": "message_batch",
      "processing_status": "\(status)",
      "request_counts": {
        "processing": \(processing),
        "succeeded": \(succeeded),
        "errored": \(errored),
        "canceled": \(cancelled),
        "expired": \(expired)
      },
      "created_at": "2024-09-24T18:37:24.100Z",
      "expires_at": "2024-09-25T18:37:24.100Z",
      "archived_at": null,
      "results_url": \(results)
    }
    """
}

private actor AnthropicBatchScriptedTransport: AIStreamingTransport {
    private var sends: [AIHTTPRequest] = []
    private var streams: [AIHTTPRequest] = []
    private var sendResponses: [AIHTTPResponse]
    private var streamChunks: [Data]

    init(sendResponses: [AIHTTPResponse], streamChunks: [Data] = []) {
        self.sendResponses = sendResponses
        self.streamChunks = streamChunks
    }

    func sendRequests() -> [AIHTTPRequest] { sends }
    func streamRequests() -> [AIHTTPRequest] { streams }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        sends.append(request)
        guard !sendResponses.isEmpty else {
            throw AIError.invalidResponse(provider: "test", message: "Missing scripted response.")
        }
        return sendResponses.removeFirst()
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        streams.append(request)
        let chunks = streamChunks
        return AIHTTPStreamResponse(
            statusCode: 200,
            headers: ["content-type": "application/jsonl"],
            body: AsyncThrowingStream { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        )
    }
}

private struct AnthropicBatchStreamResponse: Sendable {
    var statusCode: Int
    var headers: [String: String]
    var chunks: [Data]
}

private actor AnthropicBatchRedirectTransport: AIStreamingTransport {
    private var sends: [AIHTTPRequest] = []
    private var streams: [AIHTTPRequest] = []
    private var sendResponses: [AIHTTPResponse]
    private var streamResponses: [AnthropicBatchStreamResponse]

    init(
        sendResponses: [AIHTTPResponse],
        streamResponses: [AnthropicBatchStreamResponse]
    ) {
        self.sendResponses = sendResponses
        self.streamResponses = streamResponses
    }

    func streamRequests() -> [AIHTTPRequest] { streams }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        sends.append(request)
        guard !sendResponses.isEmpty else {
            throw AIError.invalidResponse(provider: "test", message: "Missing scripted response.")
        }
        return sendResponses.removeFirst()
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        streams.append(request)
        guard !streamResponses.isEmpty else {
            throw AIError.invalidResponse(provider: "test", message: "Missing scripted stream response.")
        }
        let scripted = streamResponses.removeFirst()
        return AIHTTPStreamResponse(
            statusCode: scripted.statusCode,
            headers: scripted.headers,
            body: AsyncThrowingStream { continuation in
                for chunk in scripted.chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        )
    }
}
