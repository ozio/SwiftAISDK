import Foundation
import Testing
@testable import SwiftAISDK

@Test func huggingFaceLanguageDefaultsToResponsesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"hf text","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-oss-120b")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 24))

    #expect(provider.providerID == "huggingface")
    #expect(model.providerID == "huggingface.responses")
    #expect(result.text == "hf text")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://router.huggingface.co/v1/responses")
    #expect(request.headers["authorization"] == "Bearer hf-key")
    #expect(request.headers["user-agent"] == "ai-sdk/huggingface/2.0.5")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "openai/gpt-oss-120b")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 24)
}

@Test func huggingFaceAppendsCustomUserAgentLikeUpstreamProviderVersion() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-ua","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(
        apiKey: "hf-key",
        headers: ["user-agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/huggingface/2.0.5")
}

@Test func huggingFaceResponsesAliasAndUnsupportedFamiliesMatchProviderWrapper() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.responsesModel("openai/gpt-oss-120b")
    let callableModel = try provider("openai/gpt-oss-120b")
    let responsesAliasModel = try provider.responses("openai/gpt-oss-120b")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.providerID == "huggingface.responses")
    #expect(callableModel.providerID == "huggingface.responses")
    #expect(responsesAliasModel.providerID == "huggingface.responses")
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func huggingFaceLanguageMapsNativeResponsesContentAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-hf-1","model":"deepseek-ai/DeepSeek-V3-0324","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"usage":{"input_tokens":20,"output_tokens":50,"total_tokens":70},"output":[{"id":"reasoning-1","type":"reasoning","content":[{"type":"reasoning_text","text":"thinking"}]},{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\\"city\\":\\"Tokyo\\"}","output":"weather output"},{"id":"mcp-1","type":"mcp_call","name":"search","arguments":"{\\"query\\":\\"AI\\"}","output":"found results"},{"id":"msg-1","type":"message","role":"assistant","content":[{"type":"output_text","text":"Answer with source.","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"}]}]}],"output_text":null}
    """, headers: ["hf-header": "yes"]))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be concise."),
            AIMessage(role: .user, content: [
                .text("Use the image."),
                .imageURL("https://example.com/image.png"),
                .file(mimeType: "image/png", data: Data([0, 1, 2, 3]), filename: "inline.png")
            ])
        ],
        temperature: 0.4,
        topP: 0.8,
        topK: 4,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        seed: 123,
        maxOutputTokens: 64,
        stopSequences: ["###"],
        responseFormat: .json(
            schema: [
                "type": "object",
                "properties": ["answer": ["type": "string"]],
                "required": ["answer"]
            ],
            name: "answer",
            description: "Answer schema"
        ),
        tools: ["weather": ["type": "object", "description": "Weather lookup", "properties": ["city": ["type": "string"]]]],
        providerOptions: [
            "huggingface": [
                "metadata": ["trace": "abc"],
                "instructions": "Use citations.",
                "reasoningEffort": "low",
                "strictJsonSchema": true,
                "unsupportedProperty": "drop-me"
            ],
            "openai": .object(["reasoningEffort": "high"])
        ],
        extraBody: [
            "huggingface": .object([
                "metadata": ["trace": "legacy"],
                "instructions": "legacy",
                "reasoningEffort": "high",
                "toolChoice": ["type": "tool", "toolName": "weather"],
                "responseFormat": [
                    "type": "json",
                    "schema": ["type": "string"]
                ]
            ])
        ]
    ))

    #expect(result.text == "Answer with source.")
    #expect(result.reasoning == "thinking")
    #expect(result.usage?.totalTokens == 70)
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "topK"),
        AIWarning(type: "unsupported", feature: "seed"),
        AIWarning(type: "unsupported", feature: "presencePenalty"),
        AIWarning(type: "unsupported", feature: "frequencyPenalty"),
        AIWarning(type: "unsupported", feature: "stopSequences")
    ])
    #expect(result.responseMetadata.id == "resp-hf-1")
    #expect(result.responseMetadata.modelID == "deepseek-ai/DeepSeek-V3-0324")
    #expect(result.responseMetadata.headers["hf-header"] == "yes")
    #expect(result.responseMetadata.body?["usage"]?["total_tokens"]?.intValue == 70)
    #expect(result.providerMetadata["huggingface"]?["responseId"]?.stringValue == "resp-hf-1")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/article")
    #expect(result.sources[0].title == "Example Article")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_weather")
    #expect(result.toolCalls[0].name == "weather")
    #expect(result.toolCalls[0].arguments == #"{"city":"Tokyo"}"#)
    #expect(result.toolCalls[0].providerExecuted == false)
    #expect(result.toolCalls[1].id == "mcp-1")
    #expect(result.toolCalls[1].name == "search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolResults.count == 2)
    #expect(result.toolResults[0].toolCallID == "call_weather")
    #expect(result.toolResults[0].result.stringValue == "weather output")
    #expect(result.toolResults[1].toolCallID == "mcp-1")
    #expect(result.toolResults[1].result.stringValue == "found results")

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V3-0324")
    #expect(body["input"]?[0]?["role"]?.stringValue == "system")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be concise.")
    #expect(body["input"]?[1]?["content"]?.arrayValue?.count == 3)
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["image_url"]?.stringValue == "data:image/png;base64,AAECAw==")
    #expect(body["metadata"]?["trace"]?.stringValue == "abc")
    #expect(body["instructions"]?.stringValue == "Use citations.")
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(body["text"]?["format"]?["strict"]?.boolValue == true)
    #expect(body["text"]?["format"]?["name"]?.stringValue == "answer")
    #expect(body["text"]?["format"]?["description"]?.stringValue == "Answer schema")
    #expect(body["text"]?["format"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["top_k"] == nil)
    #expect(body["presence_penalty"] == nil)
    #expect(body["frequency_penalty"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["stop"] == nil)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "weather")
    #expect(body["tools"]?[0]?["description"]?.stringValue == "Weather lookup")
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["function"]?["name"]?.stringValue == "weather")
    #expect(body["responseFormat"] == nil)
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["unsupportedProperty"] == nil)
    #expect(body["openai"] == nil)
    #expect(body["huggingface"] == nil)
}

@Test func huggingFaceProviderOptionsFollowUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-options","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: ["type": "object"]),
        providerOptions: [
            "huggingface": [
                "metadata": ["trace": "provider"],
                "instructions": "Use provider instructions.",
                "strictJsonSchema": true,
                "reasoningEffort": "medium",
                "unsupportedProperty": "drop-me"
            ]
        ],
        extraBody: [
            "huggingface": .object([
                "metadata": ["trace": "legacy"],
                "instructions": "legacy",
                "strictJsonSchema": false,
                "reasoningEffort": "low"
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["metadata"]?["trace"]?.stringValue == "provider")
    #expect(body["instructions"]?.stringValue == "Use provider instructions.")
    #expect(body["text"]?["format"]?["strict"]?.boolValue == true)
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["unsupportedProperty"] == nil)
    #expect(body["huggingface"] == nil)
}

@Test func huggingFaceProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: RecordingTransport(response: jsonResponse("{}"))))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface", message: "Hugging Face provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.metadata", message: "Hugging Face metadata cannot be null.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["metadata": .null]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.metadata", message: "Hugging Face metadata must be a string record.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["metadata": "trace"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.metadata.trace", message: "Hugging Face metadata values must be strings.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["metadata": ["trace": 1]]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.instructions", message: "Hugging Face instructions must be a string.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["instructions": true]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.strictJsonSchema", message: "Hugging Face strictJsonSchema must be a boolean.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["strictJsonSchema": "true"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.huggingface.reasoningEffort", message: "Hugging Face reasoningEffort must be a string.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], providerOptions: ["huggingface": ["reasoningEffort": 1]]))
    }
}

@Test func huggingFaceToolChoiceMapsLikeUpstreamResponsesTools() async throws {
    let choices: [(JSONValue, JSONValue?)] = [
        (.object(["type": "auto"]), .string("auto")),
        (.object(["type": "required"]), .string("required")),
        (.object(["type": "tool", "toolName": "weather"]), .object(["type": "function", "function": .object(["name": "weather"])])),
        (.object(["type": "none"]), nil)
    ]

    for (choice, expected) in choices {
        let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-tools","status":"completed","output_text":"ok"}"#))
        let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
        let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Use a tool.")],
            tools: ["weather": ["type": "object", "properties": ["city": ["type": "string"]]]],
            toolChoice: choice
        ))

        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        #expect(body["tool_choice"] == expected)
    }
}

@Test func huggingFaceProviderDefinedToolsAreSkippedWithWarningLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-provider-tools","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools.")],
        tools: [
            "weather": ["type": "object", "properties": ["city": ["type": "string"]]],
            "huggingface.search": ["type": "provider", "id": "huggingface.search", "name": "search"]
        ]
    ))

    #expect(result.warnings.contains(AIWarning(type: "unsupported", feature: "provider-defined tool huggingface.search")))
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = body["tools"]?.arrayValue ?? []
    #expect(tools.count == 1)
    #expect(tools.first?["name"]?.stringValue == "weather")
    #expect(tools.first?["type"]?.stringValue == "function")
}

@Test func huggingFaceLanguageResolvesTopLevelImageMediaTypesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-image","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")
    let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(mimeType: "image", data: pngBytes, filename: "inline.png"),
            .file(mimeType: "image/*", data: pngBytes, filename: "wildcard.png")
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["input"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["image_url"]?.stringValue == "data:image/png;base64,\(pngBytes.base64EncodedString())")
    #expect(content[1]["image_url"]?.stringValue == "data:image/png;base64,\(pngBytes.base64EncodedString())")
}

@Test func huggingFaceLanguageRejectsUnsupportedFilePartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-1","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "Hugging Face Responses API only supports image file parts; got text/plain.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .file(mimeType: "text/plain", data: Data("unsupported".utf8), filename: "notes.txt")
            ])
        ]))
    }

    let requests = await transport.requests()
    #expect(requests.isEmpty)
}

@Test func huggingFaceLanguageRejectsProviderReferenceFilePartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-hf-1","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    await #expect(throws: AIError.invalidArgument(argument: "files", message: "Hugging Face Responses API does not support file parts with provider references.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .providerReference(
                    mimeType: "image/jpeg",
                    reference: ["huggingface": "file-ref-123"],
                    filename: "remote.jpg"
                )
            ])
        ]))
    }

    let requests = await transport.requests()
    #expect(requests.isEmpty)
}

@Test func huggingFaceLanguageStreamsReasoningTextAndToolCalls() async throws {
    let chunks = [
        #"data:{"type":"response.created","response":{"id":"resp-hf-1","model":"deepseek-ai/DeepSeek-V3-0324","created_at":1741257730}}"#,
        #"data:{"type":"response.output_item.added","item":{"id":"reasoning-1","type":"reasoning"}}"#,
        #"data:{"type":"response.reasoning_text.delta","item_id":"reasoning-1","delta":"think"}"#,
        #"data:{"type":"response.reasoning_text.done","item_id":"reasoning-1"}"#,
        #"data:{"type":"response.output_item.added","item":{"id":"msg-1","type":"message","role":"assistant"}}"#,
        #"data:{"type":"response.output_text.delta","item_id":"msg-1","delta":"hello"}"#,
        #"data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg-1","type":"message","role":"assistant"}}"#,
        #"data:{"type":"response.output_item.added","item":{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather"}}"#,
        #"data:{"type":"response.output_item.done","output_index":1,"item":{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\"city\":\"Tokyo\"}","output":"sunny"}}"#,
        #"data:{"type":"response.completed","response":{"id":"resp-hf-1","model":"deepseek-ai/DeepSeek-V3-0324","created_at":1741257730,"status":"completed","incomplete_details":null,"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}"#
    ].map { Data(($0 + "\n\n").utf8) }
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], body: chunks.reduce(Data(), +)))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    var text = ""
    var reasoning = ""
    var textStarted = false
    var textEnded = false
    var reasoningStarted = false
    var reasoningEnded = false
    var toolInputStarted = false
    var toolInputEnded = false
    var finalToolCall: AIToolCall?
    var toolResult: AIToolResult?
    var finishUsage: TokenUsage?
    var finishMetadata: [String: JSONValue] = [:]
    var responseMetadata: AIResponseMetadata?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .textDeltaPart(_, delta, _):
            text += delta
        case .textStart:
            textStarted = true
        case .textEnd:
            textEnded = true
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .reasoningDeltaPart(_, delta, _):
            reasoning += delta
        case .reasoningStart:
            reasoningStarted = true
        case .reasoningEnd:
            reasoningEnded = true
        case .toolInputStart:
            toolInputStarted = true
        case .toolInputEnd:
            toolInputEnded = true
        case let .toolCall(toolCall):
            finalToolCall = toolCall
        case let .toolResult(result):
            toolResult = result
        case let .finish(_, usage):
            finishUsage = usage
        case let .finishMetadata(_, usage, metadata):
            finishUsage = usage
            finishMetadata = metadata
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        default:
            break
        }
    }

    #expect(reasoning == "think")
    #expect(text == "hello")
    #expect(textStarted)
    #expect(textEnded)
    #expect(reasoningStarted)
    #expect(reasoningEnded)
    #expect(toolInputStarted)
    #expect(toolInputEnded)
    #expect(finalToolCall?.id == "call_weather")
    #expect(finalToolCall?.name == "weather")
    #expect(finalToolCall?.arguments == #"{"city":"Tokyo"}"#)
    #expect(toolResult?.toolCallID == "call_weather")
    #expect(toolResult?.result.stringValue == "sunny")
    #expect(finishUsage?.totalTokens == 3)
    #expect(finishMetadata["huggingface"]?["responseId"]?.stringValue == "resp-hf-1")
    #expect(responseMetadata?.id == "resp-hf-1")
    #expect(responseMetadata?.modelID == "deepseek-ai/DeepSeek-V3-0324")
}
