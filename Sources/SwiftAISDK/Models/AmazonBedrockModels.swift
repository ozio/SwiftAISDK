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
        let prepared = try converseBody(for: request)
        let raw = try await config.sendJSON(path: "/model/\(encodedModelID)/converse", body: prepared.body, headers: request.headers, abortSignal: request.abortSignal)
        let text = raw["output"]?["message"]?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined()
        let reasoning = bedrockReasoningText(from: raw["output"]?["message"]?["content"])
        let toolCalls = bedrockToolCalls(from: raw["output"]?["message"]?["content"])
        guard text != nil || !reasoning.isEmpty || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in Bedrock Converse response.")
        }
        let jsonResponseToolCall = prepared.usesJsonResponseTool ? toolCalls.first { $0.name == "json" } : nil
        return TextGenerationResult(
            text: jsonResponseToolCall?.arguments ?? text ?? "",
            reasoning: reasoning,
            finishReason: bedrockFinishReason(raw["stopReason"]?.stringValue, isJsonResponseFromTool: jsonResponseToolCall != nil),
            usage: bedrockUsage(from: raw["usage"]),
            toolCalls: jsonResponseToolCall == nil ? toolCalls : [],
            providerMetadata: bedrockProviderMetadata(from: raw, isJsonResponseFromTool: jsonResponseToolCall != nil),
            rawValue: raw,
            warnings: prepared.warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try converseBody(for: request)
                    let httpRequest = try config.request(
                        path: "/model/\(encodedModelID)/converse-stream",
                        body: prepared.body,
                        headers: request.headers.mergingHeaders(["accept": "application/vnd.amazon.eventstream"]),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.sendRequest(httpRequest)
                    let parts = try streamFromBedrockResponse(providerID: providerID, response: response, includeRawChunks: request.includeRawChunks, warnings: prepared.warnings, jsonResponseToolName: prepared.usesJsonResponseTool ? "json" : nil)
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

    private func converseBody(for request: LanguageModelRequest) throws -> BedrockPreparedConverseCall {
        var providerOptions = try bedrockRequestProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody)
        let enableDocumentCitations = bedrockDocumentCitationsEnabled(providerOptions)
        var documentCounter = 0
        var warnings: [AIWarning] = []
        if request.frequencyPenalty != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
        }
        if request.presencePenalty != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
        }
        if request.seed != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "seed"))
        }
        var effectiveTools = request.tools
        var effectiveToolChoice = request.toolChoice ?? providerOptions["toolChoice"] ?? request.extraBody["toolChoice"]
        let responseJSONSchema = bedrockResponseJSONSchema(from: request.responseFormat)
        let useNativeStructuredOutput = responseJSONSchema != nil
            && modelID.contains("anthropic")
            && bedrockReasoningConfigEnabled(providerOptions["reasoningConfig"])
        let usesJsonResponseTool = responseJSONSchema != nil && !useNativeStructuredOutput
        if let responseJSONSchema, useNativeStructuredOutput {
            bedrockMergeAdditionalModelRequestFields([
                "output_config": .object([
                    "format": .object([
                        "type": .string("json_schema"),
                        "schema": responseJSONSchema
                    ])
                ])
            ], into: &providerOptions)
        } else if let responseJSONSchema {
            effectiveTools["json"] = responseJSONSchema
            effectiveToolChoice = .object(["type": .string("required")])
        }
        let preparedTools = bedrockPrepareTools(
            from: effectiveTools,
            toolChoice: effectiveToolChoice,
            modelID: modelID
        )
        warnings.append(contentsOf: preparedTools.warnings)

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
                        if preparedTools.toolConfig == nil {
                            warnings.append(AIWarning(
                                type: "unsupported",
                                feature: "toolContent",
                                message: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
                            ))
                            return .object(["text": .string("")])
                        }
                        return .object([
                            "toolUse": .object([
                                "toolUseId": .string(call.id),
                                "name": .string(call.name),
                                "input": bedrockToolArguments(call.arguments)
                            ])
                        ])
                    case let .toolResult(result):
                        if preparedTools.toolConfig == nil {
                            warnings.append(AIWarning(
                                type: "unsupported",
                                feature: "toolContent",
                                message: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
                            ))
                            return .object(["text": .string("")])
                        }
                        return .object([
                            "toolResult": .object([
                                "toolUseId": .string(result.toolCallID),
                                "content": .array([.object(["json": result.modelOutput ?? result.result])]),
                                "status": .string(result.isError ? "error" : "success")
                            ])
                        ])
                    case .providerReference, .toolApprovalRequest, .toolApprovalResponse:
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
        if let topK = request.topK { inferenceConfig["topK"] = .number(Double(topK)) }
        if !request.stopSequences.isEmpty { inferenceConfig["stopSequences"] = .array(request.stopSequences) }
        bedrockApplyReasoningConfig(
            providerOptions.removeValue(forKey: "reasoningConfig"),
            modelID: modelID,
            inferenceConfig: &inferenceConfig,
            providerOptions: &providerOptions,
            warnings: &warnings
        )
        if !inferenceConfig.isEmpty { body["inferenceConfig"] = .object(inferenceConfig) }
        if let toolConfig = preparedTools.toolConfig {
            body["toolConfig"] = toolConfig
        }
        bedrockApplyRequestProviderOptions(providerOptions, to: &body)
        body.merge(bedrockPassthroughExtraBody(request.extraBody)) { _, new in new }
        return BedrockPreparedConverseCall(body: .object(body), warnings: bedrockDeduplicatedWarnings(warnings), usesJsonResponseTool: usesJsonResponseTool)
    }
}

