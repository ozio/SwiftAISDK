import Foundation

func convertToLanguageModelPrompt(_ prompt: StandardizedPrompt) throws -> [AIMessage] {
    let approvedToolCallIDs = approvedToolCallIDs(from: prompt.messages)
    let messages = (prompt.instructions ?? []) + prompt.messages.map(convertToLanguageModelMessage)
    var combinedMessages: [AIMessage] = []

    for message in messages {
        guard message.role == .tool, combinedMessages.last?.role == .tool else {
            combinedMessages.append(message)
            continue
        }
        let previousIndex = combinedMessages.count - 1
        if let contentIndex = combinedMessages[previousIndex].content.indices.last,
           !combinedMessages[previousIndex].providerMetadata.isEmpty {
            combinedMessages[previousIndex].content[contentIndex] = mergingToolPartProviderMetadata(
                combinedMessages[previousIndex].providerMetadata,
                into: combinedMessages[previousIndex].content[contentIndex]
            )
        }
        combinedMessages[previousIndex].content.append(contentsOf: message.content)
        combinedMessages[previousIndex].providerMetadata = message.providerMetadata
    }

    let filteredMessages = combinedMessages.filter { message in
        message.role != .tool || !message.content.isEmpty
    }
    try validateToolResultAvailability(in: filteredMessages, preapprovedToolCallIDs: approvedToolCallIDs)
    return filteredMessages
}

private func approvedToolCallIDs(from messages: [AIMessage]) -> Set<String> {
    var approvalIDToToolCallID: [String: String] = [:]
    for message in messages where message.role == .assistant {
        for part in message.content {
            guard case let .toolApprovalRequest(request) = part,
                  let toolCallID = request.toolCallID,
                  !request.id.isEmpty,
                  !toolCallID.isEmpty else {
                continue
            }
            approvalIDToToolCallID[request.id] = toolCallID
        }
    }

    var approvedToolCallIDs: Set<String> = []
    for message in messages where message.role == .tool {
        for part in message.content {
            guard case let .toolApprovalResponse(response) = part,
                  let toolCallID = approvalIDToToolCallID[response.id] else {
                continue
            }
            approvedToolCallIDs.insert(toolCallID)
        }
    }
    return approvedToolCallIDs
}

func convertToLanguageModelMessage(_ message: AIMessage) -> AIMessage {
    var converted = message

    switch message.role {
    case .system:
        return message
    case .user:
        converted.content = message.content.filter { part in
            if case let .text(text, providerMetadata) = part {
                return !text.isEmpty || !providerMetadata.isEmpty
            }
            return true
        }
    case .assistant:
        converted.content = message.content.filter { part in
            switch part {
            case let .text(text, providerMetadata):
                return !text.isEmpty || !providerMetadata.isEmpty
            case .toolApprovalRequest:
                return false
            default:
                return true
            }
        }
    case .tool:
        converted.content = message.content.filter { part in
            switch part {
            case .toolResult:
                return true
            case let .toolApprovalResponse(response):
                return response.providerExecuted
            default:
                return false
            }
        }
    }

    return converted
}

private func mergingToolPartProviderMetadata(
    _ messageMetadata: [String: JSONValue],
    into part: AIContentPart
) -> AIContentPart {
    let merged = deepMergeProviderMetadata(messageMetadata, part.providerMetadata)
    switch part {
    case let .toolResult(value):
        var result = value
        result.providerMetadata = merged
        return .toolResult(result)
    case let .toolApprovalResponse(value):
        var response = value
        response.providerMetadata = merged
        return .toolApprovalResponse(response)
    default:
        return part
    }
}

private func deepMergeProviderMetadata(
    _ base: [String: JSONValue],
    _ overrides: [String: JSONValue]
) -> [String: JSONValue] {
    var merged = base
    for (key, override) in overrides {
        if case let .object(baseObject) = merged[key],
           case let .object(overrideObject) = override {
            merged[key] = .object(deepMergeProviderMetadata(baseObject, overrideObject))
        } else {
            merged[key] = override
        }
    }
    return merged
}
