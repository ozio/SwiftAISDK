import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVertexAnthropicToolsHelpersExposeSupportedSubset() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"vertex anthropic tools"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let provider = try AIProviders.googleVertexAnthropic(
        project: "test-project",
        location: "us-central1",
        settings: ProviderSettings(apiKey: "vertex-token", transport: transport)
    )
    let model = try provider.languageModel("claude-sonnet-4@20250514")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex Anthropic tools.")],
        tools: [
            "bash": GoogleVertexAnthropicTools.bash_20241022(),
            "search": GoogleVertexAnthropicTools.webSearch_20250305(maxUses: 2),
            "bm25": GoogleVertexAnthropicTools.toolSearchBm25_20251119()
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString.contains("/claude-sonnet-4@20250514:rawPredict"))
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["anthropic_version"]?.stringValue == "vertex-2023-10-16")
    #expect(body["model"] == nil)
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["type"]?.stringValue == "bash_20241022" && $0["name"]?.stringValue == "bash" })
    #expect(tools.contains { $0["type"]?.stringValue == "web_search_20250305" && $0["max_uses"]?.intValue == 2 })
    #expect(tools.contains { $0["type"]?.stringValue == "tool_search_tool_bm25_20251119" && $0["name"]?.stringValue == "tool_search_tool_bm25" })
}
@Test func googleVertexOAuthBuildsRegionalPublisherURL() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    #expect(model.providerID == "google.vertex.chat")
    let result = try await model.generate(LanguageModelRequest(messages: [.system("Brief"), .user("Hi")], maxOutputTokens: 32))

    #expect(result.text == "vertex")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent")
    #expect(request.headers["Authorization"] == "Bearer token")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["systemInstruction"]?["parts"]?[0]?["text"]?.stringValue == "Brief")
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "Hi")
}
@Test func googleVertexOAuthUsesRegionalRepHostsLikeUpstream() async throws {
    let languageTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"eu"}]},"finishReason":"STOP"}]}
    """))
    let languageProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "eu",
        accessToken: "token",
        transport: languageTransport
    ))
    _ = try await languageProvider.languageModel("gemini-2.5-pro").generate(LanguageModelRequest(messages: [.user("Hi")]))

    let languageRequest = try #require(await languageTransport.requests().first)
    #expect(languageRequest.url.absoluteString == "https://aiplatform.eu.rep.googleapis.com/v1beta1/projects/test-project/locations/eu/publishers/google/models/gemini-2.5-pro:generateContent")

    let anthropicTransport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"us"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let anthropicProvider = try AIProviders.googleVertexAnthropic(
        project: "test-project",
        location: "us",
        settings: ProviderSettings(apiKey: "vertex-token", transport: anthropicTransport)
    )
    _ = try await anthropicProvider.languageModel("claude-sonnet-4@20250514").generate(LanguageModelRequest(messages: [.user("Hi")]))

    let anthropicRequest = try #require(await anthropicTransport.requests().first)
    #expect(anthropicRequest.url.absoluteString == "https://aiplatform.us.rep.googleapis.com/v1/projects/test-project/locations/us/publishers/anthropic/models/claude-sonnet-4@20250514:rawPredict")
}
@Test func googleVertexGemmaPrependsSystemInstructionToFirstUserMessage() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex gemma"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemma-3-27b-it")

    let result = try await model.generate(LanguageModelRequest(messages: [.system("Be precise."), .user("Hi")]))

    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["systemInstruction"] == nil)
    #expect(body["contents"]?[0]?["role"]?.stringValue == "user")
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "Be precise.\n\n")
    #expect(body["contents"]?[0]?["parts"]?[1]?["text"]?.stringValue == "Hi")
}
@Test func googleVertexLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"retrievedContext":{"uri":"https://external-rag-source.com/page","title":"External RAG Source"}},{"retrievedContext":{"uri":"gs://bucket/notes.md"}}]}}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "vertex grounded")
    #expect(result.sources.count == 2)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://external-rag-source.com/page")
    #expect(result.sources[0].title == "External RAG Source")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "Unknown Document")
    #expect(result.sources[1].mediaType == "text/markdown")
    #expect(result.sources[1].filename == "notes.md")
}
@Test func googleVertexLanguagePreservesGenerateContentProviderMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex metadata"}]},"finishReason":"STOP","finishMessage":"vertex done","safetyRatings":[{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"NEGLIGIBLE"}],"groundingMetadata":{"webSearchQueries":["vertex"],"groundingChunks":[{"web":{"uri":"https://vertex.example.com","title":"Vertex"}}]}}],"promptFeedback":{"blockReason":"SAFETY"},"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3,"serviceTier":"standard"}}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Metadata?")]))
    let metadata = try #require(result.providerMetadata["google"])

    #expect(metadata["safetyRatings"]?[0]?["category"]?.stringValue == "HARM_CATEGORY_DANGEROUS_CONTENT")
    #expect(metadata["promptFeedback"]?["blockReason"]?.stringValue == "SAFETY")
    #expect(metadata["groundingMetadata"]?["webSearchQueries"]?[0]?.stringValue == "vertex")
    #expect(metadata["finishMessage"]?.stringValue == "vertex done")
    #expect(metadata["serviceTier"]?.stringValue == "standard")
}
@Test func googleVertexLanguageMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"{\\"answer\\":\\"vertex\\"}"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Answer.")],
        responseFormat: .json(schema: [
            "type": "object",
            "properties": [
                "answer": ["type": "string"],
                "count": ["type": "integer"]
            ],
            "required": ["answer"],
            "additionalProperties": false
        ])
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["generationConfig"]?["responseMimeType"]?.stringValue == "application/json")
    #expect(body["generationConfig"]?["responseSchema"]?["type"]?.stringValue == "object")
    #expect(body["generationConfig"]?["responseSchema"]?["properties"]?["answer"]?["type"]?.stringValue == "string")
    #expect(body["generationConfig"]?["responseSchema"]?["properties"]?["count"]?["type"]?.stringValue == "integer")
    #expect(body["generationConfig"]?["responseSchema"]?["required"]?[0]?.stringValue == "answer")
    #expect(body["generationConfig"]?["responseSchema"]?["additionalProperties"] == nil)
    #expect(body["responseFormat"] == nil)
}
@Test func googleVertexLanguageMapsPayGoProviderOptionsAndReasoningOverride() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex options"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Options.")],
        reasoning: "high",
        providerOptions: [
            "googleVertex": .object([
                "sharedRequestType": "priority",
                "requestType": "shared",
                "serviceTier": "priority",
                "thinkingConfig": ["thinkingBudget": 999],
                "labels": ["team": "sdk"],
                "unsupportedProperty": "drop-me"
            ])
        ]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["X-Vertex-AI-LLM-Shared-Request-Type"] == "priority")
    #expect(request.headers["X-Vertex-AI-LLM-Request-Type"] == "shared")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["generationConfig"]?["thinkingConfig"]?["thinkingBudget"]?.intValue == 999)
    #expect(body["labels"]?["team"]?.stringValue == "sdk")
    #expect(body["serviceTier"] == nil)
    #expect(body["sharedRequestType"] == nil)
    #expect(body["requestType"] == nil)
    #expect(body["unsupportedProperty"] == nil)
    #expect(result.warnings.contains { $0.type == "other" && ($0.message?.contains("'serviceTier' is a Gemini API option") ?? false) })
}
@Test func googleVertexLanguageStreamMapsStreamFunctionCallArgumentsOption() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"vertex"}],"role":"model"},"finishReason":"STOP","index":0}]}

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-3-pro")

    for try await _ in model.stream(LanguageModelRequest(
        messages: [.user("Stream.")],
        providerOptions: [
            "googleVertex": .object([
                "streamFunctionCallArguments": true
            ])
        ]
    )) {}

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["toolConfig"]?["functionCallingConfig"]?["streamFunctionCallArguments"]?.boolValue == true)
    #expect(body["streamFunctionCallArguments"] == nil)
}
@Test func googleVertexLanguageMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex tools"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "properties": ["query": ["type": "string"]],
                "required": ["query"]
            ]
        ],
        extraBody: ["toolChoice": "required"]
    ))

    #expect(result.text == "vertex tools")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"]?[0]?["functionDeclarations"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(body["toolChoice"] == nil)
}
@Test func googleVertexToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Vertex tools.")],
        tools: [
            "google.google_search": GoogleVertexTools.googleSearch(),
            "google.vertex_rag_store": GoogleVertexTools.vertexRagStore(
                ragCorpus: "projects/test-project/locations/us-central1/ragCorpora/rag-1",
                topK: 3
            )
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["googleSearch"]?.objectValue?.isEmpty == true })
    let retrieval = try #require(tools.first { $0["retrieval"] != nil })
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["rag_resources"]?["rag_corpus"]?.stringValue == "projects/test-project/locations/us-central1/ragCorpora/rag-1")
    #expect(retrieval["retrieval"]?["vertex_rag_store"]?["similarity_top_k"]?.intValue == 3)
}
@Test func googleVertexLanguageWarnsForUnsupportedProviderToolsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-pro")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: ["google.google_search": GoogleVertexTools.googleSearch()]
    ))

    #expect(result.warnings.contains {
        $0.type == "unsupported" && $0.feature == "provider-defined tool google.google_search" && $0.message == "Google Search requires Gemini 2.0 or newer."
    })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"] == nil)
}
@Test func googleVertexLanguageStreamStartCarriesProviderToolWarnings() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"vertex"}],"role":"model"},"finishReason":"STOP","index":0}]}

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-pro")

    var startWarnings: [AIWarning] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: ["google.google_search": GoogleVertexTools.googleSearch()]
    )) {
        if case let .streamStart(warnings) = part {
            startWarnings = warnings
        }
    }

    #expect(startWarnings.contains {
        $0.type == "unsupported" && $0.feature == "provider-defined tool google.google_search" && $0.message == "Google Search requires Gemini 2.0 or newer."
    })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tools"] == nil)
}
@Test func googleVertexLanguageStreamsGenerateContentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"ver"}],"role":"model"},"index":0}]}

    data: {"candidates":[{"content":{"parts":[{"text":"tex"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":2,"totalTokenCount":4}}

    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")

    var deltas: [String] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(_, value):
            usage = value
        default:
            break
        }
    }

    #expect(deltas == ["ver", "tex"])
    #expect(usage?.totalTokens == 4)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://aiplatform.googleapis.com/v1beta1/projects/test-project/locations/global/publishers/google/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
    #expect(request.headers["Authorization"] == "Bearer token")
}
@Test func googleVertexLanguageParsesAndStreamsFunctionCalls() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}
    """))
    let generateProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: generateTransport
    ))
    let generateModel = try generateProvider.languageModel("gemini-2.5-pro")

    let result = try await generateModel.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.first?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(result.toolCalls.first)).arguments.utf8))["location"]?.stringValue == "Boston")

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"weather","args":{"location":"Boston"}}}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":8,"totalTokenCount":28}}

    """))
    let streamProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "global",
        accessToken: "token",
        transport: streamTransport
    ))
    let streamModel = try streamProvider.languageModel("gemini-2.5-pro")

    var finalCall: AIToolCall?
    var finishReason: String?
    for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(finalCall?.name == "weather")
    #expect(try decodeJSONBody(Data((try #require(finalCall)).arguments.utf8))["location"]?.stringValue == "Boston")
    #expect(finishReason == "tool-calls")
}
