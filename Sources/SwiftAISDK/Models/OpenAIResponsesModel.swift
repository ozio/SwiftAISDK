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
        if case .openResponses = config.responsesRequestMode {
            if let errorMessage = raw["error"]?["message"]?.stringValue {
                throw AIError.apiCall(AIAPICallError(
                    provider: providerID,
                    statusCode: 400,
                    responseHeaders: response.response.headers,
                    responseBody: errorMessage,
                    isRetryable: false
                ))
            }
            let hasOutput = raw["output"] != nil && raw["output"] != .null
            let hasOutputText = raw["output_text"]?.stringValue != nil
            let hasChatChoices = raw["choices"]?.arrayValue != nil
            if !hasOutput,
               !hasOutputText,
               !hasChatChoices {
                let detail = raw["incomplete_details"]?["reason"]?.stringValue
                    ?? raw["status"]?.stringValue
                let message = detail.map { "Responses API returned no output (\($0))" }
                    ?? "Responses API returned no output"
                throw AIError.apiCall(AIAPICallError(
                    provider: providerID,
                    statusCode: 500,
                    responseHeaders: response.response.headers,
                    responseBody: message,
                    isRetryable: false
                ))
            }
        }
        let toolNameAliases = openAIResponsesProviderToolNameAliases(from: request.tools)
        let functionToolNames = openAIResponsesFunctionToolNames(from: request.tools)
        let toolCalls = openAIResponsesToolCalls(
            from: raw,
            providerID: providerID,
            toolNameAliases: toolNameAliases,
            functionToolNames: functionToolNames
        )
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
            mode: config.responsesRequestMode,
            toolNameAliases: toolNameAliases,
            functionToolNames: functionToolNames
        )
        let text = openAIResponsesOutputText(from: raw)
            ?? raw["choices"]?[0]?["message"]?["content"]?.stringValue
        let hasReasoning = content.contains { part in
            if case .reasoning = part { true } else { false }
        }
        guard let text = text ?? ((!toolCalls.isEmpty || hasReasoning) ? "" : nil) else {
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
            let task = Task {
                do {
                    let prepared = try preparedRequest(for: request, stream: true)
                    let body = prepared.body
                    let httpRequest = try config.request(path: "/responses", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
                    let response = try await config.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: httpRequest))
                    }
                    let responseHead = httpResponseHead(from: response, request: httpRequest)
                    continuation.yield(.streamStart(warnings: prepared.warnings))
                    let toolNameAliases = openAIResponsesProviderToolNameAliases(from: request.tools)
                    let functionToolNames = openAIResponsesFunctionToolNames(from: request.tools)
                    var toolCallBuffers = OpenAIResponsesStreamingToolCalls(
                        providerID: providerID,
                        toolNameAliases: toolNameAliases,
                        functionToolNames: functionToolNames
                    )
                    var providerMetadata: [String: JSONValue] = [:]
                    var streamResponseID: JSONValue?
                    var textItemPhases: [String: JSONValue] = [:]
                    var textItemAnnotations: [String: [JSONValue]] = [:]
                    var streamOutputLogprobs: [JSONValue] = []
                    var activeReasoning: [String: OpenAIResponsesActiveReasoning] = [:]
                    var activeOutputItemIDs: [Int: String] = [:]
                    var activeTextPartIDs: Set<String> = []
                    var activeReasoningPartIDs: Set<String> = []
                    func resolvedOutputItemID(_ itemID: String, outputIndex: Int?) -> String {
                        guard let outputIndex else { return itemID }
                        return activeOutputItemIDs[outputIndex] ?? itemID
                    }
                    var openResponsesHasToolCalls = false
                    var hasOutputStarted = false
                    var encounteredStreamError = false
                    var fallbackFinishReason: String? = "other"
                    let shouldThrowPreOutputStreamErrors = isOpenAIBackedProvider(providerID, config: config)
                    var sourceCounter = 0
                    var pendingCompletedResponse: JSONValue?
                    var pendingCompletedResponseType: String?
                    let openResponsesProviderOptionsName: String?
                    if case let .openResponses(providerOptionsName) = config.responsesRequestMode {
                        openResponsesProviderOptionsName = providerOptionsName
                    } else {
                        openResponsesProviderOptionsName = nil
                    }
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        if openAIResponsesIsChatCompletionsStreamChunk(raw) {
                            fallbackFinishReason = "error"
                            continuation.yield(.error(message: openAIResponsesChatCompletionsMismatchMessage, rawValue: raw))
                            continue
                        }
                        if let validationMessage = openAIResponsesKnownStreamEventValidationMessage(raw) {
                            encounteredStreamError = true
                            fallbackFinishReason = "error"
                            continuation.yield(.error(message: validationMessage, rawValue: raw))
                            continue
                        }
                        if raw["type"]?.stringValue == "error" {
                            if shouldThrowPreOutputStreamErrors && !hasOutputStarted {
                                throw openAIResponsesStreamAPIError(raw, providerID: providerID)
                            }
                            encounteredStreamError = true
                            fallbackFinishReason = "error"
                            if let providerError = providerID == "xai.responses"
                                ? xaiResponsesStreamProviderError(from: raw)
                                : shouldThrowPreOutputStreamErrors
                                    ? openAIProviderStreamError(from: raw)
                                    : nil {
                                continuation.yield(.providerError(providerError))
                            } else {
                                continuation.yield(.error(
                                    message: raw["message"]?.stringValue ?? raw["error"]?["message"]?.stringValue ?? "OpenAI Responses stream error.",
                                    rawValue: raw
                                ))
                            }
                            continue
                        }
                        let responsePayload = raw["response"] ?? raw
                        if raw["type"]?.stringValue == "response.created" {
                            for textID in activeTextPartIDs.sorted() {
                                continuation.yield(.textEnd(id: textID))
                            }
                            for reasoningID in activeReasoningPartIDs.sorted() {
                                continuation.yield(.reasoningEnd(id: reasoningID))
                            }
                            if let completedResponse = pendingCompletedResponse {
                                let completedWasFailed = pendingCompletedResponseType == "response.failed"
                                    || completedResponse["status"]?.stringValue == "failed"
                                let completedFinishReason = completedWasFailed
                                    ? completedResponse["incomplete_details"]?["reason"]?.stringValue == nil
                                        ? "error"
                                        : openResponsesStreamFinishReason(
                                            response: completedResponse,
                                            hasToolCalls: openResponsesHasToolCalls,
                                            mode: config.responsesRequestMode
                                        )
                                    : encounteredStreamError
                                        ? "error"
                                        : openResponsesStreamFinishReason(
                                            response: completedResponse,
                                            hasToolCalls: openResponsesHasToolCalls,
                                            mode: config.responsesRequestMode
                                        )
                                continuation.yield(.finishMetadata(
                                    reason: completedFinishReason,
                                    usage: tokenUsage(from: completedResponse),
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
                            pendingCompletedResponse = nil
                            pendingCompletedResponseType = nil
                            providerMetadata = [:]
                            streamOutputLogprobs = []
                            textItemPhases = [:]
                            textItemAnnotations = [:]
                            activeReasoning = [:]
                            activeOutputItemIDs = [:]
                            activeTextPartIDs = []
                            activeReasoningPartIDs = []
                            toolCallBuffers = OpenAIResponsesStreamingToolCalls(
                                providerID: providerID,
                                toolNameAliases: toolNameAliases,
                                functionToolNames: functionToolNames
                            )
                            streamResponseID = responsePayload["id"]
                            openResponsesHasToolCalls = false
                            hasOutputStarted = false
                            fallbackFinishReason = "other"
                            continuation.yield(.responseMetadata(
                                openAIResponsesStreamResponseMetadata(from: responsePayload, response: responseHead, modelID: modelID)
                            ))
                        }
                        openAICompatibleMergeProviderMetadata(
                            openAIResponsesProviderMetadata(from: responsePayload, providerID: providerID),
                            into: &providerMetadata
                        )
                        if openAIResponsesStreamEventStartsOutput(raw) {
                            hasOutputStarted = true
                        }
                        if raw["type"]?.stringValue == "response.output_item.added",
                           let item = raw["item"],
                           item["type"]?.stringValue == "message",
                           let itemID = item["id"]?.stringValue {
                            if let outputIndex = raw["output_index"]?.intValue {
                                activeOutputItemIDs[outputIndex] = itemID
                            }
                            if let phase = item["phase"] {
                                textItemPhases[itemID] = phase
                            }
                            textItemAnnotations[itemID] = []
                            activeTextPartIDs.insert(itemID)
                            continuation.yield(.textStart(
                                id: itemID,
                                providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: item["phase"], providerID: providerID)
                            ))
                        }
                        if raw["type"]?.stringValue == "response.output_item.added",
                           let item = raw["item"],
                           item["type"]?.stringValue == "reasoning",
                           let itemID = item["id"]?.stringValue {
                            if let outputIndex = raw["output_index"]?.intValue {
                                activeOutputItemIDs[outputIndex] = itemID
                            }
                            activeReasoning[itemID] = OpenAIResponsesActiveReasoning(
                                encryptedContent: item["encrypted_content"],
                                summaryParts: [0: .active]
                            )
                            let reasoningPartID = openResponsesProviderOptionsName == nil
                                ? "\(itemID):0"
                                : itemID
                            activeReasoningPartIDs.insert(reasoningPartID)
                            continuation.yield(.reasoningStart(
                                id: reasoningPartID,
                                providerMetadata: openAIResponsesReasoningProviderMetadata(
                                    itemID: itemID,
                                    encryptedContent: item["encrypted_content"],
                                    includeEncryptedContent: true,
                                    providerID: providerID
                                )
                            ))
                        }
                        if openResponsesProviderOptionsName != nil,
                           let delta = raw["delta"]?.stringValue,
                           raw["type"]?.stringValue == "response.reasoning_text.delta" {
                            let eventItemID = raw["item_id"]?.stringValue ?? "reasoning-0"
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            if activeReasoningPartIDs.insert(itemID).inserted {
                                continuation.yield(.reasoningStart(id: itemID))
                            }
                            continuation.yield(.reasoningDeltaPart(id: itemID, delta: delta))
                        }
                        if let delta = raw["delta"]?.stringValue ?? raw["output_text_delta"]?.stringValue,
                           openAIResponsesIsTextDelta(raw) {
                            let eventItemID = raw["item_id"]?.stringValue ?? "text-0"
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            if activeTextPartIDs.insert(itemID).inserted {
                                continuation.yield(.textStart(
                                    id: itemID,
                                    providerMetadata: openAIResponsesTextProviderMetadata(
                                        itemID: itemID,
                                        phase: textItemPhases[itemID],
                                        providerID: providerID
                                    )
                                ))
                            }
                            continuation.yield(.textDeltaPart(
                                id: itemID,
                                delta: delta,
                                providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: textItemPhases[itemID], providerID: providerID)
                            ))
                        }
                        if raw["type"]?.stringValue == "response.output_text.done",
                           let logprobs = raw["logprobs"] {
                            streamOutputLogprobs.append(logprobs)
                        }
                        if let delta = raw["delta"]?.stringValue,
                           raw["type"]?.stringValue == "response.reasoning_summary_text.delta" {
                            let eventItemID = raw["item_id"]?.stringValue ?? "reasoning-0"
                            let summaryIndex = raw["summary_index"]?.intValue ?? 0
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            let reasoningPartID = openResponsesProviderOptionsName == nil
                                ? "\(itemID):\(summaryIndex)"
                                : itemID
                            if activeReasoningPartIDs.insert(reasoningPartID).inserted {
                                continuation.yield(.reasoningStart(
                                    id: reasoningPartID,
                                    providerMetadata: openAIResponsesReasoningProviderMetadata(
                                        itemID: itemID,
                                        providerID: providerID
                                    )
                                ))
                            }
                            continuation.yield(.reasoningDeltaPart(
                                id: reasoningPartID,
                                delta: delta,
                                providerMetadata: openAIResponsesReasoningProviderMetadata(itemID: itemID, providerID: providerID)
                            ))
                        }
                        if raw["type"]?.stringValue == "response.output_text.annotation.added",
                           let annotation = raw["annotation"],
                           let eventItemID = raw["item_id"]?.stringValue {
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            textItemAnnotations[itemID, default: []].append(annotation)
                            for source in openAIResponsesSources(fromAnnotations: [annotation], providerID: providerID, sourceCounter: &sourceCounter) {
                                continuation.yield(.source(source))
                            }
                        }
                        if raw["type"]?.stringValue == "response.reasoning_summary_part.added",
                           let eventItemID = raw["item_id"]?.stringValue,
                           let summaryIndex = raw["summary_index"]?.intValue,
                           summaryIndex > 0 {
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            if openResponsesProviderOptionsName != nil {
                                continue
                            }
                            if var reasoning = activeReasoning[itemID] {
                                reasoning.summaryParts[summaryIndex] = .active
                                for canConcludeIndex in reasoning.summaryParts.keys.sorted()
                                    where reasoning.summaryParts[canConcludeIndex] == .canConclude {
                                    continuation.yield(.reasoningEnd(
                                        id: "\(itemID):\(canConcludeIndex)",
                                        providerMetadata: openAIResponsesReasoningProviderMetadata(itemID: itemID, providerID: providerID)
                                    ))
                                    activeReasoningPartIDs.remove("\(itemID):\(canConcludeIndex)")
                                    reasoning.summaryParts[canConcludeIndex] = .concluded
                                }
                                activeReasoning[itemID] = reasoning
                                activeReasoningPartIDs.insert("\(itemID):\(summaryIndex)")
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
                           let eventItemID = item["id"]?.stringValue {
                            let outputIndex = raw["output_index"]?.intValue
                            let itemID = resolvedOutputItemID(eventItemID, outputIndex: outputIndex)
                            let phase = item["phase"] ?? textItemPhases[itemID]
                            let annotations: [JSONValue]
                            if openResponsesProviderOptionsName != nil {
                                annotations = item["content"]?.arrayValue?.flatMap {
                                    openResponsesURLCitationAnnotations($0["annotations"])
                                } ?? []
                            } else {
                                annotations = textItemAnnotations[itemID] ?? []
                            }
                            continuation.yield(.textEnd(
                                id: itemID,
                                providerMetadata: openAIResponsesTextProviderMetadata(itemID: itemID, phase: phase, annotations: annotations, providerID: providerID)
                            ))
                            activeTextPartIDs.remove(itemID)
                            textItemAnnotations[itemID] = nil
                            if let outputIndex {
                                activeOutputItemIDs[outputIndex] = nil
                            }
                        }
                        if raw["type"]?.stringValue == "response.reasoning_summary_part.done",
                           let eventItemID = raw["item_id"]?.stringValue,
                           let summaryIndex = raw["summary_index"]?.intValue {
                            let itemID = resolvedOutputItemID(
                                eventItemID,
                                outputIndex: raw["output_index"]?.intValue
                            )
                            activeReasoning[itemID]?.summaryParts[summaryIndex] = .canConclude
                        }
                        if raw["type"]?.stringValue == "response.output_item.done",
                           let item = raw["item"],
                           item["type"]?.stringValue == "reasoning",
                           let eventItemID = item["id"]?.stringValue {
                            let outputIndex = raw["output_index"]?.intValue
                            let itemID = resolvedOutputItemID(eventItemID, outputIndex: outputIndex)
                            if let providerOptionsName = openResponsesProviderOptionsName {
                                continuation.yield(.reasoningEnd(
                                    id: itemID,
                                    providerMetadata: openResponsesReasoningProviderMetadata(
                                        item: item,
                                        providerOptionsName: providerOptionsName
                                    )
                                ))
                                activeReasoningPartIDs.remove(itemID)
                                activeReasoning[itemID] = nil
                            } else if let reasoning = activeReasoning[itemID] {
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
                                    activeReasoningPartIDs.remove("\(itemID):\(summaryIndex)")
                                }
                                activeReasoning[itemID] = nil
                            }
                            if let outputIndex {
                                activeOutputItemIDs[outputIndex] = nil
                            }
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
                            pendingCompletedResponse = raw["response"] ?? raw
                            pendingCompletedResponseType = "response.completed"
                        } else if raw["type"]?.stringValue == "response.incomplete" {
                            let response = raw["response"] ?? raw
                            pendingCompletedResponse = response
                            pendingCompletedResponseType = "response.incomplete"
                        } else if raw["type"]?.stringValue == "response.failed" {
                            let response = raw["response"] ?? raw
                            if shouldThrowPreOutputStreamErrors && !hasOutputStarted {
                                throw openAIResponsesStreamFailedError(raw, providerID: providerID)
                            }
                            if !encounteredStreamError {
                                encounteredStreamError = true
                                fallbackFinishReason = "error"
                                if let providerError = providerID == "xai.responses"
                                    ? xaiResponsesStreamProviderError(from: raw)
                                    : shouldThrowPreOutputStreamErrors
                                        ? openAIProviderStreamError(from: raw)
                                        : nil {
                                    continuation.yield(.providerError(providerError))
                                } else {
                                    continuation.yield(.error(
                                        message: response["error"]?["message"]?.stringValue
                                            ?? raw["error"]?["message"]?.stringValue
                                            ?? "Responses stream failed.",
                                        rawValue: raw
                                    ))
                                }
                            }
                            pendingCompletedResponse = response
                            pendingCompletedResponseType = "response.failed"
                        }
                    }
                    for textID in activeTextPartIDs.sorted() {
                        continuation.yield(.textEnd(id: textID))
                    }
                    for reasoningID in activeReasoningPartIDs.sorted() {
                        continuation.yield(.reasoningEnd(id: reasoningID))
                    }
                    for eventPart in toolCallBuffers.finishedParts() {
                        continuation.yield(eventPart)
                    }
                    if let response = pendingCompletedResponse {
                        let completedWasFailed = pendingCompletedResponseType == "response.failed"
                            || response["status"]?.stringValue == "failed"
                        let finishReason = completedWasFailed
                            ? response["incomplete_details"]?["reason"]?.stringValue == nil
                                ? "error"
                                : openResponsesStreamFinishReason(
                                    response: response,
                                    hasToolCalls: openResponsesHasToolCalls,
                                    mode: config.responsesRequestMode
                                )
                            : encounteredStreamError
                                ? "error"
                                : openResponsesStreamFinishReason(
                                    response: response,
                                    hasToolCalls: openResponsesHasToolCalls,
                                    mode: config.responsesRequestMode
                                )
                        let finishUsage = tokenUsage(from: response)
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
                    } else {
                        continuation.yield(.finishMetadata(
                            reason: fallbackFinishReason,
                            usage: nil,
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
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Prepares the same non-streaming Responses payload used by `generate`.
    /// Durable batch adapters use this hook so request conversion, provider
    /// options, warnings, and request-body transforms stay on one code path.
    func preparedBatchRequest(
        for request: LanguageModelRequest
    ) throws -> OpenAICompatibleResponsesPreparedRequest {
        try preparedRequest(for: request, stream: false)
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
        let stripsReasoningModelSampling = openAIResponsesStripsSamplingSettings(
            modelID: modelID,
            isReasoningModel: isEffectiveReasoningModel,
            options: options
        )
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
        let providerDefinedToolNames = Set(request.tools.compactMap { name, schema -> String? in
            let object = schema.objectValue
            guard object?["type"]?.stringValue == "provider"
                    || object?["id"]?.stringValue?.hasPrefix("openai.") == true else {
                return nil
            }
            return object?["name"]?.stringValue ?? name
        })
        let shellToolNames = Set(request.tools.compactMap { name, schema -> String? in
            let object = schema.objectValue
            guard object?["id"]?.stringValue == "openai.shell" else { return nil }
            return object?["name"]?.stringValue ?? name
        })
        let computerToolNames = Set(request.tools.compactMap { name, schema -> String? in
            let object = schema.objectValue
            guard object?["id"]?.stringValue == "openai.computer" else { return nil }
            return object?["name"]?.stringValue ?? name
        })
        let declaredToolSearchToolName = request.tools.compactMap { name, schema -> String? in
            let object = schema.objectValue
            guard object?["id"]?.stringValue == "openai.tool_search" else { return nil }
            return object?["name"]?.stringValue ?? name
        }.first
        let declaresRegularToolSearchFunction = openAIResponsesFunctionToolNames(from: request.tools)
            .contains("tool_search")
        let toolSearchToolName = declaredToolSearchToolName
            ?? (declaresRegularToolSearchFunction ? nil : "tool_search")
        let useDeveloperRoleForSystem = isEffectiveReasoningModel
        let compactionTrigger = (options.removeValue(forKey: "compactionTrigger")
            ?? options.removeValue(forKey: "compaction_trigger"))?.boolValue == true
        let preparedMessages = openAIResponsesMessagesByCollapsingParallelToolResults(
            request.messages,
            providerID: providerID,
            hasConversation: hasConversation,
            hasPreviousResponseID: hasPreviousResponseID,
            outputSchemaToolNames: preparedTools.outputSchemaToolNames,
            warnings: &warnings
        )
        var input = try preparedMessages.flatMap {
            try openAIResponsesInputMessageJSON(
                $0,
                store: store,
                hasConversation: hasConversation,
                hasPreviousResponseID: hasPreviousResponseID,
                processedApprovalIDs: &processedApprovalIDs,
                toolNamespaces: toolNamespaces,
                customToolNames: preparedTools.customToolNames,
                programmaticToolNames: preparedTools.programmaticToolNames,
                outputSchemaToolNames: preparedTools.outputSchemaToolNames,
                providerDefinedToolNames: providerDefinedToolNames,
                shellToolNames: shellToolNames,
                computerToolNames: computerToolNames,
                toolSearchToolName: toolSearchToolName,
                providerID: providerID,
                useDeveloperRoleForSystem: useDeveloperRoleForSystem,
                warnings: &warnings
            )
        }
        if compactionTrigger {
            input.append(.object(["type": .string("compaction_trigger")]))
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(input)
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
                body["tool_choice"] = try openAIResponsesAllowedToolsChoice(
                    from: allowedTools,
                    tools: request.tools,
                    warnings: &warnings
                )
            } else if let toolChoice = openAIResponsesToolChoice(
                from: request.toolChoice ?? request.extraBody["toolChoice"],
                customToolNames: preparedTools.customToolNames,
                programmaticToolNames: preparedTools.programmaticToolNames
            ) {
                body["tool_choice"] = toolChoice
            }
        }
        body.removeValue(forKey: "allowedTools")
        body.removeValue(forKey: "allowed_tools")
        return OpenAICompatibleResponsesPreparedRequest(body: config.transformRequestBody?(body) ?? body, warnings: warnings)
    }

    private func openResponsesPreparedRequest(for request: LanguageModelRequest, stream: Bool, providerOptionsName: String) throws -> OpenAICompatibleResponsesPreparedRequest {
        let preparedInput = openResponsesInput(
            from: request.messages,
            providerID: providerID,
            providerOptionsName: providerOptionsName
        )
        let providerOptions = try openResponsesProviderOptions(providerOptions: request.providerOptions, providerOptionsName: providerOptionsName)
        var warnings = openResponsesWarnings(for: request, includePenaltyWarnings: false) + preparedInput.warnings
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
        if let providerReasoningEffort = providerOptions["reasoningEffort"] {
            reasoning["effort"] = providerReasoningEffort
        } else if isCustomReasoning(request.reasoning),
           let requestedReasoning = request.reasoning,
           let effort = mapReasoningToProviderEffort(
               reasoning: requestedReasoning,
               effortMap: [
                   "none": "none",
                   "minimal": "low",
                   "low": "low",
                   "medium": "medium",
                   "high": "high",
                   "xhigh": "xhigh"
               ],
               warnings: &warnings
           ) {
            reasoning["effort"] = .string(effort)
        }
        if let summary = providerOptions["reasoningSummary"] { reasoning["summary"] = summary }
        if !reasoning.isEmpty { body["reasoning"] = .object(reasoning) }
        for (_, schema) in request.tools where schema["type"]?.stringValue == "provider" {
            let toolID = schema["id"]?.stringValue ?? "unknown"
            warnings.append(AIWarning(type: "unsupported", feature: "provider-defined tool \(toolID)"))
        }
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
            warnings: warnings
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

func openAIResponsesKnownStreamEventValidationMessage(_ raw: JSONValue) -> String? {
    guard let type = raw["type"]?.stringValue else { return nil }

    let isMissingOutputIndex = raw["output_index"]?.intValue == nil
    switch type {
    case "response.function_call_arguments.delta":
        guard raw["item_id"]?.stringValue != nil,
              !isMissingOutputIndex,
              raw["delta"]?.stringValue != nil else {
            return "Known response chunk failed schema validation"
        }
    case "response.function_call_arguments.done":
        guard raw["item_id"]?.stringValue != nil,
              !isMissingOutputIndex,
              raw["arguments"]?.stringValue != nil else {
            return "Known response chunk failed schema validation"
        }
    case "response.output_item.added", "response.output_item.done":
        guard let itemType = raw["item"]?["type"]?.stringValue else {
            return "Known response chunk failed schema validation"
        }
        // Upstream deliberately treats unmodelled future item types as unknown
        // events. Only validate the modeled function-call shape here.
        guard itemType != "function_call" || (
            !isMissingOutputIndex
                && raw["item"]?["id"]?.stringValue != nil
                && raw["item"]?["call_id"]?.stringValue != nil
                && raw["item"]?["name"]?.stringValue != nil
                && raw["item"]?["arguments"]?.stringValue != nil
        ) else {
            return "Known response chunk failed schema validation"
        }
    default:
        break
    }
    return nil
}
