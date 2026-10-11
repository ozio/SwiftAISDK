import Foundation
import Testing
@testable import SwiftAISDK

private final class WeeklyProviderGroupBReasoningModel: LanguageModel, @unchecked Sendable {
    let providerID = "weekly-group-b"
    let modelID = "reasoning"
    let result: TextGenerationResult
    let streamParts: [LanguageStreamPart]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart]) {
        self.result = result
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            for part in streamParts { continuation.yield(part) }
            continuation.finish()
        }
    }
}

@Test func WeeklyProviderGroupB20260927ReasoningExtractionKeepsOverlappingTextIDs() async throws {
    let model = WeeklyProviderGroupBReasoningModel(
        result: TextGenerationResult(
            text: "<think>new reason</think>answer",
            reasoning: "prior reason",
            rawValue: .object([:])
        ),
        streamParts: [
            .textStart(id: "a"),
            .textStart(id: "b"),
            .textDeltaPart(id: "a", delta: "<think>A</think>alpha"),
            .textDeltaPart(id: "b", delta: "<think>B</think>beta"),
            .textEnd(id: "a"),
            .textEnd(id: "b"),
            .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
        ]
    )
    let wrapped = wrapLanguageModel(model, middleware: extractReasoningMiddleware(tagName: "think"))
    let request = LanguageModelRequest(messages: [.user("Think")])

    let generated = try await wrapped.generate(request)
    var streamed: [LanguageStreamPart] = []
    for try await part in wrapped.stream(request) { streamed.append(part) }

    #expect(generated.reasoning == "prior reason\nnew reason")
    #expect(generated.text == "answer")
    #expect(streamed == [
        .reasoningStart(id: "reasoning-0"),
        .reasoningDeltaPart(id: "reasoning-0", delta: "A"),
        .reasoningEnd(id: "reasoning-0"),
        .textStart(id: "a"),
        .textDeltaPart(id: "a", delta: "alpha"),
        .textEnd(id: "a"),
        .reasoningStart(id: "reasoning-1"),
        .reasoningDeltaPart(id: "reasoning-1", delta: "B"),
        .reasoningEnd(id: "reasoning-1"),
        .textStart(id: "b"),
        .textDeltaPart(id: "b", delta: "beta"),
        .textEnd(id: "b"),
        .finishMetadata(reason: "stop", usage: nil, providerMetadata: [:])
    ])
}

@Test func WeeklyProviderGroupB20260927DeepSeekV4ToolResultsKeepMultimodalContent() throws {
    let result = AIToolResult(
        toolCallID: "call-1",
        toolName: "lookup",
        result: [
            "type": "content",
            "value": [
                ["type": "text", "text": "found"],
                [
                    "type": "file",
                    "mediaType": "image/png",
                    "data": ["type": "url", "url": "https://example.com/result.png"],
                    "providerOptions": ["deepseek": ["imageDetail": "high"]]
                ]
            ]
        ]
    )
    let prepared = try deepSeekMessages(
        [AIMessage(role: .tool, content: [.toolResult(result)])],
        responseFormat: nil,
        modelID: "deepseek-v4-flash"
    )
    let content = try #require(prepared.messages.first?["content"]?.arrayValue)

    #expect(content[0]["type"]?.stringValue == "text")
    #expect(content[0]["text"]?.stringValue == "found")
    #expect(content[1]["type"]?.stringValue == "image_url")
    #expect(content[1]["image_url"]?["url"]?.stringValue == "https://example.com/result.png")
    #expect(content[1]["image_url"]?["detail"]?.stringValue == "high")

    let unsupported = AIToolResult(
        toolCallID: "call-svg",
        toolName: "lookup",
        result: [
            "type": "content",
            "value": [[
                "type": "file",
                "mediaType": "image/svg+xml",
                "data": ["type": "url", "url": "https://example.com/result.svg"]
            ]]
        ]
    )
    #expect(throws: AIError.invalidArgument(
        argument: "mediaType",
        message: "DeepSeek supports JPEG, PNG, GIF, and WebP image inputs."
    )) {
        _ = try deepSeekMessages(
            [AIMessage(role: .tool, content: [.toolResult(unsupported)])],
            responseFormat: nil,
            modelID: "deepseek-v4-flash"
        )
    }
}

