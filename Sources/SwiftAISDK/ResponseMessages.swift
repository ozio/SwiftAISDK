import Foundation

public func toResponseMessages(
    content: [AIContentPart],
    toolsByName: [String: AITool] = [:]
) async throws -> [AIMessage] {
    var assistantParts: [AIContentPart] = []
    var toolParts: [AIContentPart] = []
    var toolCallsByID: [String: AIToolCall] = [:]
    var approvalRequestsByID: [String: AIToolApprovalRequest] = [:]
    let explicitToolResultIDs = Set(content.compactMap { part -> String? in
        if case let .toolResult(result) = part {
            return result.toolCallID
        }
        return nil
    })

    for part in content {
        switch part {
        case let .text(text, _) where text.isEmpty:
            continue
        case let .reasoning(text, _) where text.isEmpty:
            continue
        case let .toolCall(call):
            toolCallsByID[call.id] = call
            assistantParts.append(.toolCall(sanitizedToolCall(call)))
        case let .toolApprovalRequest(request):
            approvalRequestsByID[request.id] = request
            assistantParts.append(part)
        case let .toolApprovalResponse(response):
            toolParts.append(part)
            if !response.approved,
               let request = approvalRequestsByID[response.id],
               let toolCallID = request.toolCallID,
               !explicitToolResultIDs.contains(toolCallID) {
                toolParts.append(.toolResult(AIToolResult(
                    toolCallID: toolCallID,
                    toolName: request.toolName,
                    result: executionDeniedResult(reason: response.reason),
                    providerMetadata: response.providerMetadata
                )))
            }
        case let .toolResult(result):
            let providerExecuted = result.providerExecuted || (toolCallsByID[result.toolCallID]?.providerExecuted ?? false)
            let messagePart = try await responseToolResultPart(
                result,
                toolCall: toolCallsByID[result.toolCallID],
                toolsByName: toolsByName
            )
            if providerExecuted {
                assistantParts.append(messagePart)
            } else {
                toolParts.append(messagePart)
            }
        default:
            assistantParts.append(part)
        }
    }

    var messages: [AIMessage] = []
    if !assistantParts.isEmpty {
        messages.append(AIMessage(role: .assistant, content: assistantParts))
    }
    if !toolParts.isEmpty {
        messages.append(AIMessage(role: .tool, content: toolParts))
    }
    return messages
}

private func sanitizedToolCall(_ call: AIToolCall) -> AIToolCall {
    guard let input = try? toolArguments(from: call),
          case .object = input else {
        var sanitized = call
        sanitized.arguments = "{}"
        return sanitized
    }
    return call
}

private func responseToolResultPart(
    _ result: AIToolResult,
    toolCall: AIToolCall?,
    toolsByName: [String: AITool]
) async throws -> AIContentPart {
    guard result.modelOutput == nil,
          let tool = toolsByName[result.toolName] else {
        return .toolResult(result)
    }
    let input: JSONValue
    if let toolCall {
        input = (try? toolArguments(from: toolCall)) ?? .object([:])
    } else {
        input = .object([:])
    }
    var converted = result
    converted.modelOutput = try await tool.toModelOutput?(AIToolModelOutputContext(
        toolCallID: result.toolCallID,
        input: input,
        output: result.result
    ))
    return .toolResult(converted)
}
