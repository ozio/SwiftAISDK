import Foundation
import Testing
@testable import SwiftAISDK

@Test func amazonBedrockModeledExceptionsAreTypedInBandErrorsLikeUpstream() async throws {
    let cases: [(type: String, statusCode: Int, isRetryable: Bool)] = [
        ("internalServerException", 500, true),
        ("modelStreamErrorException", 424, true),
        ("serviceUnavailableException", 503, true),
        ("throttlingException", 429, true),
        ("validationException", 400, false)
    ]

    for testCase in cases {
        let message = "Modeled exception: \(testCase.type)"
        let frame = amazonEventStreamFrame(
            messageType: "exception",
            eventTypeHeader: ":exception-type",
            eventType: testCase.type,
            payload: Data(#"{"message":"\#(message)"}"#.utf8)
        )
        let transport = RecordingTransport(response: AIHTTPResponse(
            statusCode: 200,
            headers: ["content-type": "application/vnd.amazon.eventstream"],
            body: frame
        ))
        let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
            region: "us-east-1",
            apiKey: "bedrock-key",
            transport: transport
        ))
        let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        let parts = try await collectProviderStreamParts(
            model,
            includeRawChunks: true
        )
        let error = try #require(parts.compactMap(\.streamProviderError).first)
        let expectedRaw: JSONValue = [testCase.type: ["message": .string(message)]]

        #expect(error.message == message)
        #expect(error.type == testCase.type)
        #expect(error.statusCode == testCase.statusCode)
        #expect(error.isRetryable == testCase.isRetryable)
        #expect(error.data == expectedRaw)
        #expect(parts.contains(.raw(expectedRaw)))
        #expect(providerStreamFinishReason(in: parts) == "error")
    }
}

@Test func groqPreservesErrorEnvelopeAsTypedStreamFailureLikeUpstream() async throws {
    let raw: JSONValue = [
        "error": [
            "message": "Rate limit reached",
            "type": "rate_limit_error"
        ]
    ]
    let transport = RecordingTransport(response: sseResponse("""
    data: {"error":{"message":"Rate limit reached","type":"rate_limit_error"}}

    data: [DONE]

    """))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")
    let parts = try await collectProviderStreamParts(model, includeRawChunks: true)
    let error = try #require(parts.compactMap(\.streamProviderError).first)

    #expect(error.message == "Rate limit reached")
    #expect(error.type == "rate_limit_error")
    #expect(error.statusCode == 429)
    #expect(error.isRetryable)
    #expect(error.data == raw)
    #expect(parts.contains(.raw(raw)))
    #expect(providerStreamFinishReason(in: parts) == "error")
}

@Test func deepSeekClassifiesRateLimitAndQuotaStreamErrorsLikeUpstream() async throws {
    let cases: [(code: String, isRetryable: Bool)] = [
        ("rate_limit_exceeded", true),
        ("insufficient_quota", false)
    ]

    for testCase in cases {
        let raw: JSONValue = [
            "error": [
                "message": "Rate limit reached",
                "type": "rate_limit_error",
                "code": .string(testCase.code)
            ]
        ]
        let encoded = try #require(String(data: encodeJSONBody(raw), encoding: .utf8))
        let transport = RecordingTransport(response: sseResponse("""
        data: \(encoded)

        data: [DONE]

        """))
        let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
        let model = try provider.languageModel("deepseek-chat")
        let parts = try await collectProviderStreamParts(model, includeRawChunks: true)
        let error = try #require(parts.compactMap(\.streamProviderError).first)

        #expect(error.message == "Rate limit reached")
        #expect(error.type == "rate_limit_error")
        #expect(error.code == .string(testCase.code))
        #expect(error.statusCode == 429)
        #expect(error.isRetryable == testCase.isRetryable)
        #expect(error.data == raw)
        #expect(parts.contains(.raw(raw)))
        #expect(providerStreamFinishReason(in: parts) == "error")
    }
}

