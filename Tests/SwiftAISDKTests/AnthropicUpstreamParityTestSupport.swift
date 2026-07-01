import Foundation
import Testing
@testable import SwiftAISDK

func anthropicGeneratedBody(
    modelID: String,
    reasoning: String? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    maxOutputTokens: Int? = nil,
    responseFormat: AIResponseFormat? = nil,
    tools: [String: JSONValue] = [:],
    providerOptions: [String: JSONValue] = [:]
) async throws -> (body: JSONValue, warnings: [AIWarning], headers: [String: String]) {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel(modelID)

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: temperature,
        topP: topP,
        topK: topK,
        maxOutputTokens: maxOutputTokens,
        responseFormat: responseFormat,
        reasoning: reasoning,
        tools: tools,
        providerOptions: providerOptions
    ))

    let request = try #require(await transport.requests().first)
    return (try decodeJSONBody(try #require(request.body)), result.warnings, request.headers)
}
