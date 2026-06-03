import Foundation
import Testing
@testable import SwiftAISDK

@Test func xAILanguageDefaultsToResponsesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai text","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.languageModel("grok-4")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 12))

    #expect(provider.providerID == "xai")
    #expect(model.providerID == "xai.responses")
    #expect(result.text == "xai text")
    #expect(result.usage?.totalTokens == 5)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/responses")
    #expect(request.headers["authorization"] == "Bearer xai-key")
    #expect(request.headers["user-agent"] == "ai-sdk/xai/3.0.93")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "grok-4")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 12)
}

@Test func xAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-custom","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport
    ))
    let model = try provider.languageModel("grok-4")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer xai-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/xai/3.0.93")
}

@Test func xAIProviderAliasesUseUpstreamProviderIDsAndOptions() async throws {
    let responsesTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai responses"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: responsesTransport))
    let responsesModel = try provider.responses("grok-4")

    _ = try await responsesModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "xai": .object([
                "topLogprobs": .number(2),
                "store": .bool(false),
                "include": .array([.string("file_search_call.results")])
            ])
        ]
    ))

    #expect(responsesModel.providerID == "xai.responses")
    #expect(try provider.chat("grok-4").providerID == "xai.chat")
    #expect(try provider.imageModel("grok-2-image").providerID == "xai.image")
    #expect(try provider.videoModel("grok-2-video").providerID == "xai.video")
    #expect(provider.files().providerID == "xai.files")

    let responsesBody = try decodeJSONBody(try #require((await responsesTransport.requests()).first?.body))
    #expect(responsesBody["top_logprobs"]?.intValue == 2)
    #expect(responsesBody["logprobs"]?.boolValue == true)
    #expect(responsesBody["store"]?.boolValue == false)
    #expect(responsesBody["include"]?[0]?.stringValue == "file_search_call.results")
    #expect(responsesBody["include"]?[1]?.stringValue == "reasoning.encrypted_content")
    #expect(responsesBody["xai"] == nil)

    let chatTransport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"xai chat"},"finish_reason":"stop"}]}"#))
    let chatProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: chatTransport))
    let chatModel = try chatProvider.chat("grok-4")
    _ = try await chatModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["xai": .object(["reasoningEffort": .string("high"), "topLogprobs": .number(3)])]
    ))

    let chatBody = try decodeJSONBody(try #require((await chatTransport.requests()).first?.body))
    #expect(chatBody["reasoning_effort"]?.stringValue == "high")
    #expect(chatBody["top_logprobs"]?.intValue == 3)
    #expect(chatBody["xai"] == nil)
}

@Test func xAIResponsesProviderOptionsValidateAndMapLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai responses"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.responses("grok-4")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        seed: 42,
        providerOptions: [
            "xai": [
                "reasoningEffort": "high",
                "logprobs": false,
                "topLogprobs": 8,
                "store": false,
                "previousResponseId": "resp-old",
                "include": ["file_search_call.results"],
                "unknown": "drop-me"
            ]
        ],
        extraBody: [
            "xai": [
                "reasoningEffort": "low",
                "topLogprobs": 1,
                "unknown": "raw-kept"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "high")
    #expect(body["top_logprobs"]?.intValue == 8)
    #expect(body["logprobs"]?.boolValue == true)
    #expect(body["store"]?.boolValue == false)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["include"]?[0]?.stringValue == "file_search_call.results")
    #expect(body["include"]?[1]?.stringValue == "reasoning.encrypted_content")
    #expect(body["unknown"]?.stringValue == "raw-kept")
    #expect(body["reasoningEffort"] == nil)
    #expect(body["reasoningSummary"] == nil)
    #expect(body["topLogprobs"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["xai"] == nil)
}

@Test func xAIResponsesProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))
    let model = try provider.responses("grok-4")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI responses provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": "bad"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.reasoningEffort", message: "xAI reasoningEffort must be low, medium, or high.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["reasoningEffort": "minimal"]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.topLogprobs", message: "xAI topLogprobs must be an integer from 0 to 8.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["topLogprobs": 9]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.include", message: "xAI include must contain only file_search_call.results or be null.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["include": ["reasoning.encrypted_content"]]]
        ))
    }
}

