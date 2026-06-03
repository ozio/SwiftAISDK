import Foundation
import Testing
@testable import SwiftAISDK

@Test func cohereLanguageUsesChatEndpointAndCohereShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"co"},{"type":"text","text":"here"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":2},"billed_units":{"input_tokens":3,"output_tokens":2}}}
    """, headers: ["x-cohere": "yes"]))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief."), .user("Hi")], topP: 0.8, maxOutputTokens: 12))

    #expect(result.text == "cohere")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.responseMetadata.id == "gen-1")
    #expect(result.responseMetadata.modelID == "command-a-03-2025")
    #expect(result.responseMetadata.headers["x-cohere"] == "yes")
    #expect(result.responseMetadata.body?["generation_id"]?.stringValue == "gen-1")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cohere.com/v2/chat")
    #expect(request.headers["Authorization"] == "Bearer cohere-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "command-a-03-2025")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[1]?["content"]?.stringValue == "Hi")
    #expect(body["p"]?.doubleValue == 0.8)
    #expect(body["max_tokens"]?.intValue == 12)
    #expect(body["documents"] == nil)
}

@Test func cohereLanguageMapsStandardOptionsResponseFormatAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"plan"},{"type":"text","text":"{\\"answer\\":\\"ok\\"}"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":5,"output_tokens":6}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        temperature: 0.2,
        topP: 0.7,
        topK: 9,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 42,
        maxOutputTokens: 32,
        stopSequences: ["END"],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["answer": ["type": "string"]],
                "required": ["answer"]
            ],
            name: "ignored-by-cohere",
            description: "Ignored by Cohere"
        ),
        reasoning: "128",
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            "unused": ["type": "object"]
        ],
        toolChoice: ["type": "tool", "toolName": "lookup"],
        providerOptions: [
            "cohere": [
                "thinking": [
                    "type": "enabled",
                    "tokenBudget": 64
                ],
                "safetyMode": "STRICT"
            ]
        ],
        extraBody: [
            "cohere": [
                "responseFormat": [
                    "type": "json_object",
                    "json_schema": ["type": "string"]
                ],
                "thinking": [
                    "type": "enabled",
                    "tokenBudget": 64
                ]
            ]
        ]
    ))

    #expect(result.text == #"{"answer":"ok"}"#)
    #expect(result.reasoning == "plan")
    #expect(result.usage?.totalTokens == 11)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["temperature"]?.doubleValue == 0.2)
    #expect(body["p"]?.doubleValue == 0.7)
    #expect(body["k"]?.intValue == 9)
    #expect(body["presence_penalty"]?.doubleValue == 0.1)
    #expect(body["frequency_penalty"]?.doubleValue == 0.2)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["max_tokens"]?.intValue == 32)
    #expect(body["stop_sequences"]?[0]?.stringValue == "END")
    #expect(body["response_format"]?["type"]?.stringValue == "json_object")
    #expect(body["response_format"]?["json_schema"]?["type"]?.stringValue == "object")
    #expect(body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(body["thinking"]?["token_budget"]?.intValue == 64)
    #expect(body["tools"]?.arrayValue?.count == 1)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "lookup")
    #expect(body["tools"]?[0]?["function"]?["description"]?.stringValue == "Look up a value.")
    #expect(body["tools"]?[0]?["function"]?["parameters"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["tool_choice"]?.stringValue == "REQUIRED")
    #expect(body["safetyMode"] == nil)
    #expect(body["cohere"] == nil)
    #expect(body["responseFormat"] == nil)
    #expect(body["toolChoice"] == nil)
}

@Test func cohereLanguageExtractsUserFilesIntoDocuments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":1}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("What do these documents say?"),
            .file(mimeType: "text/plain", data: Data("First document content".utf8), filename: "doc1.txt"),
            .file(mimeType: "application/json", data: Data("{\"key\":\"value\"}".utf8), filename: "data.json"),
            .data(mimeType: "application/pdf", data: Data("PDF-like content".utf8))
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "What do these documents say?")
    #expect(body["documents"]?.arrayValue?.count == 3)
    #expect(body["documents"]?[0]?["data"]?["text"]?.stringValue == "First document content")
    #expect(body["documents"]?[0]?["data"]?["title"]?.stringValue == "doc1.txt")
    #expect(body["documents"]?[1]?["data"]?["text"]?.stringValue == "{\"key\":\"value\"}")
    #expect(body["documents"]?[1]?["data"]?["title"]?.stringValue == "data.json")
    #expect(body["documents"]?[2]?["data"]?["text"]?.stringValue == "PDF-like content")
    #expect(body["documents"]?[2]?["data"]?["title"] == nil)
    #expect(String(data: try #require(request.body), encoding: .utf8)?.contains("application/pdf") == false)
}

@Test func cohereLanguageKeepsImagesInlineWhileExtractingDocuments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":1}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Use both."),
            .file(mimeType: "image/png", data: Data([0, 1, 2, 3]), filename: "image.png"),
            .file(mimeType: "text/plain", data: Data("Document text".utf8), filename: "note.txt")
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(content[0]["text"]?.stringValue == "Use both.")
    #expect(content[1]["type"]?.stringValue == "image_url")
    #expect(content[1]["image_url"]?["url"]?.stringValue == "data:image/png;base64,AAECAw==")
    #expect(body["documents"]?.arrayValue?.count == 1)
    #expect(body["documents"]?[0]?["data"]?["text"]?.stringValue == "Document text")
    #expect(body["documents"]?[0]?["data"]?["title"]?.stringValue == "note.txt")
}

@Test func cohereLanguageParsesToolCallsAndNullArguments() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[],"tool_calls":[{"id":"currentTime_tf4dywn8wgnk","type":"function","function":{"name":"currentTime","arguments":"null"}}]},"finish_reason":"TOOL_CALL","usage":{"tokens":{"input_tokens":3,"output_tokens":2}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("What time is it?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "currentTime_tf4dywn8wgnk")
    #expect(result.toolCalls[0].name == "currentTime")
    #expect(result.toolCalls[0].arguments == "{}")
}

@Test func cohereLanguageSerializesToolCallsAndToolResultMessages() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-2","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":4,"output_tokens":1}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .assistant(toolCalls: [
            AIToolCall(id: "call_weather", name: "weather", arguments: #"{"city":"Tokyo"}"#)
        ]),
        .toolResult(AIToolResult(
            toolCallID: "call_weather",
            toolName: "weather",
            result: ["forecast": "sunny"]
        ))
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["messages"]?[0]?["role"]?.stringValue == "assistant")
    #expect(body["messages"]?[0]?["content"] == nil)
    #expect(body["messages"]?[0]?["tool_calls"]?[0]?["id"]?.stringValue == "call_weather")
    #expect(body["messages"]?[0]?["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "weather")
    #expect(body["messages"]?[0]?["tool_calls"]?[0]?["function"]?["arguments"]?.stringValue == #"{"city":"Tokyo"}"#)
    #expect(body["messages"]?[1]?["role"]?.stringValue == "tool")
    #expect(body["messages"]?[1]?["tool_call_id"]?.stringValue == "call_weather")
    #expect(body["messages"]?[1]?["content"]?.stringValue == #"{"forecast":"sunny"}"#)
}

@Test func cohereLanguageMapsCitationSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"AI helps automate work."}],"citations":[{"start":9,"end":17,"text":"automate","sources":[{"type":"document","id":"doc:0","document":{"id":"doc:0","text":"AI helps automate work.","title":"benefits.txt"}}],"type":"TEXT_CONTENT"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":4}}}
    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-r-plus")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("What are AI benefits?")]))

    #expect(result.text == "AI helps automate work.")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "cohere-citation-0")
    #expect(result.sources[0].sourceType == "document")
    #expect(result.sources[0].title == "benefits.txt")
    #expect(result.sources[0].mediaType == "text/plain")
    #expect(result.sources[0].providerMetadata["cohere"]?["start"]?.intValue == 9)
    #expect(result.sources[0].providerMetadata["cohere"]?["end"]?.intValue == 17)
    #expect(result.sources[0].providerMetadata["cohere"]?["text"]?.stringValue == "automate")
    #expect(result.sources[0].providerMetadata["cohere"]?["citationType"]?.stringValue == "TEXT_CONTENT")
    #expect(result.sources[0].providerMetadata["cohere"]?["sources"]?[0]?["document"]?["title"]?.stringValue == "benefits.txt")
    #expect(result.sources[0].rawValue?["sources"]?[0]?["id"]?.stringValue == "doc:0")
}

@Test func mistralLanguageUsesNativeChatShapeAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","created":1741257730,"model":"mistral-large-latest","choices":[{"index":0,"message":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"hmm"}]},{"type":"text","text":"bonjour"}]},"finish_reason":"model_length"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}
    """, headers: ["x-mistral": "yes"]))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Reply in French."),
            AIMessage(role: .user, content: [.text("See this"), .data(mimeType: "application/pdf", data: Data("pdf".utf8))])
        ],
        temperature: 0.2,
        topP: 0.9,
        topK: 4,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 123,
        maxOutputTokens: 16,
        reasoning: "high",
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            "unused": ["type": "object"]
        ],
        extraBody: [
            "safePrompt": true,
            "randomSeed": 7,
            "documentPageLimit": 2,
            "parallelToolCalls": false,
            "toolChoice": ["type": "tool", "toolName": "lookup"]
        ]
        ))

    #expect(result.text == "bonjour")
    #expect(result.reasoning == "hmm")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "topK"),
        AIWarning(type: "unsupported", feature: "frequencyPenalty"),
        AIWarning(type: "unsupported", feature: "presencePenalty"),
        AIWarning(
            type: "unsupported",
            feature: "reasoning",
            message: "This model does not support reasoning configuration."
        )
    ])
    #expect(result.responseMetadata.id == "cmpl-1")
    #expect(result.responseMetadata.modelID == "mistral-large-latest")
    #expect(result.responseMetadata.headers["x-mistral"] == "yes")
    #expect(result.responseMetadata.body?["id"]?.stringValue == "cmpl-1")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.mistral.ai/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer mistral-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "mistral-large-latest")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[1]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["messages"]?[1]?["content"]?[1]?["type"]?.stringValue == "document_url")
    #expect(body["messages"]?[1]?["content"]?[1]?["document_url"]?.stringValue?.hasPrefix("data:application/pdf;base64,") == true)
    #expect(body["safe_prompt"]?.boolValue == true)
    #expect(body["random_seed"]?.intValue == 7)
    #expect(body["document_page_limit"]?.intValue == 2)
    #expect(body["top_k"] == nil)
    #expect(body["presence_penalty"] == nil)
    #expect(body["frequency_penalty"] == nil)
    #expect(body["reasoning_effort"] == nil)
    #expect(body["tools"]?.arrayValue?.count == 1)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "lookup")
    #expect(body["tools"]?[0]?["function"]?["description"]?.stringValue == "Look up a value.")
    #expect(body["tools"]?[0]?["function"]?["parameters"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["tool_choice"]?.stringValue == "any")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
}

@Test func mistralLanguageMapsStandardJsonResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"ok\\":true}"},"finish_reason":"stop"}],"usage":{"total_tokens":4}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json()
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_object")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "system")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "You MUST answer with JSON.")
    #expect(body["messages"]?[1]?["role"]?.stringValue == "user")
    #expect(body["responseFormat"] == nil)
}

@Test func mistralLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            name: "answer",
            description: "Answer schema"
        )
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["name"]?.stringValue == "answer")
    #expect(body["response_format"]?["json_schema"]?["description"]?.stringValue == "Answer schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == false)
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
    #expect(body["responseFormat"] == nil)
}

@Test func mistralLanguageAllowsStructuredOutputsOverride() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        extraBody: [
            "responseFormat": [
                "type": "json",
                "schema": ["type": "object"],
                "name": "answer"
            ],
            "structuredOutputs": false,
            "strictJsonSchema": true
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_object")
    #expect(body["response_format"]?["json_schema"] == nil)
    #expect(body["responseFormat"] == nil)
    #expect(body["structuredOutputs"] == nil)
    #expect(body["strictJsonSchema"] == nil)
}

@Test func mistralLanguageUsesProviderOptionsStructuredOutputControls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"value\\":\\"ok\\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":5}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(schema: ["type": "object"], name: "answer"),
        providerOptions: [
            "mistral": [
                "structuredOutputs": true,
                "strictJsonSchema": true
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["strict"]?.boolValue == true)
    #expect(body["structuredOutputs"] == nil)
    #expect(body["strictJsonSchema"] == nil)
}

