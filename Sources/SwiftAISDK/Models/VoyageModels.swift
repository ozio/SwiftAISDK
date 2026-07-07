import Foundation

public final class VoyageEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "voyage.embedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let options = try voyageEmbeddingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        guard request.values.count <= 128 else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: 128,
                values: request.values
            )
        }
        var body: [String: JSONValue] = [
            "input": .array(request.values),
            "model": .string(modelID)
        ]
        if let dimensions = request.dimensions {
            body["output_dimension"] = .number(Double(dimensions))
        }
        for (key, value) in options {
            switch key {
            case "inputType":
                body["input_type"] = value
            case "outputDimension":
                body["output_dimension"] = value
            case "outputDtype":
                body["output_dtype"] = value
            default:
                body[key] = value
            }
        }
        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        try validateVoyageEmbeddingResponse(raw, providerID: providerID)
        let embeddings = raw["data"]?.arrayValue?
            .sorted { ($0["index"]?.doubleValue ?? 0) < ($1["index"]?.doubleValue ?? 0) }
            .map { $0["embedding"]?.arrayValue?.compactMap(\.doubleValue) ?? [] } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: TokenUsage(totalTokens: raw["usage"]?["total_tokens"]?.intValue ?? 0),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class VoyageRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "voyage.reranking"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let options = try voyageRerankingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        let preparedDocuments = voyageRerankingDocuments(from: request)
        var body: [String: JSONValue] = [
            "query": .string(request.query),
            "documents": .array(preparedDocuments.documents.map(JSONValue.string)),
            "model": .string(modelID)
        ]
        if let topK = request.topK { body["top_k"] = .number(Double(topK)) }
        for (key, value) in options {
            switch key {
            case "returnDocuments":
                body["return_documents"] = value
            default:
                body[key] = value
            }
        }
        let response = try await config.sendJSONResponse(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        try validateVoyageRerankingResponse(raw, providerID: providerID)
        return RerankingResult(
            results: rerankingResults(from: raw["data"]),
            rawValue: raw,
            warnings: preparedDocuments.warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

func voyageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "voyage")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

let voyageEmbeddingProviderOptionKeys: Set<String> = ["inputType", "truncation", "outputDimension", "outputDtype"]
let voyageRerankingProviderOptionKeys: Set<String> = ["returnDocuments", "truncation"]

func voyageEmbeddingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = voyageProviderOptions(from: extraBody)
    if let value = providerOptions["voyage"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")
        }
        for key in voyageEmbeddingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try voyageValidateEmbeddingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func voyageRerankingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = voyageProviderOptions(from: extraBody)
    if let value = providerOptions["voyage"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage", message: "Voyage provider options must be an object.")
        }
        for key in voyageRerankingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try voyageValidateRerankingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func voyageValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where voyageEmbeddingProviderOptionKeys.contains(key) {
        switch key {
        case "inputType":
            if value == .null {
                output[key] = value
                continue
            }
            guard let string = value.stringValue, ["query", "document"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.inputType", message: "Voyage inputType must be query, document, or null.")
            }
            output[key] = value
        case "truncation":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.truncation", message: "Voyage truncation cannot be null.")
            }
            try voyageRequireBoolean(value, argument: "providerOptions.voyage.truncation", message: "Voyage truncation must be a boolean.")
            output[key] = value
        case "outputDimension":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDimension", message: "Voyage outputDimension cannot be null.")
            }
            try voyageRequireNumber(value, argument: "providerOptions.voyage.outputDimension", message: "Voyage outputDimension must be a number.")
            output[key] = value
        case "outputDtype":
            guard value != .null else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDtype", message: "Voyage outputDtype cannot be null.")
            }
            guard let string = value.stringValue, ["float", "int8", "uint8", "binary", "ubinary"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.voyage.outputDtype", message: "Voyage outputDtype must be one of float, int8, uint8, binary, ubinary.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

func voyageValidateRerankingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where voyageRerankingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.voyage.\(key)", message: "Voyage \(key) cannot be null.")
        }
        try voyageRequireBoolean(value, argument: "providerOptions.voyage.\(key)", message: "Voyage \(key) must be a boolean.")
        output[key] = value
    }
    return output
}

func voyageRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

func voyageRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

func validateVoyageEmbeddingResponse(_ raw: JSONValue, providerID: String) throws {
    guard let data = raw["data"]?.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Voyage embedding response is invalid.")
    }
    if let usage = raw["usage"], usage != .null, usage["total_tokens"]?.doubleValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "Voyage embedding response is invalid.")
    }
    for item in data {
        guard item["index"]?.doubleValue != nil,
              let embedding = item["embedding"]?.arrayValue,
              embedding.allSatisfy({ $0.doubleValue != nil }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Voyage embedding response is invalid.")
        }
    }
}

func validateVoyageRerankingResponse(_ raw: JSONValue, providerID: String) throws {
    guard let data = raw["data"]?.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Voyage reranking response is invalid.")
    }
    for item in data {
        guard item["index"]?.doubleValue != nil,
              item["relevance_score"]?.doubleValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Voyage reranking response is invalid.")
        }
    }
}

struct VoyageRerankingDocuments {
    var documents: [String]
    var warnings: [AIWarning]
}

func voyageRerankingDocuments(from request: RerankingRequest) -> VoyageRerankingDocuments {
    guard let documentObjects = request.documentObjects else {
        return VoyageRerankingDocuments(documents: request.documents, warnings: [])
    }
    let documents = documentObjects.map { object in
        voyageJSONString(.object(object)) ?? ""
    }
    return VoyageRerankingDocuments(
        documents: documents,
        warnings: [
            AIWarning(
                type: "compatibility",
                feature: "object documents",
                message: "Object documents are converted to strings."
            )
        ]
    )
}

func voyageJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
