import Foundation

public final class AmazonBedrockLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let raw = try await config.sendJSON(path: "/model/\(encodedModelID)/converse", body: try converseBody(for: request), headers: request.headers, abortSignal: request.abortSignal)
        let text = raw["output"]?["message"]?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined()
        let reasoning = bedrockReasoningText(from: raw["output"]?["message"]?["content"])
        let toolCalls = bedrockToolCalls(from: raw["output"]?["message"]?["content"])
        guard text != nil || !reasoning.isEmpty || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Bedrock Converse response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            reasoning: reasoning,
            finishReason: bedrockFinishReason(raw["stopReason"]?.stringValue),
            usage: bedrockUsage(from: raw["usage"]),
            toolCalls: toolCalls,
            providerMetadata: bedrockProviderMetadata(from: raw),
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let httpRequest = try config.request(
                        path: "/model/\(encodedModelID)/converse-stream",
                        body: try converseBody(for: request),
                        headers: request.headers.mergingHeaders(["accept": "application/vnd.amazon.eventstream"]),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    let parts = try streamFromBedrockResponse(providerID: providerID, response: response, includeRawChunks: request.includeRawChunks)
                    for part in parts {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private var encodedModelID: String {
        bedrockEncodeModelID(modelID)
    }

    private func converseBody(for request: LanguageModelRequest) throws -> JSONValue {
        let providerOptions = bedrockRequestProviderOptions(from: request.extraBody)
        let enableDocumentCitations = bedrockDocumentCitationsEnabled(providerOptions)
        var documentCounter = 0

        let system = request.messages
            .filter { $0.role == .system }
            .flatMap { message in message.content.compactMap(\.text).map { JSONValue.object(["text": .string($0)]) } }

        let messages = try request.messages
            .filter { $0.role != .system }
            .map { message -> JSONValue in
                let content = try message.content.map { part -> JSONValue in
                    switch part {
                    case let .text(text):
                        return .object(["text": .string(text)])
                    case let .imageURL(url):
                        return .object(["image": .object(["source": .object(["s3Location": .object(["uri": .string(url)])])])])
                    case let .data(mimeType, data), let .file(mimeType, data, _):
                        if let imageFormat = bedrockImageFormat(for: mimeType) {
                            return .object([
                                "image": .object([
                                    "format": .string(imageFormat),
                                    "source": .object(["bytes": .string(data.base64EncodedString())])
                                ])
                            ])
                        }

                        guard let documentFormat = bedrockDocumentFormat(for: mimeType) else {
                            throw AIError.invalidArgument(
                                argument: "messages.content.data.mimeType",
                                message: "Amazon Bedrock Converse supports image MIME types \(bedrockSupportedImageMimeTypes.joined(separator: ", ")) or document MIME types \(bedrockSupportedDocumentMimeTypes.joined(separator: ", ")); got \(mimeType)."
                            )
                        }

                        documentCounter += 1
                        var document: [String: JSONValue] = [
                            "format": .string(documentFormat),
                            "name": .string("document-\(documentCounter)"),
                            "source": .object(["bytes": .string(data.base64EncodedString())])
                        ]
                        if enableDocumentCitations {
                            document["citations"] = .object(["enabled": .bool(true)])
                        }
                        return .object(["document": .object(document)])
                    case let .toolCall(call):
                        return .object([
                            "toolUse": .object([
                                "toolUseId": .string(call.id),
                                "name": .string(call.name),
                                "input": bedrockToolArguments(call.arguments)
                            ])
                        ])
                    case let .toolResult(result):
                        return .object([
                            "toolResult": .object([
                                "toolUseId": .string(result.toolCallID),
                                "content": .array([.object(["json": result.modelOutput ?? result.result])]),
                                "status": .string(result.isError ? "error" : "success")
                            ])
                        ])
                    case .toolApprovalRequest, .toolApprovalResponse:
                        return .object(["text": .string("")])
                    }
                }

                return JSONValue.object([
                    "role": .string(message.role == .assistant ? "assistant" : "user"),
                    "content": .array(content)
                ])
            }

        var body: [String: JSONValue] = ["messages": .array(messages)]
        if !system.isEmpty { body["system"] = .array(system) }

        var inferenceConfig: [String: JSONValue] = [:]
        if let maxOutputTokens = request.maxOutputTokens { inferenceConfig["maxTokens"] = .number(Double(maxOutputTokens)) }
        if let temperature = request.temperature { inferenceConfig["temperature"] = .number(min(max(temperature, 0), 1)) }
        if let topP = request.topP { inferenceConfig["topP"] = .number(topP) }
        if !request.stopSequences.isEmpty { inferenceConfig["stopSequences"] = .array(request.stopSequences) }
        if !inferenceConfig.isEmpty { body["inferenceConfig"] = .object(inferenceConfig) }
        bedrockApplyRequestProviderOptions(providerOptions, to: &body)
        body.merge(bedrockPassthroughExtraBody(request.extraBody)) { _, new in new }
        return .object(body)
    }
}

private func bedrockToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}

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
        var body: [String: JSONValue]
        if modelID.starts(with: "cohere.embed-") {
            body = ["input_type": "search_query", "texts": .array([.string(value)])]
        } else if modelID.starts(with: "amazon.nova-"), modelID.contains("embed") {
            body = [
                "taskType": "SINGLE_EMBEDDING",
                "singleEmbeddingParams": .object([
                    "embeddingPurpose": "GENERIC_INDEX",
                    "text": .object(["value": .string(value), "truncationMode": "END"])
                ])
            ]
        } else {
            body = ["inputText": .string(value)]
            if let dimensions = request.dimensions { body["dimensions"] = .number(Double(dimensions)) }
        }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/model/\(encodedModelID)/invoke", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embedding = raw["embedding"]?.arrayValue?.compactMap(\.doubleValue)
            ?? raw["embeddings"]?[0]?.arrayValue?.compactMap(\.doubleValue)
            ?? raw["embeddings"]?[0]?["embedding"]?.arrayValue?.compactMap(\.doubleValue)
            ?? []
        return EmbeddingResult(
            embeddings: [embedding],
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private var encodedModelID: String {
        bedrockEncodeModelID(modelID)
    }
}

