import Foundation

func sumTokenUsage(_ lhs: TokenUsage?, _ rhs: TokenUsage?) -> TokenUsage? {
    guard lhs != nil || rhs != nil else { return nil }
    return TokenUsage(
        inputTokens: optionalSum(lhs?.inputTokens, rhs?.inputTokens),
        outputTokens: optionalSum(lhs?.outputTokens, rhs?.outputTokens),
        totalTokens: optionalSum(lhs?.totalTokens, rhs?.totalTokens),
        inputTokensNoCache: optionalSum(lhs?.inputTokensNoCache, rhs?.inputTokensNoCache),
        inputTokensCacheRead: optionalSum(lhs?.inputTokensCacheRead, rhs?.inputTokensCacheRead),
        inputTokensCacheWrite: optionalSum(lhs?.inputTokensCacheWrite, rhs?.inputTokensCacheWrite),
        outputTextTokens: optionalSum(lhs?.outputTextTokens, rhs?.outputTextTokens),
        outputReasoningTokens: optionalSum(lhs?.outputReasoningTokens, rhs?.outputReasoningTokens),
        rawValue: rhs?.rawValue ?? lhs?.rawValue
    )
}

func optionalSum(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return lhs + rhs
    case let (lhs?, nil):
        return lhs
    case let (nil, rhs?):
        return rhs
    case (nil, nil):
        return nil
    }
}

func isCancellationTelemetryError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if error is AIAbortError {
        return true
    }
    if let retryError = error as? AIRetryError, retryError.reason == .cancelled {
        return true
    }
    return false
}

struct LanguageStreamToolStep {
    var text = ""
    var reasoning = ""
    var finishReason: String?
    var usage: TokenUsage?
    var toolCalls: [AIToolCall] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var approvalResponses: [AIToolApprovalResponse] = []
    var warnings: [AIWarning] = []
    var providerMetadata: [String: JSONValue] = [:]
    var responseMetadata = AIResponseMetadata()

    mutating func record(_ part: LanguageStreamPart) {
        switch part {
        case let .streamStart(partWarnings):
            warnings.append(contentsOf: partWarnings)
        case let .textDelta(delta):
            text += delta
        case let .textDeltaPart(_, delta, _):
            text += delta
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .reasoningDeltaPart(_, delta, _):
            reasoning += delta
        case let .toolCall(toolCall):
            toolCalls.append(toolCall)
        case let .toolApprovalRequest(approvalRequest):
            approvalRequests.append(approvalRequest)
        case let .toolApprovalResponse(approvalResponse):
            approvalResponses.append(approvalResponse)
        case let .metadata(metadata):
            providerMetadata.merge(metadata) { _, new in new }
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .finish(reason, partUsage):
            finishReason = reason
            usage = partUsage
        case let .finishMetadata(reason, partUsage, metadata):
            finishReason = reason
            usage = partUsage
            providerMetadata.merge(metadata) { _, new in new }
        default:
            break
        }
    }

    func toolStep(
        index: Int,
        toolResults: [AIToolResult],
        approvalRequests: [AIToolApprovalRequest],
        approvalResponses: [AIToolApprovalResponse]
    ) -> AIToolStep {
        AIToolStep(
            index: index,
            text: text,
            reasoning: reasoning,
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            toolResults: toolResults,
            toolApprovalRequests: self.approvalRequests + approvalRequests,
            toolApprovalResponses: self.approvalResponses + approvalResponses,
            providerMetadata: providerMetadata,
            responseMetadata: responseMetadata
        )
    }
}

func forwardLanguageStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    to continuation: AsyncThrowingStream<LanguageStreamPart, Error>.Continuation,
    toolsByName: [String: AITool] = [:]
) async throws -> LanguageStreamToolStep {
    var step = LanguageStreamToolStep()
    for try await part in stream {
        try Task.checkCancellation()
        let annotatedPart = annotateStreamPart(part, toolsByName: toolsByName)
        step.record(annotatedPart)
        continuation.yield(annotatedPart)
    }
    return step
}

func isStopConditionMet(_ stopConditions: [AIStopCondition], steps: [AIToolStep]) async throws -> Bool {
    let context = AIStopConditionContext(steps: steps)
    for condition in stopConditions {
        if try await condition.evaluate(context) {
            return true
        }
    }
    return false
}