@Test func googleInteractionsPreservesErrorEventAndFinishesFailedLikeUpstream() async throws {
    let raw: JSONValue = [
        "event_type": "error",
        "event_id": "event-error",
        "error": ["code": "429", "message": "Rate limit reached"]
    ]
    let transport = RecordingTransport(response: sseResponse("""
    data: {"event_type":"error","event_id":"event-error","error":{"code":"429","message":"Rate limit reached"}}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")
    let parts = try await collectProviderStreamParts(model, includeRawChunks: true)

    try assertGoogleInteractionsStreamError(parts, raw: raw)
}

@Test func googleVertexInteractionsPreservesErrorEventAndFinishesFailedLikeUpstream() async throws {
    let raw: JSONValue = [
        "event_type": "error",
        "event_id": "event-error",
        "error": ["code": "429", "message": "Rate limit reached"]
    ]
    let transport = RecordingTransport(response: sseResponse("""
    data: {"event_type":"error","event_id":"event-error","error":{"code":"429","message":"Rate limit reached"}}

    data: [DONE]

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.interactionsModel("gemini-omni-flash-preview")
    let parts = try await collectProviderStreamParts(model, includeRawChunks: true)

    try assertGoogleInteractionsStreamError(parts, raw: raw)
}

@Test func anthropicMapsProviderStreamErrorTypesIncludingOverloaded529LikeUpstream() async throws {
    let cases: [(type: String, statusCode: Int, isRetryable: Bool)] = [
        ("overloaded_error", 529, true),
        ("api_error", 500, true),
        ("rate_limit_error", 429, true),
        ("request_too_large", 413, false),
        ("authentication_error", 401, false),
        ("permission_error", 403, false),
        ("not_found_error", 404, false),
        ("billing_error", 400, false),
        ("invalid_request_error", 400, false)
    ]

    for testCase in cases {
        let message = "Failure: \(testCase.type)"
        let transport = RecordingTransport(response: sseResponse("""
        data: {"type":"message_start","message":{"id":"msg_error","type":"message","role":"assistant","content":[],"model":"claude-3-haiku-20240307","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":0}}}

        event: error
        data: {"type":"error","error":{"type":"\(testCase.type)","message":"\(message)"}}

        """))
        let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
        let model = try provider.languageModel("claude-3-haiku-20240307")
        let parts = try await collectProviderStreamParts(model, includeRawChunks: true)
        let error = try #require(parts.compactMap(\.streamProviderError).first)
        let expectedData: JSONValue = ["type": .string(testCase.type), "message": .string(message)]

        #expect(error.message == message)
        #expect(error.type == testCase.type)
        #expect(error.statusCode == testCase.statusCode)
        #expect(error.isRetryable == testCase.isRetryable)
        #expect(error.data == expectedData)
        #expect(parts.contains { part in
            guard case let .raw(raw) = part else { return false }
            return raw["type"]?.stringValue == "error"
                && raw["error"]?["type"]?.stringValue == testCase.type
        })
        #expect(providerStreamFinishReason(in: parts) == "error")
    }
}

@Test func openAIChatThrowsMessageOnlyErrorsBeforeOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"error":{"message":"stream failed before output"}}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    do {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {}
        Issue.record("Expected OpenAI Chat to throw before output starts.")
    } catch let AIError.apiCall(error) {
        #expect(error.statusCode == 500)
        #expect(error.isRetryable)
        #expect(error.responseBody == "stream failed before output")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func openAIChatClassifiesLateQuotaErrorsInBandLikeUpstream() async throws {
    let raw: JSONValue = [
        "error": [
            "message": "quota exhausted",
            "type": "insufficient_quota",
            "code": "insufficient_quota",
            "param": .null
        ]
    ]
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,"model":"gpt-4.1-mini","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

    data: {"error":{"message":"quota exhausted","type":"insufficient_quota","code":"insufficient_quota","param":null}}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")
    let parts = try await collectProviderStreamParts(model, includeRawChunks: true)
    let error = try #require(parts.compactMap(\.streamProviderError).first)

    #expect(error.message == "quota exhausted")
    #expect(error.type == "insufficient_quota")
    #expect(error.code == "insufficient_quota")
    #expect(error.statusCode == 429)
    #expect(!error.isRetryable)
    #expect(error.data == raw["error"])
    #expect(parts.contains(.raw(raw)))
    #expect(providerStreamFinishReason(in: parts) == "error")
}

