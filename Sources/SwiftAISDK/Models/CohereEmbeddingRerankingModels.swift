import Foundation

public final class CohereEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "cohere.textEmbedding"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let options = try cohereEmbeddingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        guard request.values.count <= 96 else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: 96,
                values: request.values
            )
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "embedding_types": .array(["float"]),
            "texts": .array(request.values),
            "input_type": options["inputType"] ?? options["input_type"] ?? .string("search_query")
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
            default:
                body[key] = value
            }
        }
        let response = try await config.sendJSONResponse(path: "/embed", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["embeddings"]?["float"]?.arrayValue?.map { $0.arrayValue?.compactMap(\.doubleValue) ?? [] } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
            usage: TokenUsage(totalTokens: raw["meta"]?["billed_units"]?["input_tokens"]?.intValue),
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class CohereRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "cohere.reranking"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let options = try cohereRerankingProviderOptions(
            extraBody: request.extraBody,
            providerOptions: request.providerOptions
        )
        let preparedDocuments = cohereRerankingDocuments(from: request)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(request.query),
            "documents": .array(preparedDocuments.documents.map(JSONValue.string))
        ]
        if let topK = request.topK { body["top_n"] = .number(Double(topK)) }
        for (key, value) in options {
            switch key {
            case "maxTokensPerDoc":
                body["max_tokens_per_doc"] = value
            default:
                body[key] = value
            }
        }
        let response = try await config.sendJSONResponse(path: "/rerank", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        return RerankingResult(
            results: rerankingResults(from: raw["results"]),
            rawValue: raw,
            warnings: preparedDocuments.warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

let cohereEmbeddingProviderOptionKeys: Set<String> = ["inputType", "truncate", "outputDimension"]
let cohereRerankingProviderOptionKeys: Set<String> = ["maxTokensPerDoc", "priority"]

func cohereEmbeddingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = cohereProviderOptions(from: extraBody)
    if let value = providerOptions["cohere"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere", message: "Cohere provider options must be an object.")
        }
        for key in cohereEmbeddingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try cohereValidateEmbeddingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func cohereRerankingProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = cohereProviderOptions(from: extraBody)
    if let value = providerOptions["cohere"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere", message: "Cohere provider options must be an object.")
        }
        for key in cohereRerankingProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try cohereValidateRerankingProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

func cohereValidateLanguageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    guard let thinking = options["thinking"] else { return [:] }
    guard thinking != .null else {
        throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking", message: "Cohere thinking cannot be null.")
    }
    guard let object = thinking.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking", message: "Cohere thinking must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let type = object["type"] {
        guard type != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.type", message: "Cohere thinking.type cannot be null.")
        }
        guard let string = type.stringValue, ["enabled", "disabled"].contains(string) else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.type", message: "Cohere thinking.type must be enabled or disabled.")
        }
        output["type"] = type
    }
    if let tokenBudget = object["tokenBudget"] {
        guard tokenBudget != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.thinking.tokenBudget", message: "Cohere thinking.tokenBudget cannot be null.")
        }
        try cohereRequireNumber(tokenBudget, argument: "providerOptions.cohere.thinking.tokenBudget", message: "Cohere thinking.tokenBudget must be a number.")
        output["tokenBudget"] = tokenBudget
    }
    return ["thinking": .object(output)]
}

func cohereValidateEmbeddingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where cohereEmbeddingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) cannot be null.")
        }
        switch key {
        case "inputType":
            guard let string = value.stringValue, ["search_document", "search_query", "classification", "clustering"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.inputType", message: "Cohere inputType must be one of search_document, search_query, classification, clustering.")
            }
            output[key] = value
        case "truncate":
            guard let string = value.stringValue, ["NONE", "START", "END"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.truncate", message: "Cohere truncate must be one of NONE, START, END.")
            }
            output[key] = value
        case "outputDimension":
            guard let number = value.doubleValue, [256, 512, 1024, 1536].contains(Int(number)), number == Double(Int(number)) else {
                throw AIError.invalidArgument(argument: "providerOptions.cohere.outputDimension", message: "Cohere outputDimension must be one of 256, 512, 1024, 1536.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

func cohereValidateRerankingProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where cohereRerankingProviderOptionKeys.contains(key) {
        guard value != .null else {
            throw AIError.invalidArgument(argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) cannot be null.")
        }
        try cohereRequireNumber(value, argument: "providerOptions.cohere.\(key)", message: "Cohere \(key) must be a number.")
        output[key] = value
    }
    return output
}

func cohereRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

struct CohereRerankingDocuments {
    var documents: [String]
    var warnings: [AIWarning]
}

func cohereRerankingDocuments(from request: RerankingRequest) -> CohereRerankingDocuments {
    guard let documentObjects = request.documentObjects else {
        return CohereRerankingDocuments(documents: request.documents, warnings: [])
    }
    let documents = documentObjects.map { object in
        cohereJSONString(.object(object)) ?? ""
    }
    return CohereRerankingDocuments(
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
