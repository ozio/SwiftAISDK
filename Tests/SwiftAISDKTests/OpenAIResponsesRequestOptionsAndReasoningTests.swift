import Foundation
import Testing
@testable import SwiftAISDK

private let openAIResponsesReasoningModelIDsLikeUpstream = [
    "o1",
    "o1-2024-12-17",
    "o3",
    "o3-2025-04-16",
    "o3-mini",
    "o3-mini-2025-01-31",
    "o4-mini",
    "o4-mini-2025-04-16",
    "gpt-5",
    "gpt-5-2025-08-07",
    "gpt-5-codex",
    "gpt-5-mini",
    "gpt-5-mini-2025-08-07",
    "gpt-5-nano",
    "gpt-5-nano-2025-08-07",
    "gpt-5-pro",
    "gpt-5-pro-2025-10-06",
    "gpt-5.1",
    "gpt-5.1-chat-latest",
    "gpt-5.1-codex-mini",
    "gpt-5.1-codex",
    "gpt-5.1-codex-max",
    "gpt-5.2",
    "gpt-5.2-chat-latest",
    "gpt-5.2-pro",
    "gpt-5.2-codex",
    "gpt-5.3-chat-latest",
    "gpt-5.3-codex",
    "gpt-5.4",
    "gpt-5.4-2026-03-05",
    "gpt-5.4-mini",
    "gpt-5.4-mini-2026-03-17",
    "gpt-5.4-nano",
    "gpt-5.4-nano-2026-03-17",
    "gpt-5.4-pro",
    "gpt-5.4-pro-2026-03-05",
    "gpt-5.5",
    "gpt-5.5-2026-04-23"
]

private let openAIResponsesNonReasoningModelIDsLikeUpstream = [
    "gpt-4.1",
    "gpt-4.1-2025-04-14",
    "gpt-4.1-mini",
    "gpt-4.1-mini-2025-04-14",
    "gpt-4.1-nano",
    "gpt-4.1-nano-2025-04-14",
    "gpt-4o",
    "gpt-4o-2024-05-13",
    "gpt-4o-2024-08-06",
    "gpt-4o-2024-11-20",
    "gpt-4o-audio-preview",
    "gpt-4o-audio-preview-2024-12-17",
    "gpt-4o-search-preview",
    "gpt-4o-search-preview-2025-03-11",
    "gpt-4o-mini-search-preview",
    "gpt-4o-mini-search-preview-2025-03-11",
    "gpt-4o-mini",
    "gpt-4o-mini-2024-07-18",
    "gpt-3.5-turbo-0125",
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-1106",
    "gpt-5-chat-latest"
]

@Test func openAIResponsesMapsTypedProviderOptionsAndAutomaticIncludesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools and structured output.")],
        responseFormat: .json(schema: ["type": "object"], name: "answer", description: "Answer schema"),
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]]
            ],
            "web_search": OpenAITools.webSearch(),
            "code_interpreter": OpenAITools.codeInterpreter()
        ],
        providerOptions: [
            "openai": [
                "store": false,
                "logprobs": 3,
                "textVerbosity": "high",
                "strictJsonSchema": false,
                "allowedTools": ["toolNames": ["lookup"], "mode": "required"],
                "promptCacheKey": "cache-key",
                "promptCacheRetention": "24h",
                "safetyIdentifier": "safe-user",
                "conversation": "conv-1",
                "previousResponseId": "resp-old",
                "truncation": "disabled",
                "include": [
                    "reasoning.encrypted_content",
                    "file_search_call.results",
                    "web_search_call.results"
                ]
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "web_search"]]
    ))

    #expect(result.text == "done")
    #expect(result.warnings.contains { $0.feature == "conversation" })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["conversation"]?.stringValue == "conv-1")
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["prompt_cache_key"]?.stringValue == "cache-key")
    #expect(body["prompt_cache_retention"]?.stringValue == "24h")
    #expect(body["safety_identifier"]?.stringValue == "safe-user")
    #expect(body["truncation"]?.stringValue == "disabled")
    #expect(body["top_logprobs"]?.intValue == 3)
    let includeValues = try #require(body["include"]?.arrayValue)
    let include = includeValues.compactMap(\.stringValue)
    #expect(include.contains("message.output_text.logprobs"))
    #expect(include.contains("web_search_call.action.sources"))
    #expect(include.contains("web_search_call.results"))
    #expect(include.contains("file_search_call.results"))
    #expect(include.contains("code_interpreter_call.outputs"))
    #expect(include.contains("reasoning.encrypted_content"))
    #expect(body["text"]?["verbosity"]?.stringValue == "high")
    #expect(body["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(body["text"]?["format"]?["name"]?.stringValue == "answer")
    #expect(body["text"]?["format"]?["description"]?.stringValue == "Answer schema")
    #expect(body["text"]?["format"]?["strict"]?.boolValue == false)
    #expect(body["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(body["tool_choice"]?["mode"]?.stringValue == "required")
    #expect(body["tool_choice"]?["tools"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
    #expect(body["allowedTools"] == nil)
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["logprobs"] == nil)
    #expect(body["textVerbosity"] == nil)
    #expect(body["openai"] == nil)
}

@Test func openAIResponsesMapsBasicProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-provider-options","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let requests: [(modelID: String, options: [String: JSONValue])] = [
        ("gpt-4o", ["instructions": "You are a friendly assistant."]),
        ("o3-mini", ["include": ["reasoning.encrypted_content"]]),
        ("o3-mini", ["include": ["reasoning.encrypted_content", "file_search_call.results", "web_search_call.results"]]),
        ("gpt-5", ["textVerbosity": "low"]),
        ("gpt-5", ["textVerbosity": "medium"]),
        ("gpt-5", ["textVerbosity": "high"]),
        ("gpt-5", ["promptCacheKey": "test-cache-key-123"]),
        ("gpt-5", ["promptCacheRetention": "24h"]),
        ("gpt-5", ["safetyIdentifier": "test-safety-identifier-123"]),
        ("gpt-5", ["truncation": "auto"]),
        ("gpt-5", ["truncation": "disabled"]),
        ("gpt-5", [:]),
        ("gpt-5", ["logprobs": 5])
    ]

    for (modelID, options) in requests {
        let result = try await provider.languageModel(modelID).generate(LanguageModelRequest(
            messages: [.user("Hello")],
            providerOptions: options.isEmpty ? [:] : ["openai": .object(options)]
        ))
        #expect(result.warnings.isEmpty)
    }

    let bodies = try await transport.requests().map { try decodeJSONBody(try #require($0.body)) }
    #expect(bodies[0]["model"]?.stringValue == "gpt-4o")
    #expect(bodies[0]["input"]?[0]?["role"]?.stringValue == "user")
    #expect(bodies[0]["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(bodies[0]["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(bodies[0]["instructions"]?.stringValue == "You are a friendly assistant.")

    #expect(bodies[1]["model"]?.stringValue == "o3-mini")
    #expect(bodies[1]["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])

    #expect(bodies[2]["model"]?.stringValue == "o3-mini")
    #expect(bodies[2]["include"]?.arrayValue?.compactMap(\.stringValue) == [
        "reasoning.encrypted_content",
        "file_search_call.results",
        "web_search_call.results"
    ])

    #expect(bodies[3]["text"]?["verbosity"]?.stringValue == "low")
    #expect(bodies[4]["text"]?["verbosity"]?.stringValue == "medium")
    #expect(bodies[5]["text"]?["verbosity"]?.stringValue == "high")
    #expect(bodies[6]["prompt_cache_key"]?.stringValue == "test-cache-key-123")
    #expect(bodies[7]["prompt_cache_retention"]?.stringValue == "24h")
    #expect(bodies[8]["safety_identifier"]?.stringValue == "test-safety-identifier-123")
    #expect(bodies[9]["truncation"]?.stringValue == "auto")
    #expect(bodies[10]["truncation"]?.stringValue == "disabled")
    #expect(bodies[11]["truncation"] == nil)
    #expect(bodies[12]["top_logprobs"]?.intValue == 5)
    #expect(bodies[12]["include"]?.arrayValue?.compactMap(\.stringValue) == ["message.output_text.logprobs"])

    for body in bodies[3...] {
        #expect(body["model"]?.stringValue == "gpt-5")
        #expect(body["input"]?[0]?["role"]?.stringValue == "user")
        #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
        #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    }
}

@Test func openAIResponsesMapsResponseFormatLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-response-format","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")
    let schema: JSONValue = [
        "type": "object",
        "properties": ["value": ["type": "string"]],
        "required": ["value"],
        "additionalProperties": false,
        "$schema": "http://json-schema.org/draft-07/schema#"
    ]

    let jsonObjectResult = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        responseFormat: .json()
    ))
    #expect(jsonObjectResult.warnings.isEmpty)

    let jsonSchemaResult = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        responseFormat: .json(schema: schema, name: "response", description: "A response")
    ))
    #expect(jsonSchemaResult.warnings.isEmpty)

    let strictFalseResult = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        responseFormat: .json(schema: schema, name: "response", description: "A response"),
        providerOptions: ["openai": ["strictJsonSchema": false]]
    ))
    #expect(strictFalseResult.warnings.isEmpty)

    let bodies = try await transport.requests().map { try decodeJSONBody(try #require($0.body)) }
    #expect(bodies[0]["text"]?["format"]?["type"]?.stringValue == "json_object")
    #expect(bodies[0]["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")

    #expect(bodies[1]["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(bodies[1]["text"]?["format"]?["name"]?.stringValue == "response")
    #expect(bodies[1]["text"]?["format"]?["description"]?.stringValue == "A response")
    #expect(bodies[1]["text"]?["format"]?["schema"] == schema)
    #expect(bodies[1]["text"]?["format"]?["strict"]?.boolValue == true)

    #expect(bodies[2]["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(bodies[2]["text"]?["format"]?["name"]?.stringValue == "response")
    #expect(bodies[2]["text"]?["format"]?["description"]?.stringValue == "A response")
    #expect(bodies[2]["text"]?["format"]?["schema"] == schema)
    #expect(bodies[2]["text"]?["format"]?["strict"]?.boolValue == false)
    #expect(bodies[2]["strictJsonSchema"] == nil)
}

@Test func openAIResponsesWarnsAboutUnsupportedSettingsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-unsupported","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        topK: 1,
        presencePenalty: 0,
        frequencyPenalty: 0,
        seed: 42,
        stopSequences: ["\n\n"]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "topK"),
        AIWarning(type: "unsupported", feature: "seed"),
        AIWarning(type: "unsupported", feature: "presencePenalty"),
        AIWarning(type: "unsupported", feature: "frequencyPenalty"),
        AIWarning(type: "unsupported", feature: "stopSequences")
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["topK"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["presence_penalty"] == nil)
    #expect(body["frequency_penalty"] == nil)
    #expect(body["stop"] == nil)
}

@Test func openAIResponsesGenerateThrowsAPIErrorLikeUpstream() async throws {
    let message = "You exceeded your current quota, please check your plan and billing details. For more information on this error, read the docs: https://platform.openai.com/docs/guides/error-codes/api-errors."
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 429,
        headers: ["content-type": "application/json"],
        body: Data(#"{"error":{"message":"\#(message)","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}"#.utf8)
    ))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    do {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))
        Issue.record("Expected OpenAI Responses API call to throw")
    } catch let AIError.apiCall(error) {
        #expect(error.statusCode == 429)
        #expect(error.responseBody.contains(message))
    }
}