@Test func WeeklyProviderGroupB20260927GatewayBrowserbaseToolsAndCancelBatch() async throws {
    let search = GatewayTools.browserbaseSearch(.init(numResults: 4))
    let fetch = GatewayTools.browserbaseFetch(.init(
        allowRedirects: true,
        allowInsecureSSL: false,
        proxies: true,
        format: "json",
        schema: ["type": "object"]
    ))
    #expect(search["id"]?.stringValue == "gateway.browserbase_search")
    #expect(search["args"]?["numResults"]?.intValue == 4)
    #expect(fetch["id"]?.stringValue == "gateway.browserbase_fetch")
    #expect(fetch["args"]?["allowInsecureSsl"]?.boolValue == false)
    #expect(fetch["args"]?["format"]?.stringValue == "json")

    let transport = RecordingTransport(response: jsonResponse(#"{"status":"completed","providerMetadata":{"trace":"ok"}}"#))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    _ = try await provider.experimentalBatch().cancelBatch(.init(batchID: "batch-42"))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(request.method == "POST")
    #expect(request.url.absoluteString.hasSuffix("/batch/cancel"))
    #expect(request.headers["user-agent"] == "ai-sdk-gateway/4.0.110")
    #expect(body["batchId"]?.stringValue == "batch-42")

    let invalidTransport = RecordingTransport(response: jsonResponse(#"{"providerMetadata":{"trace":"missing-status"}}"#))
    let invalidProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: invalidTransport))
    await #expect(throws: AIError.invalidResponse(
        provider: "gateway.batch",
        message: "Gateway batch response has an invalid status."
    )) {
        _ = try await invalidProvider.experimentalBatch().cancelBatch(.init(batchID: "batch-invalid"))
    }
}

@Test func WeeklyProviderGroupB20260927GroqRejectsEmptyChoices() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")

    await #expect(throws: AIError.invalidResponse(
        provider: "groq.chat",
        message: "Response did not contain any choices."
    )) {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
    }
    let request = try #require(await transport.requests().first)
    #expect(request.headers["user-agent"] == "ai-sdk-groq/4.0.59")
}

