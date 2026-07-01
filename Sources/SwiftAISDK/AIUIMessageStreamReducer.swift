import Foundation

public struct AIUIMessageStreamReducer: Sendable {
    public private(set) var message: AIUIMessage

    private var textPartIndexes: [String: Int] = [:]
    private var reasoningPartIndexes: [String: Int] = [:]
    private var toolCallPartIndexes: [String: Int] = [:]
    private var activeToolInputIDs: Set<String> = []
    private var fallbackToolCallIDsByIndex: [Int: String] = [:]
    private var fallbackToolCallCounter = 0

    public init(message: AIUIMessage = .assistant()) {
        self.message = message
    }

    @discardableResult
    public mutating func consume(_ part: LanguageStreamPart) throws -> AIUIMessage {
        switch part {
        case let .streamStart(warnings):
            if !warnings.isEmpty {
                message.metadata["warnings"] = .array(warnings.map(warningJSON))
            }
        case let .textStart(id, providerMetadata):
            ensureTextPart(id: id, providerMetadata: providerMetadata)
        case let .textDelta(delta):
            appendText(delta, id: nil)
        case let .textDeltaPart(id, delta, providerMetadata):
            try appendTextDeltaPart(delta, id: id, providerMetadata: providerMetadata)
        case let .textEnd(id, providerMetadata):
            try endTextPart(id: id, providerMetadata: providerMetadata)
        case let .reasoningStart(id, providerMetadata):
            ensureReasoningPart(id: id, providerMetadata: providerMetadata)
        case let .reasoningDelta(delta):
            appendReasoning(delta, id: nil)
        case let .reasoningDeltaPart(id, delta, providerMetadata):
            try appendReasoningDeltaPart(delta, id: id, providerMetadata: providerMetadata)
        case let .reasoningEnd(id, providerMetadata):
            try endReasoningPart(id: id, providerMetadata: providerMetadata)
        case let .toolInputStart(id, name, providerExecuted, dynamic, title, providerMetadata):
            ensureToolCallPart(
                id: id,
                name: name,
                providerExecuted: providerExecuted,
                dynamic: dynamic,
                title: title,
                providerMetadata: providerMetadata
            )
            activeToolInputIDs.insert(id)
        case let .toolInputDelta(id, delta, providerMetadata):
            try appendToolInputDelta(delta, id: id, providerMetadata: providerMetadata)
        case let .toolInputEnd(id, providerMetadata):
            try endToolInput(id: id, providerMetadata: providerMetadata)
        case let .toolCallDelta(id, name, argumentsDelta, index):
            appendToolCallDelta(id: id, name: name, argumentsDelta: argumentsDelta, index: index)
        case let .toolCall(call):
            upsertToolCall(call)
        case let .toolResult(result):
            message.parts.append(.toolResult(result))
        case let .toolApprovalRequest(request):
            message.parts.append(.toolApprovalRequest(request))
        case let .toolApprovalResponse(response):
            message.parts.append(.toolApprovalResponse(response))
        case let .file(file):
            message.parts.append(.file(file))
        case let .reasoningFile(file):
            message.parts.append(.reasoningFile(file))
        case let .custom(value, providerMetadata):
            message.parts.append(.custom(value, providerMetadata: providerMetadata))
        case let .source(source):
            message.parts.append(.source(source))
        case let .metadata(metadata):
            message.metadata.merge(metadata) { _, new in new }
            message.parts.append(.metadata(metadata))
        case let .responseMetadata(metadata):
            message.metadata["response"] = responseMetadataJSON(metadata)
        case let .raw(value):
            message.parts.append(.raw(value))
        case let .error(errorMessage, rawValue):
            message.parts.append(.error(message: errorMessage, rawValue: rawValue))
        case let .finish(reason, usage):
            recordFinish(reason: reason, usage: usage, providerMetadata: [:])
        case let .finishMetadata(reason, usage, providerMetadata):
            recordFinish(reason: reason, usage: usage, providerMetadata: providerMetadata)
        }

        return message
    }

    @discardableResult
    public mutating func consume<S: Sequence>(contentsOf parts: S) throws -> AIUIMessage where S.Element == LanguageStreamPart {
        for part in parts {
            try consume(part)
        }
        return message
    }