@Test func mistralUnknownFinishReasonMapsToOtherAndParallelToolsNeedTools() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-large-latest","choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"unexpected"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["parallelToolCalls": false, "toolChoice": "required"]
    ))

    #expect(result.finishReason == "other")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["parallel_tool_calls"] == nil)
    #expect(body["tool_choice"] == nil)
    #expect(body["tools"] == nil)
}

@Test func mistralLanguageParsesToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"","tool_calls":[{"id":"gSIMJiOkT","function":{"name":"weather","arguments":"{\\"location\\": \\"San Francisco\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":124,"completion_tokens":22,"total_tokens":146}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": ["location": ["type": "string"]]]]
    ))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 146)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "gSIMJiOkT")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func mistralLanguageSerializesToolCallsAndModelOutputResults() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-2","object":"chat.completion","model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}
    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Weather?"),
        .assistant(
            toolCalls: [
                AIToolCall(
                    id: "call_weather",
                    name: "weather",
                    arguments: #"{"location":"Paris"}"#
                ),
                AIToolCall(
                    id: "call_air",
                    name: "airQuality",
                    arguments: #"{"location":"Paris"}"#
                )
            ]
        ),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "call_weather",
                toolName: "weather",
                result: ["raw": "do not send"],
                modelOutput: [
                    "type": "content",
                    "value": [
                        ["type": "text", "text": "Sunny in Paris"]
                    ]
                ]
            ),
            AIToolResult(
                toolCallID: "call_air",
                toolName: "airQuality",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "text",
                    "value": "Good"
                ]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages[1]["role"]?.stringValue == "assistant")
    #expect(messages[1]["tool_calls"]?[0]?["id"]?.stringValue == "call_weather")
    #expect(messages[1]["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "weather")
    #expect(messages[1]["tool_calls"]?[0]?["function"]?["arguments"]?.stringValue == #"{"location":"Paris"}"#)
    #expect(messages[1]["tool_calls"]?[1]?["id"]?.stringValue == "call_air")
    #expect(messages[2]["role"]?.stringValue == "tool")
    #expect(messages[2]["name"]?.stringValue == "weather")
    #expect(messages[2]["tool_call_id"]?.stringValue == "call_weather")
    #expect(messages[3]["role"]?.stringValue == "tool")
    #expect(messages[3]["name"]?.stringValue == "airQuality")
    #expect(messages[3]["tool_call_id"]?.stringValue == "call_air")
    #expect(messages[3]["content"]?.stringValue == "Good")

    let content = try #require(messages[2]["content"]?.stringValue)
    let contentJSON = try decodeJSONBody(Data(content.utf8))
    #expect(contentJSON[0]?["text"]?.stringValue == "Sunny in Paris")
    #expect(contentJSON[0]?["raw"] == nil)
}

