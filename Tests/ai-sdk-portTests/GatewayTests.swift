import Foundation
import Testing
@testable import ai_sdk_port

@Test func gatewayLanguageUsesGatewayEndpointAndModelHeaders() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"via gateway"}],"finishReason":"stop"}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport), teamIDOrSlug: "team_123")
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "via gateway")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/language-model")
    #expect(request.headers["Authorization"] == "Bearer gateway-key")
    #expect(request.headers["x-vercel-ai-gateway-team"] == "team_123")
    #expect(request.headers["ai-language-model-id"] == "openai/gpt-4.1-mini")
    #expect(request.headers["ai-language-model-streaming"] == "false")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hi")
}

@Test func gatewayLanguageMapsToolsToolChoiceAndContentToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"checking"},{"type":"source","sourceType":"url","id":"src_1","url":"https://example.com/a","title":"Example A","providerMetadata":{"gateway":{"rank":1}}},{"type":"tool-call","toolCallId":"call_1","toolName":"lookup","input":"{\\"query\\":\\"weather\\"}"},{"type":"tool-call","toolCallId":"gateway_search","toolName":"perplexity_search","input":{"query":"latest news"},"providerExecuted":true}],"finishReason":"stop","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [AIMessage(role: .user, content: [
            .text("Use tools."),
            .imageURL("https://example.com/image.png"),
            .data(mimeType: "application/pdf", data: Data("%PDF".utf8))
        ])],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]]
            ],
            "gateway.perplexity_search": [
                "type": "provider",
                "id": "gateway.perplexity_search",
                "name": "perplexity_search",
                "args": ["maxResults": 5]
            ]
        ],
        extraBody: [
            "toolChoice": ["type": "tool", "toolName": "lookup"],
            "providerOptions": ["gateway": ["order": ["openai", "anthropic"]]]
        ]
    ))

    #expect(result.text == "checking")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 5)
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(try decodeJSONBody(Data(result.toolCalls[1].arguments.utf8))["query"]?.stringValue == "latest news")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].id == "src_1")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/a")
    #expect(result.sources[0].title == "Example A")
    #expect(result.sources[0].providerMetadata["gateway"]?["rank"]?.intValue == 1)

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?[0]?["content"]?[1]?["data"]?["type"]?.stringValue == "url")
    #expect(body["prompt"]?[0]?["content"]?[1]?["data"]?["url"]?.stringValue == "https://example.com/image.png")
    #expect(body["prompt"]?[0]?["content"]?[2]?["data"]?["type"]?.stringValue == "data")
    #expect(body["prompt"]?[0]?["content"]?[2]?["data"]?["data"]?.stringValue == Data("%PDF".utf8).base64EncodedString())
    #expect(body["prompt"]?[0]?["content"]?[2]?["mediaType"]?.stringValue == "application/pdf")
    let tools = try #require(body["tools"]?.arrayValue)
    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "lookup")
    #expect(functionTool["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["inputSchema"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    let providerTool = try #require(tools.first { $0["type"]?.stringValue == "provider" })
    #expect(providerTool["id"]?.stringValue == "gateway.perplexity_search")
    #expect(providerTool["name"]?.stringValue == "perplexity_search")
    #expect(providerTool["args"]?["maxResults"]?.intValue == 5)
    #expect(body["toolChoice"]?["type"]?.stringValue == "tool")
    #expect(body["toolChoice"]?["toolName"]?.stringValue == "lookup")
    #expect(body["providerOptions"]?["gateway"]?["order"]?[0]?.stringValue == "openai")
}

