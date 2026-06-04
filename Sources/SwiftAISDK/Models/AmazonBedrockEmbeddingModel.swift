import Foundation

public final class AmazonBedrockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard let value = request.values.first else {
            return EmbeddingResult(embeddings: [], rawValue: .object([:]))
        }
        guard request.values.count <= 1 else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: 1,
                values: request.values
            )
        }
        let providerOptions = try bedrockEmbeddingProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
        var body: [String: JSONValue]
        if modelID.starts(with: "cohere.embed-") {
            body = [
                "input_type": .string(try bedrockEmbeddingStringOption(
                    providerOptions["inputType"],
                    argument: "providerOptions.bedrock.inputType",
                    allowed: ["search_document", "search_query", "classification", "clustering"]
                ) ?? "search_query"),
                "texts": .array([.string(value)])
            ]
            if let truncate = try bedrockEmbeddingStringOption(providerOptions["truncate"], argument: "providerOptions.bedrock.truncate", allowed: ["NONE", "START", "END"]) {
                body["truncate"] = .string(truncate)
            }
            if let outputDimension = try bedrockEmbeddingIntOption(providerOptions["outputDimension"], argument: "providerOptions.bedrock.outputDimension", allowed: [256, 512, 1024, 1536]) {
                body["output_dimension"] = .number(Double(outputDimension))
            }
        } else if modelID.starts(with: "amazon.nova-"), modelID.contains("embed") {
            let embeddingPurpose = try bedrockEmbeddingStringOption(
                providerOptions["embeddingPurpose"],
                argument: "providerOptions.bedrock.embeddingPurpose",
                allowed: [
                    "GENERIC_INDEX",
                    "TEXT_RETRIEVAL",
                    "IMAGE_RETRIEVAL",
                    "VIDEO_RETRIEVAL",
                    "DOCUMENT_RETRIEVAL",
                    "AUDIO_RETRIEVAL",
                    "GENERIC_RETRIEVAL",
                    "CLASSIFICATION",
                    "CLUSTERING"
                ]
            ) ?? "GENERIC_INDEX"
            let embeddingDimension = try bedrockEmbeddingIntOption(providerOptions["embeddingDimension"], argument: "providerOptions.bedrock.embeddingDimension", allowed: [256, 384, 1024, 3072]) ?? 1024
            let truncate = try bedrockEmbeddingStringOption(providerOptions["truncate"], argument: "providerOptions.bedrock.truncate", allowed: ["NONE", "START", "END"]) ?? "END"
            body = [
                "taskType": "SINGLE_EMBEDDING",
                "singleEmbeddingParams": .object([
                    "embeddingPurpose": .string(embeddingPurpose),
                    "embeddingDimension": .number(Double(embeddingDimension)),
                    "text": .object(["value": .string(value), "truncationMode": .string(truncate)])
                ])
            ]
        } else {
            body = ["inputText": .string(value)]
            let providerDimensions = try bedrockEmbeddingIntOption(providerOptions["dimensions"], argument: "providerOptions.bedrock.dimensions", allowed: [256, 512, 1024])
            if let dimensions = request.dimensions ?? providerDimensions {
                body["dimensions"] = .number(Double(dimensions))
            }
            if let normalize = try bedrockEmbeddingBoolOption(providerOptions["normalize"], argument: "providerOptions.bedrock.normalize") {
                body["normalize"] = .bool(normalize)
            }
        }
        body.merge(bedrockEmbeddingPassthroughExtraBody(request.extraBody)) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/model/\(encodedModelID)/invoke", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard let embedding = bedrockEmbeddingVector(from: raw) else {
            throw AIError.invalidResponse(provider: providerID, message: "No embedding vector found in Bedrock response.")
        }
        let tokenCount = raw["inputTextTokenCount"]?.intValue ?? raw["inputTokenCount"]?.intValue
        return EmbeddingResult(
            embeddings: [embedding],
            usage: tokenCount.map { TokenUsage(inputTokens: $0, totalTokens: $0) },
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private var encodedModelID: String {
        bedrockEncodeModelID(modelID)
    }
}

func bedrockEmbeddingVector(from raw: JSONValue) -> [Double]? {
    raw["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?[0]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?[0]?["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?["float"]?[0]?.arrayValue?.compactMap(\.doubleValue)
}

let bedrockEmbeddingProviderOptionKeys: Set<String> = [
    "dimensions",
    "normalize",
    "embeddingDimension",
    "embeddingPurpose",
    "inputType",
    "truncate",
    "outputDimension"
]

func bedrockEmbeddingProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    var output = extraBody.filter { key, _ in bedrockEmbeddingProviderOptionKeys.contains(key) }
    if let bedrock = extraBody["bedrock"]?.objectValue {
        output.merge(bedrock) { _, new in new }
    }
    if let amazonBedrock = extraBody["amazonBedrock"]?.objectValue {
        output.merge(amazonBedrock) { _, new in new }
    }
    if let bedrock = providerOptions["bedrock"] {
        guard let object = bedrock.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.bedrock", message: "Bedrock provider options must be an object.")
        }
        output.merge(object) { _, new in new }
    }
    if let amazonBedrock = providerOptions["amazonBedrock"] {
        guard let object = amazonBedrock.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.amazonBedrock", message: "Amazon Bedrock provider options must be an object.")
        }
        output.merge(object) { _, new in new }
    }
    return output
}

func bedrockEmbeddingPassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in
        key != "amazonBedrock" && key != "bedrock" && !bedrockEmbeddingProviderOptionKeys.contains(key)
    }
}

func bedrockEmbeddingStringOption(_ value: JSONValue?, argument: String, allowed: Set<String>) throws -> String? {
    guard let value else { return nil }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be one of: \(allowed.sorted().joined(separator: ", ")).")
    }
    return string
}

func bedrockEmbeddingIntOption(_ value: JSONValue?, argument: String, allowed: Set<Int>) throws -> Int? {
    guard let value else { return nil }
    guard let int = value.intValue, allowed.contains(int) else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be one of: \(allowed.sorted().map(String.init).joined(separator: ", ")).")
    }
    return int
}

func bedrockEmbeddingBoolOption(_ value: JSONValue?, argument: String) throws -> Bool? {
    guard let value else { return nil }
    guard let bool = value.boolValue else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be a boolean.")
    }
    return bool
}