private struct BedrockPreparedConverseCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var usesJsonResponseTool: Bool
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
        guard request.values.count <= 1 else {
            throw AIError.invalidArgument(
                argument: "values",
                message: "Amazon Bedrock embedding models support at most 1 value per call."
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

private func bedrockEmbeddingVector(from raw: JSONValue) -> [Double]? {
    raw["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?[0]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?[0]?["embedding"]?.arrayValue?.compactMap(\.doubleValue)
        ?? raw["embeddings"]?["float"]?[0]?.arrayValue?.compactMap(\.doubleValue)
}

private let bedrockEmbeddingProviderOptionKeys: Set<String> = [
    "dimensions",
    "normalize",
    "embeddingDimension",
    "embeddingPurpose",
    "inputType",
    "truncate",
    "outputDimension"
]

private func bedrockEmbeddingProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
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

private func bedrockEmbeddingPassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in
        key != "amazonBedrock" && key != "bedrock" && !bedrockEmbeddingProviderOptionKeys.contains(key)
    }
}

private func bedrockEmbeddingStringOption(_ value: JSONValue?, argument: String, allowed: Set<String>) throws -> String? {
    guard let value else { return nil }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be one of: \(allowed.sorted().joined(separator: ", ")).")
    }
    return string
}

private func bedrockEmbeddingIntOption(_ value: JSONValue?, argument: String, allowed: Set<Int>) throws -> Int? {
    guard let value else { return nil }
    guard let int = value.intValue, allowed.contains(int) else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be one of: \(allowed.sorted().map(String.init).joined(separator: ", ")).")
    }
    return int
}

