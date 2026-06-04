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

struct BedrockPreparedConverseCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var usesJsonResponseTool: Bool
}

func bedrockToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}
