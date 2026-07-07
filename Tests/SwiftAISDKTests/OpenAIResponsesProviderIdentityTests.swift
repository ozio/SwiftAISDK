import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesWarnsForUnsupportedReasoningProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("This is a reasoning part without any provider options"),
                .reasoning("This is a reasoning part without OpenAI-specific reasoning id provider options", providerMetadata: [
                    "openai": [
                        "reasoning": [
                            "encryptedContent": "encrypted_content_001"
                        ]
                    ]
                ]),
                .reasoning("Some reasoning text", providerMetadata: [
                    "openai": [:]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?.arrayValue == [])
    #expect(result.warnings.count == 3)
    #expect(result.warnings.allSatisfy { $0.type == "other" })
    #expect(result.warnings[0].message?.contains("without any provider options") == true)
    #expect(result.warnings[1].message?.contains("without OpenAI-specific reasoning id provider options") == true)
    #expect(result.warnings[2].message?.contains("Some reasoning text") == true)
}

@Test func openAIResponsesIncludesReasoningWithoutIDWhenEncryptedContentIsPresentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            AIMessage(role: .assistant, content: [
                .reasoning("Thinking through the problem", providerMetadata: [
                    "openai": [
                        "reasoningEncryptedContent": "encrypted_reasoning_blob"
                    ]
                ])
            ])
        ],
        extraBody: ["store": false]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let reasoning = try #require(body["input"]?[0])
    #expect(reasoning["type"]?.stringValue == "reasoning")
    #expect(reasoning["id"] == nil)
    #expect(reasoning["encrypted_content"]?.stringValue == "encrypted_reasoning_blob")
    #expect(reasoning["summary"]?[0]?["text"]?.stringValue == "Thinking through the problem")
    #expect(result.warnings.isEmpty)
}

@Test func openAIProviderSettingsMapBaseURLOrganizationAndProject() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"configured","usage":{"total_tokens":2}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "https://proxy.example.com/openai/v1/",
        organization: "org-123",
        project: "proj-456",
        headers: ["OpenAI-Project": "proj-header"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "configured")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://proxy.example.com/openai/v1/responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["openai-organization"] == "org-123")
    #expect(request.headers["openai-project"] == "proj-header")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.8")
}
@Test func openAIProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"responses alias"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"chat alias"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"completion alias","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let languageModel = try provider.languageModel("gpt-5-mini")
    let responsesModel = try provider.responses("gpt-4.1")
    let chatModel = try provider.chat("gpt-4.1-mini")
    let completionModel = try provider.completion("gpt-3.5-turbo-instruct")
    let embeddingModel = try provider.embeddingModel("text-embedding-3-small")
    let imageModel = try provider.imageModel("gpt-image-1")
    let transcriptionModel = try provider.transcriptionModel("gpt-4o-transcribe")
    let speechModel = try provider.speechModel("gpt-4o-mini-tts")
    let files = provider.files()
    let skills = try provider.skills()

    #expect(provider.providerID == "openai")
    #expect(languageModel.providerID == "openai.responses")
    #expect(responsesModel.providerID == "openai.responses")
    #expect(chatModel.providerID == "openai.chat")
    #expect(completionModel.providerID == "openai.completion")
    #expect(embeddingModel.providerID == "openai.embedding")
    #expect(imageModel.providerID == "openai.image")
    #expect(transcriptionModel.providerID == "openai.transcription")
    #expect(speechModel.providerID == "openai.speech")
    #expect(files.providerID == "openai.files")
    #expect(skills.providerID == "openai.skills")

    let responsesResult = try await responsesModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await completionModel.generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "responses alias")
    #expect(chatResult.text == "chat alias")
    #expect(completionResult.text == "completion alias")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(requests[1].url.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(requests[2].url.absoluteString == "https://api.openai.com/v1/completions")
}
@Test func openAIProviderNameOverrideMatchesUpstreamSurfaceIDsAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"named","usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport, name: "branded"))

    let languageModel = try provider.languageModel("gpt-5-mini")
    let responsesModel = try provider.responses("gpt-4.1")
    let chatModel = try provider.chat("gpt-4.1-mini")
    let completionModel = try provider.completion("gpt-3.5-turbo-instruct")
    let embeddingModel = try provider.embeddingModel("text-embedding-3-small")
    let imageModel = try provider.imageModel("gpt-image-1")
    let transcriptionModel = try provider.transcriptionModel("gpt-4o-transcribe")
    let speechModel = try provider.speechModel("gpt-4o-mini-tts")
    let files = provider.files()
    let skills = try provider.skills()

    #expect(provider.providerID == "branded")
    #expect(languageModel.providerID == "branded.responses")
    #expect(responsesModel.providerID == "branded.responses")
    #expect(chatModel.providerID == "branded.chat")
    #expect(completionModel.providerID == "branded.completion")
    #expect(embeddingModel.providerID == "branded.embedding")
    #expect(imageModel.providerID == "branded.image")
    #expect(transcriptionModel.providerID == "branded.transcription")
    #expect(speechModel.providerID == "branded.speech")
    #expect(files.providerID == "branded.files")
    #expect(skills.providerID == "branded.skills")

    let result = try await languageModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "parallelToolCalls": .bool(true)
            ]),
            "branded": .object([
                "previousResponseId": .string("resp-old"),
                "reasoningEffort": .string("low"),
                "parallelToolCalls": .bool(false)
            ]),
            "branded.responses": .object([
                "serviceTier": .string("flex")
            ])
        ]
    ))

    #expect(result.text == "named")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.8")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["openai"] == nil)
    #expect(body["branded"] == nil)
    #expect(body["branded.responses"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["serviceTier"] == nil)
}
@Test func openAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom","usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport,
        name: "branded"
    ))
    let model = try provider.languageModel("gpt-5-mini")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(provider.providerID == "branded")
    #expect(model.providerID == "branded.responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/openai/4.0.8")
}
@Test func openAIResponsesMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "previousResponseId": .string("resp-old"),
                "parallelToolCalls": .bool(false),
                "reasoningEffort": .string("low"),
                "reasoningSummary": .string("auto")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["reasoningSummary"] == nil)
}