@Test func WeeklyProviderGroupB20260927OpenResponsesCustomToolsAndRegexNormalization() async throws {
    let prepared = try openAIResponsesTools(from: [
        "terminal": OpenResponsesTools.customTool(
            name: "terminal",
            description: "Run text",
            format: OpenResponsesTools.textFormat()
        ),
        "quiver": QuiverAITools.customTool(
            name: "quiver",
            description: "Render text",
            format: QuiverAITools.textFormat()
        ),
        "lookup": [
            "type": "object",
            "properties": [
                "code": ["type": "string", "pattern": "(?=abc)abc"]
            ]
        ]
    ])
    let terminal = try #require(prepared.tools.first { $0["name"]?.stringValue == "terminal" })
    let quiver = try #require(prepared.tools.first { $0["name"]?.stringValue == "quiver" })
    let lookup = try #require(prepared.tools.first { $0["name"]?.stringValue == "lookup" })

    #expect(terminal["type"]?.stringValue == "custom")
    #expect(terminal["format"]?["type"]?.stringValue == "text")
    #expect(quiver["type"]?.stringValue == "custom")
    #expect(prepared.customToolNames == ["terminal", "quiver"])
    #expect(lookup["strict"]?.boolValue == false)
    #expect(lookup["parameters"]?["properties"]?["code"]?["pattern"] == nil)
    #expect(prepared.warnings.contains { $0.feature == "JSON Schema pattern with regex lookaround" })

    let malformedGrammarTools = openResponsesFunctionTools(
        from: ["badGrammar": OpenResponsesTools.customTool(
            name: "badGrammar",
            format: .object([
                "type": "grammar",
                "syntax": "peg",
                "definition": "value"
            ])
        )],
        customToolID: "open-responses.custom"
    )
    let malformedGrammar = try #require(malformedGrammarTools.first)
    #expect(malformedGrammar["format"] == nil)

    var streamTools = OpenAIResponsesStreamingToolCalls(providerID: "open-responses.responses")
    _ = streamTools.apply(event: [
        "type": "response.output_item.added",
        "output_index": 0,
        "item": [
            "type": "function_call", "id": "item-f", "call_id": "call-f",
            "name": "lookup", "arguments": ""
        ]
    ])
    _ = streamTools.apply(event: [
        "type": "response.function_call_arguments.done",
        "item_id": "item-f", "output_index": 0, "arguments": "{\"query\":\"swift\"}"
    ])
    let functionDone = streamTools.apply(event: [
        "type": "response.output_item.done",
        "output_index": 0,
        "item": [
            "type": "function_call", "id": "item-f", "call_id": "call-f",
            "name": "lookup", "arguments": ""
        ]
    ])
    let functionCall = try #require(functionDone.compactMap { part -> AIToolCall? in
        if case let .toolCall(call) = part { return call }
        return nil
    }.first)
    #expect(functionCall.arguments == "{\"query\":\"swift\"}")

    _ = streamTools.apply(event: [
        "type": "response.output_item.added",
        "output_index": 1,
        "item": [
            "type": "custom_tool_call", "id": "item-c", "call_id": "call-c",
            "name": "terminal", "input": ""
        ]
    ])
    _ = streamTools.apply(event: [
        "type": "response.custom_tool_call_input.done",
        "item_id": "item-c", "output_index": 1, "input": "run tests"
    ])
    let customDone = streamTools.apply(event: [
        "type": "response.output_item.done",
        "output_index": 1,
        "item": [
            "type": "custom_tool_call", "id": "item-c", "call_id": "call-c",
            "name": "terminal", "input": ""
        ]
    ])
    let customCall = try #require(customDone.compactMap { part -> AIToolCall? in
        if case let .toolCall(call) = part { return call }
        return nil
    }.first)
    #expect(customCall.arguments == #""run tests""#)

    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-open","status":"completed","output_text":"ok"}"#))
    let provider = try AIProviders.openResponses(
        name: "local",
        url: "https://example.com/v1/responses",
        settings: ProviderSettings(apiKey: "key", transport: transport),
        dynamicHeaders: { ["x-dynamic": "fresh"] },
        userAgentSuffix: "example-open-responses/1.0"
    )
    _ = try await provider.languageModel("model").generate(LanguageModelRequest(
        messages: [.user("Hi")],
        responseFormat: .json(),
        tools: ["terminal": OpenResponsesTools.customTool(name: "terminal")]
    ))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"]?[0]?["type"]?.stringValue == "custom")
    #expect(body["text"]?["format"]?["type"]?.stringValue == "json_object")
    #expect(request.headers["x-dynamic"] == "fresh")
    #expect(request.headers["user-agent"] == "example-open-responses/1.0")
}