@Test func mistralLanguageStreamsNativeChunks() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","created":1741257730,"model":"mistral","choices":[{"index":0,"delta":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"hmm"}]}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":[{"type":"text","text":"bon"}]},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral","choices":[{"index":0,"delta":{"content":"jour"},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

    """, headers: ["x-stream": "yes"]))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-large-latest")

    var text: [String] = []
    var reasoning: [String] = []
    var lifecycle: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    var streamStartWarnings: [AIWarning]?
    var responseMetadata: AIResponseMetadata?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 8,
        providerOptions: ["mistral": ["documentImageLimit": 2]]
    )) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .textDeltaPart(id, delta, _):
            lifecycle.append("text-delta:\(id):\(delta)")
            text.append(delta)
        case let .textStart(id, _):
            lifecycle.append("text-start:\(id)")
        case let .textEnd(id, _):
            lifecycle.append("text-end:\(id)")
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .reasoningDeltaPart(id, delta, _):
            lifecycle.append("reasoning-delta:\(id):\(delta)")
            reasoning.append(delta)
        case let .reasoningStart(id, _):
            lifecycle.append("reasoning-start:\(id)")
        case let .reasoningEnd(id, _):
            lifecycle.append("reasoning-end:\(id)")
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["hmm"])
    #expect(text == ["bon", "jour"])
    #expect(lifecycle == [
        "reasoning-start:reasoning-0",
        "reasoning-delta:reasoning-0:hmm",
        "reasoning-end:reasoning-0",
        "text-start:0",
        "text-delta:0:bon",
        "text-delta:0:jour",
        "text-end:0"
    ])
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 3)
    #expect(streamStartWarnings == [AIWarning(type: "unsupported", feature: "topK")])
    #expect(responseMetadata?.id == "cmpl-1")
    #expect(responseMetadata?.modelID == "mistral")
    #expect(responseMetadata?.headers["x-stream"] == "yes")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["document_image_limit"]?.intValue == 2)
    #expect(body["top_k"] == nil)
}

@Test func mistralLanguageStreamsToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":null,"tool_calls":[{"id":"gSIMJiOkT","function":{"name":"weather","arguments":"{\\"location\\": \\"San Francisco\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":124,"completion_tokens":22,"total_tokens":146}}

    """))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Weather?")],
        tools: ["weather": ["type": "object", "properties": ["location": ["type": "string"]]]]
    )) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let finalToolCall = try #require(toolCall)
    #expect(deltas == [#"{"location": "San Francisco"}"#])
    #expect(inputLifecycle == [
        "start:gSIMJiOkT:weather",
        #"delta:gSIMJiOkT:{"location": "San Francisco"}"#,
        "end:gSIMJiOkT"
    ])
    #expect(finalToolCall.id == "gSIMJiOkT")
    #expect(finalToolCall.name == "weather")
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 146)
}

