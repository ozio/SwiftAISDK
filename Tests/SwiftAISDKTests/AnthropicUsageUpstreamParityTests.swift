import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicUsageUsesTopLevelUsageWhenNoRawUsageLikeUpstream() throws {
    let usage: JSONValue = [
        "input_tokens": 10,
        "output_tokens": 20
    ]

    let result = try #require(anthropicTokenUsage(from: usage))

    #expect(result.inputTokens == 10)
    #expect(result.outputTokens == 20)
    #expect(result.inputTokensNoCache == 10)
    #expect(result.inputTokensCacheRead == 0)
    #expect(result.inputTokensCacheWrite == 0)
    #expect(result.rawValue == usage)
}

@Test func anthropicUsageComputesTokenTotalsWithCacheTokensLikeUpstream() throws {
    let usage: JSONValue = [
        "input_tokens": 10,
        "output_tokens": 20,
        "cache_creation_input_tokens": 5,
        "cache_read_input_tokens": 3
    ]

    let result = try #require(anthropicTokenUsage(from: usage))

    #expect(result.inputTokens == 18)
    #expect(result.inputTokensNoCache == 10)
    #expect(result.inputTokensCacheRead == 3)
    #expect(result.inputTokensCacheWrite == 5)
    #expect(result.outputTokens == 20)
}

@Test func anthropicUsageTreatsNullCacheTokensAsZeroLikeUpstream() throws {
    let usage: JSONValue = [
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_creation_input_tokens": nil,
        "cache_read_input_tokens": nil
    ]

    let result = try #require(anthropicTokenUsage(from: usage))

    #expect(result.inputTokens == 100)
    #expect(result.inputTokensNoCache == 100)
    #expect(result.inputTokensCacheRead == 0)
    #expect(result.inputTokensCacheWrite == 0)
    #expect(result.outputTokens == 50)
}

@Test func anthropicUsageSumsCompactionIterationsLikeUpstream() throws {
    let usage: JSONValue = [
        "input_tokens": 45_000,
        "output_tokens": 1_234,
        "iterations": [
            [
                "type": "compaction",
                "input_tokens": 180_000,
                "output_tokens": 3_500
            ],
            [
                "type": "message",
                "input_tokens": 23_000,
                "output_tokens": 1_000
            ]
        ]
    ]

    let result = try #require(anthropicTokenUsage(from: usage))

    #expect(result.inputTokens == 203_000)
    #expect(result.inputTokensNoCache == 203_000)
    #expect(result.outputTokens == 4_500)
    #expect(result.rawValue == usage)
}

@Test func anthropicUsageCombinesIterationsWithTopLevelCacheTokensLikeUpstream() throws {
    let usage: JSONValue = [
        "input_tokens": 45_000,
        "output_tokens": 1_234,
        "cache_creation_input_tokens": 1_000,
        "cache_read_input_tokens": 500,
        "iterations": [
            [
                "type": "compaction",
                "input_tokens": 180_000,
                "output_tokens": 3_500
            ],
            [
                "type": "message",
                "input_tokens": 23_000,
                "output_tokens": 1_000
            ]
        ]
    ]

    let result = try #require(anthropicTokenUsage(from: usage))

    #expect(result.inputTokensNoCache == 203_000)
    #expect(result.inputTokensCacheWrite == 1_000)
    #expect(result.inputTokensCacheRead == 500)
    #expect(result.inputTokens == 204_500)
    #expect(result.outputTokens == 4_500)
}

@Test func anthropicGenerateTextUsageAndResponseMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id": "test-id",
      "type": "message",
      "role": "assistant",
      "content": [{"type": "text", "text": "Hello, World!"}],
      "model": "test-model",
      "stop_reason": "stop_sequence",
      "stop_sequence": "STOP",
      "usage": {"input_tokens": 20, "output_tokens": 5}
    }
    """, headers: ["test-header": "test-value"]))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        stopSequences: ["STOP"]
    ))

    #expect(result.text == "Hello, World!")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokensNoCache == 20)
    #expect(result.usage?.inputTokensCacheRead == 0)
    #expect(result.usage?.inputTokensCacheWrite == 0)
    #expect(result.usage?.inputTokens == 20)
    #expect(result.usage?.outputTokens == 5)
    #expect(result.responseMetadata.id == "test-id")
    #expect(result.responseMetadata.modelID == "test-model")
    #expect(result.responseMetadata.headers["test-header"] == "test-value")
    #expect(result.responseMetadata.body?["id"]?.stringValue == "test-id")
    #expect(result.responseMetadata.body?["usage"]?["input_tokens"]?.intValue == 20)
    #expect(result.providerMetadata["anthropic"]?["stopSequence"]?.stringValue == "STOP")
    #expect(result.providerMetadata["anthropic"]?["usage"]?["output_tokens"]?.intValue == 5)
}