@Test func gatewayToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"finishReason":"stop"}
    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "gateway.perplexity_search": GatewayTools.perplexitySearch(
                maxResults: 5,
                maxTokensPerPage: 3000,
                maxTokens: 9000,
                country: "US",
                searchDomainFilter: ["nature.com"],
                searchLanguageFilter: ["en"],
                searchRecencyFilter: "week"
            ),
            "gateway.parallel_search": GatewayTools.parallelSearch(
                mode: "agentic",
                maxResults: 3,
                includeDomains: ["example.com"],
                excludeDomains: ["spam.example"],
                afterDate: "2024-01-01",
                maxCharsPerResult: 500,
                maxCharsTotal: 2000,
                maxAgeSeconds: 60
            )
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let perplexitySearch = try #require(tools.first { $0["id"]?.stringValue == "gateway.perplexity_search" })
    #expect(perplexitySearch["type"]?.stringValue == "provider")
    #expect(perplexitySearch["name"]?.stringValue == "perplexity_search")
    #expect(perplexitySearch["args"]?["maxResults"]?.intValue == 5)
    #expect(perplexitySearch["args"]?["maxTokensPerPage"]?.intValue == 3000)
    #expect(perplexitySearch["args"]?["maxTokens"]?.intValue == 9000)
    #expect(perplexitySearch["args"]?["country"]?.stringValue == "US")
    #expect(perplexitySearch["args"]?["searchDomainFilter"]?[0]?.stringValue == "nature.com")
    #expect(perplexitySearch["args"]?["searchLanguageFilter"]?[0]?.stringValue == "en")
    #expect(perplexitySearch["args"]?["searchRecencyFilter"]?.stringValue == "week")

    let parallelSearch = try #require(tools.first { $0["id"]?.stringValue == "gateway.parallel_search" })
    #expect(parallelSearch["type"]?.stringValue == "provider")
    #expect(parallelSearch["name"]?.stringValue == "parallel_search")
    #expect(parallelSearch["args"]?["mode"]?.stringValue == "agentic")
    #expect(parallelSearch["args"]?["maxResults"]?.intValue == 3)
    #expect(parallelSearch["args"]?["sourcePolicy"]?["includeDomains"]?[0]?.stringValue == "example.com")
    #expect(parallelSearch["args"]?["sourcePolicy"]?["excludeDomains"]?[0]?.stringValue == "spam.example")
    #expect(parallelSearch["args"]?["sourcePolicy"]?["afterDate"]?.stringValue == "2024-01-01")
    #expect(parallelSearch["args"]?["excerpts"]?["maxCharsPerResult"]?.intValue == 500)
    #expect(parallelSearch["args"]?["excerpts"]?["maxCharsTotal"]?.intValue == 2000)
    #expect(parallelSearch["args"]?["fetchPolicy"]?["maxAgeSeconds"]?.intValue == 60)
}

@Test func gatewayLanguageStreamsV4ReasoningAndToolInputChunks() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"text-delta","id":"txt","delta":"Hello"}

    data: {"type":"reasoning-delta","id":"r","delta":"think"}

    data: {"type":"source","sourceType":"document","id":"doc_1","title":"Report","mediaType":"application/pdf","filename":"report.pdf","providerMetadata":{"gateway":{"page":2}}}

    data: {"type":"tool-input-start","id":"call_1","toolName":"lookup"}

    data: {"type":"tool-input-delta","id":"call_1","delta":"{\\"query\\":"}

    data: {"type":"tool-input-delta","id":"call_1","delta":"\\"weather\\"}"}

    data: {"type":"tool-input-end","id":"call_1"}

    data: {"type":"finish","finishReason":"stop","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}

    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.languageModel("openai/gpt-4.1-mini")

    var textDeltas: [String] = []
    var reasoningDeltas: [String] = []
    var argumentDeltas: [String] = []
    var sources: [AISource] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .textDelta(delta):
            textDeltas.append(delta)
        case let .reasoningDelta(delta):
            reasoningDeltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .toolCallDelta(_, _, argumentsDelta, _):
            argumentDeltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(textDeltas == ["Hello"])
    #expect(reasoningDeltas == ["think"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "doc_1")
    #expect(sources[0].sourceType == "document")
    #expect(sources[0].title == "Report")
    #expect(sources[0].mediaType == "application/pdf")
    #expect(sources[0].filename == "report.pdf")
    #expect(sources[0].providerMetadata["gateway"]?["page"]?.intValue == 2)
    #expect(argumentDeltas == [#"{"query":"#, #""weather"}"#])
    #expect(toolCall?.id == "call_1")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 5)
}

