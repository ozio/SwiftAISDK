import Foundation
import Testing
@testable import SwiftAISDK

@Suite("ProviderEvaluationAdaptersTests")
struct ProviderEvaluationAdaptersTests {
    @Test func anthropicEvaluationUsesMessagesStructuredOutputAndForwardsOptions() async throws {
        let transport = RecordingTransport(response: jsonResponse("""
        {"id":"msg_eval","content":[{"type":"text","text":"{\\"q0\\":0.8}"}],"stop_reason":"end_turn","usage":{"input_tokens":20,"output_tokens":4}}
        """))
        let provider = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "key",
            transport: transport,
            name: "custom.messages"
        ))
        let controller = AIAbortController()
        let result = try await provider.evaluationModel("claude-sonnet-4-6").doEvaluate(
            AIEvaluationModelV4CallOptions(
                state: ["answer": "yes"],
                questions: ["correct": .boolean(instructions: "Is it correct?")],
                abortSignal: controller.signal,
                headers: ["x-test": "anthropic"],
                providerOptions: ["anthropic": ["effort": "high"]]
            )
        )

        #expect(result.answers == ["correct": .boolean(probability: 0.8)])
        #expect(result.usage == AIEvaluationModelUsage(inputTokens: 20, outputTokens: 4))
        let request = try #require(await transport.requests().first)
        #expect(request.abortSignal === controller.signal)
        #expect(request.headers["x-test"] == "anthropic")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["model"] == "claude-sonnet-4-6")
        #expect(body["thinking"]?["type"] == nil)
        #expect(body["output_config"]?["format"]?["type"] == "json_schema")
        #expect(body["output_config"]?["format"]?["schema"]?["required"] == ["q0"])
        #expect(body["output_config"]?["effort"] == "high")
    }

    @Test func googleEvaluationUsesGeminiStructuredOutputAndForwardsOptions() async throws {
        let transport = RecordingTransport(response: jsonResponse("""
        {"responseId":"google-eval","candidates":[{"content":{"parts":[{"text":"{\\"q0\\":0.25}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":3,"totalTokenCount":15}}
        """))
        let provider = try AIProviders.google(settings: ProviderSettings(
            apiKey: "key",
            transport: transport,
            name: "custom.generative-ai"
        ))
        let controller = AIAbortController()
        let result = try await provider.evaluationModel("gemini-3.6-flash").doEvaluate(
            AIEvaluationModelV4CallOptions(
                state: ["answer": "maybe"],
                questions: ["correct": .boolean(instructions: "Is it correct?")],
                abortSignal: controller.signal,
                headers: ["x-test": "google"],
                providerOptions: ["google": ["thinkingConfig": ["thinkingLevel": "low"]]]
            )
        )

        #expect(result.answers == ["correct": .boolean(probability: 0.25)])
        #expect(result.usage == AIEvaluationModelUsage(inputTokens: 12, outputTokens: 3))
        #expect(result.response?.id == "google-eval")
        let request = try #require(await transport.requests().first)
        #expect(request.abortSignal === controller.signal)
        #expect(request.headers["x-test"] == "google")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["generationConfig"]?["responseMimeType"] == "application/json")
        #expect(body["generationConfig"]?["responseJsonSchema"]?["required"] == ["q0"])
        #expect(body["generationConfig"]?["thinkingConfig"]?["thinkingLevel"] == "low")
    }
}