public final class AmazonBedrockImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let providerOptions = bedrockImageProviderOptions(from: request.extraBody)
        let size = request.size?.split(separator: "x").compactMap { Int($0) } ?? []
        var imageGenerationConfig: [String: JSONValue] = [:]
        if size.count == 2 {
            imageGenerationConfig["width"] = .number(Double(size[0]))
            imageGenerationConfig["height"] = .number(Double(size[1]))
        }
        if let count = request.count { imageGenerationConfig["numberOfImages"] = .number(Double(count)) }
        if let seed = providerOptions["seed"] {
            imageGenerationConfig["seed"] = seed
        } else if let seed = request.extraBody["seed"] {
            imageGenerationConfig["seed"] = seed
        }
        if let quality = providerOptions["quality"] {
            imageGenerationConfig["quality"] = quality
        }
        if let cfgScale = providerOptions["cfgScale"] ?? providerOptions["cfg_scale"] {
            imageGenerationConfig["cfgScale"] = cfgScale
        }

        let body = try bedrockImageBody(
            request: request,
            providerOptions: providerOptions,
            imageGenerationConfig: imageGenerationConfig
        )
        let response = try await config.sendJSONResponse(path: "/model/\(encodedModelID)/invoke", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let base64Images = raw["images"]?.arrayValue?.compactMap(\.stringValue)
            ?? raw["artifacts"]?.arrayValue?.compactMap { $0["base64"]?.stringValue }
            ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private var encodedModelID: String {
        bedrockEncodeModelID(modelID)
    }

    private func bedrockImageBody(
        request: ImageGenerationRequest,
        providerOptions: [String: JSONValue],
        imageGenerationConfig: [String: JSONValue]
    ) throws -> [String: JSONValue] {
        var body: [String: JSONValue]
        if request.files.isEmpty {
            var textToImageParams: [String: JSONValue] = ["text": .string(request.prompt)]
            if let negativeText = providerOptions["negativeText"] ?? providerOptions["negative_text"] {
                textToImageParams["negativeText"] = negativeText
            }
            if let style = providerOptions["style"] {
                textToImageParams["style"] = style
            }
            body = [
                "taskType": .string("TEXT_IMAGE"),
                "textToImageParams": .object(textToImageParams)
            ]
            if !imageGenerationConfig.isEmpty {
                body["imageGenerationConfig"] = .object(imageGenerationConfig)
            }
            body.merge(bedrockImagePassthroughExtraBody(request.extraBody)) { _, new in new }
            return body
        }

        let taskType = providerOptions["taskType"]?.stringValue
            ?? providerOptions["task_type"]?.stringValue
            ?? ((request.mask != nil || providerOptions["maskPrompt"] != nil || providerOptions["mask_prompt"] != nil) ? "INPAINTING" : "IMAGE_VARIATION")
        let sourceImage = try bedrockImageBase64(request.files[0])

        switch taskType {
        case "INPAINTING":
            var params: [String: JSONValue] = ["image": .string(sourceImage)]
            if !request.prompt.isEmpty { params["text"] = .string(request.prompt) }
            if let negativeText = providerOptions["negativeText"] ?? providerOptions["negative_text"] {
                params["negativeText"] = negativeText
            }
            if let mask = request.mask {
                params["maskImage"] = .string(try bedrockImageBase64(mask))
            } else if let maskPrompt = providerOptions["maskPrompt"] ?? providerOptions["mask_prompt"] {
                params["maskPrompt"] = maskPrompt
            }
            body = [
                "taskType": .string("INPAINTING"),
                "inPaintingParams": .object(params)
            ]
        case "OUTPAINTING":
            var params: [String: JSONValue] = ["image": .string(sourceImage)]
            if !request.prompt.isEmpty { params["text"] = .string(request.prompt) }
            if let negativeText = providerOptions["negativeText"] ?? providerOptions["negative_text"] {
                params["negativeText"] = negativeText
            }
            if let outPaintingMode = providerOptions["outPaintingMode"] ?? providerOptions["out_painting_mode"] {
                params["outPaintingMode"] = outPaintingMode
            }
            if let mask = request.mask {
                params["maskImage"] = .string(try bedrockImageBase64(mask))
            } else if let maskPrompt = providerOptions["maskPrompt"] ?? providerOptions["mask_prompt"] {
                params["maskPrompt"] = maskPrompt
            }
            body = [
                "taskType": .string("OUTPAINTING"),
                "outPaintingParams": .object(params)
            ]
        case "BACKGROUND_REMOVAL":
            body = [
                "taskType": .string("BACKGROUND_REMOVAL"),
                "backgroundRemovalParams": .object(["image": .string(sourceImage)])
            ]
        case "IMAGE_VARIATION":
            var params: [String: JSONValue] = [
                "images": .array(try request.files.map { .string(try bedrockImageBase64($0)) })
            ]
            if !request.prompt.isEmpty { params["text"] = .string(request.prompt) }
            if let negativeText = providerOptions["negativeText"] ?? providerOptions["negative_text"] {
                params["negativeText"] = negativeText
            }
            if let similarityStrength = providerOptions["similarityStrength"] ?? providerOptions["similarity_strength"] {
                params["similarityStrength"] = similarityStrength
            }
            body = [
                "taskType": .string("IMAGE_VARIATION"),
                "imageVariationParams": .object(params)
            ]
        default:
            throw AIError.invalidArgument(argument: "extraBody.amazonBedrock.taskType", message: "Unsupported Amazon Bedrock image task type: \(taskType).")
        }

        if taskType != "BACKGROUND_REMOVAL", !imageGenerationConfig.isEmpty {
            body["imageGenerationConfig"] = .object(imageGenerationConfig)
        }
        body.merge(bedrockImagePassthroughExtraBody(request.extraBody)) { _, new in new }
        return body
    }
}

