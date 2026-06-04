import Foundation

public struct AIUIMessageValidationIssue: Equatable, CustomStringConvertible, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(path): \(message)"
    }
}

public struct AIUIMessageValidationResult: Equatable, Sendable {
    public var messages: [AIUIMessage]
    public var issues: [AIUIMessageValidationIssue]

    public init(messages: [AIUIMessage], issues: [AIUIMessageValidationIssue]) {
        self.messages = messages
        self.issues = issues
    }

    public var isValid: Bool {
        issues.isEmpty
    }
}

@discardableResult
public func validateUIMessages(_ messages: [AIUIMessage]) throws -> [AIUIMessage] {
    let result = safeValidateUIMessages(messages)
    guard result.isValid else {
        throw AIUIMessageStreamError(
            message: "Invalid UI messages.",
            validationIssues: result.issues
        )
    }
    return messages
}

public func safeValidateUIMessages(_ messages: [AIUIMessage]) -> AIUIMessageValidationResult {
    var issues: [AIUIMessageValidationIssue] = []
    var messageIDs: Set<String> = []
    var toolCallIDs: Set<String> = []
    var approvalRequestIDs: Set<String> = []

    for (messageIndex, message) in messages.enumerated() {
        let messagePath = "messages[\(messageIndex)]"
        validateNonEmpty(message.id, path: "\(messagePath).id", label: "message id", issues: &issues)
        if !message.id.isEmpty && !messageIDs.insert(message.id).inserted {
            issues.append(AIUIMessageValidationIssue(path: "\(messagePath).id", message: "message id must be unique."))
        }

        for (partIndex, part) in message.parts.enumerated() {
            let partPath = "\(messagePath).parts[\(partIndex)]"
            collectPartReferences(part, path: partPath, toolCallIDs: &toolCallIDs, approvalRequestIDs: &approvalRequestIDs, issues: &issues)
        }
    }

    for (messageIndex, message) in messages.enumerated() {
        for (partIndex, part) in message.parts.enumerated() {
            let partPath = "messages[\(messageIndex)].parts[\(partIndex)]"
            validatePartLinks(part, path: partPath, toolCallIDs: toolCallIDs, approvalRequestIDs: approvalRequestIDs, issues: &issues)
        }
    }

    return AIUIMessageValidationResult(messages: messages, issues: issues)
}

private func collectPartReferences(
    _ part: AIUIMessagePart,
    path: String,
    toolCallIDs: inout Set<String>,
    approvalRequestIDs: inout Set<String>,
    issues: inout [AIUIMessageValidationIssue]
) {
    switch part {
    case let .text(text):
        validateOptionalID(text.id, path: "\(path).text.id", issues: &issues)
    case let .reasoning(reasoning):
        validateOptionalID(reasoning.id, path: "\(path).reasoning.id", issues: &issues)
    case let .source(source):
        validateNonEmpty(source.id, path: "\(path).source.id", label: "source id", issues: &issues)
    case let .file(file), let .reasoningFile(file):
        validateNonEmpty(file.mediaType, path: "\(path).file.mediaType", label: "file media type", issues: &issues)
        if let id = file.id {
            validateNonEmpty(id, path: "\(path).file.id", label: "file id", issues: &issues)
        }
    case let .toolCall(call):
        validateNonEmpty(call.id, path: "\(path).toolCall.id", label: "tool call id", issues: &issues)
        validateNonEmpty(call.name, path: "\(path).toolCall.name", label: "tool name", issues: &issues)
        validateJSONString(call.arguments, path: "\(path).toolCall.arguments", issues: &issues)
        if !call.id.isEmpty && !toolCallIDs.insert(call.id).inserted {
            issues.append(AIUIMessageValidationIssue(path: "\(path).toolCall.id", message: "tool call id must be unique."))
        }
    case let .toolResult(result):
        validateNonEmpty(result.toolCallID, path: "\(path).toolResult.toolCallID", label: "tool call id", issues: &issues)
        validateNonEmpty(result.toolName, path: "\(path).toolResult.toolName", label: "tool name", issues: &issues)
    case let .toolApprovalRequest(request):
        validateNonEmpty(request.id, path: "\(path).toolApprovalRequest.id", label: "approval request id", issues: &issues)
        validateNonEmpty(request.toolName, path: "\(path).toolApprovalRequest.toolName", label: "tool name", issues: &issues)
        validateJSONString(request.arguments, path: "\(path).toolApprovalRequest.arguments", issues: &issues)
        if let toolCallID = request.toolCallID {
            validateNonEmpty(toolCallID, path: "\(path).toolApprovalRequest.toolCallID", label: "tool call id", issues: &issues)
        }
        if !request.id.isEmpty && !approvalRequestIDs.insert(request.id).inserted {
            issues.append(AIUIMessageValidationIssue(path: "\(path).toolApprovalRequest.id", message: "approval request id must be unique."))
        }
    case let .toolApprovalResponse(response):
        validateNonEmpty(response.id, path: "\(path).toolApprovalResponse.id", label: "approval response id", issues: &issues)
    case let .data(data):
        validateOptionalID(data.id, path: "\(path).data.id", issues: &issues)
    case .metadata:
        break
    case let .error(message, _):
        validateNonEmpty(message, path: "\(path).error.message", label: "error message", issues: &issues)
    case .custom, .raw:
        break
    }
}

private func validatePartLinks(
    _ part: AIUIMessagePart,
    path: String,
    toolCallIDs: Set<String>,
    approvalRequestIDs: Set<String>,
    issues: inout [AIUIMessageValidationIssue]
) {
    switch part {
    case let .toolResult(result):
        if !result.toolCallID.isEmpty && !toolCallIDs.contains(result.toolCallID) {
            issues.append(AIUIMessageValidationIssue(path: "\(path).toolResult.toolCallID", message: "tool result must reference an existing tool call."))
        }
    case let .toolApprovalRequest(request):
        if let toolCallID = request.toolCallID, !toolCallID.isEmpty, !toolCallIDs.contains(toolCallID) {
            issues.append(AIUIMessageValidationIssue(path: "\(path).toolApprovalRequest.toolCallID", message: "approval request must reference an existing tool call."))
        }
    case let .toolApprovalResponse(response):
        if !response.id.isEmpty && !approvalRequestIDs.contains(response.id) {
            issues.append(AIUIMessageValidationIssue(path: "\(path).toolApprovalResponse.id", message: "approval response must reference an existing approval request."))
        }
    default:
        break
    }
}

private func validateNonEmpty(
    _ value: String,
    path: String,
    label: String,
    issues: inout [AIUIMessageValidationIssue]
) {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(AIUIMessageValidationIssue(path: path, message: "\(label) must not be empty."))
    }
}

private func validateOptionalID(_ value: String?, path: String, issues: inout [AIUIMessageValidationIssue]) {
    guard let value else { return }
    validateNonEmpty(value, path: path, label: "id", issues: &issues)
}

private func validateJSONString(_ value: String, path: String, issues: inout [AIUIMessageValidationIssue]) {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    do {
        _ = try secureJSONParse(value)
    } catch {
        issues.append(AIUIMessageValidationIssue(path: path, message: "must be valid JSON."))
    }
}
