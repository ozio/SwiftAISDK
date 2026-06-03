import Foundation
import Testing
@testable import SwiftAISDK

@Test func cohereEmbeddingAndRerankingPreserveResponseMetadata() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"id":"cohere-embed","embeddings":{"float":[[0.1,0.2]]},"meta":{"billed_units":{"input_tokens":3}}}
    """, headers: ["cohere-header": "embedding"]))
    let provider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: embeddingTransport))

    let embedding = try await provider.embeddingModel("embed-v4.0").embed(EmbeddingRequest(values: ["hello"], dimensions: 64, headers: ["x-client": "swift"]))

    #expect(embedding.requestMetadata.body?["texts"]?[0]?.stringValue == "hello")
    #expect(embedding.requestMetadata.body?["output_dimension"]?.intValue == 64)
    #expect(embedding.requestMetadata.headers["x-client"] == "swift")
    #expect(embedding.requestMetadata.headers["authorization"] == nil)
    #expect(embedding.responseMetadata.id == "cohere-embed")
    #expect(embedding.responseMetadata.modelID == "embed-v4.0")
    #expect(embedding.responseMetadata.headers["cohere-header"] == "embedding")
    #expect(embedding.responseMetadata.body?["embeddings"]?["float"]?[0]?[0]?.doubleValue == 0.1)

    let rerankTransport = RecordingTransport(response: jsonResponse("""
    {"id":"cohere-rerank","results":[{"index":1,"relevance_score":0.9}]}
    """, headers: ["cohere-header": "rerank"]))
    let rerankProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: rerankTransport))

    let rerank = try await rerankProvider.rerankingModel("rerank-v3.5").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1, headers: ["x-client": "swift"]))

    #expect(rerank.requestMetadata.body?["query"]?.stringValue == "q")
    #expect(rerank.requestMetadata.body?["documents"]?[1]?.stringValue == "b")
    #expect(rerank.requestMetadata.body?["top_n"]?.intValue == 1)
    #expect(rerank.requestMetadata.headers["x-client"] == "swift")
    #expect(rerank.responseMetadata.id == "cohere-rerank")
    #expect(rerank.responseMetadata.modelID == "rerank-v3.5")
    #expect(rerank.responseMetadata.headers["cohere-header"] == "rerank")
    #expect(rerank.responseMetadata.body?["results"]?[0]?["relevance_score"]?.doubleValue == 0.9)
}

@Test func voyageMistralBasetenVectorModelsPreserveResponseMetadata() async throws {
    let voyageTransport = RecordingTransport(response: jsonResponse("""
    {"id":"voyage-embed","model":"voyage-3","data":[{"index":0,"embedding":[0.3,0.4]}],"usage":{"total_tokens":2}}
    """, headers: ["voyage-header": "embedding"]))
    let voyage = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: voyageTransport))

    let voyageEmbedding = try await voyage.embeddingModel("voyage-3").embed(EmbeddingRequest(values: ["hello"], dimensions: 32))

    #expect(voyageEmbedding.requestMetadata.body?["input"]?[0]?.stringValue == "hello")
    #expect(voyageEmbedding.requestMetadata.body?["output_dimension"]?.intValue == 32)
    #expect(voyageEmbedding.responseMetadata.id == "voyage-embed")
    #expect(voyageEmbedding.responseMetadata.modelID == "voyage-3")
    #expect(voyageEmbedding.responseMetadata.headers["voyage-header"] == "embedding")
    #expect(voyageEmbedding.responseMetadata.body?["data"]?[0]?["embedding"]?[0]?.doubleValue == 0.3)

    let voyageRerankTransport = RecordingTransport(response: jsonResponse("""
    {"id":"voyage-rerank","data":[{"index":0,"relevance_score":0.8}]}
    """, headers: ["voyage-header": "rerank"]))
    let voyageRerankProvider = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key", transport: voyageRerankTransport))

    let voyageRerank = try await voyageRerankProvider.rerankingModel("rerank-2").rerank(RerankingRequest(query: "q", documents: ["a"], topK: 1))

    #expect(voyageRerank.requestMetadata.body?["top_k"]?.intValue == 1)
    #expect(voyageRerank.responseMetadata.id == "voyage-rerank")
    #expect(voyageRerank.responseMetadata.modelID == "rerank-2")
    #expect(voyageRerank.responseMetadata.headers["voyage-header"] == "rerank")
    #expect(voyageRerank.responseMetadata.body?["data"]?[0]?["relevance_score"]?.doubleValue == 0.8)

    let mistralTransport = RecordingTransport(response: jsonResponse("""
    {"id":"mistral-embed","model":"mistral-embed","data":[{"embedding":[0.5,0.6]}],"usage":{"total_tokens":4}}
    """, headers: ["mistral-header": "embedding"]))
    let mistral = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: mistralTransport))

    let mistralEmbedding = try await mistral.embeddingModel("mistral-embed").embed(EmbeddingRequest(values: ["hello"], headers: ["x-client": "swift"]))

    #expect(mistralEmbedding.requestMetadata.body?["input"]?[0]?.stringValue == "hello")
    #expect(mistralEmbedding.requestMetadata.headers["x-client"] == "swift")
    #expect(mistralEmbedding.responseMetadata.id == "mistral-embed")
    #expect(mistralEmbedding.responseMetadata.modelID == "mistral-embed")
    #expect(mistralEmbedding.responseMetadata.headers["mistral-header"] == "embedding")
    #expect(mistralEmbedding.responseMetadata.body?["data"]?[0]?["embedding"]?[0]?.doubleValue == 0.5)

    let basetenTransport = RecordingTransport(response: jsonResponse("""
    {"id":"baseten-embed","data":[{"embedding":[0.7,0.8]}],"usage":{"total_tokens":5}}
    """, headers: ["baseten-header": "embedding"]))
    let baseten = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-abc.api.baseten.co/environments/prod/sync",
        transport: basetenTransport
    ))

    let basetenEmbedding = try await baseten.embeddingModel("embed").embed(EmbeddingRequest(values: ["hello"], dimensions: 128))

    #expect(basetenEmbedding.requestMetadata.body?["input"]?[0]?.stringValue == "hello")
    #expect(basetenEmbedding.requestMetadata.body?["model"]?.stringValue == "embed")
    #expect(basetenEmbedding.requestMetadata.body?["dimensions"] == nil)
    #expect(basetenEmbedding.responseMetadata.id == "baseten-embed")
    #expect(basetenEmbedding.responseMetadata.modelID == "embed")
    #expect(basetenEmbedding.responseMetadata.headers["baseten-header"] == "embedding")
    #expect(basetenEmbedding.responseMetadata.body?["data"]?[0]?["embedding"]?[0]?.doubleValue == 0.7)
}

@Test func gatewayTogetherAndGenericRerankingPreserveResponseMetadata() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-embed","embeddings":[[0.1,0.2]],"usage":{"tokens":3}}
    """, headers: ["gateway-header": "embedding"]))
    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: embeddingTransport))

    let embedding = try await gateway.embeddingModel("text-embedding").embed(EmbeddingRequest(values: ["a"], extraBody: ["encoding": "float"], headers: ["x-client": "swift"]))

    #expect(embedding.requestMetadata.body?["values"]?[0]?.stringValue == "a")
    #expect(embedding.requestMetadata.body?["encoding"]?.stringValue == "float")
    #expect(embedding.requestMetadata.headers["x-client"] == "swift")
    #expect(embedding.responseMetadata.id == "gateway-embed")
    #expect(embedding.responseMetadata.modelID == "text-embedding")
    #expect(embedding.responseMetadata.headers["gateway-header"] == "embedding")
    #expect(embedding.responseMetadata.body?["embeddings"]?[0]?[0]?.doubleValue == 0.1)

    let gatewayRerankTransport = RecordingTransport(response: jsonResponse("""
    {"id":"gateway-rerank","ranking":[{"index":1,"relevanceScore":0.9}]}
    """, headers: ["gateway-header": "rerank"]))
    let gatewayRerankProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: gatewayRerankTransport))

    let gatewayRerank = try await gatewayRerankProvider.rerankingModel("reranker").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))

    #expect(gatewayRerank.requestMetadata.body?["topN"]?.intValue == 1)
    #expect(gatewayRerank.responseMetadata.id == "gateway-rerank")
    #expect(gatewayRerank.responseMetadata.modelID == "reranker")
    #expect(gatewayRerank.responseMetadata.headers["gateway-header"] == "rerank")
    #expect(gatewayRerank.responseMetadata.body?["ranking"]?[0]?["relevanceScore"]?.doubleValue == 0.9)

    let togetherTransport = RecordingTransport(response: jsonResponse("""
    {"id":"together-rerank","results":[{"index":0,"relevance_score":0.75}],"usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}}
    """, headers: ["together-header": "rerank"]))
    let together = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: togetherTransport))

    let togetherRerank = try await together.rerankingModel("Salesforce/Llama-Rank-V1").rerank(RerankingRequest(query: "q", documents: ["a"], topK: 1))

    #expect(togetherRerank.requestMetadata.body?["top_n"]?.intValue == 1)
    #expect(togetherRerank.responseMetadata.id == "together-rerank")
    #expect(togetherRerank.responseMetadata.modelID == "Salesforce/Llama-Rank-V1")
    #expect(togetherRerank.responseMetadata.headers["together-header"] == "rerank")
    #expect(togetherRerank.responseMetadata.body?["results"]?[0]?["relevance_score"]?.doubleValue == 0.75)

    let genericTransport = RecordingTransport(response: jsonResponse("""
    {"id":"generic-rerank","results":[{"index":0,"score":0.66,"document":"a"}]}
    """, headers: ["generic-header": "rerank"]))
    let config = ModelHTTPConfig(
        providerID: "generic",
        baseURL: "https://api.example.com",
        headers: [:],
        transport: genericTransport
    )
    let generic = JSONRerankingModel(modelID: "rank-model", path: "/rerank", config: config)

    let genericRerank = try await generic.rerank(RerankingRequest(query: "q", documents: ["a"], topK: 1))

    #expect(genericRerank.requestMetadata.body?["top_k"]?.intValue == 1)
    #expect(genericRerank.responseMetadata.id == "generic-rerank")
    #expect(genericRerank.responseMetadata.modelID == "rank-model")
    #expect(genericRerank.responseMetadata.headers["generic-header"] == "rerank")
    #expect(genericRerank.responseMetadata.body?["results"]?[0]?["score"]?.doubleValue == 0.66)
}

