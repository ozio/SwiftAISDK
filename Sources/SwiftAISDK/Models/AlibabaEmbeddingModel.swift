import Foundation

public final class AlibabaEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "alibaba.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig
    private let maxEmbeddingsPerCall = 10

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard request.values.count <= maxEmbeddingsPerCall else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: maxEmbeddingsPerCall,
                values: request.values
            )
        }

        let options = try alibabaEmbeddingOptions(from: request)
        if options["output_type"]?.stringValue == "sparse" {
            throw AIError.invalidArgument(
                argument: "providerOptions.alibaba.outputType",
                message: "Alibaba embedding outputType 'sparse' is not supported because embeddings require dense number arrays. Use 'dense' or 'dense&sparse' instead."
            )
        }

        var parameters: [String: JSONValue] = [:]
        if let textType = options["text_type"] { parameters["text_type"] = textType }
        if let dimension = options["dimension"] ?? request.dimensions.map({ .number(Double($0)) }) {
            parameters["dimension"] = dimension
        }
        if let outputType = options["output_type"] { parameters["output_type"] = outputType }

        let body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .object(["texts": .array(request.values.map(JSONValue.string))]),
            "parameters": .object(parameters)
        ]
        let base = alibabaNativeBaseURL(config.baseURL)
        let response = try await config.transport.send(config.request(
            path: "/services/embeddings/text-embedding/text-embedding",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ).withURL(try requireURL("\(base)/api/v1/services/embeddings/text-embedding/text-embedding")))
        guard (200..<300).contains(response.statusCode) else {
            throw alibabaHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let embeddingItems = raw["output"]?["embeddings"]?.arrayValue ?? []
        let sorted = embeddingItems.sorted {
            ($0["text_index"]?.intValue ?? 0) < ($1["text_index"]?.intValue ?? 0)
        }
        let embeddings = sorted.compactMap { item -> [Double]? in
            item["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        }
        guard embeddings.count == sorted.count else {
            throw AIError.invalidResponse(provider: providerID, message: "Alibaba embedding response contained an invalid embedding.")
        }

        var providerMetadata: [String: JSONValue] = [:]
        let sparseEmbeddings = sorted.compactMap { item -> JSONValue? in
            guard let sparse = item["sparse_embedding"], sparse != .null else { return nil }
            return .object([
                "textIndex": item["text_index"],
                "sparseEmbedding": sparse
            ].compactMapValues { $0 })
        }
        if !sparseEmbeddings.isEmpty {
            providerMetadata["alibaba"] = .object(["sparseEmbeddings": .array(sparseEmbeddings)])
        }

        return EmbeddingResult(
            embeddings: embeddings,
            usage: raw["usage"].map { TokenUsage(totalTokens: $0["total_tokens"]?.intValue) },
            rawValue: raw,
            providerMetadata: providerMetadata,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: AIResponseMetadata(
                id: raw["request_id"]?.stringValue,
                timestamp: Date(),
                modelID: modelID,
                headers: response.headers,
                body: raw
            )
        )
    }
}

private func alibabaEmbeddingOptions(from request: EmbeddingRequest) throws -> [String: JSONValue] {
    var output = request.extraBody["alibaba"]?.objectValue ?? request.extraBody
    output.removeValue(forKey: "alibaba")
    if let value = request.providerOptions["alibaba"] {
        guard value != .null else { return alibabaNormalizedEmbeddingOptions(output) }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.alibaba", message: "Alibaba provider options must be an object.")
        }
        output.merge(try alibabaValidateEmbeddingProviderOptions(nested)) { _, new in new }
    }
    return alibabaNormalizedEmbeddingOptions(output)
}

private func alibabaNormalizedEmbeddingOptions(_ options: [String: JSONValue]) -> [String: JSONValue] {
    var output = options
    alibabaMoveKey("textType", to: "text_type", in: &output)
    alibabaMoveKey("outputType", to: "output_type", in: &output)
    return output
}

private func alibabaValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "textType":
            try alibabaRequireEnumOrNull(value, argument: "providerOptions.alibaba.textType", label: "textType", allowed: ["query", "document"])
        case "dimension":
            try alibabaRequirePositiveNumberOrNull(value, argument: "providerOptions.alibaba.dimension", label: "dimension")
        case "outputType":
            try alibabaRequireEnumOrNull(value, argument: "providerOptions.alibaba.outputType", label: "outputType", allowed: ["dense", "sparse", "dense&sparse"])
        default:
            continue
        }
    }
    return options
}