@Test func openAICompletionThrowsBeforeOutputAndKeepsDecodeFailuresInBandLikeUpstream() async throws {
    let earlyErrorTransport = RecordingTransport(response: sseResponse("""
    data: {"error":{"message":"completion failed before output"}}

    data: [DONE]

    """))
    let earlyErrorProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: earlyErrorTransport))
    let earlyErrorModel = try earlyErrorProvider.completionModel("gpt-3.5-turbo-instruct")

    do {
        for try await _ in earlyErrorModel.stream(LanguageModelRequest(messages: [.user("Hello")])) {}
        Issue.record("Expected OpenAI Completion to throw before output starts.")
    } catch let AIError.apiCall(error) {
        #expect(error.statusCode == 500)
        #expect(error.isRetryable)
        #expect(error.responseBody == "completion failed before output")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let malformedTransport = RecordingTransport(response: sseResponse("""
    data: {unparsable}

    data: {"id":"cmpl-1","object":"text_completion","created":1,"model":"gpt-3.5-turbo-instruct","choices":[{"text":"Hello","index":0,"finish_reason":"stop"}]}

    data: [DONE]

    """))
    let malformedProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: malformedTransport))
    let malformedModel = try malformedProvider.completionModel("gpt-3.5-turbo-instruct")
    let parts = try await collectProviderStreamParts(malformedModel, includeRawChunks: false)

    #expect(parts.contains { if case .error = $0 { return true }; return false })
    #expect(parts.contains { if case let .textDeltaPart(_, delta, _) = $0 { return delta == "Hello" }; return false })
}

@Test func xaiResponsesClassifiesQuotaFailureWithoutRetryLikeUpstream() async throws {
    let raw: JSONValue = [
        "type": "response.failed",
        "response": [
            "status": "failed",
            "error": [
                "code": "insufficient_quota",
                "message": "quota exhausted"
            ],
            "usage": ["input_tokens": 1, "output_tokens": 0]
        ]
    ]
    let encoded = try #require(String(data: encodeJSONBody(raw), encoding: .utf8))
    let transport = RecordingTransport(response: sseResponse("""
    data: \(encoded)

    """))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.languageModel("grok-4-fast-non-reasoning")
    let parts = try await collectProviderStreamParts(model, includeRawChunks: true)
    let error = try #require(parts.compactMap(\.streamProviderError).first)

    #expect(error.message == "quota exhausted")
    #expect(error.type == "response.failed")
    #expect(error.code == "insufficient_quota")
    #expect(error.statusCode == 429)
    #expect(!error.isRetryable)
    #expect(error.data == raw)
    #expect(parts.contains(.raw(raw)))
    #expect(providerStreamFinishReason(in: parts) == "error")
}

@Test func streamErrorStatusNormalizationRejectsHugeNumericCodesWithoutTrapping() throws {
    let raw: JSONValue = [
        "message": "huge numeric code",
        "type": "api_error",
        "code": .number(1e300)
    ]
    let openAIError = try #require(openAIProviderStreamError(from: raw))
    #expect(openAIError.statusCode == 500)
    #expect(openAIError.isRetryable)

    let normalized = LanguageStreamPart.error(
        message: "huge numeric code",
        rawValue: raw
    ).streamProviderError
    #expect(normalized?.statusCode == nil)
    #expect(normalized?.isRetryable == false)
}

private func collectProviderStreamParts(
    _ model: any LanguageModel,
    includeRawChunks: Bool
) async throws -> [LanguageStreamPart] {
    var parts: [LanguageStreamPart] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        includeRawChunks: includeRawChunks
    )) {
        parts.append(part)
    }
    return parts
}

private func providerStreamFinishReason(in parts: [LanguageStreamPart]) -> String? {
    for part in parts.reversed() {
        if case let .finishMetadata(reason, _, _) = part {
            return reason
        }
    }
    return nil
}

private func assertGoogleInteractionsStreamError(
    _ parts: [LanguageStreamPart],
    raw: JSONValue
) throws {
    let error = try #require(parts.compactMap(\.streamProviderError).first)
    #expect(error.message == "Rate limit reached")
    #expect(error.type == "error")
    #expect(error.code == "429")
    #expect(error.data == raw)
    #expect(parts.contains(.raw(raw)))
    #expect(providerStreamFinishReason(in: parts) == "error")
}
