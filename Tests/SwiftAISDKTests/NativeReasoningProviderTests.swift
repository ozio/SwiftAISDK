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
        extraBody: [
            "thinking": .object(["type": "disabled"]),
            "moonshotai": .object([
                "thinking": .object(["type": "enabled", "budgetTokens": 1024]),
                "reasoningHistory": .string("preserved")
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
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["budget_tokens"]?.intValue == 1024)
    #expect(body["thinking"]?["budgetTokens"] == nil)
    #expect(body["reasoning_history"]?.stringValue == "preserved")
    #expect(body["reasoningHistory"] == nil)
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
        extraBody: ["moonshotAI": ["reasoningHistory": "disabled"]]
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