@Test func openAIResponsesMapsTopLevelReasoningOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-3","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-4","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.languageModel("o3-mini").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        reasoning: "provider-default"
    ))
    let providerDefaultBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    #expect(providerDefaultBody["reasoning"] == nil)

    let mediumResult = try await provider.languageModel("o3-mini").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: 0.5,
        topP: 0.7,
        reasoning: "medium"
    ))
    let mediumBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(mediumBody["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(mediumBody["reasoning"]?["summary"]?.stringValue == "detailed")
    #expect(mediumBody["temperature"] == nil)
    #expect(mediumBody["top_p"] == nil)
    #expect(mediumResult.warnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported for reasoning models")))
    #expect(mediumResult.warnings.contains(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported for reasoning models")))

    _ = try await provider.languageModel("gpt-4o").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: 0.5,
        topP: 0.7,
        reasoning: "none"
    ))
    let noneBody = try decodeJSONBody(try #require((await transport.requests())[2].body))
    #expect(noneBody["reasoning"] == nil)
    #expect(noneBody["temperature"]?.doubleValue == 0.5)
    #expect(noneBody["top_p"]?.doubleValue == 0.7)

    _ = try await provider.languageModel("o3-mini").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        reasoning: "low",
        providerOptions: ["openai": ["reasoningEffort": "high"]]
    ))
    let precedenceBody = try decodeJSONBody(try #require((await transport.requests())[3].body))
    #expect(precedenceBody["reasoning"]?["effort"]?.stringValue == "high")
    #expect(precedenceBody["reasoning"]?["summary"]?.stringValue == "detailed")
}

@Test func openAIResponsesMapsAllTopLevelReasoningValuesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-reasoning-value","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let reasoningValues = ["none", "minimal", "low", "medium", "high", "xhigh"]

    for (index, reasoningValue) in reasoningValues.enumerated() {
        let result = try await provider.languageModel("o3-mini").generate(LanguageModelRequest(
            messages: [.user("Hello")],
            reasoning: reasoningValue
        ))

        let body = try decodeJSONBody(try #require((await transport.requests())[index].body))
        #expect(body["model"]?.stringValue == "o3-mini")
        #expect(body["input"]?[0]?["role"]?.stringValue == "user")
        #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
        #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
        #expect(body["reasoning"]?["effort"]?.stringValue == reasoningValue)
        if reasoningValue == "none" {
            #expect(body["reasoning"]?["summary"] == nil)
            #expect(result.warnings.isEmpty)
        } else {
            #expect(body["reasoning"]?["summary"]?.stringValue == "detailed")
        }
    }
}

@Test func openAIResponsesRemovesUnsupportedSamplingForO1LikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-o1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("You are a helpful assistant."), .user("Hello")],
        temperature: 0.5,
        topP: 0.3
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["temperature"] == nil)
    #expect(body["top_p"] == nil)
    #expect(body["input"]?[0]?["role"]?.stringValue == "developer")
    #expect(body["input"]?[0]?["content"]?.stringValue == "You are a helpful assistant.")
    #expect(body["input"]?[1]?["role"]?.stringValue == "user")
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported for reasoning models")))
    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported for reasoning models")))
}

@Test func openAIResponsesRemovesUnsupportedSamplingForReasoningModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-reasoning","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let expectedWarnings = [
        AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported for reasoning models"),
        AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported for reasoning models")
    ]

    for (index, modelID) in openAIResponsesReasoningModelIDsLikeUpstream.enumerated() {
        let result = try await provider.languageModel(modelID).generate(LanguageModelRequest(
            messages: [.system("You are a helpful assistant."), .user("Hello")],
            temperature: 0.5,
            topP: 0.3
        ))

        let body = try decodeJSONBody(try #require((await transport.requests())[index].body))
        #expect(body["model"]?.stringValue == modelID)
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] == nil)
        #expect(body["input"]?[0]?["role"]?.stringValue == "developer")
        #expect(body["input"]?[0]?["content"]?.stringValue == "You are a helpful assistant.")
        #expect(body["input"]?[1]?["role"]?.stringValue == "user")
        #expect(result.warnings == expectedWarnings)
    }
}