private func bedrockEmbeddingBoolOption(_ value: JSONValue?, argument: String) throws -> Bool? {
    guard let value else { return nil }
    guard let bool = value.boolValue else {
        throw AIError.invalidArgument(argument: argument, message: "Value must be a boolean.")
    }
    return bool
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
        if let count = request.count, count > maxImagesPerCall {
            throw AIError.invalidArgument(argument: "count", message: "Amazon Bedrock image model \(modelID) supports at most \(maxImagesPerCall) image(s) per call.")
        }

        let providerOptions = try bedrockImageProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
        var warnings: [AIWarning] = []
        if request.aspectRatio != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "aspectRatio",
                message: "This model does not support aspect ratio. Use size instead."
            ))
        }
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
        if raw["status"]?.stringValue == "Request Moderated" {
            let reasons = raw["details"]?["Moderation Reasons"]?.arrayValue?.compactMap(\.stringValue)
            let message = (reasons?.isEmpty == false ? reasons ?? [] : ["Unknown"]).joined(separator: ", ")
            throw AIError.invalidResponse(provider: providerID, message: "Amazon Bedrock request was moderated: \(message).")
        }
        let base64Images = raw["images"]?.arrayValue?.compactMap(\.stringValue)
            ?? raw["artifacts"]?.arrayValue?.compactMap { $0["base64"]?.stringValue }
            ?? []
        guard !base64Images.isEmpty else {
            let statusSuffix = raw["status"]?.stringValue.map { " Status: \($0)" } ?? ""
            throw AIError.invalidResponse(provider: providerID, message: "Amazon Bedrock returned no images.\(statusSuffix)")
        }
        return ImageGenerationResult(
            urls: [],
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private var maxImagesPerCall: Int {
        modelID == "amazon.nova-canvas-v1:0" ? 5 : 1
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

private struct BedrockPreparedTools {
    var toolConfig: JSONValue?
    var warnings: [AIWarning]
}

private func bedrockRequestProviderOptions(providerOptions: [String: JSONValue], extraBody: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
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

private func bedrockPassthroughExtraBody(_ extraBody: [String: JSONValue]) -> [String: JSONValue] {
    extraBody.filter { key, _ in key != "amazonBedrock" && key != "bedrock" && key != "toolChoice" }
}

private func bedrockDocumentCitationsEnabled(_ providerOptions: [String: JSONValue]) -> Bool {
    providerOptions["citations"]?["enabled"]?.boolValue ?? false
}

private func bedrockResponseJSONSchema(from responseFormat: AIResponseFormat?) -> JSONValue? {
    guard case let .json(schema, _, _) = responseFormat else { return nil }
    return schema
}

private func bedrockReasoningConfigEnabled(_ value: JSONValue?) -> Bool {
    let type = value?["type"]?.stringValue
    return type == "enabled" || type == "adaptive"
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

private func bedrockPrepareTools(from tools: [String: JSONValue], toolChoice: JSONValue?, modelID: String) -> BedrockPreparedTools {
    guard !tools.isEmpty else {
        return BedrockPreparedTools(toolConfig: nil, warnings: [])
    }

    let isAnthropicModel = modelID.contains("anthropic.")
    var warnings: [AIWarning] = []
    var bedrockTools: [JSONValue] = []
    let forcedToolName = bedrockForcedToolName(from: toolChoice)

    for (name, schema) in tools {
        if schema["type"]?.stringValue == "provider" {
            let id = schema["id"]?.stringValue ?? name
            if id == "anthropic.web_search_20250305" {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "web_search_20250305 tool",
                    message: "The web_search_20250305 tool is not supported on Amazon Bedrock."
                ))
                continue
            }
            if isAnthropicModel, let anthropicToolSchema = bedrockAnthropicProviderToolInputSchema(schema) {
                bedrockTools.append(.object([
                    "toolSpec": .object([
                        "name": .string(name),
                        "inputSchema": .object(["json": anthropicToolSchema])
                    ])
                ]))
            } else {
                warnings.append(AIWarning(type: "unsupported", feature: "tool \(id)"))
            }
            continue
        }

        if let forcedToolName, forcedToolName != name {
            continue
        }

        var toolSpec: [String: JSONValue] = [
            "name": .string(name),
            "inputSchema": .object(["json": schema])
        ]
        if let description = schema["description"]?.stringValue,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toolSpec["description"] = .string(description)
        }
        if let strict = schema["strict"] {
            toolSpec["strict"] = strict
        }
        bedrockTools.append(.object(["toolSpec": .object(toolSpec)]))
    }

    guard !bedrockTools.isEmpty else {
        return BedrockPreparedTools(toolConfig: nil, warnings: warnings)
    }

    var toolConfig: [String: JSONValue] = ["tools": .array(bedrockTools)]
    if let choice = bedrockToolChoice(from: toolChoice), !bedrockUsesAnthropicProviderTools(tools: tools, modelID: modelID) {
        if choice == .null {
            return BedrockPreparedTools(toolConfig: nil, warnings: warnings)
        }
        toolConfig["toolChoice"] = choice
    }
    return BedrockPreparedTools(toolConfig: .object(toolConfig), warnings: warnings)
}

private func bedrockUsesAnthropicProviderTools(tools: [String: JSONValue], modelID: String) -> Bool {
    modelID.contains("anthropic.") && tools.values.contains { $0["type"]?.stringValue == "provider" }
}

private func bedrockForcedToolName(from toolChoice: JSONValue?) -> String? {
    guard toolChoice?["type"]?.stringValue == "tool" else { return nil }
    return toolChoice?["toolName"]?.stringValue ?? toolChoice?["name"]?.stringValue
}

private func bedrockToolChoice(from value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if let string = value.stringValue {
        switch string {
        case "auto":
            return .object(["auto": .object([:])])
        case "required":
            return .object(["any": .object([:])])
        case "none":
            return .null
        default:
            return nil
        }
    }
    switch value["type"]?.stringValue {
    case "auto":
        return .object(["auto": .object([:])])
    case "required":
        return .object(["any": .object([:])])
    case "none":
        return .null
    case "tool":
        guard let toolName = value["toolName"]?.stringValue ?? value["name"]?.stringValue else { return nil }
        return .object(["tool": .object(["name": .string(toolName)])])
    default:
        return nil
    }
}

private func bedrockAnthropicProviderToolInputSchema(_ tool: JSONValue) -> JSONValue? {
    if let inputSchema = tool["inputSchema"] {
        return inputSchema
    }
    if let parameters = tool["parameters"] {
        return parameters
    }
    return .object(["type": .string("object"), "properties": .object([:])])
}

private func bedrockApplyReasoningConfig(
    _ value: JSONValue?,
    modelID: String,
    inferenceConfig: inout [String: JSONValue],
    providerOptions: inout [String: JSONValue],
    warnings: inout [AIWarning]
) {
    guard let value else { return }
    guard let reasoningConfig = value.objectValue else {
        warnings.append(AIWarning(type: "unsupported", feature: "reasoningConfig", message: "Bedrock reasoningConfig must be an object."))
        return
    }

    let type = reasoningConfig["type"]?.stringValue
    let budgetTokens = reasoningConfig["budgetTokens"]?.intValue
    let maxReasoningEffort = reasoningConfig["maxReasoningEffort"]?.stringValue
    let display = reasoningConfig["display"]?.stringValue
    let isAnthropicModel = modelID.contains("anthropic.")
    let isOpenAIModel = modelID.hasPrefix("openai.")
    let isAnthropicThinkingEnabled = isAnthropicModel && (type == "enabled" || type == "adaptive")

    if isAnthropicThinkingEnabled {
        if let budgetTokens, type == "enabled" {
            let existingMaxTokens = inferenceConfig["maxTokens"]?.intValue
            inferenceConfig["maxTokens"] = .number(Double((existingMaxTokens ?? 4096) + budgetTokens))
            bedrockMergeAdditionalModelRequestFields([
                "thinking": .object([
                    "type": .string("enabled"),
                    "budget_tokens": .number(Double(budgetTokens))
                ])
            ], into: &providerOptions)
        } else if type == "adaptive" {
            var thinking: [String: JSONValue] = ["type": .string("adaptive")]
            if let display {
                thinking["display"] = .string(display)
            }
            bedrockMergeAdditionalModelRequestFields(["thinking": .object(thinking)], into: &providerOptions)
        }
        if inferenceConfig.removeValue(forKey: "temperature") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled"))
        }
        if inferenceConfig.removeValue(forKey: "topP") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported when thinking is enabled"))
        }
        if inferenceConfig.removeValue(forKey: "topK") != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "topK", message: "topK is not supported when thinking is enabled"))
        }
    } else if !isAnthropicModel {
        if budgetTokens != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "budgetTokens", message: "budgetTokens applies only to Anthropic models on Bedrock and will be ignored for this model."))
        }
        if type == "adaptive" {
            warnings.append(AIWarning(type: "unsupported", feature: "adaptive thinking", message: "adaptive thinking type applies only to Anthropic models on Bedrock."))
        }
    }

    guard let maxReasoningEffort else { return }
    if isAnthropicModel {
        let existing = providerOptions["additionalModelRequestFields"]?["output_config"]?.objectValue ?? [:]
        bedrockMergeAdditionalModelRequestFields([
            "output_config": .object(existing.merging(["effort": .string(maxReasoningEffort)]) { _, new in new })
        ], into: &providerOptions)
    } else if isOpenAIModel {
        bedrockMergeAdditionalModelRequestFields(["reasoning_effort": .string(maxReasoningEffort)], into: &providerOptions)
    } else {
        var nested: [String: JSONValue] = [:]
        if let type, type != "adaptive" {
            nested["type"] = .string(type)
        }
        if let budgetTokens {
            nested["budgetTokens"] = .number(Double(budgetTokens))
        }
        nested["maxReasoningEffort"] = .string(maxReasoningEffort)
        bedrockMergeAdditionalModelRequestFields(["reasoningConfig": .object(nested)], into: &providerOptions)
    }
}

