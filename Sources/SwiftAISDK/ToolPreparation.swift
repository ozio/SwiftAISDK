import Foundation
import CryptoKit

private let functionToolMetadataKeys: Set<String> = [
    "description",
    "inputExamples",
    "providerOptions",
    "strict"
]

func prepareTools(
    tools: [String: JSONValue]?,
    toolOrder: [String]? = nil
) -> [JSONValue]? {
    guard let tools, !tools.isEmpty else { return nil }

    return orderedToolEntries(tools: tools, toolOrder: toolOrder).map { name, tool in
        let object = tool.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            return .object([
                "type": .string("provider"),
                "name": .string(name),
                "id": object?["id"] ?? .string(name),
                "args": object?["args"] ?? .object([:])
            ])
        }

        var output: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "inputSchema": inputSchemaWithoutToolMetadata(tool)
        ]
        if let description = object?["description"] {
            output["description"] = description
        }
        if let inputExamples = object?["inputExamples"] {
            output["inputExamples"] = inputExamples
        }
        if let providerOptions = object?["providerOptions"] {
            output["providerOptions"] = providerOptions
        }
        if let strict = object?["strict"] {
            output["strict"] = strict
        }
        return .object(output)
    }
}

func filterActiveTools(
    tools: [String: JSONValue]?,
    activeTools: [String]?
) -> [String: JSONValue]? {
    guard let tools else { return nil }
    guard let activeTools else { return tools }

    return tools.filter { name, _ in activeTools.contains(name) }
}

