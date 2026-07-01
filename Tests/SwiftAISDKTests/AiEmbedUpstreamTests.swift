import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiEmbedReturnsResultAndForwardsOptionsLikeUpstream() async throws {
    let warning = AIWarning(
        type: "unsupported",
        feature: "dimensions",
        message: "Dimensions parameter not supported"
    )
    let responseMetadata = AIResponseMetadata(
        headers: ["foo": "bar"],
        body: ["foo": "bar"]
    )
    let model = MockEmbeddingModel(results: [
        EmbeddingResult(
            embeddings: [[0.1, 0.2, 0.3]],
            usage: TokenUsage(totalTokens: 10),
            rawValue: ["raw": true],
            warnings: [warning],
            providerMetadata: [
                "gateway": [
                    "routing": [
                        "resolvedProvider": "test-provider"
                    ]
                ]
            ],
            responseMetadata: responseMetadata
        )
    ])

    let result = try await AI.embed(
        model: model,
        value: "sunny day at the beach",
        dimensions: 3,
        providerOptions: [
            "aProvider": [
                "someKey": "someValue"
            ]
        ],
        extraBody: [
            "extra": true
        ],
        headers: [
            "custom-request-header": "request-header-value"
        ]
    )

    #expect(result.embeddings == [[0.1, 0.2, 0.3]])
    #expect(result.usage == TokenUsage(totalTokens: 10))
    #expect(result.warnings == [warning])
    #expect(result.providerMetadata["gateway"]?["routing"]?["resolvedProvider"]?.stringValue == "test-provider")
    #expect(result.responseMetadata == responseMetadata)
    #expect(result.requestMetadata.body?["values"]?[0]?.stringValue == "sunny day at the beach")
    #expect(result.requestMetadata.body?["dimensions"]?.intValue == 3)
    #expect(result.requestMetadata.body?["providerOptions"]?["aProvider"]?["someKey"]?.stringValue == "someValue")
    #expect(result.requestMetadata.body?["extraBody"]?["extra"]?.boolValue == true)
    #expect(result.requestMetadata.headers["custom-request-header"] == "request-header-value")
    #expect(model.requests.count == 1)
    #expect(model.requests[0].values == ["sunny day at the beach"])
    #expect(model.requests[0].dimensions == 3)
    #expect(model.requests[0].headers == ["custom-request-header": "request-header-value"])
    #expect(model.requests[0].providerOptions["aProvider"]?["someKey"]?.stringValue == "someValue")
    #expect(model.requests[0].extraBody["extra"]?.boolValue == true)
}