func bedrockEncodeModelID(_ modelID: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return modelID.addingPercentEncoding(withAllowedCharacters: allowed) ?? modelID
}

private let bedrockDocumentMimeTypes: [String: String] = [
    "application/pdf": "pdf",
    "text/csv": "csv",
    "application/msword": "doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.ms-excel": "xls",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
    "text/html": "html",
    "text/plain": "txt",
    "text/markdown": "md"
]

private let bedrockImageMimeTypes: [String: String] = [
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp"
]

private var bedrockSupportedDocumentMimeTypes: [String] {
    bedrockDocumentMimeTypes.keys.sorted()
}

private var bedrockSupportedImageMimeTypes: [String] {
    bedrockImageMimeTypes.keys.sorted()
}

private func bedrockDocumentFormat(for mimeType: String) -> String? {
    bedrockDocumentMimeTypes[mimeType]
}

private func bedrockImageFormat(for mimeType: String) -> String? {
    bedrockImageMimeTypes[mimeType]
}

private func bedrockRequestProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody["amazonBedrock"]?.objectValue ?? extraBody["bedrock"]?.objectValue ?? [:]
}

private func bedrockPassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in key != "amazonBedrock" && key != "bedrock" }
}

private func bedrockDocumentCitationsEnabled(_ providerOptions: [String: JSONValue]) -> Bool {
    providerOptions["citations"]?["enabled"]?.boolValue ?? false
}

