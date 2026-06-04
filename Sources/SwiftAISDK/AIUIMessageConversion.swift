import Foundation

public func convertToModelMessages(_ messages: [AIUIMessage]) throws -> [AIMessage] {
    _ = try validateUIMessages(messages)
    return try messages.enumerated().map { index, message in
        try convertToModelMessage(message, path: "messages[\(index)]")
    }
}

public func convertToModelMessage(_ message: AIUIMessage) throws -> AIMessage {
    try convertToModelMessage(message, path: "message")
}

private func convertToModelMessage(_ message: AIUIMessage, path: String) throws -> AIMessage {
    var content: [AIContentPart] = []
    var reasoningParts: [String] = []

    for (partIndex, part) in message.parts.enumerated() {
        let partPath = "\(path).parts[\(partIndex)]"
        switch part {
        case let .text(text):
            if !text.text.isEmpty {
                content.append(.text(text.text))
            }
        case let .reasoning(reasoning):
            if !reasoning.text.isEmpty {
                reasoningParts.append(reasoning.text)
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
        case .source, .reasoningFile, .data, .metadata, .error, .custom, .raw:
            break
        }
    }

    return AIMessage(
        role: message.role,
        content: content,
        reasoning: reasoningParts.isEmpty ? nil : reasoningParts.joined()
    )
}

private func appendModelFile(
    _ file: AIStreamFile,
    path: String,
    content: inout [AIContentPart]
) throws {
    if let data = file.data {
        content.append(.file(mimeType: file.mediaType, data: data, filename: file.filename))
        return
    }

    if let url = file.url, file.mediaType.lowercased().hasPrefix("image/") {
        content.append(.imageURL(url))
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
