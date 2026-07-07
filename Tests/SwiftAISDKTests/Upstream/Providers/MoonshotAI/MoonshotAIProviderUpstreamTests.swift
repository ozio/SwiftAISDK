import Testing
@testable import SwiftAISDK

@Test func moonshotKimiK25SupportsStructuredOutputsLikeUpstream() async throws {
    let schema: JSONValue = [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": [
            "answer": ["type": "string"]
        ],
        "required": ["answer"],
        "additionalProperties": false
    ]

    let structuredTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"answer\\":\\"moon\\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
    """))
    let structuredProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: structuredTransport))
    let structuredModel = try structuredProvider.languageModel("kimi-k2.5")
    _ = try await structuredModel.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: schema, name: "response")
    ))

    let structuredBody = try decodeJSONBody(try #require((await structuredTransport.requests()).first?.body))
    #expect(structuredBody["response_format"]?["type"]?.stringValue == "json_schema")
    let sentSchema = try #require(structuredBody["response_format"]?["json_schema"]?["schema"])
    #expect(sentSchema["$schema"] == nil)
    #expect(sentSchema["type"]?.stringValue == "object")
    #expect(sentSchema["properties"]?["answer"]?["type"]?.stringValue == "string")

    let legacyTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"{\\"answer\\":\\"moon\\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
    """))
    let legacyProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: legacyTransport))
    let legacyModel = try legacyProvider.languageModel("moonshot-v1-32k")
    _ = try await legacyModel.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: schema, name: "response")
    ))

    let legacyBody = try decodeJSONBody(try #require((await legacyTransport.requests()).first?.body))
    #expect(legacyBody["response_format"] == ["type": "json_object"])
}

@Test func moonshotStructuredOutputSupportMatchesUpstreamModelHelper() {
    #expect(moonshotSupportsStructuredOutputs(modelID: "kimi-k2.5"))
    #expect(moonshotSupportsStructuredOutputs(modelID: "kimi-k2.6"))
    #expect(moonshotSupportsStructuredOutputs(modelID: "kimi-k2.7-code"))
    #expect(moonshotSupportsStructuredOutputs(modelID: "kimi-k2.7-code-highspeed"))
    #expect(!moonshotSupportsStructuredOutputs(modelID: "moonshot-v1-8k"))
    #expect(!moonshotSupportsStructuredOutputs(modelID: "moonshot-v1-32k"))
    #expect(!moonshotSupportsStructuredOutputs(modelID: "moonshot-v1-128k"))
    #expect(!moonshotSupportsStructuredOutputs(modelID: "custom-model-id"))
}
