import Foundation

public final class OpenAICompatibleResponsesModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try preparedRequest(for: request, stream: false)
        let response = try await config.sendJSONResponse(path: "/responses", modelID: modelID, body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let toolNameAliases = openAIResponsesProviderToolNameAliases(from: request.tools)
        let toolCalls = openAIResponsesToolCalls(from: raw, providerID: providerID, toolNameAliases: toolNameAliases)
        let toolResults = openAIResponsesToolResults(from: raw, providerID: providerID, toolNameAliases: toolNameAliases)
        let toolApprovalRequests = openAIResponsesToolApprovalRequests(from: raw, providerID: providerID)
        let sources = openAIResponsesSources(from: raw, providerID: providerID)
        let content = openAIResponsesResultContent(
            from: raw,
            toolCalls: toolCalls,
            toolResults: toolResults,
            toolApprovalRequests: toolApprovalRequests,
            sources: sources,
            providerID: providerID,
            toolNameAliases: toolNameAliases
        )
        let text = openAIResponsesOutputText(from: raw)
            ?? raw["choices"]?[0]?["message"]?["content"]?.stringValue
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No output text found in responses API response.")
        }
        let hasClientToolCalls = toolCalls.contains { !$0.providerExecuted }
        let finishReason: String?
        if case .openResponses = config.responsesRequestMode {
            finishReason = openResponsesFinishReason(
                incompleteReason: raw["incomplete_details"]?["reason"]?.stringValue,
                hasToolCalls: hasClientToolCalls
            )
        } else {
            finishReason = openAIResponsesFinishReason(
                status: raw["status"]?.stringValue,
                incompleteReason: raw["incomplete_details"]?["reason"]?.stringValue,
                hasToolCalls: hasClientToolCalls
            )
        }
        return TextGenerationResult(
            text: text,
            content: content,
            finishReason: finishReason,
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            toolResults: toolResults,
            toolApprovalRequests: toolApprovalRequests,
            sources: sources,
            providerMetadata: openAIResponsesProviderMetadata(from: raw, providerID: providerID),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try preparedRequest(for: request, stream: true)
                    let body = prepared.body
                    let response = try await config.transport.send(config.request(path: "/responses", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
                    }
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    let toolNameAliases = openAIResponsesProviderToolNameAliases(from: request.tools)
                    var toolCallBuffers = OpenAIResponsesStreamingToolCalls(providerID: providerID, toolNameAliases: toolNameAliases)
                    var providerMetadata: [String: JSONValue] = [:]
                    var streamResponseID: JSONValue?
                    var textItemPhases: [String: JSONValue] = [:]
                    var textItemAnnotations: [String: [JSONValue]] = [:]
                    var streamOutputLogprobs: [JSONValue] = []
                    var activeReasoning: [String: OpenAIResponsesActiveReasoning] = [:]
                    var openResponsesHasToolCalls = false
                    var hasOutputStarted = false
                    let shouldThrowPreOutputStreamErrors = isOpenAIBackedProvider(providerID, config: config)
                    var sourceCounter = 0
                    let streamEvents = parseServerSentEvents(response.body).filter { $0.data != "[DONE]" }
                    for (eventIndex, event) in streamEvents.enumerated() {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if openAIResponsesIsChatCompletionsStreamChunk(raw) {
                            continuation.yield(.error(message: openAIResponsesChatCompletionsMismatchMessage, rawValue: raw))
                            continue
                        }
                        if raw["type"]?.stringValue == "error" {
                            if shouldThrowPreOutputStreamErrors && !hasOutputStarted {
                                throw openAIResponsesStreamAPIError(raw, providerID: providerID)
                            }
                            continuation.yield(.error(
                                message: raw["message"]?.stringValue ?? raw["error"]?["message"]?.stringValue ?? "OpenAI Responses stream error.",
                                rawValue: raw
                            ))
                            continue
                        }
                        let responsePayload = raw["response"] ?? raw
                        openAICompatibleMergeProviderMetadata(
                            openAIResponsesProviderMetadata(from: responsePayload, providerID: providerID),
                            into: &providerMetadata
                        )
                        if raw["type"]?.stringValue == "response.created" {
                            streamResponseID = responsePayload["id"]
                            openResponsesHasToolCalls = false
                            continuation.yield(.responseMetadata(
                                openAIResponsesStreamResponseMetadata(from: responsePayload, response: response, modelID: modelID)
                            ))
                        }
                        if openAIResponsesStreamEventStartsOutput(raw) {
                            hasOutputStarted = true
                        }
                        if raw["type"]?.stringValue == "response.output_item.added",
                           let item = raw["item"],
                           item["type"]?.stringValue == "message",
                           let itemID = item["id"]?.stringValue {
                            if let phase = item["phase"] {
                                textItemPhases[itemID] = phase
                            }
                            textItemAnnotations[itemID] = []
                            continuation.yield(.textStart(
                                id: itemID,
                                providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: item["phase"], providerID: providerID)
                            ))
                        }
                        if raw["type"]?.stringValue == "response.output_item.added",
                           let item = raw["item"],
                           item["type"]?.stringValue == "reasoning",
                           let itemID = item["id"]?.stringValue {
                            activeReasoning[itemID] = OpenAIResponsesActiveReasoning(
                                encryptedContent: item["encrypted_content"],
                                summaryParts: [0: .active]
                            )
                            continuation.yield(.reasoningStart(
                                id: "\(itemID):0",
                                providerMetadata: openAIResponsesReasoningProviderMetadata(
                                    itemID: itemID,
                                    encryptedContent: item["encrypted_content"],
                                    includeEncryptedContent: true,
                                    providerID: providerID
                                )
                            ))
                        }
                        if let delta = raw["delta"]?.stringValue ?? raw["output_text_delta"]?.stringValue, openAIResponsesIsTextDelta(raw) {
                            continuation.yield(.textDelta(delta))
                            if let itemID = raw["item_id"]?.stringValue {
                                continuation.yield(.textDeltaPart(
                                    id: itemID,
                                    delta: delta,
                                    providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: textItemPhases[itemID], providerID: providerID)
                                ))
                            }
                        }
                        if raw["type"]?.stringValue == "response.output_text.done",
                           let logprobs = raw["logprobs"] {
                            streamOutputLogprobs.append(logprobs)
                        }
                        if let delta = raw["delta"]?.stringValue, raw["type"]?.stringValue == "response.reasoning_summary_text.delta" {
                            continuation.yield(.reasoningDelta(delta))
                            if let itemID = raw["item_id"]?.stringValue,
                               let summaryIndex = raw["summary_index"]?.intValue {
                                continuation.yield(.reasoningDeltaPart(
                                    id: "\(itemID):\(summaryIndex)",
                                    delta: delta,
                                    providerMetadata: openAIResponsesReasoningProviderMetadata(itemID: itemID, providerID: providerID)
                                ))
                            }
                        }
                        if raw["type"]?.stringValue == "response.output_text.annotation.added",
                           let annotation = raw["annotation"],
                           let itemID = raw["item_id"]?.stringValue {
                            textItemAnnotations[itemID, default: []].append(annotation)
                            for source in openAIResponsesSources(fromAnnotations: [annotation], providerID: providerID, sourceCounter: &sourceCounter) {
                                continuation.yield(.source(source))
                            }
                        }
                        if raw["type"]?.stringValue == "response.reasoning_summary_part.added",
                           let itemID = raw["item_id"]?.stringValue,
                           let summaryIndex = raw["summary_index"]?.intValue,
                           summaryIndex > 0,
                           var reasoning = activeReasoning[itemID] {
                            reasoning.summaryParts[summaryIndex] = .active
                            for canConcludeIndex in reasoning.summaryParts.keys.sorted()
                                where reasoning.summaryParts[canConcludeIndex] == .canConclude {
                                continuation.yield(.reasoningEnd(
                                    id: "\(itemID):\(canConcludeIndex)",
                                    providerMetadata: openAIResponsesReasoningProviderMetadata(itemID: itemID, providerID: providerID)
                                ))
                                reasoning.summaryParts[canConcludeIndex] = .concluded
                            }
                            activeReasoning[itemID] = reasoning
                            continuation.yield(.reasoningStart(
                                id: "\(itemID):\(summaryIndex)",
                                providerMetadata: openAIResponsesReasoningProviderMetadata(
                                    itemID: itemID,
                                    encryptedContent: reasoning.encryptedContent,
                                    includeEncryptedContent: true,
                                    providerID: providerID
                                )
                            ))
                        }
                        for eventPart in toolCallBuffers.apply(event: raw) {
                            if case let .toolCall(toolCall) = eventPart,
                               !toolCall.providerExecuted,
                               toolCall.rawValue?["type"]?.stringValue != "local_shell_call",
                               toolCall.rawValue?["type"]?.stringValue != "apply_patch_call" {
                                openResponsesHasToolCalls = true
                            }
                            continuation.yield(eventPart)
                        }
                        if raw["type"]?.stringValue == "response.output_item.done",
                           let item = raw["item"],
                           item["type"]?.stringValue == "message",
                           let itemID = item["id"]?.stringValue {
                            let phase = item["phase"] ?? textItemPhases[itemID]
                            let annotations = textItemAnnotations[itemID] ?? []
                            continuation.yield(.textEnd(
                                id: itemID,
                                providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: phase, annotations: annotations, providerID: providerID)
                            ))
                            textItemAnnotations[itemID] = nil
                        }
                        if raw["type"]?.stringValue == "response.reasoning_summary_part.done",
                           let itemID = raw["item_id"]?.stringValue,
                           let summaryIndex = raw["summary_index"]?.intValue {
                            activeReasoning[itemID]?.summaryParts[summaryIndex] = .canConclude
                        }
                        if raw["type"]?.stringValue == "response.output_item.done",
                           let item = raw["item"],
                           item["type"]?.stringValue == "reasoning",
                           let itemID = item["id"]?.stringValue,
                           let reasoning = activeReasoning[itemID] {
                            let summaryPartIndices = reasoning.summaryParts.keys.sorted().filter {
                                reasoning.summaryParts[$0] == .active || reasoning.summaryParts[$0] == .canConclude
                            }
                            for summaryIndex in summaryPartIndices {
                                continuation.yield(.reasoningEnd(
                                    id: "\(itemID):\(summaryIndex)",
                                    providerMetadata: openAIResponsesReasoningProviderMetadata(
                                        itemID: itemID,
                                        encryptedContent: item["encrypted_content"],
                                        includeEncryptedContent: true,
                                        providerID: providerID
                                    )
                                ))
                            }
                            activeReasoning[itemID] = nil
                        }
                        if raw["type"]?.stringValue == "response.output_item.done",
                           let item = raw["item"],
                           item["type"]?.stringValue == "compaction",
                           let itemID = item["id"]?.stringValue {
                            continuation.yield(.custom(
                                .object(["kind": .string("openai.compaction")]),
                                providerMetadata: openAIResponsesCompactionProviderMetadata(
                                    itemID: itemID,
                                    encryptedContent: item["encrypted_content"],
                                    providerID: providerID
                                )
                            ))
                        }
                        if raw["type"]?.stringValue == "response.completed" {
                            let hasLaterResponse = streamEvents[(eventIndex + 1)...].contains { laterEvent in
                                guard let laterRaw = try? decodeJSONBody(Data(laterEvent.data.utf8)) else { return false }
                                return laterRaw["type"]?.stringValue == "response.created"
                            }
                            guard !hasLaterResponse else { continue }
                            let response = raw["response"] ?? raw
                            let finishReason = openResponsesStreamFinishReason(
                                response: response,
                                hasToolCalls: openResponsesHasToolCalls,
                                mode: config.responsesRequestMode
                            )
                            let finishUsage = tokenUsage(from: response)
                            if providerMetadata.isEmpty {
                                continuation.yield(.finish(reason: finishReason, usage: finishUsage))
                            } else {
                                continuation.yield(.finishMetadata(
                                    reason: finishReason,
                                    usage: finishUsage,
                                    providerMetadata: openAIResponsesProviderMetadataByPreservingResponseID(
                                        openAIResponsesProviderMetadataByApplyingStreamLogprobs(
                                            providerMetadata,
                                            streamOutputLogprobs: streamOutputLogprobs,
                                            providerID: providerID
                                        ),
                                        responseID: streamResponseID,
                                        providerID: providerID
                                    )
                                ))
                            }
                        } else if raw["type"]?.stringValue == "response.incomplete" {
                            let response = raw["response"] ?? raw
                            let finishReason = openResponsesStreamFinishReason(
                                response: response,
                                hasToolCalls: openResponsesHasToolCalls,
                                mode: config.responsesRequestMode
                            )
                            let finishUsage = tokenUsage(from: response)
                            if providerMetadata.isEmpty {
                                continuation.yield(.finish(reason: finishReason, usage: finishUsage))
                            } else {
                                continuation.yield(.finishMetadata(
                                    reason: finishReason,
                                    usage: finishUsage,
                                    providerMetadata: openAIResponsesProviderMetadataByPreservingResponseID(
                                        openAIResponsesProviderMetadataByApplyingStreamLogprobs(
                                            providerMetadata,
                                            streamOutputLogprobs: streamOutputLogprobs,
                                            providerID: providerID
                                        ),
                                        responseID: streamResponseID,
                                        providerID: providerID
                                    )
                                ))
                            }
                        } else if raw["type"]?.stringValue == "response.failed" {
                            let response = raw["response"] ?? raw
                            if shouldThrowPreOutputStreamErrors && !hasOutputStarted {
                                throw openAIResponsesStreamFailedError(response, providerID: providerID)
                            }
                            let finishReason = response["incomplete_details"]?["reason"]?.stringValue == nil
                                ? "error"
                                : openResponsesStreamFinishReason(
                                    response: response,
                                    hasToolCalls: openResponsesHasToolCalls,
                                    mode: config.responsesRequestMode
                                )
                            let finishUsage = tokenUsage(from: response)
                            if providerMetadata.isEmpty {
                                continuation.yield(.finish(reason: finishReason, usage: finishUsage))
                            } else {
                                continuation.yield(.finishMetadata(
                                    reason: finishReason,
                                    usage: finishUsage,
                                    providerMetadata: openAIResponsesProviderMetadataByPreservingResponseID(
                                        openAIResponsesProviderMetadataByApplyingStreamLogprobs(
                                            providerMetadata,
                                            streamOutputLogprobs: streamOutputLogprobs,
                                            providerID: providerID
                                        ),
                                        responseID: streamResponseID,
                                        providerID: providerID
                                    )
                                ))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func preparedRequest(for request: LanguageModelRequest, stream: Bool) throws -> OpenAICompatibleResponsesPreparedRequest {
        switch config.responsesRequestMode {
        case .openAICompatible:
            return try openAICompatiblePreparedRequest(for: request, stream: stream)
        case let .openResponses(providerOptionsName):
            return try openResponsesPreparedRequest(for: request, stream: stream, providerOptionsName: providerOptionsName)
        }
    }

    private func openAICompatiblePreparedRequest(for request: LanguageModelRequest, stream: Bool) throws -> OpenAICompatibleResponsesPreparedRequest {
        if providerID.hasPrefix("xai.") {
            return try xaiResponsesPreparedRequest(
                modelID: modelID,
                providerID: providerID,
                request: request,
                stream: stream,
                transformRequestBody: config.transformRequestBody
            )
        }
        let extraBody: [String: JSONValue]
        if isOpenAIBackedProvider(providerID, config: config) {
            extraBody = openAIResponsesProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot)
        } else {
            extraBody = request.extraBody
        }
        var options = openAIResponsesOptions(from: extraBody)
        let isEffectiveReasoningModel = openAIResponsesEffectiveReasoningModel(modelID: modelID, options: options)
        openAIResponsesApplyTopLevelReasoning(request.reasoning, isReasoningModel: isEffectiveReasoningModel, to: &options)
        let isOpenAIBacked = isOpenAIBackedProvider(providerID, config: config)
        var warnings = openResponsesWarnings(for: request)
        if isOpenAIBacked {
            warnings.append(contentsOf: openAIResponsesOpenAIBackedWarnings(options: options))
        }
        openAIResponsesFinalizeReasoningOptions(isReasoningModel: isEffectiveReasoningModel, options: &options, warnings: &warnings)
        if isOpenAIBacked {
            openAIResponsesApplyAutomaticOptions(to: &options, tools: request.tools, isReasoningModel: isEffectiveReasoningModel)
        }
        let stripsReasoningModelSampling = openAIResponsesStripsSamplingSettings(isReasoningModel: isEffectiveReasoningModel, options: options)
        if stripsReasoningModelSampling {
            if request.temperature != nil {
                warnings.append(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported for reasoning models"))
            }
            if request.topP != nil {
                warnings.append(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported for reasoning models"))
            }
        }
        let store = options["store"]?.boolValue ?? true
        let hasConversation = options["conversation"] != nil
        let hasPreviousResponseID = options["previous_response_id"] != nil
        var processedApprovalIDs: Set<String> = []
        let toolNamespaces = openAIResponsesToolNamespaces(from: request.tools)
        let preparedTools = try openAIResponsesTools(from: request.tools)
        let useDeveloperRoleForSystem = isEffectiveReasoningModel
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(try request.messages.flatMap {
                try openAIResponsesInputMessageJSON(
                    $0,
                    store: store,
                    hasConversation: hasConversation,
                    hasPreviousResponseID: hasPreviousResponseID,
                    processedApprovalIDs: &processedApprovalIDs,
                    toolNamespaces: toolNamespaces,
                    customToolNames: preparedTools.customToolNames,
                    providerID: providerID,
                    useDeveloperRoleForSystem: useDeveloperRoleForSystem,
                    warnings: &warnings
                )
            })
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature, !stripsReasoningModelSampling { body["temperature"] = .number(temperature) }
        if let topP = request.topP, !stripsReasoningModelSampling { body["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        body.merge(options) { _, new in new }
        if let textVerbosity = body.removeValue(forKey: "textVerbosity") {
            var text = body["text"]?.objectValue ?? [:]
            text["verbosity"] = textVerbosity
            body["text"] = .object(text)
        }
        let strictJsonSchema = body.removeValue(forKey: "strictJsonSchema")
        if let textFormat = openAIResponsesTextFormat(from: request.responseFormat, strictJsonSchema: strictJsonSchema) {
            var text = body["text"]?.objectValue ?? [:]
            text["format"] = textFormat
            body["text"] = .object(text)
        }
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
            if let allowedTools = options["allowedTools"] ?? options["allowed_tools"] {
                body["tool_choice"] = openAIResponsesAllowedToolsChoice(from: allowedTools)
            } else if let toolChoice = openAIResponsesToolChoice(from: request.toolChoice ?? request.extraBody["toolChoice"], customToolNames: preparedTools.customToolNames) {
                body["tool_choice"] = toolChoice
            }
        }
        body.removeValue(forKey: "allowedTools")
        body.removeValue(forKey: "allowed_tools")
        return OpenAICompatibleResponsesPreparedRequest(body: config.transformRequestBody?(body) ?? body, warnings: warnings)
    }

    private func openResponsesPreparedRequest(for request: LanguageModelRequest, stream: Bool, providerOptionsName: String) throws -> OpenAICompatibleResponsesPreparedRequest {
        let preparedInput = openResponsesInput(from: request.messages, providerID: providerID)
        let providerOptions = try openResponsesProviderOptions(providerOptions: request.providerOptions, providerOptionsName: providerOptionsName)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": preparedInput.input
        ]
        if stream { body["stream"] = .bool(true) }
        if let instructions = preparedInput.instructions { body["instructions"] = .string(instructions) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let presencePenalty = request.presencePenalty { body["presence_penalty"] = .number(presencePenalty) }
        if let frequencyPenalty = request.frequencyPenalty { body["frequency_penalty"] = .number(frequencyPenalty) }
        var reasoning: [String: JSONValue] = [:]
        if let effort = providerOptions["reasoningEffort"] { reasoning["effort"] = effort }
        if let summary = providerOptions["reasoningSummary"] { reasoning["summary"] = summary }
        if !reasoning.isEmpty { body["reasoning"] = .object(reasoning) }
        let tools = openResponsesFunctionTools(from: request.tools)
        if !tools.isEmpty { body["tools"] = .array(tools) }
        if let toolChoice = openResponsesToolChoice(from: request.toolChoice ?? request.extraBody["toolChoice"]) {
            body["tool_choice"] = toolChoice
        }
        if let textFormat = openResponsesTextFormat(from: request.responseFormat) {
            body["text"] = .object(["format": textFormat])
        }
        return OpenAICompatibleResponsesPreparedRequest(
            body: config.transformRequestBody?(body) ?? body,
            warnings: openResponsesWarnings(for: request) + preparedInput.warnings
        )
    }
}

let openAIResponsesChatCompletionsMismatchMessage =
    "Received a Chat Completions stream while using the OpenAI Responses API. " +
    "The default OpenAI provider model uses the Responses API. If your custom baseURL targets a Chat Completions-compatible endpoint, use openai.chat('model-id') or createOpenAI(...).chat('model-id') instead. " +
    "You can also use @ai-sdk/openai-compatible for OpenAI-compatible providers."

func openAIResponsesIsChatCompletionsStreamChunk(_ raw: JSONValue) -> Bool {
    raw["choices"]?.arrayValue != nil && raw["type"]?.stringValue == nil
}