private func bedrockApplyRequestProviderOptions(_ providerOptions: [String: JSONValue], to body: inout [String: JSONValue]) {
    if let guardrailConfig = providerOptions["guardrailConfig"] {
        body["guardrailConfig"] = guardrailConfig
    }
    if let additionalModelRequestFields = providerOptions["additionalModelRequestFields"] {
        body["additionalModelRequestFields"] = additionalModelRequestFields
    }
    if let serviceTier = providerOptions["serviceTier"] {
        if let serviceTierType = serviceTier.stringValue {
            body["serviceTier"] = .object(["type": .string(serviceTierType)])
        } else {
            body["serviceTier"] = serviceTier
        }
    }
}

private let bedrockImageProviderOptionKeys: Set<String> = [
    "negativeText",
    "negative_text",
    "quality",
    "cfgScale",
    "cfg_scale",
    "style",
    "taskType",
    "task_type",
    "maskPrompt",
    "mask_prompt",
    "outPaintingMode",
    "out_painting_mode",
    "similarityStrength",
    "similarity_strength",
    "seed"
]

private func bedrockImageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let amazonBedrock = extraBody["amazonBedrock"]?.objectValue {
        return amazonBedrock
    }
    if let bedrock = extraBody["bedrock"]?.objectValue {
        return bedrock
    }
    return extraBody.filter { key, _ in bedrockImageProviderOptionKeys.contains(key) }
}

private func bedrockImagePassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in
        key != "amazonBedrock" && key != "bedrock" && !bedrockImageProviderOptionKeys.contains(key)
    }
}

private func bedrockImageBase64(_ file: ImageInputFile) throws -> String {
    guard let data = file.data else {
        throw AIError.invalidArgument(
            argument: "files",
            message: "URL-based images are not supported for Amazon Bedrock image editing."
        )
    }
    return data.base64EncodedString()
}

func bedrockToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, part in
        guard let toolUse = part["toolUse"] else { return nil }
        let name = toolUse["name"]?.stringValue ?? "tool-\(index)"
        return AIToolCall(
            id: toolUse["toolUseId"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: bedrockToolArguments(toolUse["input"]),
            rawValue: part
        )
    } ?? []
}

func bedrockToolArguments(_ value: JSONValue?) -> String {
    guard let value else { return "{}" }
    guard let data = try? encodeJSONBody(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

func bedrockReasoningText(from value: JSONValue?) -> String {
    value?.arrayValue?.compactMap { part in
        part["reasoningContent"]?["reasoningText"]?["text"]?.stringValue
    }.joined() ?? ""
}

func bedrockProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]
    if let trace = raw["trace"] {
        payload["trace"] = trace
    }
    if let performanceConfig = raw["performanceConfig"] {
        payload["performanceConfig"] = performanceConfig
    }
    if let serviceTier = raw["serviceTier"] {
        payload["serviceTier"] = serviceTier
    }
    if let stopSequence = raw["additionalModelResponseFields"]?["delta"]?["stop_sequence"] {
        payload["stopSequence"] = stopSequence
    }
    var usage: [String: JSONValue] = [:]
    if let cacheWriteInputTokens = raw["usage"]?["cacheWriteInputTokens"] {
        usage["cacheWriteInputTokens"] = cacheWriteInputTokens
    }
    if let cacheDetails = raw["usage"]?["cacheDetails"] {
        usage["cacheDetails"] = cacheDetails
    }
    if !usage.isEmpty {
        payload["usage"] = .object(usage)
    }
    guard !payload.isEmpty else { return [:] }
    return [
        "amazonBedrock": .object(payload),
        "bedrock": .object(payload)
    ]
}