@Test func openAIResponsesSendsReasoningProviderOptionsForReasoningModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-reasoning-options","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    for (index, modelID) in openAIResponsesReasoningModelIDsLikeUpstream.enumerated() {
        let result = try await provider.languageModel(modelID).generate(LanguageModelRequest(
            messages: [.user("Hello")],
            providerOptions: [
                "openai": [
                    "reasoningEffort": "low",
                    "reasoningSummary": "auto"
                ]
            ]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests())[index].body))
        #expect(body["model"]?.stringValue == modelID)
        #expect(body["reasoning"]?["effort"]?.stringValue == "low")
        #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
        #expect(result.warnings.isEmpty)
    }
}

@Test func openAIResponsesHandlesForceReasoningAndCodexMaxReasoningOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-force","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-codex-max","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let forcedResult = try await provider.languageModel("stealth-reasoning-model").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "forceReasoning": true,
                "reasoningEffort": "low",
                "reasoningSummary": "auto"
            ]
        ]
    ))
    let forcedBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    #expect(forcedBody["model"]?.stringValue == "stealth-reasoning-model")
    #expect(forcedBody["reasoning"]?["effort"]?.stringValue == "low")
    #expect(forcedBody["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(forcedBody["forceReasoning"] == nil)
    #expect(forcedResult.warnings.isEmpty)

    let codexMaxResult = try await provider.languageModel("gpt-5.1-codex-max").generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "xhigh"]]
    ))
    let codexMaxBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    #expect(codexMaxBody["model"]?.stringValue == "gpt-5.1-codex-max")
    #expect(codexMaxBody["reasoning"]?["effort"]?.stringValue == "xhigh")
    #expect(codexMaxBody["reasoning"]?["summary"]?.stringValue == "detailed")
    #expect(codexMaxResult.warnings.isEmpty)
}

@Test func openAIResponsesWarnsForReasoningProviderOptionsOnNonReasoningModelsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-non-reasoning","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let expectedWarnings = [
        AIWarning(type: "unsupported", feature: "reasoningEffort", message: "reasoningEffort is not supported for non-reasoning models")
    ]

    for (index, modelID) in openAIResponsesNonReasoningModelIDsLikeUpstream.enumerated() {
        let result = try await provider.languageModel(modelID).generate(LanguageModelRequest(
            messages: [.user("Hello")],
            providerOptions: ["openai": ["reasoningEffort": "low"]]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests())[index].body))
        #expect(body["model"]?.stringValue == modelID)
        #expect(body["reasoning"] == nil)
        #expect(body["reasoningEffort"] == nil)
        #expect(result.warnings == expectedWarnings)
    }
}

@Test func openAIResponsesGenerateMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output_text":"partial","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "partial")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 3)
}
@Test func openAIResponsesGenerateMapsAnnotationSourcesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "id": "resp-annotations",
      "status": "completed",
      "output_text": "Based on web search and file content.",
      "output": [
        {
          "id": "msg-annotations",
          "type": "message",
          "status": "completed",
          "role": "assistant",
          "content": [
            {
              "type": "output_text",
              "text": "Based on web search and file content.",
              "annotations": [
                {"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":0,"end_index":10},
                {"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123},
                {"type":"container_file_citation","container_id":"cntr-1","file_id":"cfile-1","filename":"rolls.csv","start_index":42,"end_index":51},
                {"type":"file_path","file_id":"cfile-path","index":7}
              ]
            }
          ]
        }
      ],
      "usage": {"input_tokens":1,"output_tokens":2,"total_tokens":3}
    }
    """#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.sources.map(\.sourceType) == ["url", "document", "document", "document"])
    #expect(result.sources[0].url == "https://example.com")
    #expect(result.sources[0].title == "Example URL")
    #expect(result.sources[1].mediaType == "text/plain")
    #expect(result.sources[1].filename == "resource1.json")
    #expect(result.sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(result.sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(result.sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)
    #expect(result.sources[2].providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(result.sources[2].providerMetadata["openai"]?["containerId"]?.stringValue == "cntr-1")
    #expect(result.sources[3].mediaType == "application/octet-stream")
    #expect(result.sources[3].filename == "cfile-path")
    #expect(result.sources[3].providerMetadata["openai"]?["type"]?.stringValue == "file_path")
}
