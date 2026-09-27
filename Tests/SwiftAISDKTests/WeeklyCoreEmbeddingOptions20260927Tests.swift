import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCoreEmbeddingOptions20260927Tests")
struct WeeklyCoreEmbeddingOptions20260927Tests {
    @Test func providerOptionsTransformerRunsOnlyWhenAutomaticBatchingIsActive() async throws {
        let directProbe = Weekly20260927EmbeddingTransformerProbe()
        let directModel = Weekly20260927EmbeddingTransformerModel(
            maxEmbeddingsPerCall: nil,
            probe: directProbe
        )
        _ = try await AI.embedMany(
            model: directModel,
            values: ["one"],
            providerOptions: ["test": ["content": ["direct"]]],
            retryPolicy: .none
        )
        #expect(await directProbe.transformCount() == 0)
        #expect(directModel.requests().first?.providerOptions["test"]?["slice"] == nil)

        let batchedProbe = Weekly20260927EmbeddingTransformerProbe()
        let batchedModel = Weekly20260927EmbeddingTransformerModel(
            maxEmbeddingsPerCall: 10,
            probe: batchedProbe
        )
        _ = try await AI.embedMany(
            model: batchedModel,
            values: ["one"],
            providerOptions: ["test": ["content": ["batched"]]],
            retryPolicy: .none
        )
        #expect(await batchedProbe.transformCount() == 1)
        #expect(batchedModel.requests().first?.providerOptions["test"]?["slice"] == [0, 1])
    }
}

private actor Weekly20260927EmbeddingTransformerProbe {
    private var count = 0

    func recordTransform() {
        count += 1
    }

    func transformCount() -> Int {
        count
    }
}

private final class Weekly20260927EmbeddingTransformerModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "weekly.embedding-transformer"
    let modelID = "probe"
    let maxEmbeddingsPerCall: Int?
    let maxInputBytesPerCall: Int? = nil
    let providerOptionsTransformer: AIEmbeddingProviderOptionsTransformer?

    private let lock = NSLock()
    private var recordedRequests: [EmbeddingRequest] = []

    init(
        maxEmbeddingsPerCall: Int?,
        probe: Weekly20260927EmbeddingTransformerProbe
    ) {
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        providerOptionsTransformer = { context in
            await probe.recordTransform()
            var options = context.providerOptions
            var provider = options["test"]?.objectValue ?? [:]
            provider["slice"] = [
                .number(Double(context.startIndex)),
                .number(Double(context.endIndex))
            ]
            options["test"] = .object(provider)
            return options
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        lock.withLock { recordedRequests.append(request) }
        return EmbeddingResult(
            embeddings: request.values.map { _ in [0.1, 0.2] },
            usage: TokenUsage(inputTokens: request.values.count),
            rawValue: [:]
        )
    }

    func requests() -> [EmbeddingRequest] {
        lock.withLock { recordedRequests }
    }
}
