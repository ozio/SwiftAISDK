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
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values)
        ]
        if let dimensions = request.dimensions { body["dimensions"] = .number(Double(dimensions)) }
        body.merge(request.extraBody) { _, new in new }

        let response = try await config.sendJSONResponse(
            path: "/embeddings",
            modelID: modelID,
            body: .object(body),
            headers: request.headers
        )
        let raw = response.json
        guard let data = raw["data"]?.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No embedding data found.")
        }
        let embeddings = data.compactMap { item -> [Double]? in
            item["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        }
        return EmbeddingResult(
            embeddings: embeddings,
            usage: tokenUsage(from: raw),
            rawValue: raw,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

extension ModelHTTPConfig {
    var basetenEmbeddingConfig: ModelHTTPConfig? {
        guard baseURL.contains("/sync"), !baseURL.contains("/predict") else { return nil }
        let embeddingBaseURL = baseURL.contains("/sync/v1") ? baseURL : "\(baseURL)/v1"
        return ModelHTTPConfig(
            providerID: providerID,
            baseURL: embeddingBaseURL,
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
