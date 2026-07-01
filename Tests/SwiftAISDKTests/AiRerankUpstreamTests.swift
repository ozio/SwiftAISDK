import Foundation
import Testing
@testable import SwiftAISDK

private let rerankStringDocuments = [
    "sunny day at the beach",
    "rainy day in the city",
    "cloudy day in the mountains"
]

@Test func aiRerankStringDocumentsForwardsCallOptionsLikeUpstream() async throws {
    let abortController = AIAbortController()
    let providerOptions: [String: JSONValue] = [
        "aProvider": [
            "someKey": "someValue"
        ]
    ]
    let model = MockRerankingModel(result: RerankingResult(
        results: [
            RerankedDocument(index: 2, score: 0.9, document: rerankStringDocuments[2]),
            RerankedDocument(index: 0, score: 0.8, document: rerankStringDocuments[0]),
            RerankedDocument(index: 1, score: 0.7, document: rerankStringDocuments[1])
        ],
        rawValue: .object([:])
    ))

    _ = try await AI.rerank(
        model: model,
        request: RerankingRequest(
            query: "rainy day",
            documents: rerankStringDocuments,
            topK: 3,
            providerOptions: providerOptions,
            headers: [
                "x-custom": "header-value"
            ],
            abortSignal: abortController.signal
        )
    )

    let request = try #require(model.requests.first)
    #expect(request.query == "rainy day")
    #expect(request.documents == rerankStringDocuments)
    #expect(request.documentObjects == nil)
    #expect(request.topK == 3)
    #expect(request.providerOptions == providerOptions)
    #expect(request.headers == ["x-custom": "header-value"])
    #expect(request.abortSignal === abortController.signal)
}

@Test func aiRerankObjectDocumentsForwardsCallOptionsLikeUpstream() async throws {
    let documents: [[String: JSONValue]] = [
        ["id": "123", "name": "sunny day at the beach"],
        ["id": "456", "name": "rainy day in the city"],
        ["id": "789", "name": "cloudy day in the mountains"]
    ]
    let model = MockRerankingModel(result: RerankingResult(
        results: [
            RerankedDocument(index: 2, score: 0.9),
            RerankedDocument(index: 0, score: 0.8),
            RerankedDocument(index: 1, score: 0.7)
        ],
        rawValue: .object([:])
    ))

    _ = try await AI.rerank(
        model: model,
        request: RerankingRequest(
            query: "rainy day",
            documents: documents,
            topK: 3,
            providerOptions: [
                "aProvider": [
                    "someKey": "someValue"
                ]
            ]
        )
    )

    let request = try #require(model.requests.first)
    #expect(request.query == "rainy day")
    #expect(request.documents == [])
    #expect(request.documentObjects == documents)
    #expect(request.documentsJSON == documents.map(JSONValue.object))
    #expect(request.topK == 3)
    #expect(request.providerOptions["aProvider"]?["someKey"]?.stringValue == "someValue")
}

@Test func aiRerankReturnsRankingProviderMetadataAndResponseLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "aProvider": [
            "someResponseKey": "someResponseValue"
        ]
    ]
    let responseMetadata = AIResponseMetadata(
        id: "mock-response-id",
        timestamp: Date(timeIntervalSince1970: 1_735_689_600),
        modelID: "mock-response-model-id",
        headers: [
            "content-type": "application/json"
        ],
        body: [
            "id": "123"
        ]
    )
    let expectedRanking = [
        RerankedDocument(index: 2, score: 0.9, document: rerankStringDocuments[2]),
        RerankedDocument(index: 0, score: 0.8, document: rerankStringDocuments[0]),
        RerankedDocument(index: 1, score: 0.7, document: rerankStringDocuments[1])
    ]
    let model = MockRerankingModel(result: RerankingResult(
        results: expectedRanking,
        rawValue: .object(["id": "123"]),
        providerMetadata: providerMetadata,
        responseMetadata: responseMetadata
    ))

    let result = try await AI.rerank(
        model: model,
        request: RerankingRequest(query: "rainy day", documents: rerankStringDocuments, topK: 3)
    )

    #expect(result.results == expectedRanking)
    #expect(result.providerMetadata == providerMetadata)
    #expect(result.responseMetadata == responseMetadata)
    #expect(result.rawValue["id"]?.stringValue == "123")
}