@Test func mistralEmbeddingUsesFloatEncodingAndLimit() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3,0.4]}],"usage":{"prompt_tokens":6}}"#))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.embeddingModel("mistral-embed")

    let result = try await model.embed(EmbeddingRequest(values: ["hello", "world"]))

    #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(result.usage?.inputTokens == 6)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.mistral.ai/v1/embeddings")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["input"]?[0]?.stringValue == "hello")
    #expect(body["encoding_format"]?.stringValue == "float")
}

@Test func mistralModelsMapNestedProviderOptions() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#))
    let chatProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: chatTransport))
    let chatModel = try chatProvider.languageModel("mistral-small-latest")

    _ = try await chatModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        tools: ["lookup": ["type": "object", "properties": [:]]],
        providerOptions: [
            "mistral": [
                "safePrompt": true,
                "documentImageLimit": 5,
                "documentPageLimit": 7,
                "parallelToolCalls": false,
                "reasoningEffort": "none",
                "randomSeed": 99,
                "unsupported": "drop-me"
            ],
            "cohere": [
                "safePrompt": true
            ]
        ],
        extraBody: [
            "safePrompt": false,
            "mistral": [
                "safePrompt": false,
                "randomSeed": 11,
                "documentImageLimit": 3,
                "parallelToolCalls": true,
                "reasoningEffort": "high",
                "rawExtra": "keep-me"
            ]
        ]
    ))

    let chatRequest = try #require(await chatTransport.requests().first)
    let chatBody = try decodeJSONBody(try #require(chatRequest.body))
    #expect(chatBody["mistral"] == nil)
    #expect(chatBody["cohere"] == nil)
    #expect(chatBody["unsupported"] == nil)
    #expect(chatBody["safe_prompt"]?.boolValue == true)
    #expect(chatBody["random_seed"]?.intValue == 11)
    #expect(chatBody["document_image_limit"]?.intValue == 5)
    #expect(chatBody["document_page_limit"]?.intValue == 7)
    #expect(chatBody["parallel_tool_calls"]?.boolValue == false)
    #expect(chatBody["reasoning_effort"]?.stringValue == "none")
    #expect(chatBody["rawExtra"]?.stringValue == "keep-me")

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}]}"#))
    let embeddingProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("mistral-embed")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["hello"],
        extraBody: ["mistral": ["encoding_format": "float"]]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["mistral"] == nil)
    #expect(embeddingBody["encoding_format"]?.stringValue == "float")
}