@Test func amazonBedrockEmbeddingAndRerankingPreserveResponseMetadata() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse("""
    {"id":"bedrock-embed","embedding":[0.1,0.2,0.3]}
    """, headers: ["bedrock-header": "embedding"]))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-west-2",
        apiKey: "bearer-key",
        transport: embeddingTransport
    ))
    let embedding = try await provider.embeddingModel("amazon.titan-embed-text-v2:0").embed(EmbeddingRequest(values: ["hello"], dimensions: 256))

    #expect(embedding.requestMetadata.body?["inputText"]?.stringValue == "hello")
    #expect(embedding.requestMetadata.body?["dimensions"]?.intValue == 256)
    #expect(embedding.responseMetadata.id == "bedrock-embed")
    #expect(embedding.responseMetadata.modelID == "amazon.titan-embed-text-v2:0")
    #expect(embedding.responseMetadata.headers["bedrock-header"] == "embedding")
    #expect(embedding.responseMetadata.body?["embedding"]?[0]?.doubleValue == 0.1)

    let rerankTransport = RecordingTransport(response: jsonResponse("""
    {"id":"bedrock-rerank","results":[{"index":1,"relevanceScore":0.81}]}
    """, headers: ["bedrock-header": "rerank"]))
    let rerankProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-west-2",
        apiKey: "bearer-key",
        transport: rerankTransport
    ))
    let rerank = try await rerankProvider.rerankingModel("cohere.rerank-v3-5:0").rerank(RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))

    #expect(rerank.requestMetadata.body?["rerankingConfiguration"]?["amazonBedrockRerankingConfiguration"]?["numberOfResults"]?.intValue == 1)
    #expect(rerank.responseMetadata.id == "bedrock-rerank")
    #expect(rerank.responseMetadata.modelID == "cohere.rerank-v3-5:0")
    #expect(rerank.responseMetadata.headers["bedrock-header"] == "rerank")
    #expect(rerank.responseMetadata.body?["results"]?[0]?["relevanceScore"]?.doubleValue == 0.81)
}