@Test func xAIResponsesProviderOptionsNullNamespaceAndIncludeNullMatchUpstream() async throws {
    let nullNamespaceTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai responses"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: nullNamespaceTransport))
    let model = try provider.responses("grok-4")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["xai": .null],
        extraBody: ["xai": ["topLogprobs": 2, "store": false]]
    ))

    let nullNamespaceBody = try decodeJSONBody(try #require((await nullNamespaceTransport.requests()).first?.body))
    #expect(nullNamespaceBody["top_logprobs"]?.intValue == 2)
    #expect(nullNamespaceBody["topLogprobs"] == nil)
    #expect(nullNamespaceBody["include"]?[0]?.stringValue == "reasoning.encrypted_content")
    #expect(nullNamespaceBody["xai"] == nil)

    let includeNullTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"xai responses"}"#))
    let includeNullProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: includeNullTransport))
    let includeNullModel = try includeNullProvider.responses("grok-4")

    _ = try await includeNullModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        providerOptions: ["xai": ["include": .null]]
    ))

    let includeNullBody = try decodeJSONBody(try #require((await includeNullTransport.requests()).first?.body))
    #expect(includeNullBody["include"] == nil)
}

@Test func xAIResponsesInputConverterOwnsSystemFilesAndToolOutputs() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai responses"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.responses("grok-4")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .system("Be precise."),
        AIMessage(role: .user, content: [
            .text("Read the uploaded file."),
            .providerReference(mimeType: "application/pdf", reference: ["xai": "file_xai_pdf"])
        ]),
        AIMessage(role: .assistant, content: [
            .text("I will call a tool."),
            .toolCall(AIToolCall(
                id: "call-1",
                name: "lookup",
                arguments: #"{"q":"xai"}"#,
                providerMetadata: ["xai": .object(["itemId": .string("fc_item_1")])]
            ))
        ]),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "call-1",
                toolName: "lookup",
                result: .object(["type": .string("execution-denied")])
            )
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input[0]["role"]?.stringValue == "system")
    #expect(input[0]["content"]?.stringValue == "Be precise.")
    #expect(input[1]["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(input[1]["content"]?[1]?["type"]?.stringValue == "input_file")
    #expect(input[1]["content"]?[1]?["file_id"]?.stringValue == "file_xai_pdf")
    #expect(input[2]["role"]?.stringValue == "assistant")
    #expect(input[2]["content"]?.stringValue == "I will call a tool.")
    #expect(input[3]["type"]?.stringValue == "function_call")
    #expect(input[3]["id"]?.stringValue == "fc_item_1")
    #expect(input[3]["call_id"]?.stringValue == "call-1")
    #expect(input[4]["type"]?.stringValue == "function_call_output")
    #expect(input[4]["output"]?.stringValue == "tool execution denied")

    let rejectingProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))
    let rejectingModel = try rejectingProvider.responses("grok-4")
    await #expect(throws: AIError.invalidArgument(argument: "messages", message: "xAI Responses requires a URL or Files API provider reference for non-image file parts.")) {
        _ = try await rejectingModel.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .file(mimeType: "application/pdf", data: Data("pdf".utf8), filename: "inline.pdf")
            ])
        ]))
    }
}

