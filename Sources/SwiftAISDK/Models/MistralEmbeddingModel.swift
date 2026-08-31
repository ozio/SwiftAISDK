import Foundation

public final class MistralEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "mistral.embedding"
    public let modelID: String
    public var maxEmbeddingsPerCall: Int? { 32 }
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let embeddingLimit = maxEmbeddingsPerCall ?? 32
        guard request.values.count <= embeddingLimit else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: embeddingLimit,
                values: request.values
            )
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values),
            "encoding_format": .string("float")
        ]
        body.merge(mistralProviderOptions(from: request.extraBody)) { _, new in new }
        if let providerValue = request.providerOptions["mistral"] {
            if providerValue != .null {
                guard let providerOptions = providerValue.objectValue else {
                    throw AIError.invalidArgument(argument: "providerOptions.mistral", message: "Mistral provider options must be an object.")
                }
                for key in mistralEmbeddingProviderOptionKeys {
                    body.removeValue(forKey: key)
                }
                for (key, value) in try mistralValidateEmbeddingProviderOptions(providerOptions) {
                    switch key {
                    case "outputDimension":
                        body["output_dimension"] = value
                    case "outputDtype":
                        body["output_dtype"] = value
                    default:
                        body[key] = value
                    }
                }
            }
        }
        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        return try Self.result(from: response, modelID: modelID, request: request, body: body)
    }

    private static func result(from response: (json: JSONValue, response: AIHTTPResponse), modelID: String, request: EmbeddingRequest, body: [String: JSONValue]) throws -> EmbeddingResult {
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

private func mistralValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where mistralEmbeddingProviderOptionKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "metadata":
            guard value.objectValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.mistral.metadata", message: "Mistral metadata must be an object.")
            }
        case "outputDimension":
            guard let dimension = value.intValue, value.doubleValue == Double(dimension), dimension > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.mistral.outputDimension", message: "Mistral outputDimension must be a positive integer.")
            }
        case "outputDtype":
            guard let dtype = value.stringValue, ["float", "int8", "uint8", "binary", "ubinary"].contains(dtype) else {
                throw AIError.invalidArgument(argument: "providerOptions.mistral.outputDtype", message: "Mistral outputDtype must be float, int8, uint8, binary, or ubinary.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}
