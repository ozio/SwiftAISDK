import Foundation
import Testing
@testable import ai_sdk_port

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
    #expect(request.headers["Authorization"] == "Bearer xai-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "grok-4")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 12)
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
        ]
    ))

    #expect(result.text == "xai tools")
    let body = try decodeJSONBody(try #require((await transport.requests().first)?.body))
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
    #expect(request.headers["Authorization"] == "Bearer hf-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "openai/gpt-oss-120b")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 24)
}

@Test func huggingFaceResponsesAliasAndUnsupportedFamiliesMatchProviderWrapper() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"hf text"}"#))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.responsesModel("openai/gpt-oss-120b")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(model.providerID == "huggingface.responses")
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "huggingface", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func huggingFaceLanguageMapsNativeResponsesContentAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-hf-1","model":"deepseek-ai/DeepSeek-V3-0324","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"usage":{"input_tokens":20,"output_tokens":50,"total_tokens":70},"output":[{"id":"reasoning-1","type":"reasoning","content":[{"type":"reasoning_text","text":"thinking"}]},{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\\"city\\":\\"Tokyo\\"}"},{"id":"mcp-1","type":"mcp_call","name":"search","arguments":"{\\"query\\":\\"AI\\"}","output":"found results"},{"id":"msg-1","type":"message","role":"assistant","content":[{"type":"output_text","text":"Answer with source.","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"}]}]}],"output_text":null}
    """))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be concise."),
            AIMessage(role: .user, content: [
                .text("Use the image."),
                .imageURL("https://example.com/image.png"),
                .file(mimeType: "image/png", data: Data([0, 1, 2, 3]), filename: "inline.png"),
                .file(mimeType: "text/plain", data: Data("ignored".utf8), filename: "ignored.txt")
            ])
        ],
        temperature: 0.4,
        topP: 0.8,
        maxOutputTokens: 64,
        tools: ["weather": ["type": "object", "properties": ["city": ["type": "string"]]]],
        extraBody: [
            "huggingface": .object([
                "metadata": ["trace": "abc"],
                "instructions": "Use citations.",
                "reasoningEffort": "low",
                "toolChoice": ["type": "tool", "toolName": "weather"]
            ])
        ]
    ))

    #expect(result.text == "Answer with source.")
    #expect(result.reasoning == "thinking")
    #expect(result.usage?.totalTokens == 70)
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
    #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "weather")
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["name"]?.stringValue == "weather")
    #expect(body["huggingface"] == nil)
}

@Test func huggingFaceLanguageStreamsReasoningTextAndToolCalls() async throws {
    let chunks = [
        #"data:{"type":"response.reasoning_text.delta","item_id":"reasoning-1","delta":"think"}"#,
        #"data:{"type":"response.output_text.delta","item_id":"msg-1","delta":"hello"}"#,
        #"data:{"type":"response.output_item.done","output_index":1,"item":{"id":"call-1","type":"function_call","call_id":"call_weather","name":"weather","arguments":"{\"city\":\"Tokyo\"}"}}"#,
        #"data:{"type":"response.completed","response":{"id":"resp-hf-1","status":"completed","incomplete_details":null,"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}"#
    ].map { Data(($0 + "\n\n").utf8) }
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], body: chunks.reduce(Data(), +)))
    let provider = try AIProviders.huggingFace(settings: ProviderSettings(apiKey: "hf-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    var text = ""
    var reasoning = ""
    var finalToolCall: AIToolCall?
    var finishUsage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .toolCall(toolCall):
            finalToolCall = toolCall
        case let .finish(_, usage):
            finishUsage = usage
        default:
            break
        }
    }

    #expect(reasoning == "think")
    #expect(text == "hello")
    #expect(finalToolCall?.id == "call_weather")
    #expect(finalToolCall?.name == "weather")
    #expect(finalToolCall?.arguments == #"{"city":"Tokyo"}"#)
    #expect(finishUsage?.totalTokens == 3)
}

@Test func openResponsesProviderUsesConfiguredEndpointAndResponsesBody() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom text","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openResponses(
        name: "lmstudio",
        url: "https://open.example.test/custom/responses",
        settings: ProviderSettings(apiKey: "open-key", headers: ["X-Custom": "yes"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        maxOutputTokens: 12,
        extraBody: ["previousResponseId": "resp-old"]
    ))

    #expect(result.text == "custom text")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://open.example.test/custom/responses")
    #expect(request.headers["Authorization"] == "Bearer open-key")
    #expect(request.headers["X-Custom"] == "yes")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "local-model")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
    #expect(body["max_output_tokens"]?.intValue == 12)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["messages"] == nil)
}

@Test func perplexityLanguageUsesNativeChatShapeAndKeepsMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}],"citations":["https://example.com/a"],"images":[{"image_url":"https://img.example.com/a.png","origin_url":"https://origin.example.com","height":512,"width":768}],"usage":{"prompt_tokens":3,"completion_tokens":4,"total_tokens":7,"citation_tokens":2,"num_search_queries":1,"cost":{"request_cost":0.01,"total_cost":0.02}}}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Search carefully."),
            AIMessage(role: .user, content: [
                .text("Look at this."),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: Data("pdf".utf8))
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
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "citation-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/a")
    #expect(result.sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(result.rawValue["citations"]?[0]?.stringValue == "https://example.com/a")
    #expect(result.rawValue["images"]?[0]?["image_url"]?.stringValue == "https://img.example.com/a.png")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.perplexity.ai/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer pplx-key")
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
    #expect(content?[2]?["file_name"]?.stringValue == "document-2.pdf")
}

@Test func perplexityLanguageStreamsNativeChunksWithUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"hel"},"finish_reason":null}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3},"citations":["https://example.com/a"]}

    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"lo"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4,"citation_tokens":1,"num_search_queries":1}}

    data: [DONE]

    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.languageModel("sonar")

    var deltas: [String] = []
    var sources: [AISource] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(deltas == ["hel", "lo"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "citation-0")
    #expect(sources[0].url == "https://example.com/a")
    #expect(sources[0].providerMetadata["perplexity"]?["citationIndex"]?.intValue == 0)
    #expect(totalTokens == 4)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Hi")
}

@Test func basetenChatUsesBearerAuthAndModelAPIBase() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"baseten"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: transport))
    let model = try provider.languageModel("deepseek-ai/DeepSeek-V3-0324")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "baseten")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://inference.baseten.co/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V3-0324")
}

@Test func basetenEmbeddingRequiresSyncModelURL() throws {
    let provider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    #expect(throws: AIError.self) {
        _ = try provider.embeddingModel("embeddings")
    }
}

@Test func basetenEmbeddingUsesSyncModelURL() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        baseURL: "https://model-123.api.baseten.co/environments/production/sync",
        transport: transport
    ))
    let model = try provider.embeddingModel("embeddings")

    let result = try await model.embed(EmbeddingRequest(values: ["hello"]))

    #expect(result.embeddings == [[0.1, 0.2]])
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://model-123.api.baseten.co/environments/production/sync/v1/embeddings")
    #expect(request.headers["Authorization"] == "Bearer baseten-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "embeddings")
    #expect(body["input"]?[0]?.stringValue == "hello")
}