@Test func WeeklyProviderGroupB20260927OpenAIChatKeepsAudioTranscriptAsText() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"choices":[{"message":{"content":null,"audio":{"transcript":"spoken answer"}},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"","audio":{"transcript":"empty fallback"}},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"written answer","audio":{"transcript":"ignored transcript"}},"finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: transport))
    let model = try provider.chatModel("gpt-audio")
    let result = try await model.generate(.init(messages: [.user("Speak")]))
    let emptyFallback = try await model.generate(.init(messages: [.user("Speak")]))
    let written = try await model.generate(.init(messages: [.user("Speak")]))

    #expect(result.text == "spoken answer")
    #expect(result.content.contains(.text("spoken answer")))
    #expect(emptyFallback.text == "empty fallback")
    #expect(emptyFallback.content == [.text("empty fallback")])
    #expect(written.text == "written answer")
    #expect(written.content == [.text("written answer")])
    let request = try #require(await transport.requests().first)
    #expect(request.headers["user-agent"] == "ai-sdk-openai/4.0.91")

    let responsesTransport = RecordingTransport(response: jsonResponse(#"{"id":"resp-sol","status":"completed","output_text":"done"}"#))
    let responsesProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: responsesTransport))
    _ = try await responsesProvider.languageModel("gpt-6-sol").generate(LanguageModelRequest(
        messages: [.user("Think")],
        providerOptions: ["openai": ["reasoningEffortUpdate": "none"]]
    ))
    let responsesBody = try decodeJSONBody(try #require((await responsesTransport.requests()).first?.body))
    #expect(responsesBody["input"]?[0]?["type"]?.stringValue == "configuration_update")
    #expect(responsesBody["input"]?[0]?["reasoning"]?["effort"]?.stringValue == "none")

    await #expect(throws: AIError.invalidArgument(
        argument: "messages.providerMetadata.openai.reasoningEffortUpdate",
        message: "Message-level reasoningEffortUpdate must be none, low, medium, high, xhigh, or max."
    )) {
        _ = try await responsesProvider.languageModel("gpt-6-sol").generate(LanguageModelRequest(messages: [
            AIMessage(role: .system, content: [], providerMetadata: ["openai": ["reasoningEffortUpdate": 42]]),
            .user("Think")
        ]))
    }
}

