import Foundation
import Testing
@testable import SwiftAISDK

@Suite("ZAIProviderTests", .serialized)
struct ZAIProviderTests {
    private static let successResponse = #"{"id":"chatcmpl-123","request_id":"request-123","created":1777000000,"model":"glm-5.3","choices":[{"index":0,"message":{"role":"assistant","content":"The answer is 42.","reasoning_content":"I should calculate the answer.","tool_calls":[{"id":"call-1","type":"function","function":{"name":"calculator","arguments":"{\"value\":42}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":7,"prompt_tokens_details":{"cached_tokens":3},"total_tokens":17}}"#

    @Test func ZAIProviderCreatesCallableLanguageAndChatModels() throws {
        let provider = createZai(settings: ProviderSettings(
            apiKey: "test-key",
            transport: RecordingTransport(responses: [])
        ))

        let callable = try provider("glm-5.3")
        let language = try provider.languageModel("glm-5.2")
        let chat = try provider.chat("glm-4.7")

        #expect(provider.providerID == "zai")
        #expect(zai.providerID == "zai")
        #expect(provider.supportedCapabilities == [.language])
        #expect(callable is ZAILanguageModel)
        #expect(callable.providerID == "zai.chat")
        #expect(callable.modelID == "glm-5.3")
        #expect(language.providerID == "zai.chat")
        #expect(language.modelID == "glm-5.2")
        #expect(chat.providerID == "zai.chat")
        #expect(chat.modelID == "glm-4.7")

        #expect(throws: AIError.unsupportedModel(provider: "zai", capability: .embedding, modelID: "embed")) {
            _ = try provider.embeddingModel("embed")
        }
        #expect(throws: AIError.unsupportedModel(provider: "zai", capability: .image, modelID: "image")) {
            _ = try provider.imageModel("image")
        }
    }

    @Test func ZAIProviderUsesDefaultEndpointEnvironmentKeyAndVersionedUserAgent() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let provider = createZAI(settings: ProviderSettings(
            environment: ["ZAI_API_KEY": "environment-key"],
            transport: transport
        ))

        _ = try await provider("glm-5.3").generate(
            LanguageModelRequest(messages: [.user("Hello")])
        )

        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
        #expect(request.headers["authorization"] == "Bearer environment-key")
        #expect(request.headers["user-agent"] == "ai-sdk/zai/3.0.15")
    }

    @Test func ZAIProviderDefersMissingAPIKeyUntilRequestTime() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let provider = createZai(settings: ProviderSettings(
            environment: [:],
            transport: transport
        ))
        let model = try provider("glm-5.3")

        #expect(model.providerID == "zai.chat")
        await #expect(throws: AIError.missingAPIKey(
            provider: "zai",
            environmentVariables: ["ZAI_API_KEY"]
        )) {
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func ZAIProviderStillRequiresAKeyBeforeApplyingCustomAuthorization() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let provider = createZai(settings: ProviderSettings(
            headers: ["Authorization": "Bearer custom-key"],
            environment: [:],
            transport: transport
        ))

        await #expect(throws: AIError.missingAPIKey(
            provider: "zai",
            environmentVariables: ["ZAI_API_KEY"]
        )) {
            _ = try await provider("glm-5.3").generate(
                LanguageModelRequest(messages: [.user("Hello")])
            )
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func ZAIProviderHonorsCustomBaseURLHeadersAndCallerBodyTransform() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let provider = createZai(settings: ProviderSettings(
            apiKey: "unused-key",
            baseURL: "https://example.com/zai/",
            headers: [
                "Authorization": "Bearer custom-key",
                "User-Agent": "TestApp/1.0",
                "X-Custom": "value"
            ],
            transport: transport,
            transformRequestBody: { body in
                var body = body
                body["caller_marker"] = true
                return body
            }
        ))

        _ = try await provider.chat("glm-5.3").generate(
            LanguageModelRequest(messages: [.user("Hello")])
        )

        let request = try #require(await transport.requests().first)
        let body = try decodeJSONBody(try #require(request.body))
        #expect(request.url.absoluteString == "https://example.com/zai/chat/completions")
        #expect(request.headers["authorization"] == "Bearer custom-key")
        #expect(request.headers["x-custom"] == "value")
        #expect(request.headers["user-agent"] == "TestApp/1.0 ai-sdk/zai/3.0.15")
        #expect(body["caller_marker"]?.boolValue == true)
    }

    @Test func ZAILanguageMapsProviderOptionsAndOmitsUnsupportedStandardOptions() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let model = try createZai(settings: ProviderSettings(
            apiKey: "test-key",
            transport: transport
        ))("glm-5.3")

        let result = try await model.generate(LanguageModelRequest(
            messages: [.user("Hello")],
            topK: 10,
            presencePenalty: 0.3,
            frequencyPenalty: 0.2,
            seed: 42,
            reasoning: "low",
            tools: [
                "calculator": [
                    "type": "object",
                    "description": "Calculate a value",
                    "properties": [:]
                ]
            ],
            toolChoice: ["type": "required"],
            providerOptions: [
                "zai": [
                    "doSample": false,
                    "thinking": ["type": "enabled", "clearThinking": false],
                    "reasoningEffort": "max",
                    "toolStream": true,
                    "requestId": "request-123456",
                    "userId": "user-123456",
                    "ignoredOption": true
                ]
            ]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        #expect(body["model"]?.stringValue == "glm-5.3")
        #expect(body["do_sample"]?.boolValue == false)
        #expect(body["thinking"]?["type"]?.stringValue == "enabled")
        #expect(body["thinking"]?["clear_thinking"]?.boolValue == false)
        #expect(body["reasoning_effort"]?.stringValue == "max")
        #expect(body["tool_stream"]?.boolValue == true)
        #expect(body["request_id"]?.stringValue == "request-123456")
        #expect(body["user_id"]?.stringValue == "user-123456")
        #expect(body["frequency_penalty"] == nil)
        #expect(body["presence_penalty"] == nil)
        #expect(body["seed"] == nil)
        #expect(body["ignoredOption"] == nil)
        #expect(body["tool_choice"] == nil)
        #expect(body["tools"]?.arrayValue?.count == 1)
        #expect(result.warnings == [
            AIWarning(type: "unsupported", feature: "topK"),
            AIWarning(type: "unsupported", feature: "frequencyPenalty"),
            AIWarning(type: "unsupported", feature: "presencePenalty"),
            AIWarning(type: "unsupported", feature: "seed"),
            AIWarning(
                type: "unsupported",
                feature: "toolChoice required",
                message: "Z.AI currently supports only automatic tool selection."
            )
        ])
    }

    @Test func ZAILanguageToolChoiceNoneOmitsTools() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hello")],
            tools: ["calculator": ["type": "object", "properties": [:]]],
            toolChoice: ["type": "none"]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        #expect(body["tools"] == nil)
        #expect(body["tool_choice"] == nil)
    }

    @Test func ZAILanguageValidatesProviderOptionsBeforeSending() async throws {
        let transport = RecordingTransport(response: jsonResponse(Self.successResponse))
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        await #expect(throws: AIError.invalidArgument(
            argument: "providerOptions",
            message: "invalid zai provider options"
        )) {
            _ = try await model.generate(LanguageModelRequest(
                messages: [.user("Hello")],
                providerOptions: ["zai": ["requestId": "short"]]
            ))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func ZAILanguageParsesOrderedContentUsageAndMetadata() async throws {
        let transport = RecordingTransport(response: jsonResponse(
            Self.successResponse,
            headers: ["x-zai-request-id": "request-123"]
        ))
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

        #expect(result.text == "The answer is 42.")
        #expect(result.reasoning == "I should calculate the answer.")
        #expect(result.finishReason == "tool-calls")
        #expect(result.content.count == 3)
        if case let .text(text, _) = result.content[0] {
            #expect(text == "The answer is 42.")
        } else {
            Issue.record("Expected text content first")
        }
        if case let .reasoning(reasoning, _) = result.content[1] {
            #expect(reasoning == "I should calculate the answer.")
        } else {
            Issue.record("Expected reasoning content second")
        }
        if case let .toolCall(call) = result.content[2] {
            #expect(call.id == "call-1")
            #expect(call.name == "calculator")
            #expect(call.arguments == #"{"value":42}"#)
        } else {
            Issue.record("Expected tool call third")
        }
        #expect(result.usage?.inputTokens == 10)
        #expect(result.usage?.inputTokensCacheRead == 3)
        #expect(result.usage?.inputTokensNoCache == 7)
        #expect(result.usage?.outputTokens == 7)
        #expect(result.usage?.totalTokens == 17)
        #expect(result.responseMetadata.id == "chatcmpl-123")
        #expect(result.responseMetadata.modelID == "glm-5.3")
        #expect(result.responseMetadata.timestamp == Date(timeIntervalSince1970: 1_777_000_000))
        #expect(result.responseMetadata.headers["x-zai-request-id"] == "request-123")
        #expect(result.providerMetadata["zai"] == .object([:]))
        #expect(result.requestMetadata.body?["model"]?.stringValue == "glm-5.3")
        #expect(result.requestMetadata.body?["messages"]?[0]?["content"]?.stringValue == "Hello")
    }

    @Test(arguments: [
        ("sensitive", "content-filter"),
        ("model_context_window_exceeded", "length"),
        ("network_error", "error")
    ])
    func ZAILanguageMapsProviderFinishReasons(raw: String, unified: String) async throws {
        let response = """
        {"id":"finish-reason","model":"glm-5.3","choices":[{"message":{"content":null},"finish_reason":"\(raw)"}]}
        """
        let model = try createZai(settings: ProviderSettings(
            apiKey: "test-key",
            transport: RecordingTransport(response: jsonResponse(response))
        ))("glm-5.3")

        let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        #expect(result.text.isEmpty)
        #expect(result.finishReason == unified)
    }

    @Test(arguments: [
        #"{"choices":[{}]}"#,
        #"{"choices":[{"message":false}]}"#,
        #"{"choices":[{"message":{"content":42}}]}"#,
        #"{"choices":[{"message":{"content":[42]}}]}"#,
        #"{"choices":[{"message":{"role":"user","content":null}}]}"#
    ])
    func ZAILanguageRejectsMalformedNullableContentEnvelopes(body: String) async throws {
        let model = try createZai(settings: ProviderSettings(
            apiKey: "test-key",
            transport: RecordingTransport(response: jsonResponse(body))
        ))("glm-5.3")

        await #expect(throws: AIError.invalidResponse(
            provider: "zai.chat",
            message: "Chat completion choice did not contain a valid assistant message."
        )) {
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        }
    }

    @Test func ZAILanguageStreamsReasoningTextRawUsageAndProviderOptions() async throws {
        let transport = RecordingTransport(response: sseResponse("""
        data: {"id":"chatcmpl-stream","created":1777000000,"model":"glm-5.3","choices":[{"delta":{"role":"assistant","reasoning_content":"Think."},"finish_reason":null}]}

        data: {"id":"chatcmpl-stream","created":1777000000,"model":"glm-5.3","choices":[{"delta":{"content":"Answer."},"finish_reason":null}]}

        data: {"id":"chatcmpl-stream","created":1777000000,"model":"glm-5.3","choices":[{"delta":{},"finish_reason":"stop"}]}

        data: {"id":"chatcmpl-stream","created":1777000000,"model":"glm-5.3","choices":[],"usage":{"prompt_tokens":4,"completion_tokens":3,"total_tokens":7}}

        data: [DONE]
        """))
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        var partTypes: [String] = []
        var finishReason: String?
        var usage: TokenUsage?
        for try await part in model.stream(LanguageModelRequest(
            messages: [.user("Hello")],
            includeRawChunks: true,
            providerOptions: ["zai": ["toolStream": true]]
        )) {
            switch part {
            case .streamStart: partTypes.append("stream-start")
            case .raw: partTypes.append("raw")
            case .responseMetadata: partTypes.append("response-metadata")
            case .reasoningStart: partTypes.append("reasoning-start")
            case .reasoningDeltaPart: partTypes.append("reasoning-delta")
            case .reasoningEnd: partTypes.append("reasoning-end")
            case .textStart: partTypes.append("text-start")
            case .textDeltaPart: partTypes.append("text-delta")
            case .textEnd: partTypes.append("text-end")
            case let .finishMetadata(reason, value, _):
                partTypes.append("finish")
                finishReason = reason
                usage = value
            default: break
            }
        }

        #expect(partTypes == [
            "stream-start",
            "raw", "response-metadata", "reasoning-start", "reasoning-delta",
            "raw", "reasoning-end", "text-start", "text-delta",
            "raw", "raw", "text-end", "finish"
        ])
        #expect(finishReason == "stop")
        #expect(usage?.inputTokens == 4)
        #expect(usage?.outputTokens == 3)
        #expect(usage?.totalTokens == 7)
        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        #expect(body["stream"]?.boolValue == true)
        #expect(body["tool_stream"]?.boolValue == true)
        #expect(body["stream_options"] == nil)
    }

    @Test func ZAILanguageStreamsIncrementalToolCallArguments() async throws {
        let transport = RecordingTransport(response: sseResponse("""
        data: {"id":"chatcmpl-tool","created":1777000000,"model":"glm-5.3","choices":[{"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call-weather","function":{"name":"weather","arguments":"{\\"city\\""}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool","created":1777000000,"model":"glm-5.3","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"Paris\\"}"}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool","created":1777000000,"model":"glm-5.3","choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":5,"completion_tokens":4,"total_tokens":9}}

        data: [DONE]
        """))
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        var lifecycle: [String] = []
        var completedCall: AIToolCall?
        for try await part in model.stream(LanguageModelRequest(
            messages: [.user("Weather?")],
            tools: ["weather": ["type": "object", "properties": [:]]],
            providerOptions: ["zai": ["toolStream": true]]
        )) {
            switch part {
            case let .toolInputStart(id, name, _, _, _, _):
                lifecycle.append("start:\(id):\(name)")
            case let .toolInputDelta(id, delta, _):
                lifecycle.append("delta:\(id):\(delta)")
            case let .toolInputEnd(id, _):
                lifecycle.append("end:\(id)")
            case let .toolCall(call):
                completedCall = call
            default:
                break
            }
        }

        #expect(lifecycle == [
            "start:call-weather:weather",
            #"delta:call-weather:{"city""#,
            #"delta:call-weather::"Paris"}"#,
            "end:call-weather"
        ])
        #expect(completedCall?.id == "call-weather")
        #expect(completedCall?.name == "weather")
        #expect(completedCall?.arguments == #"{"city":"Paris"}"#)
    }

    @Test func ZAILanguageParsesFlatAndNestedErrorEnvelopes() async throws {
        let responses = [
            AIHTTPResponse(
                statusCode: 400,
                headers: ["x-zai": "flat"],
                body: Data(#"{"code":1001,"message":"Invalid request."}"#.utf8)
            ),
            AIHTTPResponse(
                statusCode: 401,
                headers: ["x-zai": "nested"],
                body: Data(#"{"error":{"code":"unauthorized","message":"Bad key."}}"#.utf8)
            )
        ]
        let transport = RecordingTransport(responses: responses)
        let model = try createZai(settings: ProviderSettings(apiKey: "test-key", transport: transport))("glm-5.3")

        await #expect(throws: AIError.apiCall(
            provider: "zai.chat",
            statusCode: 400,
            body: "Invalid request.",
            headers: ["x-zai": "flat"]
        )) {
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        }
        await #expect(throws: AIError.apiCall(
            provider: "zai.chat",
            statusCode: 401,
            body: "Bad key.",
            headers: ["x-zai": "nested"]
        )) {
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        }
    }

    @Test func ZAILanguagePublishesHTTPImageAndVideoURLSupport() throws {
        let model = try createZai(settings: ProviderSettings(
            apiKey: "test-key",
            transport: RecordingTransport(responses: [])
        ))("glm-5.3")

        #expect(isURLSupported(
            mediaType: "image/png",
            url: "https://example.com/image.png",
            supportedURLs: model.supportedURLs
        ))
        #expect(isURLSupported(
            mediaType: "video/mp4",
            url: "http://example.com/video.mp4",
            supportedURLs: model.supportedURLs
        ))
        #expect(!isURLSupported(
            mediaType: "audio/wav",
            url: "https://example.com/audio.wav",
            supportedURLs: model.supportedURLs
        ))
        #expect(!isURLSupported(
            mediaType: "image/png",
            url: "file:///tmp/image.png",
            supportedURLs: model.supportedURLs
        ))
    }
}
