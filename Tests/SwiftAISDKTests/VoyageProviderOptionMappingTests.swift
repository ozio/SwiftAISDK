import Foundation
import Testing
@testable import SwiftAISDK

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