@Test func WeeklyProviderGroupB20260927PerplexityAgentDefaultAndSonarCompatibility() async throws {
    let agentTransport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","created_at":1,"model":"pplx","object":"response","status":"completed","output":[{"type":"message","id":"msg-1","content":[{"type":"output_text","text":"agent answer","annotations":[{"url":"https://example.com/source","title":"Source"}]}]},{"type":"search_results","results":[{"id":7,"title":"Source","url":"https://example.com/source","snippet":"evidence"}]}],"usage":{"input_tokens":5,"output_tokens":3,"total_tokens":8,"input_tokens_details":{"cached_tokens":2},"output_tokens_details":{"reasoning_tokens":1},"tool_calls_details":{"web_search":{"invocation":1}},"cost":{"total_cost":0.01,"currency":"USD"}}}
    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: agentTransport))
    let agentModel = try provider.languageModel("fast")
    let result = try await agentModel.generate(LanguageModelRequest(
        messages: [.user("Research")],
        responseFormat: .json(schema: ["type": "object"], name: "result"),
        tools: ["lookup": [
            "type": "object",
            "description": "Lookup",
            "strict": true,
            "properties": ["query": ["type": "string"]]
        ]],
        providerOptions: ["perplexity": [
            "instructions": "Be precise",
            "maxSteps": 4,
            "models": ["sonar"],
            "reasoning": ["effort": "high"],
            "skills": [["type": "builtin", "name": "office/pdf"]]
        ]]
    ))
    let agentRequest = try #require(await agentTransport.requests().first)
    let agentBody = try decodeJSONBody(try #require(agentRequest.body))
    #expect(agentRequest.url.absoluteString == "https://api.perplexity.ai/v1/agent")
    #expect(agentRequest.headers["user-agent"] == "ai-sdk-perplexity/5.0.10")
    #expect(agentBody["preset"]?.stringValue == "fast")
    #expect(agentBody["model"] == nil)
    #expect(agentBody["max_steps"]?.intValue == 4)
    #expect(agentBody["tools"]?[0]?["description"]?.stringValue == "Lookup")
    #expect(agentBody["tools"]?[0]?["strict"]?.boolValue == true)
    #expect(agentBody["tools"]?[0]?["parameters"]?["description"] == nil)
    #expect(agentBody["tools"]?[0]?["parameters"]?["strict"] == nil)
    #expect(agentBody["response_format"]?["json_schema"]?["description"] == nil)
    #expect(result.text == "agent answer")
    #expect(result.sources.count == 1)
    #expect(result.sources.first?.id == "7")
    #expect(result.usage?.inputTokensCacheRead == 2)
    #expect(result.usage?.outputReasoningTokens == 1)

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.perplexity.max_steps",
        message: "Perplexity max_steps must be a positive integer."
    )) {
        _ = try await agentModel.generate(.init(
            messages: [.user("Research")],
            providerOptions: ["perplexity": ["maxSteps": 1.5]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.perplexity.reasoning.effort",
        message: "Perplexity reasoning effort is unsupported."
    )) {
        _ = try await agentModel.generate(.init(
            messages: [.user("Research")],
            providerOptions: ["perplexity": ["reasoning": ["effort": 42]]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.perplexity.tools",
        message: "Perplexity mcp tools require server_label and server_url strings."
    )) {
        _ = try await agentModel.generate(.init(
            messages: [.user("Research")],
            providerOptions: ["perplexity": ["tools": [["type": "mcp"]]]]
        ))
    }

    let failedBody = #"{"id":"resp-failed","created_at":1,"model":"pplx","object":"response","status":"failed","output":[],"error":{"message":"quota"}}"#
    let failedTransport = RecordingTransport(response: jsonResponse(failedBody))
    let failedProvider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: failedTransport))
    do {
        _ = try await failedProvider.languageModel("fast").generate(.init(messages: [.user("Research")]))
        Issue.record("Expected Perplexity failed response to throw an API call error")
    } catch let error as AIError {
        guard case let .apiCall(apiError) = error else {
            Issue.record("Expected Perplexity API call error, received \(error)")
            return
        }
        #expect(apiError.statusCode == 400)
        #expect(apiError.isRetryable == false)
        #expect(apiError.responseBody == failedBody)
    }

    let sonarTransport = RecordingTransport(response: jsonResponse(#"{"id":"chat-1","created":1,"model":"sonar","choices":[{"message":{"role":"assistant","content":"sonar answer"},"finish_reason":"stop"}]}"#))
    let sonarProvider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: sonarTransport))
    let sonar = try await sonarProvider.sonarModel("sonar").generate(.init(messages: [.user("Hi")]))
    #expect(sonar.text == "sonar answer")
    #expect(try #require(await sonarTransport.requests().first).url.absoluteString == "https://api.perplexity.ai/chat/completions")
}

@Test func WeeklyProviderGroupB20260927QuiverArrowUsesResponsesAndCustomTools() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-q","status":"completed","output_text":"arrow answer"}"#))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let result = try await provider.languageModel("arrow-2").generate(LanguageModelRequest(
        messages: [.user("Draw")],
        responseFormat: .json(schema: ["type": "object"], name: "drawing"),
        tools: ["draw": QuiverAITools.customTool(name: "draw", format: QuiverAITools.textFormat())],
        providerOptions: ["quiverai": ["reasoningEffort": "xhigh", "reasoningSummary": "auto"]]
    ))
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(request.url.absoluteString == "https://api.quiver.ai/v1/responses")
    #expect(request.headers["user-agent"] == "ai-sdk-quiverai/2.0.59")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "custom")
    #expect(body["reasoning"]?["effort"]?.stringValue == "xhigh")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["text"] == nil)
    #expect(result.text == "arrow answer")
    #expect(result.warnings.contains { $0.feature == "responseFormat" })

    let responseErrorTransport = RecordingTransport(response: jsonResponse(#"{"error":{"message":"slow down","status_code":429}}"#))
    let responseErrorProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: responseErrorTransport))
    do {
        _ = try await responseErrorProvider.languageModel("arrow-2").generate(.init(messages: [.user("Draw")]))
        Issue.record("Expected Quiver response error to throw")
    } catch let error as AIError {
        guard case let .apiCall(apiError) = error else {
            Issue.record("Expected Quiver API call error, received \(error)")
            return
        }
        #expect(apiError.statusCode == 429)
        #expect(apiError.isRetryable)
        #expect(apiError.responseBody.contains("status_code"))
    }

    let fractionalStatusTransport = RecordingTransport(response: jsonResponse(#"{"error":{"message":"bad fractional status","status_code":429.5}}"#))
    let fractionalStatusProvider = try AIProviders.quiverAI(settings: ProviderSettings(
        apiKey: "quiver-key",
        transport: fractionalStatusTransport
    ))
    do {
        _ = try await fractionalStatusProvider.languageModel("arrow-2").generate(.init(messages: [.user("Draw")]))
        Issue.record("Expected Quiver fractional response status to throw")
    } catch let error as AIError {
        guard case let .apiCall(apiError) = error else {
            Issue.record("Expected Quiver fractional-status API call error, received \(error)")
            return
        }
        #expect(apiError.statusCode == 400)
        #expect(apiError.isRetryable == false)
        #expect(apiError.responseBody.contains("429.5"))
    }

    let failedResponse = AIHTTPResponse(
        statusCode: 409,
        headers: ["content-type": "application/json"],
        body: Data(#"{"status":409,"code":"conflict","message":"conflict","request_id":"req-1"}"#.utf8)
    )
    let failedTransport = RecordingTransport(response: failedResponse)
    let failedProvider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: failedTransport))
    do {
        _ = try await failedProvider.languageModel("arrow-2").generate(.init(messages: [.user("Draw")]))
        Issue.record("Expected Quiver failed HTTP response to throw")
    } catch let error as AIError {
        guard case let .apiCall(apiError) = error else {
            Issue.record("Expected Quiver failed-response API call error, received \(error)")
            return
        }
        #expect(apiError.statusCode == 409)
        #expect(apiError.isRetryable == false)
        #expect(apiError.responseBody == "conflict")
    }
}