@Test func xAIToolsHelpersMirrorResponsesToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"xai tools"}"#))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.languageModel("grok-4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use xAI tools.")],
        tools: [
            "web": XAITools.webSearch(
                allowedDomains: ["example.com"],
                excludedDomains: ["blocked.example"],
                enableImageSearch: true,
                enableImageUnderstanding: true
            ),
            "x": XAITools.xSearch(
                allowedXHandles: ["xai"],
                excludedXHandles: ["old_handle"],
                fromDate: "2026-01-01",
                toDate: "2026-02-01",
                enableImageUnderstanding: true,
                enableVideoUnderstanding: true
            ),
            "code": XAITools.codeExecution(),
            "file": XAITools.fileSearch(vectorStoreIDs: ["vs_xai"], maxNumResults: 6),
            "mcp": XAITools.mcpServer(
                serverURL: "https://mcp.example.com",
                serverLabel: "docs",
                serverDescription: "Docs tools",
                allowedTools: ["search"],
                headers: ["x-tool": "yes"],
                authorization: "Bearer token"
            ),
            "image": XAITools.viewImage(),
            "video": XAITools.viewXVideo()
        ],
        toolChoice: ["type": "tool", "toolName": "web"]
    ))

    #expect(result.text == "xai tools")
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "toolChoice for server-side tool \"web\"")])
    let body = try decodeJSONBody(try #require((await transport.requests().first)?.body))
    #expect(body["tool_choice"] == nil)
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 7)
    let web = try #require(tools.first { $0["type"]?.stringValue == "web_search" })
    #expect(web["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(web["excluded_domains"]?[0]?.stringValue == "blocked.example")
    #expect(web["enable_image_search"]?.boolValue == true)
    #expect(web["enable_image_understanding"]?.boolValue == true)
    let xSearch = try #require(tools.first { $0["type"]?.stringValue == "x_search" })
    #expect(xSearch["allowed_x_handles"]?[0]?.stringValue == "xai")
    #expect(xSearch["excluded_x_handles"]?[0]?.stringValue == "old_handle")
    #expect(xSearch["from_date"]?.stringValue == "2026-01-01")
    #expect(xSearch["to_date"]?.stringValue == "2026-02-01")
    #expect(xSearch["enable_image_understanding"]?.boolValue == true)
    #expect(xSearch["enable_video_understanding"]?.boolValue == true)
    #expect(tools.contains { $0["type"]?.stringValue == "code_interpreter" })
    #expect(tools.contains { $0["type"]?.stringValue == "view_image" })
    #expect(tools.contains { $0["type"]?.stringValue == "view_x_video" })
    let fileSearch = try #require(tools.first { $0["type"]?.stringValue == "file_search" })
    #expect(fileSearch["vector_store_ids"]?[0]?.stringValue == "vs_xai")
    #expect(fileSearch["max_num_results"]?.intValue == 6)
    let mcp = try #require(tools.first { $0["type"]?.stringValue == "mcp" })
    #expect(mcp["server_url"]?.stringValue == "https://mcp.example.com")
    #expect(mcp["server_label"]?.stringValue == "docs")
    #expect(mcp["server_description"]?.stringValue == "Docs tools")
    #expect(mcp["allowed_tools"]?[0]?.stringValue == "search")
    #expect(mcp["headers"]?["x-tool"]?.stringValue == "yes")
    #expect(mcp["authorization"]?.stringValue == "Bearer token")
}

@Test func openResponsesProviderUsesConfiguredEndpointAndResponsesBody() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"reasoning","content":[{"text":"thinking"}]},{"type":"message","content":[{"text":"custom text"}]}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openResponses(
        name: "lmstudio",
        url: "https://open.example.test/custom/responses",
        settings: ProviderSettings(apiKey: "open-key", headers: ["X-Custom": "yes"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("Be terse."), .user("Hi")],
        temperature: 0.2,
        topP: 0.9,
        topK: 4,
        presencePenalty: 0.3,
        frequencyPenalty: 0.4,
        seed: 42,
        maxOutputTokens: 12,
        stopSequences: ["ignored"],
        responseFormat: .json(schema: ["type": "object"], name: "answer", description: "Answer schema"),
        tools: [
            "lookup": ["type": "object", "description": "Lookup things", "strict": true],
            "hosted": ["type": "provider", "id": "openai.web_search"]
        ],
        toolChoice: ["type": "tool", "toolName": "lookup"],
        providerOptions: [
            "lmstudio": [
                "reasoningEffort": "xhigh",
                "reasoningSummary": "auto",
                "unknown": "dropped"
            ]
        ],
        extraBody: ["previousResponseId": "ignored"]
    ))

    #expect(result.text == "custom text")
    #expect(result.usage?.totalTokens == 3)
    #expect(model.providerID == "lmstudio.responses")
    #expect(result.warnings.map(\.feature).contains("stopSequences"))
    #expect(result.warnings.map(\.feature).contains("topK"))
    #expect(result.warnings.map(\.feature).contains("seed"))
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://open.example.test/custom/responses")
    #expect(request.headers["authorization"] == "Bearer open-key")
    #expect(request.headers["x-custom"] == "yes")
    #expect(request.headers["user-agent"] == "ai-sdk/open-responses/1.0.16")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "local-model")
    #expect(body["instructions"]?.stringValue == "Be terse.")
    #expect(body["input"]?[0]?["type"]?.stringValue == "message")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["temperature"]?.doubleValue == 0.2)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["presence_penalty"]?.doubleValue == 0.3)
    #expect(body["frequency_penalty"]?.doubleValue == 0.4)
    #expect(body["max_output_tokens"]?.intValue == 12)
    #expect(body["reasoning"]?["effort"]?.stringValue == "xhigh")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["tools"]?.arrayValue?.count == 1)
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["tools"]?[0]?["description"]?.stringValue == "Lookup things")
    #expect(body["tools"]?[0]?["strict"]?.boolValue == true)
    #expect(body["tools"]?[0]?["parameters"]?["strict"] == nil)
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["name"]?.stringValue == "lookup")
    #expect(body["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(body["text"]?["format"]?["name"]?.stringValue == "answer")
    #expect(body["text"]?["format"]?["description"]?.stringValue == "Answer schema")
    #expect(body["text"]?["format"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["text"]?["format"]?["strict"]?.boolValue == true)
    #expect(body["previous_response_id"] == nil)
    #expect(body["unknown"] == nil)
    #expect(body["messages"] == nil)
}

