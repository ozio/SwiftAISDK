import Foundation
import Testing
@testable import SwiftAISDK

private let providerGroupBParallelArguments = #"{"tool_uses":[{"recipient_name":"functions.weather","parameters":{"location":"San Francisco"}},{"recipient_name":"functions.cityAttractions","parameters":{"city":"Rome"}}]}"#

private func providerGroupBParallelMetadata(index: Int, cacheBreakpoint: Bool = false) -> [String: JSONValue] {
    var openAI: [String: JSONValue] = [
        "parallelToolCall": [
            "itemId": "fc_parallel",
            "toolCallId": "call_parallel",
            "toolName": "parallel",
            "input": .string(providerGroupBParallelArguments),
            "index": .number(Double(index)),
            "count": 2
        ]
    ]
    if cacheBreakpoint {
        openAI["promptCacheBreakpoint"] = ["mode": "explicit"]
    }
    return ["openai": .object(openAI)]
}

@Test func providerGroupBCompatibleChatParsesArrayContentAndForwardsReasoningNone() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "choices":[{
        "message":{"content":[
          {"type":"text","text":"hello "},
          {"type":"thinking","thinking":[
            {"type":"text","text":"think "},
            {"type":"future","value":"ignored"},
            {"type":"text","text":"more"}
          ]},
          {"type":"future","value":"ignored"},
          {"type":"text","text":"world"}
        ],"reasoning_content":"tail"},
        "finish_reason":"stop"
      }]
    }
    """#))
    let provider = try AIProviders.openAICompatible(
        name: "compatible",
        baseURL: "https://compatible.example/v1",
        apiKey: "test-key",
        transport: transport
    )

    let result = try await provider.chatModel("chat-model").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        reasoning: "none"
    ))

    #expect(result.text == "hello world")
    #expect(result.reasoning == "think moretail")
    #expect(result.content == [
        .text("hello "),
        .reasoning("think more"),
        .text("world"),
        .reasoning("tail")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning_effort"]?.stringValue == "none")
}

@Test func providerGroupBCompatibleChatStreamsArrayTextAndThinkingParts() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"plan"}]},{"type":"future","value":"ignored"},{"type":"text","text":"answer"}]},"finish_reason":null}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

    data: [DONE]
    """#))
    let provider = try AIProviders.openAICompatible(
        name: "compatible",
        baseURL: "https://compatible.example/v1",
        apiKey: "test-key",
        transport: transport
    )

    var reasoning = ""
    var text = ""
    for try await part in try provider.chatModel("chat-model").stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .reasoningDeltaPart(_, delta, _): reasoning += delta
        case let .textDeltaPart(_, delta, _): text += delta
        default: break
        }
    }

    #expect(reasoning == "plan")
    #expect(text == "answer")
}

@Test func providerGroupBOpenAIChatNormalizesNonObjectReplayedToolArguments() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.chatModel("gpt-4.1-mini").generate(LanguageModelRequest(messages: [
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(id: "call_1", name: "lookup", arguments: #"["not","an","object"]"#))
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["messages"]?[0]?["tool_calls"]?[0]?["function"]?["arguments"]?.stringValue == "{}")
}

@Test func providerGroupBOpenAIResponsesReplaysRegularFunctionNamedToolSearch() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.languageModel("gpt-4o").generate(LanguageModelRequest(
        messages: [
            .user("Search synthetic records."),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_123",
                    name: "tool_search",
                    arguments: #"{"query":"synthetic query","limit":10}"#
                ))
            ]),
            .toolResponses(toolResults: [
                AIToolResult(toolCallID: "call_123", toolName: "tool_search", result: ["tools": []])
            ])
        ],
        tools: [
            "tool_search": [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "limit": ["type": "number"]
                ],
                "required": ["query", "limit"],
                "additionalProperties": false
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "tool_search")
    let input = try #require(body["input"]?.arrayValue)
    #expect(input[1]["type"]?.stringValue == "function_call")
    #expect(input[1]["name"]?.stringValue == "tool_search")
    #expect(input[2]["type"]?.stringValue == "function_call_output")
    #expect(input[2]["output"]?.stringValue == #"{"tools":[]}"#)
}

