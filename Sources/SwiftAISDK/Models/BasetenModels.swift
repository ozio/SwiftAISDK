import Foundation

public final class BasetenEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "baseten.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard !request.values.isEmpty else {
            throw AIError.invalidArgument(argument: "values", message: "Input list cannot be empty")
        }

        var allData: [JSONValue] = []
        var promptTokens = 0
        var totalTokens = 0
        var rawResponses: [JSONValue] = []
        var responseMetadata = AIResponseMetadata()
        let batches = request.values.chunked(into: basetenPerformanceClientBatchSize)

        var batchStartIndex = 0
        for (batchIndex, batch) in batches.enumerated() {
            let body = basetenPerformanceEmbeddingBody(values: batch, modelID: modelID)
            var headers = request.headers
            headers["x-baseten-customer-request-id"] = headers["x-baseten-customer-request-id"] ?? "swift-ai-sdk-\(UUID().uuidString)-\(batchIndex)"
            let response = try await config.sendJSONResponse(
                path: "/embeddings",
                modelID: modelID,
                body: body,
                headers: headers,
                abortSignal: request.abortSignal
            )
            let raw = response.json
            rawResponses.append(raw)
            if batchIndex == 0 {
                responseMetadata = aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
            }
            guard let data = raw["data"]?.arrayValue else {
                throw AIError.invalidResponse(provider: providerID, message: "No embedding data found.")
            }
            allData.append(contentsOf: basetenAdjustEmbeddingIndexes(data, startIndex: batchStartIndex))
            promptTokens += raw["usage"]?["prompt_tokens"]?.intValue ?? raw["usage"]?["input_tokens"]?.intValue ?? 0
            totalTokens += raw["usage"]?["total_tokens"]?.intValue ?? 0
            batchStartIndex += batch.count
        }

        guard !allData.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No embedding data found.")
        }
        let embeddings = allData.compactMap { item -> [Double]? in
            item["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        }
        let raw = basetenCombinedEmbeddingRawValue(
            data: allData,
            modelID: modelID,
            promptTokens: promptTokens,
            totalTokens: totalTokens,
            rawResponses: rawResponses
        )
        return EmbeddingResult(
            embeddings: embeddings,
            usage: tokenUsage(from: raw),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(
                body: basetenPerformanceEmbeddingBody(values: request.values, modelID: modelID),
                headers: request.headers
            ),
            responseMetadata: responseMetadata
        )
    }
}

private let basetenPerformanceClientBatchSize = 128

private func basetenPerformanceEmbeddingBody(values: [String], modelID: String) -> JSONValue {
    .object([
        "input": .array(values.map(JSONValue.string)),
        "model": .string(modelID)
    ])
}

private func basetenCombinedEmbeddingRawValue(
    data: [JSONValue],
    modelID: String,
    promptTokens: Int,
    totalTokens: Int,
    rawResponses: [JSONValue]
) -> JSONValue {
    var raw: [String: JSONValue] = [
        "object": .string("list"),
        "data": .array(data),
        "model": .string(modelID),
        "usage": .object([
            "prompt_tokens": .number(Double(promptTokens)),
            "total_tokens": .number(Double(totalTokens))
        ])
    ]
    if rawResponses.count > 1 {
        raw["responses"] = .array(rawResponses)
    }
    return .object(raw)
}

private func basetenAdjustEmbeddingIndexes(_ data: [JSONValue], startIndex: Int) -> [JSONValue] {
    data.map { item in
        guard var object = item.objectValue else { return item }
        let index = object["index"]?.intValue ?? 0
        object["index"] = .number(Double(index + startIndex))
        return .object(object)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension ModelHTTPConfig {
    var basetenEmbeddingConfig: ModelHTTPConfig? {
        guard let modelURL, modelURL.contains("/sync"), !modelURL.contains("/predict") else { return nil }
        let embeddingBaseURL = modelURL.contains("/sync/v1") ? modelURL : "\(modelURL)/v1"
        return ModelHTTPConfig(
            providerID: providerID,
            baseURL: embeddingBaseURL,
            modelURL: modelURL,
            headers: headers,
            transport: transport,
            includeUsage: includeUsage,
            queryParams: queryParams,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody
        )
    }
}
