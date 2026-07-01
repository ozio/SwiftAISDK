import Foundation

public func convertToModelMessages(_ messages: [AIUIMessage]) throws -> [AIMessage] {
    _ = try validateUIMessages(messages)
    return try messages.enumerated().flatMap { index, message in
        let modelMessage = try convertToModelMessage(message, path: "messages[\(index)]")
        return splitAssistantResponseMessages(modelMessage)
    }
}

public func convertToModelMessage(_ message: AIUIMessage) throws -> AIMessage {
    try convertToModelMessage(message, path: "message")
}

private func convertToModelMessage(_ message: AIUIMessage, path: String) throws -> AIMessage {
    var content: [AIContentPart] = []
    var providerMetadata: [String: JSONValue] = [:]
    var systemText = ""

    for (partIndex, part) in message.parts.enumerated() {
        let partPath = "\(path).parts[\(partIndex)]"
        switch part {
        case let .text(text):
            if message.role == .system {
                systemText += text.text
                providerMetadata.merge(text.providerMetadata) { _, new in new }
            } else if !text.text.isEmpty {
                content.append(.text(text.text, providerMetadata: text.providerMetadata))
            }
        case let .reasoning(reasoning):
            if !reasoning.text.isEmpty {
                content.append(.reasoning(reasoning.text, providerMetadata: reasoning.providerMetadata))
            }
        case let .file(file):
            try appendModelFile(file, path: partPath, content: &content)
        case let .toolCall(call):
            content.append(.toolCall(call))
        case let .toolResult(result):
            content.append(.toolResult(result))
        case let .toolApprovalRequest(request):
            content.append(.toolApprovalRequest(request))
        case let .toolApprovalResponse(response):
            content.append(.toolApprovalResponse(response))
        case let .custom(value, providerMetadata):
            content.append(.custom(value, providerMetadata: providerMetadata))
        case .source, .reasoningFile, .data, .metadata, .error, .raw:
            break
        }
    }

    if message.role == .system, !systemText.isEmpty {
        content.insert(.text(systemText), at: 0)
    }

    return AIMessage(
        role: message.role,
        content: content,
        providerMetadata: providerMetadata
    )
}

private func splitAssistantResponseMessages(_ message: AIMessage) -> [AIMessage] {
    guard message.role == .assistant else {
        return [message]
    }

    var assistantParts: [AIContentPart] = []
    var toolParts: [AIContentPart] = []
    var toolCallsByID: [String: AIToolCall] = [:]
    var approvalRequestsByID: [String: AIToolApprovalRequest] = [:]
    let explicitToolResultIDs = Set(message.content.compactMap { part -> String? in
        if case let .toolResult(result) = part {
            return result.toolCallID
        }
        return nil
    })

    for part in message.content {
        switch part {
        case let .toolCall(call):
            toolCallsByID[call.id] = call
            assistantParts.append(part)
        case let .toolApprovalRequest(request):
            approvalRequestsByID[request.id] = request
            assistantParts.append(part)
        case let .toolApprovalResponse(response):
            toolParts.append(.toolApprovalResponse(response))
            if !response.approved,
               let request = approvalRequestsByID[response.id],
               let toolCallID = request.toolCallID,
               !explicitToolResultIDs.contains(toolCallID) {
                toolParts.append(.toolResult(AIToolResult(
                    toolCallID: toolCallID,
                    toolName: request.toolName,
                    result: executionDeniedResult(reason: response.reason),
                    providerExecuted: response.providerExecuted,
                    providerMetadata: response.providerMetadata
                )))
            }
        case let .toolResult(result):
            let providerExecuted = result.providerExecuted || (toolCallsByID[result.toolCallID]?.providerExecuted ?? false)
            if providerExecuted {
                assistantParts.append(.toolResult(result))
            } else {
                toolParts.append(.toolResult(result))
            }
        default:
            assistantParts.append(part)
        }
    }

    var messages: [AIMessage] = []
    if !assistantParts.isEmpty {
        messages.append(AIMessage(
            role: .assistant,
            content: assistantParts,
            providerMetadata: message.providerMetadata
        ))
    }
    if !toolParts.isEmpty {
        messages.append(AIMessage(role: .tool, content: toolParts))
    }
    return messages
}

private func appendModelFile(
    _ file: AIStreamFile,
    path: String,
    content: inout [AIContentPart]
) throws {
    if let providerReference = file.providerReference {
        content.append(.providerReference(
            mimeType: file.mediaType,
            reference: providerReference,
            filename: file.filename,
            providerMetadata: file.providerMetadata
        ))
        return
    }

    if let data = file.data {
        content.append(.file(
            mimeType: file.mediaType,
            data: data,
            filename: file.filename,
            providerMetadata: file.providerMetadata
        ))
        return
    }

    if let url = file.url, file.mediaType.lowercased().hasPrefix("image/") {
        content.append(.imageURL(url, providerMetadata: file.providerMetadata))
        return
    }

    if file.url != nil {
        throw unsupportedModelConversionPart(
            path: "\(path).file",
            message: "URL files can only be converted to model messages when mediaType starts with image/."
        )
    }

    throw unsupportedModelConversionPart(
        path: "\(path).file",
        message: "file parts need inline data or an image URL to be converted to model messages."
    )
}

private func unsupportedModelConversionPart(path: String, message: String) -> AIUIMessageStreamError {
    AIUIMessageStreamError(
        message: "Cannot convert UI messages to model messages.",
        validationIssues: [AIUIMessageValidationIssue(path: path, message: message)]
    )
}