@Test func providerGroupBOpenAIResponsesPreservesScalarToolResultCacheBreakpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.languageModel("gpt-4o").generate(LanguageModelRequest(messages: [
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "call_1",
                toolName: "lookup",
                result: ["type": "json", "value": ["stable": true]],
                providerMetadata: ["openai": ["promptCacheBreakpoint": ["mode": "explicit"]]]
            )
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let output = try #require(body["input"]?[0]?["output"]?.arrayValue)
    #expect(output == [[
        "type": "input_text",
        "text": #"{"stable":true}"#,
        "prompt_cache_breakpoint": ["mode": "explicit"]
    ]])
}

@Test func providerGroupBOpenAIResponsesPreservesParallelResultCacheBreakpoints() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-next","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.languageModel("gpt-5.4").generate(LanguageModelRequest(
        messages: [
            .user("Plan both cities"),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(
                    id: "call_parallel_0",
                    name: "weather",
                    arguments: #"{"location":"San Francisco"}"#,
                    providerMetadata: providerGroupBParallelMetadata(index: 0)
                )),
                .toolCall(AIToolCall(
                    id: "call_parallel_1",
                    name: "cityAttractions",
                    arguments: #"{"city":"Rome"}"#,
                    providerMetadata: providerGroupBParallelMetadata(index: 1)
                ))
            ]),
            .toolResponses(toolResults: [
                AIToolResult(
                    toolCallID: "call_parallel_0",
                    toolName: "weather",
                    result: ["temperature": 72],
                    providerMetadata: providerGroupBParallelMetadata(index: 0, cacheBreakpoint: true)
                ),
                AIToolResult(
                    toolCallID: "call_parallel_1",
                    toolName: "cityAttractions",
                    result: "Colosseum",
                    providerMetadata: providerGroupBParallelMetadata(index: 1, cacheBreakpoint: true)
                )
            ])
        ],
        tools: [
            "weather": ["type": "object"],
            "cityAttractions": ["type": "object"]
        ],
        providerOptions: ["openai": ["previousResponseId": "resp_parallel", "store": true]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let output = try #require(body["input"]?.arrayValue?.first {
        $0["type"]?.stringValue == "function_call_output"
    }?["output"]?.arrayValue)
    #expect(output == [
        [
            "type": "input_text",
            "text": #"{"temperature":72}"#,
            "prompt_cache_breakpoint": ["mode": "explicit"]
        ],
        [
            "type": "input_text",
            "text": "\nColosseum",
            "prompt_cache_breakpoint": ["mode": "explicit"]
        ]
    ])
}

@Test func providerGroupBOpenAIResponsesSignalsMalformedKnownStreamEvents() async throws {
    let functionCall: JSONValue = [
        "id": "fc_1",
        "type": "function_call",
        "name": "get_weather",
        "call_id": "call_1",
        "arguments": #"{"city":"Berlin"}"#,
        "status": "completed"
    ]
    let chunks: [JSONValue] = [
        [
            "type": "response.created",
            "response": ["id": "response_1", "created_at": 1, "model": "gpt-5.1"]
        ],
        [
            "type": "response.output_item.added",
            "item": [
                "id": "fc_1", "type": "function_call", "name": "get_weather",
                "call_id": "call_1", "arguments": "", "status": "in_progress"
            ]
        ],
        [
            "type": "response.function_call_arguments.delta",
            "item_id": "fc_1", "delta": #"{"city":"Berlin"}"#
        ],
        [
            "type": "response.function_call_arguments.done",
            "item_id": "fc_1", "arguments": #"{"city":"Berlin"}"#
        ],
        ["type": "response.output_item.done", "item": functionCall],
        [
            "type": "response.completed",
            "response": [
                "incomplete_details": .null,
                "output": [functionCall],
                "usage": ["input_tokens": 1, "output_tokens": 2]
            ]
        ]
    ]
    let data = try chunks.map {
        "data: \(String(data: try encodeJSONBody($0), encoding: .utf8) ?? "")\n\n"
    }.joined()
    let transport = RecordingTransport(response: sseResponse(data))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    var errors: [String] = []
    var finishReason: String?
    for try await part in try provider.languageModel("gpt-5.1").stream(
        LanguageModelRequest(messages: [.user("Hello")])
    ) {
        switch part {
        case let .error(message, _): errors.append(message)
        case let .finishMetadata(reason, _, _): finishReason = reason
        default: break
        }
    }

    #expect(errors == Array(repeating: "Known response chunk failed schema validation", count: 4))
    #expect(finishReason == "error")
}

