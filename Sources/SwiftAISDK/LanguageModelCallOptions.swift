import Foundation

func prepareLanguageModelCallOptions(_ request: LanguageModelRequest) throws -> LanguageModelRequest {
    if let maxOutputTokens = request.maxOutputTokens, maxOutputTokens < 1 {
        throw AIError.invalidArgument(argument: "maxOutputTokens", message: "maxOutputTokens must be >= 1")
    }
    var prepared = request
    prepared.messages = try convertToLanguageModelPrompt(StandardizedPrompt(messages: request.messages))
    return prepared
}

func validateToolResultAvailability(
    in messages: [AIMessage],
    preapprovedToolCallIDs: Set<String> = []
) throws {
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

    var approvedToolCallIDs = preapprovedToolCallIDs
    for message in messages where message.role == .tool {
        for part in message.content {
            guard case let .toolApprovalResponse(response) = part,
                  let toolCallID = approvalIDToToolCallID[response.id] else {
                continue
            }
            approvedToolCallIDs.insert(toolCallID)
        }
    }

    var missingToolCallIDs: [String] = []
    var pendingToolCallIDs: Set<String> = []

    func closeApprovedToolCalls() {
        guard !approvedToolCallIDs.isEmpty else { return }
        missingToolCallIDs.removeAll { approvedToolCallIDs.contains($0) }
        pendingToolCallIDs.subtract(approvedToolCallIDs)
    }

    for message in messages {
        switch message.role {
        case .assistant:
            for part in message.content {
                guard case let .toolCall(call) = part, !call.providerExecuted else { continue }
                if pendingToolCallIDs.insert(call.id).inserted {
                    missingToolCallIDs.append(call.id)
                }
            }
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                missingToolCallIDs.removeAll { $0 == result.toolCallID }
                pendingToolCallIDs.remove(result.toolCallID)
            }
        case .user, .system:
            closeApprovedToolCalls()
            if !missingToolCallIDs.isEmpty {
                throw AIMissingToolResultsError(toolCallIDs: missingToolCallIDs)
            }
        }
    }

    closeApprovedToolCalls()
    if !missingToolCallIDs.isEmpty {
        throw AIMissingToolResultsError(toolCallIDs: missingToolCallIDs)
    }
}
