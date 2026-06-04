import Foundation

public final class MistralEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "mistral.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard request.values.count <= 32 else {
            throw AIError.invalidResponse(provider: providerID, message: "Mistral supports at most 32 embedding inputs per call.")
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values),
            "encoding_format": .string("float")
        ]
        body.merge(mistralProviderOptions(from: request.extraBody)) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["data"]?.arrayValue?.compactMap { item in
            item["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: tokenUsage(from: raw),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}
