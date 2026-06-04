import Foundation

func toolsDictionary(from tools: [AITool]) -> [String: JSONValue] {
    Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.schema) })
}

func toolsByName(from tools: [AITool]) throws -> [String: AITool] {
    var output: [String: AITool] = [:]
    for tool in tools {
        guard output[tool.name] == nil else {
            throw AIError.invalidArgument(argument: "executableTools", message: "Duplicate tool name '\(tool.name)'.")
        }
        output[tool.name] = tool
    }
    return output
}

struct AIToolExecutionBatch: Sendable {
    var results: [AIToolResult] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var approvalResponses: [AIToolApprovalResponse] = []
    var needsUserApproval = false
}

func toolResponseMessages(
    approvalResponses: [AIToolApprovalResponse],
    toolResults: [AIToolResult]
) -> [AIMessage] {
    guard !approvalResponses.isEmpty || !toolResults.isEmpty else { return [] }
    return [AIMessage.toolResponses(approvalResponses: approvalResponses, toolResults: toolResults)]
}

func annotateToolCalls(_ calls: [AIToolCall], toolsByName: [String: AITool]) -> [AIToolCall] {
    calls.map { call in
        guard toolsByName[call.name]?.dynamic == true, !call.dynamic else { return call }
        var annotated = call
        annotated.dynamic = true
        return annotated
    }
}

func annotateToolResult(_ result: AIToolResult, toolsByName: [String: AITool]) -> AIToolResult {
    guard toolsByName[result.toolName]?.dynamic == true, !result.dynamic else { return result }
    var annotated = result
    annotated.dynamic = true
    return annotated
}

func annotateStreamPart(_ part: LanguageStreamPart, toolsByName: [String: AITool]) -> LanguageStreamPart {
    switch part {
    case let .toolInputStart(id, name, providerExecuted, dynamic, title, providerMetadata):
        guard toolsByName[name]?.dynamic == true, !dynamic else { return part }
        return .toolInputStart(
            id: id,
            name: name,
            providerExecuted: providerExecuted,
            dynamic: true,
            title: title,
            providerMetadata: providerMetadata
        )
    case let .toolCall(call):
        return .toolCall(annotateToolCalls([call], toolsByName: toolsByName)[0])
    case let .toolResult(result):
        return .toolResult(annotateToolResult(result, toolsByName: toolsByName))
    default:
        return part
    }
}

func executeToolCalls(
    _ calls: [AIToolCall],
    toolsByName: [String: AITool],
    request: LanguageModelRequest,
    toolApproval: AIToolApproval?,
    telemetry: AIToolLoopTelemetryContext? = nil,
    stepIndex: Int = 0
) async throws -> AIToolExecutionBatch {
    var batch = AIToolExecutionBatch()
    for call in calls {
        guard let tool = toolsByName[call.name] else {
            throw AINoSuchToolError(toolName: call.name, availableToolNames: Array(toolsByName.keys))
        }
        await telemetry?.recordToolStart(stepIndex: stepIndex, call: call, tool: tool)
        do {
            let arguments = try toolArguments(from: call)
            let refinedArguments: JSONValue
            do {
                refinedArguments = try await tool.refineArguments?(arguments) ?? arguments
            } catch {
                throw AIToolCallRepairError(
                    toolName: call.name,
                    toolCallID: call.id,
                    originalError: String(describing: error)
                )
            }
            try validateToolArguments(refinedArguments, schema: tool.parameters, call: call)
            let approvalStatus = try await toolApproval?(AIToolApprovalContext(
                toolCall: call,
                arguments: refinedArguments,
                tool: tool,
                request: request
            )) ?? .notApplicable
            let approvalID = "approval-\(call.id)"
            var approvalRequest: AIToolApprovalRequest?
            var approvalResponse: AIToolApprovalResponse?
            switch approvalStatus {
            case .notApplicable:
                break
            case let .approved(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    isAutomatic: true,
                    providerMetadata: call.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: true,
                    reason: reason,
                    providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
            case let .denied(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    isAutomatic: true,
                    providerMetadata: call.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: false,
                    reason: reason,
                    providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
                let dynamic = call.dynamic || tool.dynamic
                let result = AIToolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    result: executionDeniedResult(reason: reason),
                    dynamic: dynamic,
                    providerMetadata: call.providerMetadata
                )
                batch.results.append(result)
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: call,
                    status: "denied",
                    arguments: refinedArguments,
                    result: result,
                    approvalRequest: approvalRequest,
                    approvalResponse: approvalResponse
                )
                continue
            case .userApproval:
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.needsUserApproval = true
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: call,
                    status: "userApproval",
                    arguments: refinedArguments,
                    approvalRequest: approvalRequest
                )
                continue
            }
            let resultValue: JSONValue
            let executionContext = AIToolExecutionContext(
                toolCallID: call.id,
                messages: request.messages,
                abortSignal: request.abortSignal,
                metadata: call.providerMetadata
            )
            if let telemetry {
                resultValue = try await telemetry.executeTool(call: call) {
                    try await tool.executeWithContext(refinedArguments, executionContext)
                }
            } else {
                resultValue = try await tool.executeWithContext(refinedArguments, executionContext)
            }
            let modelOutput = try await tool.toModelOutput?(AIToolModelOutputContext(
                toolCallID: call.id,
                input: refinedArguments,
                output: resultValue
            ))
            let dynamic = call.dynamic || tool.dynamic
            let result = AIToolResult(
                toolCallID: call.id,
                toolName: call.name,
                result: resultValue,
                modelOutput: modelOutput,
                dynamic: dynamic,
                providerMetadata: call.providerMetadata
            )
            batch.results.append(result)
            await telemetry?.recordToolEnd(
                stepIndex: stepIndex,
                call: call,
                status: "executed",
                arguments: refinedArguments,
                result: result,
                approvalRequest: approvalRequest,
                approvalResponse: approvalResponse
            )
        } catch {
            await telemetry?.recordToolError(stepIndex: stepIndex, call: call, error: error)
            throw error
        }
    }
    return batch
}

func executionDeniedResult(reason: String?) -> JSONValue {
    .object([
        "type": .string("execution-denied"),
        "reason": reason.map(JSONValue.string)
    ].compactMapValues { $0 })
}

func toolArguments(from call: AIToolCall) throws -> JSONValue {
    let trimmed = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .object([:]) }
    do {
        return try decodeJSONBody(Data(trimmed.utf8))
    } catch {
        throw AIInvalidToolInputError(
            toolName: call.name,
            toolCallID: call.id,
            message: "Tool call arguments must be valid JSON."
        )
    }
}

func validateToolArguments(_ arguments: JSONValue, schema: JSONValue, call: AIToolCall) throws {
    do {
        try AIJSONSchemaValidator.validate(arguments, schema: schema)
    } catch let issue as AIJSONSchemaValidationIssue {
        throw AIInvalidToolInputError(
            toolName: call.name,
            toolCallID: call.id,
            input: arguments,
            message: "Tool call arguments do not match tool schema: \(issue.description)",
            validationError: issue
        )
    }
}
