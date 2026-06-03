import Foundation
import Testing
@testable import SwiftAISDK

@Test func xAIChatProviderOptionsValidateAndMapLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.chat("grok-4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 3,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 42,
        maxOutputTokens: 12,
        stopSequences: ["stop"],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["answer": ["type": "string"]],
                "required": ["answer"]
            ],
            name: "answer"
        ),
        providerOptions: [
            "xai": [
                "reasoningEffort": "high",
                "logprobs": false,
                "topLogprobs": 3,
                "parallel_function_calling": false,
                "searchParameters": [
                    "mode": "on",
                    "returnCitations": true,
                    "fromDate": "2024-01-01",
                    "toDate": "2024-12-31",
                    "maxSearchResults": 10,
                    "sources": [
                        [
                            "type": "web",
                            "country": "US",
                            "excludedWebsites": ["example.com"],
                            "allowedWebsites": ["x.ai"],
                            "safeSearch": false,
                            "unknown": "drop-me"
                        ],
                        [
                            "type": "x",
                            "includedXHandles": ["grok"],
                            "excludedXHandles": ["openai"],
                            "postFavoriteCount": 5,
                            "postViewCount": 50
                        ],
                        [
                            "type": "news",
                            "country": "GB"
                        ],
                        [
                            "type": "rss",
                            "links": ["https://status.x.ai/feed.xml"]
                        ]
                    ],
                    "unknown": "drop-me"
                ],
                "unknown": "drop-me"
            ]
        ],
        extraBody: [
            "xai": [
                "reasoningEffort": "low",
                "topLogprobs": 1,
                "customRaw": "kept"
            ]
        ]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "topK"),
        AIWarning(type: "unsupported", feature: "frequencyPenalty"),
        AIWarning(type: "unsupported", feature: "presencePenalty"),
        AIWarning(type: "unsupported", feature: "stopSequences")
    ])

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "grok-4")
    #expect(body["max_completion_tokens"]?.intValue == 12)
    #expect(body["max_tokens"] == nil)
    #expect(body["stop"] == nil)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["reasoning_effort"]?.stringValue == "high")
    #expect(body["top_logprobs"]?.intValue == 3)
    #expect(body["logprobs"]?.boolValue == true)
    #expect(body["parallel_function_calling"]?.boolValue == false)
    #expect(body["customRaw"]?.stringValue == "kept")
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
    #expect(body["search_parameters"]?["mode"]?.stringValue == "on")
    #expect(body["search_parameters"]?["return_citations"]?.boolValue == true)
    #expect(body["search_parameters"]?["from_date"]?.stringValue == "2024-01-01")
    #expect(body["search_parameters"]?["to_date"]?.stringValue == "2024-12-31")
    #expect(body["search_parameters"]?["max_search_results"]?.intValue == 10)
    #expect(body["search_parameters"]?["sources"]?[0]?["excluded_websites"]?[0]?.stringValue == "example.com")
    #expect(body["search_parameters"]?["sources"]?[0]?["allowed_websites"]?[0]?.stringValue == "x.ai")
    #expect(body["search_parameters"]?["sources"]?[0]?["safe_search"]?.boolValue == false)
    #expect(body["search_parameters"]?["sources"]?[1]?["included_x_handles"]?[0]?.stringValue == "grok")
    #expect(body["search_parameters"]?["sources"]?[1]?["excluded_x_handles"]?[0]?.stringValue == "openai")
    #expect(body["search_parameters"]?["sources"]?[1]?["post_favorite_count"]?.intValue == 5)
    #expect(body["search_parameters"]?["sources"]?[1]?["post_view_count"]?.intValue == 50)
    #expect(body["search_parameters"]?["sources"]?[2]?["country"]?.stringValue == "GB")
    #expect(body["search_parameters"]?["sources"]?[3]?["links"]?[0]?.stringValue == "https://status.x.ai/feed.xml")
    #expect(body["reasoningEffort"] == nil)
    #expect(body["topLogprobs"] == nil)
    #expect(body["searchParameters"] == nil)
    #expect(body["xai"] == nil)
}