@Test func gatewayEmbeddingAndRerankingUseGatewayEndpoints() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"embeddings":[[0.1,0.2]],"usage":{"tokens":3}}
    """))
    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: embeddingTransport))
    let embeddings = try await gateway.embeddingModel("text-embedding").embed(EmbeddingRequest(values: ["a"]))
    #expect(embeddings.embeddings == [[0.1, 0.2]])
    #expect(embeddings.usage?.totalTokens == 3)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/embedding-model")
    #expect(embeddingRequest.headers["ai-model-id"] == "text-embedding")

    let rerankTransport = RecordingTransport(response: jsonResponse("""
    {"ranking":[{"index":1,"relevanceScore":0.9}]}
    """))
    let rerankGateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: rerankTransport))
    let ranking = try await rerankGateway.rerankingModel("reranker").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results == [RerankedDocument(index: 1, score: 0.9)])
    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/reranking-model")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["topN"]?.intValue == 1)
}

@Test func gatewayMetadataMethodsUseManagementEndpointsAndMapResponses() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"models":[{"id":"openai/gpt-5","name":"GPT-5","modelType":"language","specification":{"specificationVersion":"v4","provider":"openai","modelId":"gpt-5"}}]}"#),
        jsonResponse(#"{"balance":"42.00","total_used":"8.50"}"#),
        jsonResponse("""
        {"results":[{"day":"2026-03-01","model":"anthropic/claude-sonnet-4.6","provider":"anthropic","credential_type":"byok","total_cost":10.5,"market_cost":9.25,"input_tokens":100,"output_tokens":50,"cached_input_tokens":20,"cache_creation_input_tokens":5,"reasoning_tokens":7,"request_count":25}]}
        """),
        jsonResponse("""
        {"data":{"id":"gen_01","total_cost":0.12,"upstream_inference_cost":0.08,"usage":0.12,"created_at":"2026-03-01T00:00:00Z","model":"anthropic/claude-sonnet-4.6","is_byok":true,"provider_name":"anthropic","streamed":true,"finish_reason":"stop","latency":123,"generation_time":456,"native_tokens_prompt":100,"native_tokens_completion":50,"native_tokens_reasoning":7,"native_tokens_cached":20,"native_tokens_cache_creation":5,"billable_web_search_calls":2}}
        """)
    ])
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", baseURL: "https://custom-gateway.example.com/v4/ai", transport: transport), teamIDOrSlug: "team_123")

    let models = try await provider.getAvailableModels()
    #expect(models.first?.id == "openai/gpt-5")
    #expect(models.first?.provider == "openai")
    #expect(models.first?.modelID == "gpt-5")

    let credits = try await provider.getCredits()
    #expect(credits == GatewayCredits(balance: "42.00", totalUsed: "8.50"))

    let report = try await provider.getSpendReport(GatewaySpendReportParams(
        startDate: "2026-03-01",
        endDate: "2026-03-25",
        groupBy: "model",
        datePart: "day",
        userID: "user-123",
        model: "anthropic/claude-sonnet-4.6",
        provider: "anthropic",
        credentialType: "byok",
        tags: ["production", "api"]
    ))
    #expect(report.results.first?.day == "2026-03-01")
    #expect(report.results.first?.model == "anthropic/claude-sonnet-4.6")
    #expect(report.results.first?.credentialType == "byok")
    #expect(report.results.first?.totalCost == 10.5)
    #expect(report.results.first?.marketCost == 9.25)
    #expect(report.results.first?.inputTokens == 100)
    #expect(report.results.first?.requestCount == 25)

    let generation = try await provider.getGenerationInfo(id: "gen_01")
    #expect(generation.id == "gen_01")
    #expect(generation.totalCost == 0.12)
    #expect(generation.upstreamInferenceCost == 0.08)
    #expect(generation.model == "anthropic/claude-sonnet-4.6")
    #expect(generation.isByok)
    #expect(generation.providerName == "anthropic")
    #expect(generation.streamed)
    #expect(generation.finishReason == "stop")
    #expect(generation.promptTokens == 100)
    #expect(generation.billableWebSearchCalls == 2)

    let requests = await transport.requests()
    #expect(requests.count == 4)
    #expect(requests[0].url.absoluteString == "https://custom-gateway.example.com/v4/ai/config")
    #expect(requests[1].url.absoluteString == "https://custom-gateway.example.com/v1/credits")
    #expect(requests[2].url.path == "/v1/report")
    let reportItems = Dictionary(uniqueKeysWithValues: URLComponents(url: requests[2].url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
    #expect(reportItems["start_date"] == "2026-03-01")
    #expect(reportItems["end_date"] == "2026-03-25")
    #expect(reportItems["group_by"] == "model")
    #expect(reportItems["date_part"] == "day")
    #expect(reportItems["user_id"] == "user-123")
    #expect(reportItems["model"] == "anthropic/claude-sonnet-4.6")
    #expect(reportItems["provider"] == "anthropic")
    #expect(reportItems["credential_type"] == "byok")
    #expect(reportItems["tags"] == "production,api")
    #expect(requests[3].url.absoluteString == "https://custom-gateway.example.com/v1/generation?id=gen_01")
    for request in requests {
        #expect(request.headers["Authorization"] == "Bearer gateway-key")
        #expect(request.headers["x-vercel-ai-gateway-team"] == "team_123")
        #expect(request.headers["ai-gateway-protocol-version"] == "0.0.1")
    }
}

@Test func gatewayImageMapsFilesMaskAndProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"images":["base64-image"]}"#))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.imageModel("google/imagen-4.0-generate")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "Edit these images",
        size: "1024x1024",
        count: 2,
        files: [
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png"),
            ImageInputFile(url: "https://example.com/reference.png")
        ],
        mask: ImageInputFile(data: Data([4, 5, 6]), mediaType: "image/png"),
        extraBody: [
            "aspectRatio": "16:9",
            "seed": 42,
            "providerOptions": [
                "gateway": [
                    "order": ["vertex", "openai"],
                    "serviceTier": "priority"
                ]
            ]
        ]
    ))

    #expect(result.base64Images == ["base64-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/image-model")
    #expect(request.headers["ai-image-model-specification-version"] == "4")
    #expect(request.headers["ai-model-id"] == "google/imagen-4.0-generate")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "Edit these images")
    #expect(body["n"]?.intValue == 2)
    #expect(body["size"]?.stringValue == "1024x1024")
    #expect(body["aspectRatio"]?.stringValue == "16:9")
    #expect(body["seed"]?.intValue == 42)
    #expect(body["providerOptions"]?["gateway"]?["order"]?[0]?.stringValue == "vertex")
    #expect(body["providerOptions"]?["gateway"]?["serviceTier"]?.stringValue == "priority")
    #expect(body["files"]?[0]?["type"]?.stringValue == "file")
    #expect(body["files"]?[0]?["mediaType"]?.stringValue == "image/png")
    #expect(body["files"]?[0]?["data"]?.stringValue == Data([1, 2, 3]).base64EncodedString())
    #expect(body["files"]?[1]?["type"]?.stringValue == "url")
    #expect(body["files"]?[1]?["url"]?.stringValue == "https://example.com/reference.png")
    #expect(body["mask"]?["type"]?.stringValue == "file")
    #expect(body["mask"]?["mediaType"]?.stringValue == "image/png")
    #expect(body["mask"]?["data"]?.stringValue == Data([4, 5, 6]).base64EncodedString())
}

@Test func gatewayVideoThrowsOnErrorEvent() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"error","message":"Rate limit exceeded","errorType":"rate_limit_exceeded","statusCode":429,"param":null}

    """))
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: transport))
    let model = try provider.videoModel("fal/luma-ray-2")

    do {
        _ = try await model.generateVideo(VideoGenerationRequest(
            prompt: "A sunset",
            aspectRatio: "16:9",
            durationSeconds: 5,
            extraBody: [
                "n": 1,
                "resolution": "1920x1080",
                "fps": 24,
                "seed": 42,
                "providerOptions": ["fal": ["motionStrength": 0.8]]
            ]
        ))
        Issue.record("Expected Gateway video error event to throw.")
    } catch let error as AIError {
        #expect(error == .httpStatus(provider: "gateway", statusCode: 429, body: "Rate limit exceeded"))
    }

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/video-model")
    #expect(request.headers["ai-video-model-specification-version"] == "4")
    #expect(request.headers["ai-model-id"] == "fal/luma-ray-2")
    #expect(request.headers["accept"] == "text/event-stream")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["prompt"]?.stringValue == "A sunset")
    #expect(body["aspectRatio"]?.stringValue == "16:9")
    #expect(body["duration"]?.intValue == 5)
    #expect(body["n"]?.intValue == 1)
    #expect(body["resolution"]?.stringValue == "1920x1080")
    #expect(body["fps"]?.intValue == 24)
    #expect(body["seed"]?.intValue == 42)
    #expect(body["providerOptions"]?["fal"]?["motionStrength"]?.doubleValue == 0.8)
}