@Test func aiRerankFillsRequestMetadataLikeUpstream() async throws {
    let providerOptions: [String: JSONValue] = [
        "aProvider": [
            "someKey": "someValue"
        ]
    ]
    let model = MockRerankingModel(result: RerankingResult(
        results: [RerankedDocument(index: 0, score: 0.9, document: rerankStringDocuments[0])],
        rawValue: .object([:])
    ))

    let result = try await AI.rerank(
        model: model,
        request: RerankingRequest(
            query: "rainy day",
            documents: rerankStringDocuments,
            topK: 2,
            providerOptions: providerOptions,
            headers: [
                "x-custom": "header-value"
            ]
        )
    )

    #expect(result.requestMetadata.headers == ["x-custom": "header-value"])
    #expect(result.requestMetadata.body?["query"]?.stringValue == "rainy day")
    #expect(result.requestMetadata.body?["documents"]?[0]?.stringValue == "sunny day at the beach")
    #expect(result.requestMetadata.body?["documents"]?[2]?.stringValue == "cloudy day in the mountains")
    #expect(result.requestMetadata.body?["topK"]?.intValue == 2)
    #expect(result.requestMetadata.body?["providerOptions"]?["aProvider"]?["someKey"]?.stringValue == "someValue")
}

@Test func aiRerankLogsWarningsLikeUpstreamEndEvent() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "test warning")
    ]
    let recorder = RerankWarningLogRecorder()
    let model = MockRerankingModel(result: RerankingResult(
        results: [RerankedDocument(index: 0, score: 0.9, document: rerankStringDocuments[0])],
        rawValue: .object([:]),
        warnings: expectedWarnings
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.rerank(
            model: model,
            request: RerankingRequest(query: "rainy day", documents: rerankStringDocuments)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-reranking")
    ])
}

@Test func aiRerankRecordsTelemetryStartAndEndLikeUpstreamCallbacks() async throws {
    let recorder = TelemetryRecorder()
    let warning = AIWarning(type: "other", message: "test warning")
    let providerMetadata: [String: JSONValue] = [
        "aProvider": [
            "someResponseKey": "someResponseValue"
        ]
    ]
    let responseMetadata = AIResponseMetadata(
        id: "mock-response-id",
        timestamp: Date(timeIntervalSince1970: 1_748_736_000),
        modelID: "mock-response-model-id",
        headers: [
            "content-type": "application/json"
        ],
        body: [
            "id": "123"
        ]
    )
    let model = MockRerankingModel(result: RerankingResult(
        results: [
            RerankedDocument(index: 2, score: 0.9, document: rerankStringDocuments[2]),
            RerankedDocument(index: 0, score: 0.8, document: rerankStringDocuments[0]),
            RerankedDocument(index: 1, score: 0.7, document: rerankStringDocuments[1])
        ],
        rawValue: .object(["id": "123"]),
        warnings: [warning],
        providerMetadata: providerMetadata,
        responseMetadata: responseMetadata
    ))

    try await AIWarningLogging.withLoggingDisabled {
        _ = try await AI.rerank(
            model: model,
            request: RerankingRequest(
                query: "rainy day",
                documents: rerankStringDocuments,
                topK: 3,
                providerOptions: [
                    "aProvider": [
                        "someKey": "someValue"
                    ]
                ],
                headers: [
                    "x-custom": "header-value"
                ]
            ),
            telemetry: Telemetry.Options(functionID: "rerank-fn", integrations: [recorder])
        )
    }

    let events = await recorder.events()
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.rerank" })
    #expect(events.allSatisfy { $0.providerID == "mock" })
    #expect(events.allSatisfy { $0.modelID == "mock-reranking" })
    #expect(events.allSatisfy { $0.functionID == "rerank-fn" })
    #expect(events[0].callID == events[1].callID)
    #expect(events[0].input?["query"]?.stringValue == "rainy day")
    #expect(events[0].input?["documents"]?[1]?.stringValue == "rainy day in the city")
    #expect(events[0].input?["topK"]?.intValue == 3)
    #expect(events[0].input?["providerOptions"]?["aProvider"]?["someKey"]?.stringValue == "someValue")
    #expect(events[0].input?["headers"]?["x-custom"]?.stringValue == "header-value")
    #expect(events[1].output?["results"]?[0]?["index"]?.intValue == 2)
    #expect(events[1].output?["results"]?[0]?["score"]?.doubleValue == 0.9)
    #expect(events[1].output?["results"]?[0]?["document"]?.stringValue == "cloudy day in the mountains")
    #expect(events[1].warnings == [warning])
    #expect(events[1].providerMetadata == providerMetadata)
    #expect(events[1].responseMetadata == responseMetadata)
}

private actor RerankWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}
