import Foundation

public final class AmazonBedrockLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "amazon-bedrock"
    public let modelID: String
    public let supportedURLs: [String: [AISupportedURLPattern]] = [
        "image/*": [AISupportedURLPattern(bedrockIsS3URL)]
    ]
    private let config: BedrockRuntimeConfig

    init(modelID: String, config: BedrockRuntimeConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try converseBody(for: request)
        let raw = try await config.sendJSON(path: "/model/\(encodedModelID)/converse", body: prepared.body, headers: request.headers, abortSignal: request.abortSignal)
        let rawText = raw["output"]?["message"]?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined()
        let text = rawText.map { text in
            prepared.usesJsonInstruction ? BedrockJSONObjectTextExtractor().process(text) : text
        }
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
                    let parts = try streamFromBedrockResponse(
                        providerID: providerID,
                        response: response,
                        includeRawChunks: request.includeRawChunks,
                        warnings: prepared.warnings,
                        jsonResponseToolName: prepared.usesJsonResponseTool ? "json" : nil,
                        extractJSONObjectText: prepared.usesJsonInstruction
                    )
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
        var warnings: [AIWarning] = []
        bedrockApplyTopLevelReasoning(
            request.reasoning,
            modelID: modelID,
            maxOutputTokens: request.maxOutputTokens,
            providerOptions: &providerOptions,
            warnings: &warnings
        )
        let enableDocumentCitations = bedrockDocumentCitationsEnabled(providerOptions)
        var documentCounter = 0
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
        let modelSupportsStructuredOutput = anthropicModelCapabilities(modelID).supportsStructuredOutput
        let useNativeStructuredOutput = responseJSONSchema != nil
            && modelID.contains("anthropic")
            && bedrockSupportsNativeStructuredOutput(modelID: modelID)
            && (modelSupportsStructuredOutput || bedrockReasoningConfigEnabled(providerOptions["reasoningConfig"]))
        let usesJsonInstruction = responseJSONSchema != nil
            && modelID.contains("anthropic")
            && !bedrockSupportsStrictToolSpec(modelID: modelID)
            && !request.tools.isEmpty
        let usesJsonResponseTool = responseJSONSchema != nil && !useNativeStructuredOutput && !usesJsonInstruction
        if let responseJSONSchema, useNativeStructuredOutput {
            bedrockMergeAdditionalModelRequestFields([
                "output_config": .object([
                    "format": .object([
                        "type": .string("json_schema"),
                        "schema": anthropicSanitizeJSONSchema(responseJSONSchema)
                    ])
                ])
            ], into: &providerOptions)
        } else if let responseJSONSchema, usesJsonResponseTool {
            effectiveTools["json"] = responseJSONSchema
            effectiveToolChoice = .object(["type": .string("required")])
        }
        let preparedTools = bedrockPrepareTools(
            from: effectiveTools,
            toolChoice: effectiveToolChoice,
            modelID: modelID
        )
        warnings.append(contentsOf: preparedTools.warnings)

        let messagesWithJSONInstruction = usesJsonInstruction
            ? injectJSONInstruction(
                into: request.messages,
                schema: responseJSONSchema,
                instruction: AIJSONInstruction(
                    schemaSuffix: "You MUST answer with only a JSON object that matches the JSON schema above. Do not wrap it in markdown fences or include any other text."
                )
            )
            : request.messages

        let system = messagesWithJSONInstruction
            .filter { $0.role == .system }
            .flatMap { message -> [JSONValue] in
                var blocks = message.content.compactMap(\.text).map { JSONValue.object(["text": .string($0)]) }
                if let cachePoint = bedrockCachePoint(from: message.providerMetadata) {
                    blocks.append(cachePoint)
                }
                return blocks
            }

        let messages = try messagesWithJSONInstruction
            .filter { $0.role != .system }
            .map { message -> JSONValue in
                var content: [JSONValue] = []
                for part in message.content {
                    switch part {
                    case let .text(text, providerMetadata):
                        content.append(.object(["text": .string(text)]))
                        if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                            content.append(cachePoint)
                        }
                    case let .reasoning(text, providerMetadata):
                        if let reasoning = bedrockReasoningContentBlock(text: text, providerMetadata: providerMetadata) {
                            content.append(reasoning)
                        }
                        if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                            content.append(cachePoint)
                        }
                    case .reasoningFile, .custom:
                        content.append(.object(["text": .string("")]))
                    case let .imageURL(url, providerMetadata):
                        guard bedrockIsS3URL(url), let imageFormat = bedrockImageFormat(forURL: url) else {
                            throw AIError.invalidArgument(
                                argument: "messages.content.imageURL",
                                message: "Amazon Bedrock Converse supports only s3:// image URLs ending in .jpg, .jpeg, .png, .gif, or .webp."
                            )
                        }
                        content.append(.object([
                            "image": .object([
                                "format": .string(imageFormat),
                                "source": .object([
                                    "s3Location": .object(["uri": .string(url)])
                                ])
                            ])
                        ]))
                        if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                            content.append(cachePoint)
                        }
                    case let .data(mimeType, data, providerMetadata):
                        let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
                        if let imageFormat = bedrockImageFormat(for: resolvedMimeType) {
                            content.append(.object([
                                "image": .object([
                                    "format": .string(imageFormat),
                                    "source": .object(["bytes": .string(data.base64EncodedString())])
                                ])
                            ]))
                            if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                                content.append(cachePoint)
                            }
                            continue
                        }

                        if let videoFormat = bedrockVideoFormat(for: resolvedMimeType) {
                            content.append(.object([
                                "video": .object([
                                    "format": .string(videoFormat),
                                    "source": .object(["bytes": .string(data.base64EncodedString())])
                                ])
                            ]))
                            if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                                content.append(cachePoint)
                            }
                            continue
                        }

                        guard let documentFormat = bedrockDocumentFormat(for: resolvedMimeType) else {
                            throw AIError.invalidArgument(
                                argument: "messages.content.data.mimeType",
                                message: "Amazon Bedrock Converse supports image MIME types \(bedrockSupportedImageMimeTypes.joined(separator: ", ")), video MIME types \(bedrockSupportedVideoMimeTypes.joined(separator: ", ")), or document MIME types \(bedrockSupportedDocumentMimeTypes.joined(separator: ", ")); got \(mimeType)."
                            )
                        }

                        documentCounter += 1
                        var document: [String: JSONValue] = [
                            "format": .string(documentFormat),
                            "name": .string("document-\(documentCounter)"),
                            "source": .object(["bytes": .string(data.base64EncodedString())])
                        ]
                        if enableDocumentCitations || bedrockDocumentCitationsEnabled(providerMetadata) {
                            document["citations"] = .object(["enabled": .bool(true)])
                        }
                        content.append(.object(["document": .object(document)]))
                        if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                            content.append(cachePoint)
                        }
                    case let .file(mimeType, data, filename, providerMetadata):
                        let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
                        if let imageFormat = bedrockImageFormat(for: resolvedMimeType) {
                            content.append(.object([
                                "image": .object([
                                    "format": .string(imageFormat),
                                    "source": .object(["bytes": .string(data.base64EncodedString())])
                                ])
                            ]))
                            if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                                content.append(cachePoint)
                            }
                            continue
                        }

                        if let videoFormat = bedrockVideoFormat(for: resolvedMimeType) {
                            content.append(.object([
                                "video": .object([
                                    "format": .string(videoFormat),
                                    "source": .object(["bytes": .string(data.base64EncodedString())])
                                ])
                            ]))
                            if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                                content.append(cachePoint)
                            }
                            continue
                        }

                        guard let documentFormat = bedrockDocumentFormat(for: resolvedMimeType) else {
                            throw AIError.invalidArgument(
                                argument: "messages.content.file.mimeType",
                                message: "Amazon Bedrock Converse supports image MIME types \(bedrockSupportedImageMimeTypes.joined(separator: ", ")), video MIME types \(bedrockSupportedVideoMimeTypes.joined(separator: ", ")), or document MIME types \(bedrockSupportedDocumentMimeTypes.joined(separator: ", ")); got \(mimeType)."
                            )
                        }

                        documentCounter += 1
                        var document: [String: JSONValue] = [
                            "format": .string(documentFormat),
                            "name": .string(filename.map(stripFileExtension) ?? "document-\(documentCounter)"),
                            "source": .object(["bytes": .string(data.base64EncodedString())])
                        ]
                        if enableDocumentCitations || bedrockDocumentCitationsEnabled(providerMetadata) {
                            document["citations"] = .object(["enabled": .bool(true)])
                        }
                        content.append(.object(["document": .object(document)]))
                        if let cachePoint = bedrockCachePoint(from: providerMetadata) {
                            content.append(cachePoint)
                        }
                    case let .toolCall(call):
                        if preparedTools.toolConfig == nil {
                            warnings.append(AIWarning(
                                type: "unsupported",
                                feature: "toolContent",
                                message: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
                            ))
                            content.append(.object(["text": .string("")]))
                            continue
                        }
                        content.append(.object([
                            "toolUse": .object([
                                "toolUseId": .string(call.id),
                                "name": .string(bedrockSanitizeToolName(call.name)),
                                "input": bedrockToolArguments(call.arguments)
                            ])
                        ]))
                    case let .toolResult(result):
                        if preparedTools.toolConfig == nil {
                            warnings.append(AIWarning(
                                type: "unsupported",
                                feature: "toolContent",
                                message: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
                            ))
                            content.append(.object(["text": .string("")]))
                            continue
                        }
                        content.append(.object([
                            "toolResult": .object([
                                "toolUseId": .string(result.toolCallID),
                                "content": .array(try bedrockToolResultContent(result, documentCounter: &documentCounter)),
                                "status": .string(result.isError ? "error" : "success")
                            ])
                        ]))
                        if let cachePoint = bedrockCachePoint(from: result.providerMetadata) {
                            content.append(cachePoint)
                        }
                    case .providerReference, .toolApprovalRequest, .toolApprovalResponse:
                        content.append(.object(["text": .string("")]))
                    }
                }
                if let cachePoint = bedrockCachePoint(from: message.providerMetadata) {
                    content.append(cachePoint)
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
        return BedrockPreparedConverseCall(
            body: .object(body),
            warnings: bedrockDeduplicatedWarnings(warnings),
            usesJsonResponseTool: usesJsonResponseTool,
            usesJsonInstruction: usesJsonInstruction
        )
    }
}

struct BedrockPreparedConverseCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var usesJsonResponseTool: Bool
    var usesJsonInstruction: Bool
}

func bedrockToolArguments(_ arguments: String) -> JSONValue {
    let decoded = (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
    guard case .object = decoded else {
        return .object(["rawInvalidInput": decoded])
    }
    return decoded
}