@Test func WeeklyProviderGroupB20260927XAIResponsesMapsNewOptions() throws {
    let prepared = try xaiResponsesPreparedRequest(
        modelID: "grok-4",
        providerID: "xai.responses",
        request: LanguageModelRequest(
            messages: [.user("Hi")],
            topK: 17,
            providerOptions: ["xai": [
                "reasoningEffort": "high",
                "reasoningSummary": "detailed",
                "minP": 0.2,
                "maxTurns": 3,
                "parallelToolCalls": false,
                "promptCacheKey": "cache-1",
                "safetyIdentifier": "safe-1",
                "user": "user-1",
                "store": false
            ]]
        ),
        stream: false,
        transformRequestBody: nil
    )
    #expect(prepared.body["top_k"]?.intValue == 17)
    #expect(prepared.body["min_p"]?.doubleValue == 0.2)
    #expect(prepared.body["max_turns"]?.intValue == 3)
    #expect(prepared.body["parallel_tool_calls"]?.boolValue == false)
    #expect(prepared.body["prompt_cache_key"]?.stringValue == "cache-1")
    #expect(prepared.body["safety_identifier"]?.stringValue == "safe-1")
    #expect(prepared.body["user"]?.stringValue == "user-1")
    #expect(prepared.body["reasoning"]?["effort"]?.stringValue == "high")
    #expect(prepared.body["reasoning"]?["summary"] == nil)
    #expect(prepared.body["include"]?.arrayValue?.contains(.string("reasoning.encrypted_content")) == true)
    #expect(!prepared.warnings.contains { $0.feature == "topK" })
}

