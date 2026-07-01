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
        combinedMessages[combinedMessages.count - 1].content.append(contentsOf: message.content)
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