    public static func snapshots(
        from stream: AsyncThrowingStream<LanguageStreamPart, Error>,
        messageID: String = UUID().uuidString,
        terminateOnError: Bool = false
    ) -> AsyncThrowingStream<AIUIMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var reducer = AIUIMessageStreamReducer(message: .assistant(id: messageID))
                do {
                    for try await part in stream {
                        try Task.checkCancellation()
                        if terminateOnError, case let .error(message, _) = part {
                            throw AIUIMessageStreamError(message: message, chunkType: "error")
                        }
                        continuation.yield(try reducer.consume(part))
                    }
                    continuation.finish()
                } catch let error as AIUIMessageStreamError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIUIMessageStreamError(message: String(describing: error)))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private mutating func ensureTextPart(
        id: String?,
        providerMetadata: [String: JSONValue] = [:],
        state: AIUIStreamingPartState? = .streaming
    ) {
        let key = id ?? "$default"
        if let index = textPartIndexes[key], case let .text(part) = message.parts[index] {
            message.parts[index] = .text(AIUITextPart(
                id: part.id,
                text: part.text,
                state: part.state ?? state,
                providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
            ))
            return
        }
        textPartIndexes[key] = message.parts.count
        message.parts.append(.text(AIUITextPart(id: id, text: "", state: state, providerMetadata: providerMetadata)))
    }

    private mutating func appendText(_ delta: String, id: String?, providerMetadata: [String: JSONValue] = [:]) {
        ensureTextPart(id: id, providerMetadata: providerMetadata, state: id == nil ? nil : .streaming)
        let key = id ?? "$default"
        guard let index = textPartIndexes[key], case let .text(part) = message.parts[index] else { return }
        message.parts[index] = .text(AIUITextPart(
            id: part.id,
            text: part.text + delta,
            state: part.state,
            providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
        ))
    }

    private mutating func appendTextDeltaPart(
        _ delta: String,
        id: String,
        providerMetadata: [String: JSONValue]
    ) throws {
        guard textPartIndexes[id] != nil else {
            throw missingStartError(chunkType: "text-delta", chunkID: id, startChunkType: "text-start")
        }
        appendText(delta, id: id, providerMetadata: providerMetadata)
    }

    private mutating func endTextPart(id: String, providerMetadata: [String: JSONValue]) throws {
        guard let index = textPartIndexes[id], case let .text(part) = message.parts[index] else {
            throw missingStartError(chunkType: "text-end", chunkID: id, startChunkType: "text-start")
        }
        message.parts[index] = .text(AIUITextPart(
            id: part.id,
            text: part.text,
            state: .done,
            providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
        ))
        textPartIndexes.removeValue(forKey: id)
    }

    private mutating func ensureReasoningPart(
        id: String?,
        providerMetadata: [String: JSONValue] = [:],
        state: AIUIStreamingPartState? = .streaming
    ) {
        let key = id ?? "$default"
        if let index = reasoningPartIndexes[key], case let .reasoning(part) = message.parts[index] {
            message.parts[index] = .reasoning(AIUIReasoningPart(
                id: part.id,
                text: part.text,
                state: part.state ?? state,
                providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
            ))
            return
        }
        reasoningPartIndexes[key] = message.parts.count
        message.parts.append(.reasoning(AIUIReasoningPart(id: id, text: "", state: state, providerMetadata: providerMetadata)))
    }

    private mutating func appendReasoning(_ delta: String, id: String?, providerMetadata: [String: JSONValue] = [:]) {
        ensureReasoningPart(id: id, providerMetadata: providerMetadata, state: id == nil ? nil : .streaming)
        let key = id ?? "$default"
        guard let index = reasoningPartIndexes[key], case let .reasoning(part) = message.parts[index] else { return }
        message.parts[index] = .reasoning(AIUIReasoningPart(
            id: part.id,
            text: part.text + delta,
            state: part.state,
            providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
        ))
    }

    private mutating func appendReasoningDeltaPart(
        _ delta: String,
        id: String,
        providerMetadata: [String: JSONValue]
    ) throws {
        guard reasoningPartIndexes[id] != nil else {
            throw missingStartError(chunkType: "reasoning-delta", chunkID: id, startChunkType: "reasoning-start")
        }
        appendReasoning(delta, id: id, providerMetadata: providerMetadata)
    }

    private mutating func endReasoningPart(id: String, providerMetadata: [String: JSONValue]) throws {
        guard let index = reasoningPartIndexes[id], case let .reasoning(part) = message.parts[index] else {
            throw missingStartError(chunkType: "reasoning-end", chunkID: id, startChunkType: "reasoning-start")
        }
        message.parts[index] = .reasoning(AIUIReasoningPart(
            id: part.id,
            text: part.text,
            state: .done,
            providerMetadata: part.providerMetadata.merging(providerMetadata) { _, new in new }
        ))
        reasoningPartIndexes.removeValue(forKey: id)
    }

    private mutating func ensureToolCallPart(
        id: String,
        name: String,
        providerExecuted: Bool = false,
        dynamic: Bool = false,
        title: String? = nil,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        if let index = toolCallPartIndexes[id], case let .toolCall(call) = message.parts[index] {
            message.parts[index] = .toolCall(AIToolCall(
                id: call.id,
                name: call.name.isEmpty ? name : call.name,
                arguments: call.arguments,
                providerExecuted: call.providerExecuted || providerExecuted,
                dynamic: call.dynamic || dynamic,
                title: call.title ?? title,
                providerMetadata: call.providerMetadata.merging(providerMetadata) { _, new in new },
                rawValue: call.rawValue
            ))
            return
        }
        toolCallPartIndexes[id] = message.parts.count
        message.parts.append(.toolCall(AIToolCall(
            id: id,
            name: name,
            arguments: "",
            providerExecuted: providerExecuted,
            dynamic: dynamic,
            title: title,
            providerMetadata: providerMetadata
        )))
    }

    private mutating func appendToolArguments(_ delta: String, id: String, providerMetadata: [String: JSONValue] = [:]) {
        ensureToolCallPart(id: id, name: "", providerMetadata: providerMetadata)
        guard let index = toolCallPartIndexes[id], case let .toolCall(call) = message.parts[index] else { return }
        message.parts[index] = .toolCall(AIToolCall(
            id: call.id,
            name: call.name,
            arguments: call.arguments + delta,
            providerExecuted: call.providerExecuted,
            dynamic: call.dynamic,
            title: call.title,
            providerMetadata: call.providerMetadata.merging(providerMetadata) { _, new in new },
            rawValue: call.rawValue
        ))
    }

    private mutating func mergeToolMetadata(id: String, providerMetadata: [String: JSONValue]) {
        ensureToolCallPart(id: id, name: "", providerMetadata: providerMetadata)
    }

    private mutating func appendToolInputDelta(
        _ delta: String,
        id: String,
        providerMetadata: [String: JSONValue]
    ) throws {
        guard activeToolInputIDs.contains(id) else {
            throw missingStartError(chunkType: "tool-input-delta", chunkID: id, startChunkType: "tool-input-start")
        }
        appendToolArguments(delta, id: id, providerMetadata: providerMetadata)
    }

    private mutating func endToolInput(id: String, providerMetadata: [String: JSONValue]) throws {
        guard activeToolInputIDs.contains(id) else {
            throw missingStartError(chunkType: "tool-input-end", chunkID: id, startChunkType: "tool-input-start")
        }
        mergeToolMetadata(id: id, providerMetadata: providerMetadata)
        activeToolInputIDs.remove(id)
    }

    private mutating func appendToolCallDelta(id: String?, name: String?, argumentsDelta: String, index: Int?) {
        let toolID = id ?? fallbackToolCallID(index: index)
        ensureToolCallPart(id: toolID, name: name ?? "")
        appendToolArguments(argumentsDelta, id: toolID)
    }

    private mutating func upsertToolCall(_ call: AIToolCall) {
        if let index = toolCallPartIndexes[call.id] {
            message.parts[index] = .toolCall(call)
        } else {
            toolCallPartIndexes[call.id] = message.parts.count
            message.parts.append(.toolCall(call))
        }
    }

    private mutating func fallbackToolCallID(index: Int?) -> String {
        if let index {
            if let id = fallbackToolCallIDsByIndex[index] {
                return id
            }
            let id = "tool-call-\(index)"
            fallbackToolCallIDsByIndex[index] = id
            return id
        }
        let id = "tool-call-\(fallbackToolCallCounter)"
        fallbackToolCallCounter += 1
        return id
    }

    private mutating func recordFinish(reason: String?, usage: TokenUsage?, providerMetadata: [String: JSONValue]) {
        message.metadata["finishReason"] = reason.map(JSONValue.string)
        message.metadata["usage"] = usage.map(aiUIMessageTokenUsageJSON)
        if !providerMetadata.isEmpty {
            message.metadata["providerMetadata"] = .object(providerMetadata)
        }
    }

    private func missingStartError(chunkType: String, chunkID: String, startChunkType: String) -> AIUIMessageStreamError {
        AIUIMessageStreamError(
            message: "Received \(chunkType) for missing stream part with ID \"\(chunkID)\". Ensure a \"\(startChunkType)\" chunk is sent before any \"\(chunkType)\" chunks.",
            chunkType: chunkType,
            chunkID: chunkID
        )
    }
}

