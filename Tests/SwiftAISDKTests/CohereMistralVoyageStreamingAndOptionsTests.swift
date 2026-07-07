import Foundation
import Testing
@testable import SwiftAISDK

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
    data: {"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"weather_dqgshstja6p9","type":"function","function":{"name":"weather","arguments":"{ \"location\" :"}}}}}

    data: {"type":"tool-call-delta","delta":{"message":{"tool_calls":{"function":{"arguments":" \"San Francisco\" }"}}}}}

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
    #expect(deltas == ["{ \"location\" :", " \"San Francisco\" }"])
    #expect(inputLifecycle == [
        "start:weather_dqgshstja6p9:weather",
        "delta:weather_dqgshstja6p9:{ \"location\" :",
        "delta:weather_dqgshstja6p9: \"San Francisco\" }",
        "end:weather_dqgshstja6p9"
    ])
    #expect(call.id == "weather_dqgshstja6p9")
    #expect(call.name == "weather")
    #expect(call.arguments == #"{"location":"San Francisco"}"#)
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 5)
}
@Test func cohereLanguageStreamsParseErrorsAsErrorPartsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"message-start","id":"msg-err"}

    data: not-json

    """))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: transport))
    let model = try provider.languageModel("command-a-03-2025")

    var errors: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .error(message, _):
            errors.append(message)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(errors.count == 1)
    #expect(finishReason == "error")
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

    let tooManyValues = Array(repeating: "x", count: 97)
    await #expect(throws: AITooManyEmbeddingValuesForCallError(
        provider: "cohere.textEmbedding",
        modelID: "embed-english-v3.0",
        maxEmbeddingsPerCall: 96,
        values: tooManyValues
    )) {
        _ = try await embeddingModel.embed(EmbeddingRequest(values: tooManyValues))
    }
    #expect(await embeddingTransport.requests().count == 1)

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

    #expect(embedding.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(embedding.usage?.totalTokens == 9)
    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.url.absoluteString == "https://api.voyageai.com/v1/embeddings")
    #expect(embeddingRequest.headers["authorization"] == "Bearer voyage-key")
    #expect(embeddingRequest.headers["user-agent"] == "ai-sdk/voyage/2.0.5")
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
    #expect(rerankRequest.headers["user-agent"] == "ai-sdk/voyage/2.0.5")
    let rerankBody = try decodeJSONBody(try #require(rerankRequest.body))
    #expect(rerankBody["top_k"]?.intValue == 2)
    #expect(rerankBody["return_documents"]?.boolValue == true)
    #expect(rerankBody["returnDocuments"] == nil)
    #expect(rerankBody["truncation"]?.boolValue == true)
}

@Test func voyageEmbeddingAndRerankingAcceptNullishUsageLikeUpstreamV4() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"model":"voyage-3.5","data":[{"index":1,"embedding":[0.3,0.4]},{"index":0,"embedding":[0.1,0.2]}],"usage":null}
    """))
    let embeddingProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: embeddingTransport))
    let embedding = try await embeddingProvider.embeddingModel("voyage-3.5").embed(EmbeddingRequest(values: ["a", "b"]))

    #expect(embedding.embeddings == [[0.1, 0.2], [0.3, 0.4]])
    #expect(embedding.usage?.totalTokens == 0)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":1,"relevance_score":0.57},{"index":0,"relevance_score":0.25}]}"#))
    let rerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: rerankTransport))
    let reranking = try await rerankProvider.rerankingModel("rerank-2.5").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 2))

    #expect(reranking.results.map(\.index) == [1, 0])
    #expect(reranking.results.map(\.score) == [0.57, 0.25])
}