@Test func providerGroupBOpenResponsesNormalizesFailedStreamEvent() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"type":"response.failed","response":{"id":"resp_failed","status":"failed","error":{"type":"server_error","code":"upstream_failure","message":"provider failed"}}}
    """#))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )

    var errorMessage: String?
    var errorType: String?
    var finishReason: String?
    for try await part in try provider.languageModel("local-model").stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .error(message, rawValue):
            errorMessage = message
            errorType = rawValue?["type"]?.stringValue
        case let .finishMetadata(reason, _, _):
            finishReason = reason
        default: break
        }
    }

    #expect(errorMessage == "provider failed")
    #expect(errorType == "response.failed")
    #expect(finishReason == "error")
}

@Test func providerGroupBXAIWebSearchResultOmitsNullsAndFiltersSources() throws {
    let result = openAIResponsesWebSearchResult(from: [
        "type": "search",
        "query": .null,
        "sources": [
            ["type": "url", "url": "https://example.com", "title": "ignored"],
            ["type": "api", "name": "finance"]
        ]
    ], providerID: "xai.responses")

    #expect(result == [
        "action": ["type": "search"],
        "sources": [["type": "url", "url": "https://example.com"]]
    ])
}

@Test func providerGroupBXAIVideoEncodesRequestIDAsOnePathSegment() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":".."}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    _ = try await provider.videoModel("grok-2-video").generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["xai": ["pollIntervalMs": 1]]
    ))

    let requests = await transport.requests()
    #expect(requests[1].url.absoluteString == "https://api.x.ai/v1/videos/%252E%252E")
}

@Test func providerGroupBAzureDeepSeekKeepsPenaltySampling() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.azure(settings: ProviderSettings(
        apiKey: "azure-key",
        baseURL: "https://resource.openai.azure.com/openai/v1",
        transport: transport
    ))

    _ = try await provider.deepseek("deepseek-r1").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        presencePenalty: 0.25,
        frequencyPenalty: 0.5
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["presence_penalty"]?.doubleValue == 0.25)
    #expect(body["frequency_penalty"]?.doubleValue == 0.5)
}

@Test func providerGroupBGatewayBatchMapsWebhookURLToCallbackURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"batchId":"job_1","status":"pending"}"#))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try #require(try provider.languageModel("openai/gpt-4.1-mini") as? any BatchLanguageModel)

    _ = try await model.startBatch(AIBatchStartOptions(
        requests: [
            AILanguageModelBatchRequest(
                id: "request_1",
                request: LanguageModelRequest(messages: [.user("Hello")])
            )
        ],
        webhookURL: "https://example.com/batch-complete"
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["callbackUrl"]?.stringValue == "https://example.com/batch-complete")
}

@Test func providerGroupBGatewayBatchOmitsInvalidNormalizedRequestCounts() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"status":"pending","requestCounts":{"total":3,"pending":2,"completed":2,"failed":0}}"#),
        jsonResponse(#"{"status":"pending","requestCounts":{"total":3,"pending":-1,"completed":3,"failed":1}}"#),
        jsonResponse(#"{"status":"completed","requestCounts":{"total":3,"pending":0,"completed":2,"failed":1}}"#)
    ])
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try #require(try provider.languageModel("openai/gpt-4.1-mini") as? any BatchLanguageModel)

    let inconsistent = try await model.getBatchStatus(AIBatchOperationOptions(batchID: "inconsistent"))
    let negative = try await model.getBatchStatus(AIBatchOperationOptions(batchID: "negative"))
    let valid = try await model.getBatchStatus(AIBatchOperationOptions(batchID: "valid"))

    #expect(inconsistent.requestCounts == nil)
    #expect(negative.requestCounts == nil)
    #expect(valid.requestCounts == AIBatchRequestCounts(total: 3, pending: 0, completed: 2, failed: 1))
}

@Test func providerGroupBXAIResponsesBatchUploadsPaginatesAndConvertsResults() async throws {
    let completedBatch = #"""
    {
      "batch_id":"batch_123",
      "create_time":"2026-08-25T12:00:00Z",
      "expire_time":"2099-08-26T12:00:00Z",
      "cancel_time":null,
      "cancel_by_xai_message":null,
      "state":{"num_requests":3,"num_pending":0,"num_success":1,"num_error":1,"num_cancelled":1}
    }
    """#
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"file_123","filename":"batch.jsonl"}"#),
        jsonResponse(#"""
        {
          "batch_id":"batch_123",
          "create_time":"2026-08-25T12:00:00Z",
          "expire_time":"2099-08-26T12:00:00Z",
          "state":{"num_requests":2,"num_pending":2,"num_success":0,"num_error":0,"num_cancelled":0}
        }
        """#),
        jsonResponse(completedBatch),
        jsonResponse(#"""
        {
          "results":[{
            "batch_request_id":"france",
            "batch_result":{"response":{"chat_get_completion":{
              "id":"response_123",
              "created":1700000000,
              "model":"grok-4.3",
              "choices":[{"message":{"role":"assistant","content":"Paris","reasoning_content":"Reasoning","tool_calls":null},"index":0,"finish_reason":"stop"}],
              "usage":{"prompt_tokens":10,"completion_tokens":3,"total_tokens":14,"prompt_tokens_details":{"cached_tokens":2},"completion_tokens_details":{"reasoning_tokens":1},"cost_in_usd_ticks":123},
              "citations":["https://example.com/source"],
              "service_tier":"default"
            }},"error":{"code":0,"message":""}}
          }],
          "pagination_token":"next/page"
        }
        """#),
        jsonResponse(#"""
        {
          "results":[
            {"batch_request_id":"failed","batch_result":{"error":{"code":3,"message":"Invalid request."}},"error_message":"Invalid request."},
            {"batch_request_id":"cancelled","batch_result":{"error":{"code":1,"message":"Cancelled."}}}
          ],
          "pagination_token":null
        }
        """#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try #require(try provider.languageModel("grok-4.3") as? any BatchLanguageModel)

    let started = try await model.startBatch(AIBatchStartOptions(
        requests: [
            AILanguageModelBatchRequest(id: "france", request: LanguageModelRequest(messages: [.user("Capital of France?")])),
            AILanguageModelBatchRequest(id: "germany", request: LanguageModelRequest(messages: [.user("Capital of Germany?")], topK: 10))
        ],
        webhookURL: "https://example.com/hook"
    ))
    #expect(started.batchID == "batch_123")
    #expect(started.status.status == .pending)
    #expect(started.warnings.contains { $0.requestID == nil && $0.warning.feature == "webhookUrl" })
    #expect(started.warnings.contains { $0.requestID == "germany" && $0.warning.feature == "topK" })

    let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: "batch_123"))
    var results: [AIBatchItemResult<TextGenerationResult>] = []
    for try await result in stream { results.append(result) }
    #expect(results.count == 3)
    guard case let .succeeded(id, generation) = results[0] else {
        Issue.record("Expected successful xAI batch item")
        return
    }
    #expect(id == "france")
    #expect(generation.text == "Paris")
    #expect(generation.reasoning == "Reasoning")
    #expect(generation.sources.first?.url == "https://example.com/source")
    #expect(generation.providerMetadata["xai"]?["costInUsdTicks"]?.intValue == 123)
    #expect(generation.providerMetadata["xai"]?["serviceTier"]?.stringValue == "default")
    #expect(generation.usage?.rawValue?["cost_in_usd_ticks"]?.intValue == 123)
    guard case let .failed(failedID, error, _) = results[1] else {
        Issue.record("Expected failed xAI batch item")
        return
    }
    #expect(failedID == "failed")
    #expect(error == AIBatchError(message: "Invalid request.", code: "3"))
    guard case let .cancelled(cancelledID, cancelledError, _) = results[2] else {
        Issue.record("Expected cancelled xAI batch item")
        return
    }
    #expect(cancelledID == "cancelled")
    #expect(cancelledError == AIBatchError(message: "Cancelled.", code: "1"))

    let requests = await transport.requests()
    #expect(requests.map(\.url.absoluteString) == [
        "https://api.x.ai/v1/files",
        "https://api.x.ai/v1/batches",
        "https://api.x.ai/v1/batches/batch_123",
        "https://api.x.ai/v1/batches/batch_123/results?limit=1000",
        "https://api.x.ai/v1/batches/batch_123/results?limit=1000&pagination_token=next%2Fpage"
    ])
    let uploadBody = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(uploadBody.contains(#"name="file"; filename="batch.jsonl""#))
    #expect(uploadBody.contains(#""custom_id":"france""#))
    #expect(!uploadBody.contains(#"name="purpose""#))
    let createBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(createBody == ["name": "ai-sdk-text-batch", "input_file_id": "file_123"])
}

@Test func providerGroupBXAIResponsesBatchConvertsChatLevelErrorsPerItem() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"batch_id":"batch_error","state":{"num_requests":2,"num_pending":0,"num_success":2,"num_error":0,"num_cancelled":0}}"#),
        jsonResponse(#"""
        {
          "results":[
            {
              "batch_request_id":"chat-error",
              "batch_result":{"response":{"chat_get_completion":{"error":"Model overloaded.","code":"overloaded"}}}
            },
            {
              "batch_request_id":"valid",
              "batch_result":{"response":{"chat_get_completion":{
                "choices":[{"message":{"role":"assistant","content":"Berlin","reasoning_content":null,"tool_calls":null},"index":0,"finish_reason":"stop"}],
                "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}
              }}}
            }
          ],
          "pagination_token":null
        }
        """#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try #require(try provider.languageModel("grok-4.3") as? any BatchLanguageModel)

    let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: ".."))
    var results: [AIBatchItemResult<TextGenerationResult>] = []
    for try await result in stream { results.append(result) }

    guard case let .failed(id, error, _) = results[0] else {
        Issue.record("Expected chat-level xAI batch error")
        return
    }
    #expect(id == "chat-error")
    #expect(error == AIBatchError(message: "Model overloaded.", code: "overloaded"))
    guard case let .succeeded(validID, valid) = results[1] else {
        Issue.record("Expected later xAI batch result to succeed")
        return
    }
    #expect(validID == "valid")
    #expect(valid.text == "Berlin")
    #expect(await transport.requests().map(\.url.absoluteString) == [
        "https://api.x.ai/v1/batches/%252E%252E",
        "https://api.x.ai/v1/batches/%252E%252E/results?limit=1000"
    ])
}

@Test func providerGroupBXAIResponsesBatchKeepsMalformedResponseItemLocal() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"batch_id":"batch_invalid","state":{"num_requests":2,"num_pending":0,"num_success":2,"num_error":0,"num_cancelled":0}}"#),
        jsonResponse(#"""
        {
          "results":[
            {
              "batch_request_id":"invalid",
              "batch_result":{"response":{"chat_get_completion":{
                "choices":[{"message":{"role":"assistant","content":"Bad"},"index":"zero","finish_reason":"stop"}]
              }}}
            },
            {
              "batch_request_id":"valid",
              "batch_result":{"response":{"chat_get_completion":{
                "choices":[{"message":{"role":"assistant","content":"Berlin","reasoning_content":null,"tool_calls":null},"index":0,"finish_reason":"stop"}],
                "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}
              }}}
            }
          ],
          "pagination_token":null
        }
        """#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try #require(try provider.languageModel("grok-4.3") as? any BatchLanguageModel)

    let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: "batch_invalid"))
    var results: [AIBatchItemResult<TextGenerationResult>] = []
    for try await result in stream { results.append(result) }

    guard case let .failed(invalidID, invalidError, _) = results[0] else {
        Issue.record("Expected malformed xAI response to fail locally")
        return
    }
    #expect(invalidID == "invalid")
    #expect(invalidError == AIBatchError(
        message: "xAI returned an invalid Responses batch result.",
        code: "invalid_response"
    ))
    guard case let .succeeded(validID, valid) = results[1] else {
        Issue.record("Expected later xAI batch result to succeed")
        return
    }
    #expect(validID == "valid")
    #expect(valid.text == "Berlin")
}