@Test func mistralLanguageProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: RecordingTransport(responses: [])))
    let model = try provider.languageModel("mistral-small-latest")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral", message: "Mistral provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["mistral": "not-an-object"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral.safePrompt", message: "Mistral safePrompt cannot be null.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["mistral": .object(["safePrompt": .null])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral.parallelToolCalls", message: "Mistral parallelToolCalls must be a boolean.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["mistral": .object(["parallelToolCalls": "false"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral.documentImageLimit", message: "Mistral documentImageLimit must be a number.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["mistral": .object(["documentImageLimit": "5"])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral.reasoningEffort", message: "Mistral reasoningEffort must be high or none.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["mistral": .object(["reasoningEffort": "medium"])]
        ))
    }
}

@Test func cohereLanguageStreamsChatEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message-start","id":"msg-1"}

    data: {"type":"content-start","index":0,"delta":{"message":{"content":{"type":"text"}}}}

    data: {"type":"content-delta","index":0,"delta":{"message":{"content":{"text":"co"}}}}

    data: {"type":"content-delta","index":0,"delta":{"message":{"content":{"text":"here"}}}}

    data: {"type":"content-end","index":0}

    data: {"type":"message-end","delta":{"finish_reason":"MAX_TOKENS","usage":{"tokens":{"input_tokens":1,"output_tokens":2}}}}

    """, headers: ["x-stream": "yes"]))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    var deltas: [String] = []
    var lifecycle: [String] = []
    var finishReason: String?
    var streamStartWarnings: [AIWarning]?
    var responseMetadata: AIResponseMetadata?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        topK: 5,
        providerOptions: ["cohere": ["priority": 1]]
    )) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .textDeltaPart(id, delta, _):
            lifecycle.append("delta:\(id):\(delta)")
            deltas.append(delta)
        case let .textStart(id, _):
            lifecycle.append("start:\(id)")
        case let .textEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .responseMetadata(metadata):
            if metadata.id == "msg-1" {
                responseMetadata = metadata
            }
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["co", "here"])
    #expect(lifecycle == ["start:0", "delta:0:co", "delta:0:here", "end:0"])
    #expect(finishReason == "length")
    #expect(streamStartWarnings == [])
    #expect(responseMetadata?.id == "msg-1")
    #expect(responseMetadata?.headers["x-stream"] == "yes")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["k"]?.intValue == 5)
    #expect(body["priority"] == nil)
}

@Test func cohereLanguageStreamsToolCallEvents() async throws {
    let transport = RecordingTransport(response: sseResponse(#"""
    data: {"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"weather_dqgshstja6p9","type":"function","function":{"name":"weather","arguments":"{\"location\":"}}}}}

    data: {"type":"tool-call-delta","delta":{"message":{"tool_calls":{"function":{"arguments":"\"San Francisco\"}"}}}}}

    data: {"type":"tool-call-end"}

    data: {"type":"message-end","delta":{"finish_reason":"TOOL_CALL","usage":{"tokens":{"input_tokens":3,"output_tokens":2}}}}

    """#))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let call = try #require(finalCall)
    #expect(deltas == ["{\"location\":", "\"San Francisco\"}"])
    #expect(inputLifecycle == [
        "start:weather_dqgshstja6p9:weather",
        "delta:weather_dqgshstja6p9:{\"location\":",
        "delta:weather_dqgshstja6p9:\"San Francisco\"}",
        "end:weather_dqgshstja6p9"
    ])
    #expect(call.id == "weather_dqgshstja6p9")
    #expect(call.name == "weather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 5)
}

@Test func cohereEmbeddingAndRerankingUseNativeEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"embeddings":{"float":[[0.1,0.2],[0.3,0.4]]},"meta":{"billed_units":{"input_tokens":7}}}
    """))
    let embeddingProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("embed-english-v3.0")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hello", "world"], dimensions: 512, extraBody: ["inputType": "classification", "truncate": "END"]))

    #expect(embedding.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(embedding.usage?.totalTokens == 7)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.cohere.com/v2/embed")
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["texts"]?[0]?.stringValue == "hello")
    #expect(embeddingBody["embedding_types"]?[0]?.stringValue == "float")
    #expect(embeddingBody["input_type"]?.stringValue == "classification")
    #expect(embeddingBody["output_dimension"]?.intValue == 512)
    #expect(embeddingBody["truncate"]?.stringValue == "END")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"id":"rank-1","results":[{"index":1,"relevance_score":0.9},{"index":0,"relevance_score":0.1}]}"#))
    let rerankProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-v3.5")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, extraBody: ["maxTokensPerDoc": 256]))

    #expect(reranking.results.map(\.index) == [1, 0])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.cohere.com/v2/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_n"]?.intValue == 1)
    #expect(rerankBody["max_tokens_per_doc"]?.intValue == 256)
}