@Test func openResponsesProviderAllowsOptionalAPIKeyAndValidatesProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom auth"}"#))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(headers: ["Authorization": "Bearer custom-key"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.providerID == "open-responses.responses")
    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer custom-key")
    #expect(request.headers["user-agent"] == "ai-sdk/open-responses/1.0.16")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.open-responses", message: "Open Responses provider options must be an object.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["open-responses": "bad"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.open-responses.reasoningEffort", message: "Open Responses reasoningEffort must be none, low, medium, high, or xhigh.")) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["open-responses": ["reasoningEffort": "minimal"]]
        ))
    }
}

@Test func openResponsesProviderPreservesFileNamesAndRichToolResultContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")
    let pdf = Data("pdf".utf8)
    let imageBytes = Data([0x89, 0x50, 0x4E, 0x47])

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Use files."),
            .file(mimeType: "application/pdf", data: pdf, filename: "brief.pdf"),
            .data(mimeType: "application/pdf", data: pdf),
            .file(mimeType: "image/png", data: imageBytes, filename: "ignored-image-name.png")
        ]),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"docs"}"#))
        ]),
        .toolResponses(toolResults: [
            AIToolResult(
                toolCallID: "call-1",
                toolName: "lookup",
                result: ["raw": "fallback"],
                modelOutput: [
                    "type": "content",
                    "value": [
                        ["type": "text", "text": "found"],
                        ["type": "image-data", "mediaType": "image/png", "data": "base64-image"],
                        ["type": "image-url", "url": "https://example.com/plot.png"],
                        ["type": "file-data", "mediaType": "application/pdf", "filename": "result.pdf", "data": "base64-pdf"],
                        ["type": "video-data", "data": "unsupported"]
                    ]
                ]
            )
        ])
    ]))

    #expect(result.text == "ok")
    #expect(result.warnings == [AIWarning(type: "other", message: "unsupported tool content part type: video-data")])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let firstContent = try #require(body["input"]?[0]?["content"]?.arrayValue)
    #expect(firstContent[1]["type"]?.stringValue == "input_file")
    #expect(firstContent[1]["filename"]?.stringValue == "brief.pdf")
    #expect(firstContent[1]["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
    #expect(firstContent[2]["type"]?.stringValue == "input_file")
    #expect(firstContent[2]["filename"]?.stringValue == "data")
    #expect(firstContent[3]["type"]?.stringValue == "input_image")
    #expect(firstContent[3]["image_url"]?.stringValue == "data:image/png;base64,\(imageBytes.base64EncodedString())")

    #expect(body["input"]?[1]?["type"]?.stringValue == "function_call")
    #expect(body["input"]?[1]?["call_id"]?.stringValue == "call-1")
    let toolOutput = try #require(body["input"]?[2]?["output"]?.arrayValue)
    #expect(toolOutput.map { $0["type"]?.stringValue } == ["input_text", "input_image", "input_image", "input_file"])
    #expect(toolOutput[0]["text"]?.stringValue == "found")
    #expect(toolOutput[1]["image_url"]?.stringValue == "data:image/png;base64,base64-image")
    #expect(toolOutput[2]["image_url"]?.stringValue == "https://example.com/plot.png")
    #expect(toolOutput[3]["filename"]?.stringValue == "result.pdf")
    #expect(toolOutput[3]["file_data"]?.stringValue == "data:application/pdf;base64,base64-pdf")
}

