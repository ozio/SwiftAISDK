import Foundation
import Testing
@testable import SwiftAISDK

@Test func moonshotLanguageTransformsThinkingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"moon"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":80,"cached_tokens":30,"completion_tokens_details":{"reasoning_tokens":20}}}
    """))
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
    let model = try provider.languageModel("kimi-k2-thinking")

    #expect(model.providerID == "moonshotai.chat")
    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: [
            "moonshotai": [
                "thinking": .object(["type": "enabled", "budgetTokens": 1024, "extra": "drop-me"]),
                "reasoningHistory": .string("preserved"),
                "extraProviderOption": .string("drop-me")
            ]
        ],
        extraBody: [
            "thinking": .object(["type": "disabled"]),
            "moonshotai": .object([
                "extraRaw": .string("keep-me"),
                "thinking": .object(["type": "disabled", "budgetTokens": 2048]),
                "reasoningHistory": .string("interleaved")
            ])
        ]
    ))

    #expect(result.text == "moon")
    #expect(result.usage?.inputTokens == 100)
    #expect(result.usage?.outputTokens == 80)
    #expect(result.usage?.totalTokens == 180)
    #expect(result.usage?.inputTokensNoCache == 70)
    #expect(result.usage?.inputTokensCacheRead == 30)
    #expect(result.usage?.inputTokensCacheWrite == nil)
    #expect(result.usage?.outputTextTokens == 60)
    #expect(result.usage?.outputReasoningTokens == 20)
    #expect(result.usage?.rawValue?["cached_tokens"]?.intValue == 30)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.moonshot.ai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer moonshot-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["moonshotai"] == nil)
    #expect(body["extraRaw"]?.stringValue == "keep-me")
    #expect(body["extraProviderOption"] == nil)
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 1024)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["thinking"]?["extra"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "preserved")
    #expect(body["reasoningHistory"] == nil)
}

@Test func moonshotLanguageHandlesThinkingWithoutBudgetTokens() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"moon"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
    """))
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
    let model = try provider.languageModel("kimi-k2-thinking")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["moonshotAI": ["thinking": ["type": "enabled"]]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"] == nil)
}

@Test func moonshotLanguageProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: RecordingTransport(response: jsonResponse("{}"))))
    let model = try provider.languageModel("kimi-k2-thinking")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai", message: "MoonshotAI provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai.thinking", message: "MoonshotAI thinking must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": ["thinking": .null]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai.thinking.type", message: "MoonshotAI thinking.type must be enabled or disabled.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": ["thinking": ["type": "auto"]]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai.thinking.budgetTokens", message: "MoonshotAI thinking.budgetTokens must be an integer greater than or equal to 1024.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": ["thinking": ["budgetTokens": 1023]]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai.thinking.budgetTokens", message: "MoonshotAI thinking.budgetTokens must be an integer greater than or equal to 1024.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": ["thinking": ["budgetTokens": 1024.5]]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.moonshotai.reasoningHistory", message: "MoonshotAI reasoningHistory must be disabled, interleaved, or preserved.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["moonshotai": ["reasoningHistory": "auto"]]))
    }
}

@Test func moonshotLanguageStreamsUsageWithoutTotalTokens() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"moon"},"finish_reason":null}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":4,"cached_tokens":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
    let model = try provider.languageModel("kimi-k2-thinking")

    var text: [String] = []
    var lifecycle: [String] = []
    var finishReason: String?
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["moonshotAI": ["reasoningHistory": "disabled"]]
    )) {
        switch part {
        case let .streamStart(warnings):
            #expect(warnings == [])
        case let .textStart(id, _):
            lifecycle.append("start:\(id)")
        case let .textDelta(delta):
            text.append(delta)
        case let .textDeltaPart(id, delta, _):
            lifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .finish(reason, finalUsage):
            finishReason = reason
            usage = finalUsage
        default:
            break
        }
    }

    #expect(text == ["moon"])
    #expect(lifecycle == ["start:txt-0", "delta:txt-0:moon", "end:txt-0"])
    #expect(finishReason == "stop")
    #expect(usage?.inputTokens == 3)
    #expect(usage?.outputTokens == 4)
    #expect(usage?.totalTokens == 7)
    #expect(usage?.inputTokensNoCache == 2)
    #expect(usage?.inputTokensCacheRead == 1)
    #expect(usage?.outputTextTokens == 4)
    #expect(usage?.outputReasoningTokens == 0)
    #expect(usage?.rawValue?["cached_tokens"]?.intValue == 1)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream_options"]?["include_usage"]?.boolValue == true)
    #expect(body["moonshotAI"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "disabled")
}

@Test func moonshotLanguageConvertsUsageVariantsLikeUpstream() async throws {
    let cases: [(String, String, Int, Int, Int, Int, Int, Int)] = [
        (#"{"prompt_tokens":100,"completion_tokens":50}"#, "basic", 100, 50, 100, 0, 50, 0),
        (#"{"prompt_tokens":100,"completion_tokens":50,"cached_tokens":30}"#, "top-cache", 100, 50, 70, 30, 50, 0),
        (#"{"prompt_tokens":100,"completion_tokens":50,"prompt_tokens_details":{"cached_tokens":25}}"#, "nested-cache", 100, 50, 75, 25, 50, 0),
        (#"{"prompt_tokens":100,"completion_tokens":50,"cached_tokens":40,"prompt_tokens_details":{"cached_tokens":25}}"#, "top-cache-wins", 100, 50, 60, 40, 50, 0),
        (#"{"prompt_tokens":100,"completion_tokens":80,"completion_tokens_details":{"reasoning_tokens":30}}"#, "reasoning", 100, 80, 100, 0, 50, 30),
        (#"{"prompt_tokens":null,"completion_tokens":null,"cached_tokens":null}"#, "nulls", 0, 0, 0, 0, 0, 0)
    ]

    for (usageJSON, label, inputTokens, outputTokens, inputNoCache, cacheRead, outputText, outputReasoning) in cases {
        let transport = RecordingTransport(response: jsonResponse("""
        {"choices":[{"message":{"content":"\(label)"},"finish_reason":"stop"}],"usage":\(usageJSON)}
        """))
        let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: transport))
        let result = try await provider.languageModel("kimi-k2").generate(LanguageModelRequest(messages: [.user("Hi")]))

        #expect(result.text == label)
        #expect(result.usage?.inputTokens == inputTokens)
        #expect(result.usage?.outputTokens == outputTokens)
        #expect(result.usage?.inputTokensNoCache == inputNoCache)
        #expect(result.usage?.inputTokensCacheRead == cacheRead)
        #expect(result.usage?.outputTextTokens == outputText)
        #expect(result.usage?.outputReasoningTokens == outputReasoning)
    }
}

@Test func moonshotLanguageReturnsEmptyUsageWhenProviderOmitsUsage() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"moon"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: generateTransport))
    let generate = try await generateProvider.languageModel("kimi-k2").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(generate.text == "moon")
    #expect(generate.usage == TokenUsage())

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"moon"},"finish_reason":null}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: streamTransport))
    var finishUsage: TokenUsage?
    let streamModel = try streamProvider.languageModel("kimi-k2")
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finish(_, usage) = part {
            finishUsage = usage
        }
    }

    #expect(finishUsage == TokenUsage())
}

@Test func moonshotProviderRejectsUnsupportedEmbeddingAndImageModels() throws {
    let provider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key"))

    #expect(throws: AIError.unsupportedModel(provider: "moonshotai", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "moonshotai", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}