func bedrockProviderMetadata(fromStreamMetadata raw: JSONValue?) -> [String: JSONValue] {
    guard let raw else { return [:] }
    var payload: [String: JSONValue] = [:]
    if let trace = raw["trace"] {
        payload["trace"] = trace
    }
    if let performanceConfig = raw["performanceConfig"] {
        payload["performanceConfig"] = performanceConfig
    }
    if let serviceTier = raw["serviceTier"] {
        payload["serviceTier"] = serviceTier
    }
    var usage: [String: JSONValue] = [:]
    if let cacheWriteInputTokens = raw["usage"]?["cacheWriteInputTokens"] {
        usage["cacheWriteInputTokens"] = cacheWriteInputTokens
    }
    if let cacheDetails = raw["usage"]?["cacheDetails"] {
        usage["cacheDetails"] = cacheDetails
    }
    if !usage.isEmpty {
        payload["usage"] = .object(usage)
    }
    guard !payload.isEmpty else { return [:] }
    return [
        "amazonBedrock": .object(payload),
        "bedrock": .object(payload)
    ]
}

func bedrockFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop_sequence", "end_turn":
        return "stop"
    case "max_tokens":
        return "length"
    case "content_filtered", "guardrail_intervened":
        return "content-filter"
    case "tool_use":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}

func bedrockUsage(from raw: JSONValue?) -> TokenUsage? {
    guard let raw else { return nil }
    return TokenUsage(
        inputTokens: raw["inputTokens"]?.intValue,
        outputTokens: raw["outputTokens"]?.intValue,
        totalTokens: raw["totalTokens"]?.intValue
    )
}

public final class AmazonBedrockRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let modelID: String
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        let providerOptions = bedrockRequestProviderOptions(from: request.extraBody)
        let modelArn = "arn:aws:bedrock:\(config.region)::foundation-model/\(modelID)"
        var modelConfiguration: [String: JSONValue] = ["modelArn": .string(modelArn)]
        if let additionalModelRequestFields = providerOptions["additionalModelRequestFields"] {
            modelConfiguration["additionalModelRequestFields"] = additionalModelRequestFields
        }

        var bedrockRerankingConfiguration: [String: JSONValue] = [
            "modelConfiguration": .object(modelConfiguration)
        ]
        if let topK = request.topK {
            bedrockRerankingConfiguration["numberOfResults"] = .number(Double(topK))
        }

        var body: [String: JSONValue] = [
            "queries": .array([.object(["type": "TEXT", "textQuery": .object(["text": .string(request.query)])])]),
            "sources": .array(request.documents.map { .object(["type": "INLINE", "inlineDocumentSource": .object(["type": "TEXT", "textDocument": .object(["text": .string($0)])])]) }),
            "rerankingConfiguration": .object([
                "type": "BEDROCK_RERANKING_MODEL",
                "amazonBedrockRerankingConfiguration": .object(bedrockRerankingConfiguration)
            ])
        ]
        if let nextToken = providerOptions["nextToken"] {
            body["nextToken"] = nextToken
        }
        body.merge(bedrockPassthroughExtraBody(request.extraBody)) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/rerank", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let results = raw["results"]?.arrayValue?.compactMap { item -> RerankedDocument? in
            guard let index = item["index"]?.intValue,
                  let score = item["relevanceScore"]?.doubleValue ?? item["score"]?.doubleValue else { return nil }
            return RerankedDocument(index: index, score: score)
        } ?? []
        return RerankingResult(
            results: results,
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}
