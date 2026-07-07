import Foundation
import Testing
@testable import SwiftAISDK

@Test func voyageProviderExposesEmbeddingAndRerankingAliasesLikeUpstream() throws {
    let provider = try AIProviders.voyage(settings: ProviderSettings(
        apiKey: "voyage-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    let embeddingModelIDs = [
        "voyage-4-large",
        "voyage-4",
        "voyage-4-lite",
        "voyage-4-nano",
        "voyage-code-3.5",
        "voyage-code-3",
        "voyage-3-large",
        "voyage-3.5",
        "voyage-3.5-lite",
        "voyage-3",
        "voyage-3-lite",
        "voyage-finance-2",
        "voyage-law-2",
        "voyage-multilingual-2",
        "voyage-code-2",
        "voyage-2",
        "custom-embedding-model"
    ]
    for modelID in embeddingModelIDs {
        #expect(try provider.embeddingModel(modelID).providerID == "voyage.embedding")
        #expect(try provider.embedding(modelID).modelID == modelID)
        #expect(try provider.textEmbeddingModel(modelID).modelID == modelID)
        #expect(try provider.textEmbedding(modelID).modelID == modelID)
    }

    let rerankingModelIDs = [
        "rerank-2.5",
        "rerank-2.5-lite",
        "rerank-2",
        "rerank-2-lite",
        "rerank-1",
        "rerank-lite-1",
        "custom-reranking-model"
    ]
    for modelID in rerankingModelIDs {
        #expect(try provider.rerankingModel(modelID).providerID == "voyage.reranking")
        #expect(try provider.reranking(modelID).modelID == modelID)
    }

    #expect(throws: AIError.unsupportedModel(provider: "voyage", capability: .language, modelID: "some-model")) {
        _ = try provider.languageModel("some-model")
    }
    #expect(throws: AIError.unsupportedModel(provider: "voyage", capability: .image, modelID: "some-model")) {
        _ = try provider.imageModel("some-model")
    }
}

@Test func voyageEmbeddingProviderOptionsFollowUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[0.1]}],"usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: transport))
    let model = try provider.embeddingModel("voyage-4")

    _ = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: [
            "voyage": [
                "inputType": .null,
                "truncation": true,
                "outputDimension": 768,
                "outputDtype": "ubinary",
                "extra": "drop-me"
            ]
        ],
        extraBody: [
            "voyage": [
                "inputType": "document",
                "truncation": false,
                "outputDimension": 512,
                "outputDtype": "int8",
                "rawExtra": "keep-me"
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["voyage"] == nil)
    #expect(body["extra"] == nil)
    #expect(body["input_type"] == .null)
    #expect(body["truncation"]?.boolValue == true)
    #expect(body["output_dimension"]?.intValue == 768)
    #expect(body["output_dtype"]?.stringValue == "ubinary")
    #expect(body["rawExtra"]?.stringValue == "keep-me")
}

@Test func voyageEmbeddingProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[0.1]}],"usage":{"total_tokens":1}}"#))))
    let model = try provider.embeddingModel("voyage-4")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": "bad"]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.inputType", message: "Voyage inputType must be query, document, or null.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": ["inputType": "search_query"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.truncation", message: "Voyage truncation cannot be null.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": ["truncation": .null]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.truncation", message: "Voyage truncation must be a boolean.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": ["truncation": "true"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.outputDimension", message: "Voyage outputDimension must be a number.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": ["outputDimension": "768"]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.outputDtype", message: "Voyage outputDtype must be one of float, int8, uint8, binary, ubinary.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"], providerOptions: ["voyage": ["outputDtype": "bool"]]))
    }
}

@Test func voyageRerankingProviderOptionsValidateLikeUpstreamSchema() async throws {
    let provider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"relevance_score":0.8}]}"#))))
    let model = try provider.rerankingModel("rerank-2.5")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["voyage": false]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.returnDocuments", message: "Voyage returnDocuments cannot be null.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["voyage": ["returnDocuments": .null]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.voyage.truncation", message: "Voyage truncation must be a boolean.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"], providerOptions: ["voyage": ["truncation": "true"]]))
    }
}

@Test func voyageEmbeddingResponseValidationMatchesUpstreamSchema() async throws {
    let provider = try AIProviders.voyage(settings: ProviderSettings(
        apiKey: "voyage-key",
        transport: RecordingTransport(response: jsonResponse(#"{"usage":{"total_tokens":"bad"},"data":[{"index":0,"embedding":[0.1]}]}"#))
    ))
    let model = try provider.embeddingModel("voyage-4")

    await #expect(throws: AIError.invalidResponse(provider: "voyage.embedding", message: "Voyage embedding response is invalid.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["hello"]))
    }
}

@Test func voyageEmbeddingRejectsTooManyValuesBeforeRequestLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[0.1]}],"usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: transport))
    let model = try provider.embeddingModel("voyage-4")
    let values = (0..<129).map { "value-\($0)" }

    await #expect(throws: AITooManyEmbeddingValuesForCallError(
        provider: "voyage.embedding",
        modelID: "voyage-4",
        maxEmbeddingsPerCall: 128,
        values: values
    )) {
        _ = try await model.embed(EmbeddingRequest(values: values))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func voyageRerankingResponseValidationMatchesUpstreamSchema() async throws {
    let provider = try AIProviders.voyage(settings: ProviderSettings(
        apiKey: "voyage-key",
        transport: RecordingTransport(response: jsonResponse(#"{"data":[{"index":"bad","relevance_score":0.8}]}"#))
    ))
    let model = try provider.rerankingModel("rerank-2.5")

    await #expect(throws: AIError.invalidResponse(provider: "voyage.reranking", message: "Voyage reranking response is invalid.")) {
        _ = try await model.rerank(RerankingRequest(query: "q", documents: ["a"]))
    }
}