@Test func openResponsesProviderMapsFinishReasonsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-tool","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\"query\":\"weather\"}"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#),
        jsonResponse(#"{"id":"resp-length","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"function_call","id":"fc_2","call_id":"call_2","name":"lookup","arguments":"{}"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#),
        jsonResponse(#"{"id":"resp-filter","status":"incomplete","incomplete_details":{"reason":"content_filter"},"output":[{"type":"message","content":[{"text":"blocked"}]}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#)
    ])
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let toolResult = try await model.generate(LanguageModelRequest(messages: [.user("Use a tool.")]))
    let lengthResult = try await model.generate(LanguageModelRequest(messages: [.user("Use a tool.")]))
    let filterResult = try await model.generate(LanguageModelRequest(messages: [.user("Say something.")]))

    #expect(toolResult.text == "")
    #expect(toolResult.toolCalls.first?.id == "call_1")
    #expect(toolResult.finishReason == "tool-calls")
    #expect(lengthResult.finishReason == "length")
    #expect(filterResult.finishReason == "content-filter")
}

@Test func openResponsesProviderStreamsFinishReasonsLikeUpstream() async throws {
    let toolTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":""}}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let toolProvider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: toolTransport)
    )
    let toolModel = try toolProvider.languageModel("local-model")

    var toolCall: AIToolCall?
    var toolFinishReason: String?
    for try await part in toolModel.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, _):
            toolFinishReason = reason
        default:
            break
        }
    }

    #expect(toolCall?.id == "call_1")
    #expect(toolFinishReason == "tool-calls")

    let failedTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.failed","response":{"status":"failed","error":{"code":"server_error","message":"Nope"},"usage":{"input_tokens":1,"output_tokens":0,"total_tokens":1}}}

    """))
    let failedProvider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(apiKey: "open-key", transport: failedTransport)
    )
    let failedModel = try failedProvider.languageModel("local-model")

    var failedFinishReason: String?
    var failedTotalTokens: Int?
    for try await part in failedModel.stream(LanguageModelRequest(messages: [.user("Fail.")])) {
        if case let .finish(reason, usage) = part {
            failedFinishReason = reason
            failedTotalTokens = usage?.totalTokens
        }
    }

    #expect(failedFinishReason == "error")
    #expect(failedTotalTokens == 1)
}

@Test func perplexityLanguageUsesNativeChatShapeAndKeepsMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}],"citations":["https://example.com/a"],"images":[{"image_url":"https://img.example.com/a.png","origin_url":"https://origin.example.com","height":512,"width":768}],"usage":{"prompt_tokens":3,"completion_tokens":4,"total_tokens":7,"reasoning_tokens":1,"citation_tokens":2,"num_search_queries":1,"cost":{"request_cost":0.01,"total_cost":0.02}}}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Search carefully."),
            AIMessage(role: .user, content: [
                .text("Look at this."),
                .imageURL("https://example.com/image.png"),
                .file(mimeType: "application/pdf", data: Data("pdf".utf8), filename: "brief.pdf")
            ])
        ],
        temperature: 0.2,
        topP: 0.9,
        maxOutputTokens: 64,
        stopSequences: ["ignored"],
        extraBody: ["search_mode": "academic"]
    ))

    #expect(result.text == "answer")
    #expect(result.usage?.totalTokens == 7)
    #expect(result.usage?.inputTokensNoCache == 3)
    #expect(result.usage?.outputReasoningTokens == 1)
    #expect(result.usage?.outputTextTokens == 3)
    #expect(result.usage?.rawValue?["reasoning_tokens"]?.intValue == 1)
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "citation-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/a")
    #expect(result.sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(result.rawValue["citations"]?[0]?.stringValue == "https://example.com/a")
    #expect(result.rawValue["images"]?[0]?["image_url"]?.stringValue == "https://img.example.com/a.png")
    #expect(result.providerMetadata["perplexity"]?["images"]?[0]?["imageUrl"]?.stringValue == "https://img.example.com/a.png")
    #expect(result.providerMetadata["perplexity"]?["usage"]?["citationTokens"]?.intValue == 2)
    #expect(result.providerMetadata["perplexity"]?["usage"]?["numSearchQueries"]?.intValue == 1)
    #expect(result.providerMetadata["perplexity"]?["cost"]?["requestCost"]?.doubleValue == 0.01)
    #expect(result.providerMetadata["perplexity"]?["cost"]?["totalCost"]?.doubleValue == 0.02)
    #expect(result.requestMetadata.body?["model"]?.stringValue == "sonar")
    #expect(result.requestMetadata.body?["messages"]?[1]?["content"]?[2]?["file_name"]?.stringValue == "brief.pdf")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.perplexity.ai/chat/completions")
    #expect(request.headers["authorization"] == "Bearer pplx-key")
    #expect(request.headers["user-agent"] == "ai-sdk/perplexity/3.0.33")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "sonar")
    #expect(body["temperature"]?.doubleValue == 0.2)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["max_tokens"]?.intValue == 64)
    #expect(body["stop"] == nil)
    #expect(body["search_mode"]?.stringValue == "academic")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Search carefully.")
    let content = body["messages"]?[1]?["content"]
    #expect(content?[0]?["type"]?.stringValue == "text")
    #expect(content?[1]?["type"]?.stringValue == "image_url")
    #expect(content?[1]?["image_url"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(content?[2]?["type"]?.stringValue == "file_url")
    #expect(content?[2]?["file_url"]?["url"]?.stringValue == Data("pdf".utf8).base64EncodedString())
    #expect(content?[2]?["file_name"]?.stringValue == "brief.pdf")
}

@Test func perplexityLanguageAppliesTransformRequestBodyToGenerateAndStream() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-transform","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(
        apiKey: "pplx-key",
        transport: generateTransport,
        transformRequestBody: { body in
            var body = body
            body["search_mode"] = .string("academic")
            return body
        }
    ))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "answer")
    #expect(result.requestMetadata.body?["search_mode"]?.stringValue == "academic")
    let generateBody = try decodeJSONBody(try #require((await generateTransport.requests()).first?.body))
    #expect(generateBody["search_mode"]?.stringValue == "academic")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-transform","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"hi"},"finish_reason":"stop"}]}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.perplexity(settings: ProviderSettings(
        apiKey: "pplx-key",
        transport: streamTransport,
        transformRequestBody: { body in
            var body = body
            body["search_domain_filter"] = .array([.string("example.com")])
            return body
        }
    ))
    let streamModel = try streamProvider.languageModel("sonar")

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {}

    let streamBody = try decodeJSONBody(try #require((await streamTransport.requests()).first?.body))
    #expect(streamBody["stream"]?.boolValue == true)
    #expect(streamBody["search_domain_filter"]?[0]?.stringValue == "example.com")
}

@Test func perplexityLanguageMapsStructuredFormatWarningsAndMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-structured","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"{\\"ok\\":true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":6,"total_tokens":11}}
    """, headers: ["pplx-header": "structured"]))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("JSON")],
        topK: 3,
        presencePenalty: 0.2,
        frequencyPenalty: 0.4,
        seed: 42,
        maxOutputTokens: 32,
        stopSequences: ["###"],
        responseFormat: .json(schema: [
            "type": "object",
            "properties": ["ok": ["type": "boolean"]],
            "required": ["ok"]
        ]),
        reasoning: "custom",
        providerOptions: [
            "perplexity": [
                "search_recency_filter": "month"
            ]
        ],
        extraBody: [
            "perplexity": [
                "return_images": true
            ],
            "responseFormat": [
                "type": "json",
                "schema": ["type": "string"]
            ]
        ]
    ))

    #expect(result.text == "{\"ok\":true}")
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "topK"),
        AIWarning(type: "unsupported", feature: "stopSequences"),
        AIWarning(type: "unsupported", feature: "seed"),
        AIWarning(type: "unsupported", feature: "reasoning", message: "This provider does not support reasoning configuration.")
    ])
    #expect(result.responseMetadata.id == "ppl-structured")
    #expect(result.responseMetadata.modelID == "sonar")
    #expect(result.responseMetadata.headers["pplx-header"] == "structured")
    #expect(result.responseMetadata.body?["usage"]?["total_tokens"]?.intValue == 11)

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?["type"]?.stringValue == "json_schema")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["type"]?.stringValue == "object")
    #expect(body["response_format"]?["json_schema"]?["schema"]?["properties"]?["ok"]?["type"]?.stringValue == "boolean")
    #expect(body["responseFormat"] == nil)
    #expect(body["top_k"]?.intValue == 3)
    #expect(body["presence_penalty"]?.doubleValue == 0.2)
    #expect(body["frequency_penalty"]?.doubleValue == 0.4)
    #expect(body["max_tokens"]?.intValue == 32)
    #expect(body["stop"] == nil)
    #expect(body["seed"] == nil)
    #expect(body["reasoning"] == nil)
    #expect(body["return_images"]?.boolValue == true)
    #expect(body["search_recency_filter"]?.stringValue == "month")
    #expect(body["perplexity"] == nil)

    await #expect(throws: AIError.invalidArgument(argument: "messages", message: "Perplexity does not support tool messages.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            .toolResponses(toolResults: [
                AIToolResult(toolCallID: "call-1", toolName: "lookup", result: "done")
            ])
        ]))
    }
}