@Test func WeeklyProviderGroupB20260927XAIVideo15MapsStorageKeyframesAndLastFrame() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-1"}"#),
        jsonResponse(#"{"status":"done","progress":100,"video":{"respect_moderation":true,"duration":4,"file_output":{"file_id":"file-1","filename":"clip.mp4","public_url":"https://x.ai/clip.mp4","expires_at":9,"public_url_expires_at":8},"storage_error":"mirror failed"},"usage":{"cost_in_usd_ticks":12}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let result = try await provider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
        prompt: "A scene",
        frameImages: [
            .init(image: .init(url: "https://example.com/first.png"), frameType: .firstFrame),
            .init(image: .init(url: "https://example.com/last.png"), frameType: .lastFrame)
        ],
        generateAudio: true,
        providerOptions: ["xai": [
            "pollIntervalMs": 1,
            "keyframes": [["imageUrl": "https://example.com/key.png", "timestampSeconds": 2]],
            "storageOptions": [
                "filename": "clip.mp4",
                "expiresAfter": 600,
                "publicUrl": ["expiresAfter": 3600]
            ]
        ]]
    ))
    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests.first?.body))
    #expect(requests.first?.headers["user-agent"] == "ai-sdk-xai/5.0.20")
    #expect(body["generate_audio"]?.boolValue == true)
    #expect(body["keyframes"]?[0]?["image"]?["url"]?.stringValue == "https://example.com/key.png")
    #expect(body["keyframes"]?[0]?["timestamp_s"]?.intValue == 2)
    #expect(body["last_frame"]?["url"]?.stringValue == "https://example.com/last.png")
    #expect(body["storage_options"]?["expires_after"]?.intValue == 600)
    #expect(body["storage_options"]?["public_url"]?["expires_after"]?.intValue == 3600)
    #expect(result.urls == ["https://x.ai/clip.mp4"])
    #expect(result.providerMetadata["xai"]?["fileOutput"]?["fileId"]?.stringValue == "file-1")
    #expect(result.providerMetadata["xai"]?["storageError"]?.stringValue == "mirror failed")

    let audioTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-audio"}"#),
        jsonResponse(#"{"status":"done","progress":100,"video":{"url":"https://x.ai/audio-reference.mp4"}}"#)
    ])
    let audioProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: audioTransport))
    let audioResult = try await audioProvider.videoModel("grok-imagine-video-1.5").generateVideo(VideoGenerationRequest(
        prompt: "Animate voices",
        frameImages: [
            .init(image: .init(url: "https://example.com/first.png"), frameType: .firstFrame)
        ],
        inputReferences: [
            ImageInputFile(url: "https://example.com/voice-1.mp3", mediaType: "audio/mpeg"),
            ImageInputFile(url: "https://example.com/voice-2.wav", mediaType: "audio/wav")
        ],
        providerOptions: ["xai": [
            "pollIntervalMs": 1,
            "referenceVoiceIds": ["preset-1", "preset-2"]
        ]]
    ))
    let audioRequests = await audioTransport.requests()
    let audioBody = try decodeJSONBody(try #require(audioRequests.first?.body))
    let audioReferences = try #require(audioBody["reference_audios"]?.arrayValue)
    #expect(audioBody["reference_images"] == nil)
    #expect(audioReferences.count == 3)
    #expect(audioReferences[0]["url"]?.stringValue == "https://example.com/voice-1.mp3")
    #expect(audioReferences[1]["url"]?.stringValue == "https://example.com/voice-2.wav")
    #expect(audioReferences[2]["voice_id"]?.stringValue == "preset-1")
    #expect(audioResult.warnings.contains {
        $0.feature == "inputReferences" && $0.message?.contains("at most 3 audio references") == true
    })
}

