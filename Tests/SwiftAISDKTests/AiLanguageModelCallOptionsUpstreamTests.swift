import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiPrepareLanguageModelCallOptionsPassesThroughValidTypedSettingsLikeUpstream() async throws {
    let request = LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: 0.7,
        topP: 0.9,
        topK: 50,
        presencePenalty: 0.5,
        frequencyPenalty: 0.3,
        seed: 42,
        maxOutputTokens: 100,
        stopSequences: ["stop"],
        reasoning: "high"
    )
    let prepared = try prepareLanguageModelCallOptions(request)

    #expect(prepared.maxOutputTokens == 100)
    #expect(prepared.temperature == 0.7)
    #expect(prepared.topP == 0.9)
    #expect(prepared.topK == 50)
    #expect(prepared.presencePenalty == 0.5)
    #expect(prepared.frequencyPenalty == 0.3)
    #expect(prepared.seed == 42)
    #expect(prepared.stopSequences == ["stop"])
    #expect(prepared.reasoning == "high")

    let model = MockLanguageModel(result: TextGenerationResult(text: "ok", rawValue: .object([:])))
    _ = try await AI.generateText(model: model, request: request, retryPolicy: .none)
    let forwarded = try #require(model.requests.first)
    #expect(forwarded.maxOutputTokens == 100)
    #expect(forwarded.temperature == 0.7)
    #expect(forwarded.topP == 0.9)
    #expect(forwarded.topK == 50)
    #expect(forwarded.presencePenalty == 0.5)
    #expect(forwarded.frequencyPenalty == 0.3)
    #expect(forwarded.seed == 42)
    #expect(forwarded.stopSequences == ["stop"])
    #expect(forwarded.reasoning == "high")
}

@Test func aiPrepareLanguageModelCallOptionsAllowsNilOptionalSettingsLikeUpstream() throws {
    let prepared = try prepareLanguageModelCallOptions(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(prepared.maxOutputTokens == nil)
    #expect(prepared.temperature == nil)
    #expect(prepared.topP == nil)
    #expect(prepared.topK == nil)
    #expect(prepared.presencePenalty == nil)
    #expect(prepared.frequencyPenalty == nil)
    #expect(prepared.seed == nil)
    #expect(prepared.stopSequences.isEmpty)
    #expect(prepared.reasoning == nil)
}

@Test func aiPrepareLanguageModelCallOptionsPassesThroughReasoningValuesLikeUpstream() throws {
    for reasoning in ["none", "minimal", "low", "medium", "high", "xhigh", "provider-default"] {
        let prepared = try prepareLanguageModelCallOptions(LanguageModelRequest(
            messages: [.user("Hello")],
            reasoning: reasoning
        ))
        #expect(prepared.reasoning == reasoning)
    }
}

@Test func aiGenerateTextRejectsMaxOutputTokensLessThanOneLikeUpstream() async {
    let model = MockLanguageModel(result: TextGenerationResult(text: "ok", rawValue: .object([:])))

    await #expect(throws: AIError.invalidArgument(argument: "maxOutputTokens", message: "maxOutputTokens must be >= 1")) {
        _ = try await AI.generateText(
            model: model,
            request: LanguageModelRequest(messages: [.user("Hello")], maxOutputTokens: 0),
            retryPolicy: .none
        )
    }
    #expect(model.requests.isEmpty)
}

@Test func aiStreamTextRejectsMaxOutputTokensLessThanOneLikeUpstream() async {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [.textDelta("ok"), .finish(reason: "stop", usage: nil)]
    )
    let stream = AI.streamText(
        model: model,
        request: LanguageModelRequest(messages: [.user("Hello")], maxOutputTokens: 0),
        retryPolicy: .none
    )

    await #expect(throws: AIError.invalidArgument(argument: "maxOutputTokens", message: "maxOutputTokens must be >= 1")) {
        for try await _ in stream {}
    }
    #expect(model.streamRequests.isEmpty)
}