@Test func perplexityLanguageMapsMissingFinishReasonToOtherLikeUpstream() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-no-finish","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":null}]}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: generateTransport))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.finishReason == "other")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-no-finish","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"hi"},"finish_reason":null}]}

    data: [DONE]

    """))
    let streamProvider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("sonar")

    var finishReason: String?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finishMetadata(reason, _, _) = part {
            finishReason = reason
        }
    }

    #expect(finishReason == "other")
}

@Test func perplexityGenerateResponseValidationMatchesUpstreamSchema() async throws {
    let provider = try AIProviders.perplexity(settings: ProviderSettings(
        apiKey: "pplx-key",
        transport: RecordingTransport(response: jsonResponse("""
        {"id":"ppl-invalid","model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}
        """))
    ))
    let model = try provider.languageModel("sonar")

    await #expect(throws: AIError.invalidResponse(provider: "perplexity", message: "Perplexity response is invalid.")) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    }
}

@Test func perplexityLanguageStreamsNativeChunksWithUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"hel"},"finish_reason":null}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3},"citations":["https://example.com/a"]}

    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"lo"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4,"reasoning_tokens":1,"citation_tokens":1,"num_search_queries":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    var streamStartWarnings: [AIWarning]?
    var textLifecycle: [String] = []
    var sources: [AISource] = []
    var finishReason: String?
    var totalTokens: Int?
    var outputReasoningTokens: Int?
    var outputTextTokens: Int?
    var providerMetadata: [String: JSONValue] = [:]
    var metadata: AIResponseMetadata?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .streamStart(warnings):
            streamStartWarnings = warnings
        case let .textStart(id, _):
            textLifecycle.append("start:\(id)")
        case let .textDeltaPart(id, delta, _):
            textLifecycle.append("delta:\(id):\(delta)")
        case let .textEnd(id, _):
            textLifecycle.append("end:\(id)")
        case let .source(source):
            sources.append(source)
        case let .finishMetadata(reason, usage, metadata):
            finishReason = reason
            totalTokens = usage?.totalTokens
            outputReasoningTokens = usage?.outputReasoningTokens
            outputTextTokens = usage?.outputTextTokens
            providerMetadata = metadata
        case let .responseMetadata(value):
            metadata = value
        default:
            break
        }
    }

    #expect(streamStartWarnings == [])
    #expect(textLifecycle == ["start:0", "delta:0:hel", "delta:0:lo", "end:0"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "citation-0")
    #expect(sources[0].url == "https://example.com/a")
    #expect(sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(finishReason == "stop")
    #expect(totalTokens == 4)
    #expect(outputReasoningTokens == 1)
    #expect(outputTextTokens == 1)
    #expect(providerMetadata["perplexity"]?["usage"]?["citationTokens"]?.intValue == 1)
    #expect(providerMetadata["perplexity"]?["usage"]?["numSearchQueries"]?.intValue == 1)
    #expect(providerMetadata["perplexity"]?["images"] == .null)
    #expect(providerMetadata["perplexity"]?["cost"] == .null)
    #expect(metadata?.id == "ppl-1")
    #expect(metadata?.modelID == "sonar")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func perplexityLanguageStreamsParseErrorsAsErrorPartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: not-json

    data: [DONE]

    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    var errors: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .error(message, _):
            errors.append(message)
        case let .finishMetadata(reason, _, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(errors.count == 1)
    #expect(finishReason == "other")
}