func signToolApproval(
    secret: String,
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> String {
    signToolApproval(
        secret: Data(secret.utf8),
        approvalID: approvalID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input
    )
}

func signToolApproval(
    secret: Data,
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> String {
    let payload = toolApprovalSigningPayload(
        approvalID: approvalID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input
    )
    let signature = HMAC<SHA256>.authenticationCode(
        for: Data(payload.utf8),
        using: SymmetricKey(data: secret)
    )
    return toolApprovalBase64URL(Data(signature))
}

func verifyToolApprovalSignature(
    secret: String,
    signature: String,
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> Bool {
    verifyToolApprovalSignature(
        secret: Data(secret.utf8),
        signature: signature,
        approvalID: approvalID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input
    )
}

func verifyToolApprovalSignature(
    secret: Data,
    signature: String,
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> Bool {
    guard let signatureBytes = toolApprovalBase64URLData(signature) else { return false }
    let payload = toolApprovalSigningPayload(
        approvalID: approvalID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input
    )
    return HMAC<SHA256>.isValidAuthenticationCode(
        signatureBytes,
        authenticating: Data(payload.utf8),
        using: SymmetricKey(data: secret)
    )
}

func maybeSignApproval(
    secret: String?,
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> String? {
    guard let secret else { return nil }
    return signToolApproval(
        secret: secret,
        approvalID: approvalID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input
    )
}

func validateToolContext(
    toolName: String,
    context: JSONValue,
    contextSchema: JSONValue?
) throws -> JSONValue {
    guard let contextSchema else { return context }

    do {
        try AIJSONSchemaValidator.validate(context, schema: contextSchema)
        return context
    } catch let error as AITypeValidationError {
        throw AITypeValidationError(
            value: error.value,
            schema: error.schema,
            path: error.path,
            message: error.message,
            context: AITypeValidationContext(field: "tool context", entityName: toolName)
        )
    }
}

struct AICollectedToolApproval: Equatable, Sendable {
    var approvalRequest: AIToolApprovalRequest
    var approvalResponse: AIToolApprovalResponse
    var toolCall: AIToolCall
}

struct AICollectedToolApprovals: Equatable, Sendable {
    var approvedToolApprovals: [AICollectedToolApproval]
    var deniedToolApprovals: [AICollectedToolApproval]

    static var empty: AICollectedToolApprovals {
        AICollectedToolApprovals(approvedToolApprovals: [], deniedToolApprovals: [])
    }
}

func collectToolApprovals(messages: [AIMessage]) throws -> AICollectedToolApprovals {
    guard let lastMessage = messages.last, lastMessage.role == .tool else {
        return .empty
    }

    var toolCallsByID: [String: AIToolCall] = [:]
    var approvalRequestsByID: [String: AIToolApprovalRequest] = [:]
    for message in messages where message.role == .assistant {
        for part in message.content {
            switch part {
            case let .toolCall(toolCall):
                toolCallsByID[toolCall.id] = toolCall
            case let .toolApprovalRequest(request):
                approvalRequestsByID[request.id] = request
            case .text, .reasoning, .reasoningFile, .custom, .imageURL, .data, .file, .providerReference, .toolResult, .toolApprovalResponse:
                break
            }
        }
    }

    var toolResultsByToolCallID: [String: AIToolResult] = [:]
    for part in lastMessage.content {
        if case let .toolResult(result) = part {
            toolResultsByToolCallID[result.toolCallID] = result
        }
    }

    var approvedToolApprovals: [AICollectedToolApproval] = []
    var deniedToolApprovals: [AICollectedToolApproval] = []
    for part in lastMessage.content {
        guard case let .toolApprovalResponse(response) = part else { continue }
        guard let request = approvalRequestsByID[response.id] else {
            throw AIInvalidToolApprovalError(approvalID: response.id)
        }
        guard let toolCallID = request.toolCallID,
              let toolCall = toolCallsByID[toolCallID] else {
            throw AIToolCallNotFoundForApprovalError(
                toolCallID: request.toolCallID ?? "",
                approvalID: request.id
            )
        }
        if toolResultsByToolCallID[toolCallID] != nil {
            continue
        }

        let approval = AICollectedToolApproval(
            approvalRequest: request,
            approvalResponse: response,
            toolCall: toolCall
        )
        if response.approved {
            approvedToolApprovals.append(approval)
        } else {
            deniedToolApprovals.append(approval)
        }
    }

    return AICollectedToolApprovals(
        approvedToolApprovals: approvedToolApprovals,
        deniedToolApprovals: deniedToolApprovals
    )
}

func validateApprovedToolApprovals(
    approvedToolApprovals: [AICollectedToolApproval],
    toolsByName: [String: AITool],
    request: LanguageModelRequest,
    toolApproval: AIToolApproval?,
    toolApprovalSecret: String? = nil
) async throws -> AICollectedToolApprovals {
    var approved: [AICollectedToolApproval] = []
    var denied: [AICollectedToolApproval] = []

    for approval in approvedToolApprovals {
        let toolCall = approval.toolCall
        guard let tool = toolsByName[toolCall.name] else {
            throw AINoSuchToolError(toolName: toolCall.name, availableToolNames: Array(toolsByName.keys))
        }
        let arguments = try toolArguments(from: toolCall)

        if let toolApprovalSecret {
            let signature = approval.approvalRequest.providerMetadata["signature"]?.stringValue
            guard let signature else {
                throw AIInvalidToolApprovalSignatureError(
                    approvalID: approval.approvalRequest.id,
                    toolCallID: toolCall.id,
                    reason: "missing signature"
                )
            }

            let valid = verifyToolApprovalSignature(
                secret: toolApprovalSecret,
                signature: signature,
                approvalID: approval.approvalRequest.id,
                toolCallID: toolCall.id,
                toolName: toolCall.name,
                input: arguments
            )
            guard valid else {
                throw AIInvalidToolApprovalSignatureError(
                    approvalID: approval.approvalRequest.id,
                    toolCallID: toolCall.id,
                    reason: "invalid signature"
                )
            }
        }

        try validateToolArguments(arguments, schema: tool.parameters, call: toolCall)

        let approvalStatus = try await resolveToolApproval(
            toolsByName: toolsByName,
            toolCall: toolCall,
            arguments: arguments,
            request: request,
            toolApproval: toolApproval
        )

        if case let .denied(reason) = approvalStatus {
            var deniedApproval = approval
            deniedApproval.approvalResponse.approved = false
            deniedApproval.approvalResponse.reason = reason ?? deniedApproval.approvalResponse.reason
            denied.append(deniedApproval)
        } else {
            approved.append(approval)
        }
    }

    return AICollectedToolApprovals(
        approvedToolApprovals: approved,
        deniedToolApprovals: denied
    )
}

private func toolApprovalSigningPayload(
    approvalID: String,
    toolCallID: String,
    toolName: String,
    input: JSONValue
) -> String {
    let inputDigest = toolApprovalBase64URL(Data(SHA256.hash(data: Data(toolApprovalCanonicalJSON(input).utf8))))
    return "\(approvalID)\n\(toolCallID)\n\(toolName)\n\(inputDigest)"
}

private func toolApprovalCanonicalJSON(_ value: JSONValue) -> String {
    switch value {
    case let .string(string):
        return toolApprovalJSONStringLiteral(string)
    case let .number(number):
        return number.rounded() == number ? String(Int(number)) : String(number)
    case let .bool(bool):
        return bool ? "true" : "false"
    case let .array(array):
        return "[\(array.map(toolApprovalCanonicalJSON).joined(separator: ","))]"
    case let .object(object):
        let entries = object.keys.sorted().map { key in
            "\(toolApprovalJSONStringLiteral(key)):\(toolApprovalCanonicalJSON(object[key] ?? .null))"
        }
        return "{\(entries.joined(separator: ","))}"
    case .null:
        return "null"
    }
}

private func toolApprovalJSONStringLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "\"\(value)\""
    }
    return string.replacingOccurrences(of: "\\/", with: "/")
}

private func toolApprovalBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func toolApprovalBase64URLData(_ string: String) -> Data? {
    var base64 = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: padding))
    return Data(base64Encoded: base64)
}

private func orderedToolEntries(
    tools: [String: JSONValue],
    toolOrder: [String]?
) -> [(String, JSONValue)] {
    guard let toolOrder else {
        return tools.map { ($0.key, $0.value) }
    }

    let ordered = tools
        .filter { name, _ in toolOrder.contains(name) }
        .sorted { lhs, rhs in
            (toolOrder.firstIndex(of: lhs.key) ?? Int.max) < (toolOrder.firstIndex(of: rhs.key) ?? Int.max)
        }
        .map { ($0.key, $0.value) }

    let unordered = tools
        .filter { name, _ in !toolOrder.contains(name) }
        .sorted { lhs, rhs in lhs.key < rhs.key }
        .map { ($0.key, $0.value) }

    return ordered + unordered
}

private func inputSchemaWithoutToolMetadata(_ tool: JSONValue) -> JSONValue {
    guard var object = tool.objectValue else { return tool }
    for key in functionToolMetadataKeys {
        object.removeValue(forKey: key)
    }
    return .object(object)
}