@Test func WeeklyProviderGroupB20260927GatewayConditionalEvaluationFallbacks() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "answers": {"correct": {"type": "boolean", "probability": 0.8}},
      "model": "openai/gpt-5.6-sol",
      "providerMetadata": {"gateway": {"routing": {"modelAttempts": []}}}
    }
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(
        apiKey: "gateway-key",
        baseURL: "https://api.test.com",
        transport: transport
    ))
    let model = try provider.evaluationModel("typesafe-ai/jev")
    let providerOptions: [String: JSONValue] = [
        "gateway": [
            "models": [
                [
                    "model": "openai/gpt-5.6-sol",
                    "when": [
                        "any": [
                            [
                                "question": "correct",
                                "probabilityBetween": [0.4, 0.6]
                            ],
                            [
                                "atLeast": [
                                    "count": 1,
                                    "conditions": [
                                        [
                                            "question": "correct",
                                            "confidenceBelow": 0.7
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "anthropic/claude-sonnet-5"
            ],
            "order": ["openai"],
            "serviceOwnedOption": ["nested": ["value", 1, true]]
        ],
        "typesafe": ["effort": "high"]
    ]

    let result = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
        state: "The answer is correct.",
        questions: ["correct": .boolean(instructions: "Is this correct?")],
        providerOptions: providerOptions
    ))

    #expect(result.response?.modelID == "openai/gpt-5.6-sol")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["providerOptions"] == .object(providerOptions))

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.gateway.models",
        message: "Gateway probabilityBetween minimum must not exceed its maximum."
    )) {
        _ = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
            state: "state",
            questions: ["correct": .boolean(instructions: "Correct?")],
            providerOptions: ["gateway": [
                "models": [[
                    "model": "openai/gpt-5.6-sol",
                    "when": [
                        "question": "correct",
                        "probabilityBetween": [0.7, 0.3]
                    ]
                ]]
            ]]
        ))
    }

    var tooDeep: JSONValue = [
        "question": "correct",
        "confidenceBelow": 0.5
    ]
    for _ in 0..<5 {
        tooDeep = ["any": [tooDeep]]
    }
    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.gateway.models",
        message: "Gateway decision fallback conditions can be nested at most 5 levels deep."
    )) {
        _ = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
            state: "state",
            questions: ["correct": .boolean(instructions: "Correct?")],
            providerOptions: ["gateway": [
                "models": [[
                    "model": "openai/gpt-5.6-sol",
                    "when": tooDeep
                ]]
            ]]
        ))
    }
    #expect(await transport.requests().count == 1)
}

@Test func WeeklyProviderGroupB20260927PerplexityAcceptsNullAgentStreamFields() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.keepalive","sequence_number":null,"response":null,"item":null,"output_index":null,"item_id":null,"content_index":null,"delta":null,"text":null,"thought":null,"queries":null,"urls":null,"results":null,"contents":null,"error":null}

    data: {"type":"response.reasoning.started","sequence_number":0,"thought":null}

    data: {"type":"response.reasoning.fetch_url_results","call_id":"call-1","sequence_number":1,"thought":"Fetched content from 0 URLs","contents":null}

    data: {"type":"response.reasoning.search_results","sequence_number":2,"results":null}

    data: {"type":"response.reasoning.stopped","sequence_number":3}

    data: {"type":"response.output_text.delta","item_id":"msg-1","output_index":0,"content_index":null,"delta":"Hello"}

    data: {"type":"response.output_text.done","item_id":"msg-1","output_index":0,"content_index":null,"text":null}

    data: [DONE]

    """))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(
        apiKey: "pplx-key",
        transport: transport
    ))
    let model = try provider.languageModel("fast")

    var parts: [LanguageStreamPart] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Research")])) {
        parts.append(part)
    }

    let hasError = parts.contains { part in
        if case .error = part { return true }
        return false
    }
    #expect(!hasError)
    #expect(parts.contains(.reasoningStart(id: "reasoning-0")))
    #expect(parts.contains(.reasoningDeltaPart(
        id: "reasoning-0",
        delta: "Fetched content from 0 URLs"
    )))
    #expect(parts.contains(.reasoningEnd(id: "reasoning-0")))
    #expect(parts.contains(.textStart(id: "msg-1")))
    #expect(parts.contains(.textDeltaPart(id: "msg-1", delta: "Hello")))
    #expect(parts.contains(.textEnd(id: "msg-1")))
}
