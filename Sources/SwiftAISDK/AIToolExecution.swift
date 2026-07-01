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

struct AIParsedToolCall: Equatable, Sendable {
    var toolCall: AIToolCall
    var input: JSONValue
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

func parseToolCall(
    _ call: AIToolCall,
    toolsByName: [String: AITool]?,
    repairToolCall: AIToolCallRepair? = nil,
    request: LanguageModelRequest? = nil
) async throws -> AIParsedToolCall {
    guard let toolsByName else {
        if call.providerExecuted {
            return AIParsedToolCall(toolCall: call, input: try toolArguments(from: call))
        }
        throw AINoSuchToolError(toolName: call.name)
    }

    do {
        return try await parseToolCallWithoutRepair(call, toolsByName: toolsByName)
    } catch {
        guard let repairToolCall, isRepairableToolCallError(error) else {
            throw error
        }
        let repairedCall: AIToolCall?
        do {
            repairedCall = try await repairToolCall(AIToolCallRepairContext(
                toolCall: call,
                toolsByName: toolsByName,
                request: request,
                error: error
            ))
        } catch {
            throw AIToolCallRepairError(
                toolName: call.name,
                toolCallID: call.id,
                originalError: String(describing: error)
            )
        }
        guard let repairedCall else {
            throw error
        }
        return try await parseToolCallWithoutRepair(repairedCall, toolsByName: toolsByName)
    }
}

private func parseToolCallWithoutRepair(
    _ call: AIToolCall,
    toolsByName: [String: AITool]
) async throws -> AIParsedToolCall {
    guard let tool = toolsByName[call.name] else {
        if call.providerExecuted {
            return AIParsedToolCall(toolCall: call, input: try toolArguments(from: call))
        }
        throw AINoSuchToolError(toolName: call.name, availableToolNames: Array(toolsByName.keys))
    }
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

    var parsedCall = call
    if arguments != refinedArguments {
        parsedCall.arguments = canonicalJSONText(refinedArguments) ?? parsedCall.arguments
    }
    if tool.dynamic {
        parsedCall.dynamic = true
    }
    return AIParsedToolCall(toolCall: parsedCall, input: refinedArguments)
}

private func isRepairableToolCallError(_ error: any Error) -> Bool {
    error is AINoSuchToolError || error is AIInvalidToolInputError
}

func resolveToolApproval(
    toolsByName: [String: AITool],
    toolCall: AIToolCall,
    arguments: JSONValue,
    request: LanguageModelRequest,
    toolApproval: AIToolApproval?
) async throws -> AIToolApprovalStatus {
    guard let tool = toolsByName[toolCall.name] else {
        throw AINoSuchToolError(toolName: toolCall.name, availableToolNames: Array(toolsByName.keys))
    }

    if let toolApproval {
        return try await toolApproval(AIToolApprovalContext(
            toolCall: toolCall,
            arguments: arguments,
            tool: tool,
            request: request,
            toolContext: rawToolContext(for: tool, toolCall: toolCall, request: request)
        )) ?? .notApplicable
    }

    guard let needsApproval = tool.needsApproval else {
        return .notApplicable
    }

    let toolContext = try validatedToolContext(for: tool, toolCall: toolCall, request: request)
    let needsUserApproval = try await needsApproval(arguments, AIToolNeedsApprovalContext(
        toolCallID: toolCall.id,
        messages: request.messages,
        context: toolContext
    ))
    return needsUserApproval ? .userApproval : .notApplicable
}

private func rawToolContext(for tool: AITool, toolCall: AIToolCall, request: LanguageModelRequest) -> JSONValue? {
    request.toolContexts[tool.name] ?? toolCall.providerMetadata["context"]
}

private func validatedToolContext(for tool: AITool, toolCall: AIToolCall, request: LanguageModelRequest) throws -> JSONValue? {
    guard let rawContext = rawToolContext(for: tool, toolCall: toolCall, request: request) else { return nil }
    return try validateToolContext(
        toolName: tool.name,
        context: rawContext,
        contextSchema: tool.contextSchema
    )
}

func executeToolCalls(
    _ calls: [AIToolCall],
    toolsByName: [String: AITool],
    request: LanguageModelRequest,
    toolApproval: AIToolApproval?,
    repairToolCall: AIToolCallRepair? = nil,
    telemetry: AIToolLoopTelemetryContext? = nil,
    stepIndex: Int = 0,
    convertToolErrorsToResults: Bool = false,
    invokeInputAvailableCallbacks: Bool = true
) async throws -> AIToolExecutionBatch {
    var batch = AIToolExecutionBatch()
    for call in calls {
        do {
            let parsedToolCall = try await parseToolCall(
                call,
                toolsByName: toolsByName,
                repairToolCall: repairToolCall,
                request: request
            )
            let parsedCall = parsedToolCall.toolCall
            let refinedArguments = parsedToolCall.input
            guard let tool = toolsByName[parsedCall.name] else {
                throw AINoSuchToolError(toolName: parsedCall.name, availableToolNames: Array(toolsByName.keys))
            }
            if invokeInputAvailableCallbacks {
                await tool.onInputAvailable?(AIToolInputAvailableContext(
                    toolCallID: parsedCall.id,
                    input: refinedArguments,
                    messages: request.messages,
                    abortSignal: request.abortSignal,
                    toolContext: request.toolContexts[tool.name]
                ))
            }
            await telemetry?.recordToolStart(stepIndex: stepIndex, call: parsedCall, tool: tool)
            let approvalStatus = try await resolveToolApproval(
                toolsByName: toolsByName,
                toolCall: parsedCall,
                arguments: refinedArguments,
                request: request,
                toolApproval: toolApproval
            )
            let approvalID = "approval-\(parsedCall.id)"
            var approvalRequest: AIToolApprovalRequest?
            var approvalResponse: AIToolApprovalResponse?
            switch approvalStatus {
            case .notApplicable:
                break
            case let .approved(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: parsedCall.name,
                    arguments: parsedCall.arguments,
                    toolCallID: parsedCall.id,
                    isAutomatic: true,
                    providerMetadata: parsedCall.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: true,
                    reason: reason,
                    providerExecuted: parsedCall.providerExecuted,
                    providerMetadata: parsedCall.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
            case let .denied(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: parsedCall.name,
                    arguments: parsedCall.arguments,
                    toolCallID: parsedCall.id,
                    isAutomatic: true,
                    providerMetadata: parsedCall.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: false,
                    reason: reason,
                    providerExecuted: parsedCall.providerExecuted,
                    providerMetadata: parsedCall.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
                let dynamic = parsedCall.dynamic || tool.dynamic
                let result = AIToolResult(
                    toolCallID: parsedCall.id,
                    toolName: parsedCall.name,
                    result: executionDeniedResult(reason: reason),
                    dynamic: dynamic,
                    providerMetadata: parsedCall.providerMetadata
                )
                batch.results.append(result)
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: parsedCall,
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
                    toolName: parsedCall.name,
                    arguments: parsedCall.arguments,
                    toolCallID: parsedCall.id,
                    providerMetadata: parsedCall.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.needsUserApproval = true
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: parsedCall,
                    status: "userApproval",
                    arguments: refinedArguments,
                    approvalRequest: approvalRequest
                )
                continue
            }
            let resultValue: JSONValue
            let toolContext = try validatedToolContext(for: tool, toolCall: parsedCall, request: request)
            let executionContext = AIToolExecutionContext(
                toolCallID: parsedCall.id,
                messages: request.messages,
                abortSignal: request.abortSignal,
                metadata: parsedCall.providerMetadata,
                toolContext: toolContext
            )
            do {
                if let telemetry {
                    resultValue = try await telemetry.executeTool(call: parsedCall) {
                        try await tool.executeWithContext(refinedArguments, executionContext)
                    }
                } else {
                    resultValue = try await tool.executeWithContext(refinedArguments, executionContext)
                }
            } catch {
                guard convertToolErrorsToResults else { throw error }
                await telemetry?.recordToolError(stepIndex: stepIndex, call: parsedCall, error: error)
                let dynamic = parsedCall.dynamic || tool.dynamic
                batch.results.append(toolExecutionErrorResult(
                    error,
                    toolCall: parsedCall,
                    dynamic: dynamic
                ))
                continue
            }
            let modelOutput = try await tool.toModelOutput?(AIToolModelOutputContext(
                toolCallID: parsedCall.id,
                input: refinedArguments,
                output: resultValue
            ))
            let dynamic = parsedCall.dynamic || tool.dynamic
            let result = AIToolResult(
                toolCallID: parsedCall.id,
                toolName: parsedCall.name,
                result: resultValue,
                modelOutput: modelOutput,
                dynamic: dynamic,
                providerMetadata: parsedCall.providerMetadata
            )
            batch.results.append(result)
            await telemetry?.recordToolEnd(
                stepIndex: stepIndex,
                call: parsedCall,
                status: "executed",
                arguments: refinedArguments,
                result: result,
                approvalRequest: approvalRequest,
                approvalResponse: approvalResponse
            )
        } catch {
            await telemetry?.recordToolError(stepIndex: stepIndex, call: call, error: error)
            if convertToolErrorsToResults, isToolCallResultError(error) {
                batch.results.append(toolCallErrorResult(
                    error,
                    toolCall: call,
                    dynamic: call.dynamic || (toolsByName[call.name]?.dynamic == true)
                ))
                continue
            }
            throw error
        }
    }
    return batch
}

struct AIHistoricalToolApprovalExecution: Sendable {
    var responseMessages: [AIMessage] = []
    var toolResults: [AIToolResult] = []
    var approvalResponses: [AIToolApprovalResponse] = []
}

func executeHistoricalToolApprovals(
    request: LanguageModelRequest,
    toolsByName: [String: AITool],
    toolApproval: AIToolApproval?,
    toolApprovalSecret: String? = nil,
    telemetry: AIToolLoopTelemetryContext? = nil,
    stepIndex: Int = 0
) async throws -> AIHistoricalToolApprovalExecution {
    let collected = try collectToolApprovals(messages: request.messages)
    guard !collected.approvedToolApprovals.isEmpty || !collected.deniedToolApprovals.isEmpty else {
        return AIHistoricalToolApprovalExecution()
    }

    let localApprovedApprovals = collected.approvedToolApprovals.filter {
        !$0.toolCall.providerExecuted && !$0.approvalResponse.providerExecuted
    }
    let localDeniedApprovals = collected.deniedToolApprovals.filter {
        !$0.toolCall.providerExecuted && !$0.approvalResponse.providerExecuted
    }
    let providerExecutedDeniedApprovals = collected.deniedToolApprovals.filter {
        $0.toolCall.providerExecuted || $0.approvalResponse.providerExecuted
    }

    let validated = try await validateApprovedToolApprovals(
        approvedToolApprovals: localApprovedApprovals,
        toolsByName: toolsByName,
        request: request,
        toolApproval: toolApproval,
        toolApprovalSecret: toolApprovalSecret
    )
    let approvedBatch = try await executeToolCalls(
        validated.approvedToolApprovals.map(\.toolCall),
        toolsByName: toolsByName,
        request: request,
        toolApproval: { _ in .notApplicable },
        telemetry: telemetry,
        stepIndex: stepIndex,
        convertToolErrorsToResults: true
    )

    let deniedApprovals = localDeniedApprovals + providerExecutedDeniedApprovals + validated.deniedToolApprovals
    let deniedResults = deniedApprovals.map { approval in
        let toolCall = approval.toolCall
        let providerExecuted = toolCall.providerExecuted || approval.approvalResponse.providerExecuted
        let providerMetadata = toolCall.providerMetadata
            .merging(approval.approvalResponse.providerMetadata) { current, _ in current }
        return AIToolResult(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            result: executionDeniedResult(reason: approval.approvalResponse.reason),
            dynamic: toolCall.dynamic || (toolsByName[toolCall.name]?.dynamic == true),
            providerExecuted: providerExecuted,
            providerMetadata: providerMetadata
        )
    }
    let toolResults = approvedBatch.results + deniedResults

    return AIHistoricalToolApprovalExecution(
        responseMessages: toolResponseMessages(
            approvalResponses: [],
            toolResults: toolResults
        ),
        toolResults: toolResults,
        approvalResponses: []
    )
}

func executionDeniedResult(reason: String?) -> JSONValue {
    .object([
        "type": .string("execution-denied"),
        "reason": reason.map(JSONValue.string)
    ].compactMapValues { $0 })
}

func toolExecutionErrorResult(_ error: Error, toolCall: AIToolCall, dynamic: Bool) -> AIToolResult {
    AIToolResult(
        toolCallID: toolCall.id,
        toolName: toolCall.name,
        result: [
            "type": .string("error-text"),
            "value": .string("Error: \(String(describing: error))")
        ],
        isError: true,
        dynamic: dynamic,
        providerMetadata: toolCall.providerMetadata
    )
}

func toolCallErrorResult(_ error: Error, toolCall: AIToolCall, dynamic: Bool) -> AIToolResult {
    AIToolResult(
        toolCallID: toolCall.id,
        toolName: toolCall.name,
        result: [
            "type": .string("error-text"),
            "value": .string(String(describing: error))
        ],
        isError: true,
        dynamic: dynamic,
        providerMetadata: toolCall.providerMetadata
    )
}

func isToolCallResultError(_ error: Error) -> Bool {
    error is AIInvalidToolInputError || error is AINoSuchToolError || error is AIToolCallRepairError
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