private func warningJSON(_ warning: AIWarning) -> JSONValue {
    aiWarningJSON(warning)
}

private func responseMetadataJSON(_ metadata: AIResponseMetadata) -> JSONValue {
    .object([
        "id": metadata.id.map(JSONValue.string),
        "timestamp": metadata.timestamp.map { .string(iso8601String($0)) },
        "modelID": metadata.modelID.map(JSONValue.string),
        "headers": metadata.headers.isEmpty ? nil : .object(metadata.headers.mapValues(JSONValue.string)),
        "body": metadata.body
    ])
}

private func aiUIMessageTokenUsageJSON(_ usage: TokenUsage) -> JSONValue {
    .object([
        "inputTokens": usage.inputTokens.map(jsonNumber),
        "outputTokens": usage.outputTokens.map(jsonNumber),
        "totalTokens": usage.totalTokens.map(jsonNumber),
        "inputTokensNoCache": usage.inputTokensNoCache.map(jsonNumber),
        "inputTokensCacheRead": usage.inputTokensCacheRead.map(jsonNumber),
        "inputTokensCacheWrite": usage.inputTokensCacheWrite.map(jsonNumber),
        "outputTextTokens": usage.outputTextTokens.map(jsonNumber),
        "outputReasoningTokens": usage.outputReasoningTokens.map(jsonNumber),
        "rawValue": usage.rawValue
    ])
}

private func jsonNumber(_ value: Int) -> JSONValue {
    .number(Double(value))
}

private func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