@Test func cohereModelsMapNestedProviderOptions() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse(#"{"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":1,"output_tokens":1}}}"#))
    let chatProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: chatTransport))
    let chatModel = try chatProvider.languageModel("command-a-reasoning-08-2025")

    _ = try await chatModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "cohere": [
                "thinking": [
                    "type": "enabled",
                    "tokenBudget": 128
                ]
            ]
        ]
    ))

    let chatRequest = try #require(await chatTransport.requests().first)
    let chatBody = try decodeJSONBody(try #require(chatRequest.body))
    #expect(chatBody["cohere"] == nil)
    #expect(chatBody["thinking"]?["type"]?.stringValue == "enabled")
    #expect(chatBody["thinking"]?["token_budget"]?.intValue == 128)

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"embeddings":{"float":[[0.1,0.2]]},"meta":{"billed_units":{"input_tokens":3}}}"#))
    let embeddingProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("embed-v4.0")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: [
            "cohere": [
                "inputType": "clustering",
                "outputDimension": 1536,
                "truncate": "NONE",
                "priority": 999
            ],
            "voyage": [
                "inputType": "query"
            ]
        ],
        extraBody: [
            "cohere": [
                "inputType": "search_document",
                "outputDimension": 1024,
                "truncate": "START",
                "rawExtra": "keep-me"
            ]
        ]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["cohere"] == nil)
    #expect(embeddingBody["voyage"] == nil)
    #expect(embeddingBody["priority"] == nil)
    #expect(embeddingBody["input_type"]?.stringValue == "clustering")
    #expect(embeddingBody["output_dimension"]?.intValue == 1536)
    #expect(embeddingBody["truncate"]?.stringValue == "NONE")
    #expect(embeddingBody["rawExtra"]?.stringValue == "keep-me")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.8}]}"#))
    let rerankProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-v3.5")

    let rerankResult = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: [["body": "a", "source": "doc-1"]],
        providerOptions: [
            "cohere": [
                "maxTokensPerDoc": 512,
                "priority": 2,
                "truncate": "drop-me"
            ],
            "voyage": [
                "returnDocuments": true
            ]
        ],
        extraBody: [
            "cohere": [
                "maxTokensPerDoc": 128,
                "priority": 1,
                "rawRerank": true
            ]
        ]
    ))

    #expect(rerankResult.warnings == [
        AIWarning(type: "compatibility", feature: "object documents", message: "Object documents are converted to strings.")
    ])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["cohere"] == nil)
    #expect(rerankBody["voyage"] == nil)
    #expect(rerankBody["truncate"] == nil)
    #expect(rerankBody["max_tokens_per_doc"]?.intValue == 512)
    #expect(rerankBody["priority"]?.intValue == 2)
    #expect(rerankBody["rawRerank"]?.boolValue == true)
    let documentText = try #require(rerankBody["documents"]?[0]?.stringValue)
    let documentJSON = try decodeJSONBody(Data(documentText.utf8))
    #expect(documentJSON["body"]?.stringValue == "a")
    #expect(documentJSON["source"]?.stringValue == "doc-1")
}