@Test func xAIChatProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))
    let model = try provider.chat("grok-4")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI chat provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": "bad"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.reasoningEffort", message: "xAI reasoningEffort must be low or high.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["reasoningEffort": "minimal"]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.topLogprobs", message: "xAI topLogprobs must be an integer from 0 to 8.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["topLogprobs": 9]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.mode", message: "xAI searchParameters.mode must be off, auto, or on.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["searchParameters": ["mode": "always"]]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.searchParameters.sources.country", message: "xAI source country must be a two-letter string.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["searchParameters": ["mode": "auto", "sources": [["type": "web", "country": "USA"]]]]]
        ))
    }
}

@Test func xAIChatProviderOptionsNullNamespaceAndLogprobsMatchUpstream() async throws {
    let nullNamespaceTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: nullNamespaceTransport))
    let model = try provider.chat("grok-4")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        reasoning: "xhigh",
        providerOptions: ["xai": .null],
        extraBody: ["xai": ["topLogprobs": 2]]
    ))

    let nullNamespaceBody = try decodeJSONBody(try #require((await nullNamespaceTransport.requests()).first?.body))
    #expect(nullNamespaceBody["top_logprobs"]?.intValue == 2)
    #expect(nullNamespaceBody["logprobs"]?.boolValue == true)
    #expect(nullNamespaceBody["reasoning_effort"]?.stringValue == "high")

    let logprobsFalseTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}]}"#))
    let logprobsFalseProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: logprobsFalseTransport))
    let logprobsFalseModel = try logprobsFalseProvider.chat("grok-4")

    _ = try await logprobsFalseModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["xai": ["logprobs": false]]
    ))

    let logprobsFalseBody = try decodeJSONBody(try #require((await logprobsFalseTransport.requests()).first?.body))
    #expect(logprobsFalseBody["logprobs"] == nil)
}

@Test func xAIChatUsageCountsReasoningAndCacheTokensLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}],
      "usage":{
        "prompt_tokens":12,
        "completion_tokens":2,
        "total_tokens":438,
        "prompt_tokens_details":{"text_tokens":12,"audio_tokens":0,"image_tokens":0,"cached_tokens":3},
        "completion_tokens_details":{"reasoning_tokens":424}
      }
    }
    """#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.chat("grok-4")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.usage?.inputTokens == 12)
    #expect(result.usage?.inputTokensNoCache == 9)
    #expect(result.usage?.inputTokensCacheRead == 3)
    #expect(result.usage?.outputTokens == 426)
    #expect(result.usage?.outputTextTokens == 2)
    #expect(result.usage?.outputReasoningTokens == 424)
    #expect(result.usage?.totalTokens == 438)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"xai"},"finish_reason":null}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":4142,"completion_tokens":254,"total_tokens":8724,"prompt_tokens_details":{"cached_tokens":4328}}}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: streamTransport))
    let streamModel = try streamProvider.chat("grok-4")

    var finishUsage: TokenUsage?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finish(_, usage) = part {
            finishUsage = usage
        }
    }

    #expect(finishUsage?.inputTokens == 8_470)
    #expect(finishUsage?.inputTokensNoCache == 4_142)
    #expect(finishUsage?.inputTokensCacheRead == 4_328)
    #expect(finishUsage?.outputTokens == 254)
    #expect(finishUsage?.outputTextTokens == 254)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 8_724)
}

@Test func xAIChatConvertsProviderReferenceFilePartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.chat("grok-4")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Read this file"),
            .providerReference(mimeType: "application/pdf", reference: ["xai": "file-pdf456", "openai": "file-openai"])
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["messages"]?[0]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Read this file")
    #expect(body["messages"]?[0]?["content"]?[1]?["type"]?.stringValue == "file")
    #expect(body["messages"]?[0]?["content"]?[1]?["file"]?["file_id"]?.stringValue == "file-pdf456")

    let missingProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))
    let missingModel = try missingProvider.chat("grok-4")
    await #expect(throws: AINoSuchProviderReferenceError(provider: "xai", reference: ["openai": "file-openai"])) {
        _ = try await missingModel.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .providerReference(mimeType: "image/png", reference: ["openai": "file-openai"])
            ])
        ]))
    }
}