private func bedrockMergeAdditionalModelRequestFields(_ fields: [String: JSONValue], into providerOptions: inout [String: JSONValue]) {
    var existing = providerOptions["additionalModelRequestFields"]?.objectValue ?? [:]
    existing.merge(fields) { old, new in
        if var oldObject = old.objectValue,
           let newObject = new.objectValue {
            oldObject.merge(newObject) { _, nestedNew in nestedNew }
            return .object(oldObject)
        }
        return new
    }
    providerOptions["additionalModelRequestFields"] = .object(existing)
}

private func bedrockDeduplicatedWarnings(_ warnings: [AIWarning]) -> [AIWarning] {
    var seen: Set<String> = []
    var output: [AIWarning] = []
    for warning in warnings {
        let key = "\(warning.type)|\(warning.feature ?? "")|\(warning.setting ?? "")|\(warning.message ?? "")"
        if seen.insert(key).inserted {
            output.append(warning)
        }
    }
    return output
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

private func bedrockImageProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    var output = extraBody.filter { key, _ in bedrockImageProviderOptionKeys.contains(key) }
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

func bedrockProviderMetadata(from raw: JSONValue, isJsonResponseFromTool: Bool = false) -> [String: JSONValue] {
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
    if isJsonResponseFromTool {
        payload["isJsonResponseFromTool"] = .bool(true)
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

func bedrockFinishReason(_ reason: String?, isJsonResponseFromTool: Bool = false) -> String? {
    switch reason {
    case "stop_sequence", "end_turn":
        return "stop"
    case "max_tokens":
        return "length"
    case "content_filtered", "guardrail_intervened":
        return "content-filter"
    case "tool_use":
        return isJsonResponseFromTool ? "stop" : "tool-calls"
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
        let providerOptions = try bedrockRequestProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody)
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