@Test func voyageEmbeddingAndRerankingUseNativeEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"model":"voyage-3","data":[{"index":1,"embedding":[0.3,0.4]},{"index":0,"embedding":[0.1,0.2]}],"usage":{"total_tokens":9}}
    """))
    let embeddingProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("voyage-3")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["a", "b"], dimensions: 256, extraBody: ["inputType": "query", "truncation": true, "outputDtype": "float"]))

    #expect(embedding.embeddings == [[0.3, 0.4], [0.1, 0.2]])
    #expect(embedding.usage?.totalTokens == 9)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.voyageai.com/v1/embeddings")
    #expect(embeddingRequest.headers["Authorization"] == "Bearer voyage-key")
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["input"]?[0]?.stringValue == "a")
    #expect(embeddingBody["input_type"]?.stringValue == "query")
    #expect(embeddingBody["truncation"]?.boolValue == true)
    #expect(embeddingBody["output_dimension"]?.intValue == 256)
    #expect(embeddingBody["output_dtype"]?.stringValue == "float")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"relevance_score":0.7},{"index":1,"relevance_score":0.2}],"usage":{"total_tokens":5}}"#))
    let rerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-2.5")

    let reranking = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 2, extraBody: ["returnDocuments": true, "truncation": true]))

    #expect(reranking.results.map(\.score) == [0.7, 0.2])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://api.voyageai.com/v1/rerank")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_k"]?.intValue == 2)
    #expect(rerankBody["return_documents"]?.boolValue == true)
    #expect(rerankBody["returnDocuments"] == nil)
    #expect(rerankBody["truncation"]?.boolValue == true)
}

@Test func voyageModelsMapNestedProviderOptions() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[0.1,0.2]}],"usage":{"total_tokens":3}}"#))
    let embeddingProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("voyage-4")

    _ = try await embeddingModel.embed(EmbeddingRequest(
        values: ["a"],
        providerOptions: [
            "voyage": [
                "inputType": "query",
                "truncation": true,
                "outputDimension": 768,
                "outputDtype": "binary",
                "unsupported": "drop-me"
            ],
            "openai": [
                "dimensions": 999
            ]
        ],
        extraBody: [
            "voyage": [
                "inputType": "document",
                "truncation": false,
                "outputDimension": 512,
                "outputDtype": "int8"
            ]
        ]
    ))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    let embeddingBody = try decodeJSONBody(try #require(embeddingRequest.body))
    #expect(embeddingBody["voyage"] == nil)
    #expect(embeddingBody["openai"] == nil)
    #expect(embeddingBody["unsupported"] == nil)
    #expect(embeddingBody["input_type"]?.stringValue == "query")
    #expect(embeddingBody["truncation"]?.boolValue == true)
    #expect(embeddingBody["output_dimension"]?.intValue == 768)
    #expect(embeddingBody["output_dtype"]?.stringValue == "binary")

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"relevance_score":0.7}],"usage":{"total_tokens":3}}"#))
    let rerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("rerank-2.5")

    let rerankResult = try await rerankModel.rerank(RerankingRequest(
        query: "q",
        documents: [["body": "a"]],
        providerOptions: [
            "voyage": [
                "returnDocuments": true,
                "truncation": true,
                "inputType": "drop-me"
            ],
            "cohere": [
                "priority": 1
            ]
        ],
        extraBody: [
            "voyage": [
                "returnDocuments": false,
                "truncation": false
            ]
        ]
    ))

    #expect(rerankResult.warnings == [
        AIWarning(type: "compatibility", feature: "object documents", message: "Object documents are converted to strings.")
    ])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["voyage"] == nil)
    #expect(rerankBody["cohere"] == nil)
    #expect(rerankBody["inputType"] == nil)
    #expect(rerankBody["return_documents"]?.boolValue == true)
    #expect(rerankBody["truncation"]?.boolValue == true)
    let documentText = try #require(rerankBody["documents"]?[0]?.stringValue)
    let documentJSON = try decodeJSONBody(Data(documentText.utf8))
    #expect(documentJSON["body"]?.stringValue == "a")
}
