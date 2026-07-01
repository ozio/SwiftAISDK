import Foundation
import Testing
@testable import SwiftAISDK

actor PrepareStepSnapshotCapture {
    struct Snapshot: Sendable {
        var stepNumber: Int
        var initialMessages: [AIMessage]
        var requestMessages: [AIMessage]
        var responseMessages: [AIMessage]
    }

    private var values: [Snapshot] = []

    func record(_ context: AIPrepareStepContext) {
        values.append(Snapshot(
            stepNumber: context.stepNumber,
            initialMessages: context.initialRequest.messages,
            requestMessages: context.request.messages,
            responseMessages: context.responseMessages
        ))
    }

    func snapshots() -> [Snapshot] {
        values
    }
}

actor ToolExecutionInputListCapture {
    private var inputs: [JSONValue] = []

    func record(_ input: JSONValue) {
        inputs.append(input)
    }

    func values() -> [JSONValue] {
        inputs
    }
}

actor ToolExecutionContextListCapture {
    struct Call: Sendable {
        var toolCallID: String?
        var arguments: JSONValue
        var messages: [AIMessage]
    }

    private var values: [Call] = []

    func record(arguments: JSONValue, context: AIToolExecutionContext) {
        values.append(Call(
            toolCallID: context.toolCallID,
            arguments: arguments,
            messages: context.messages
        ))
    }

    func calls() -> [Call] {
        values
    }
}

actor ApprovalContextCapture {
    struct Call: Equatable, Sendable {
        var toolCallID: String
        var arguments: JSONValue
        var messages: [AIMessage]
        var toolContext: JSONValue?

        init(
            toolCallID: String,
            arguments: JSONValue,
            messages: [AIMessage],
            toolContext: JSONValue? = nil
        ) {
            self.toolCallID = toolCallID
            self.arguments = arguments
            self.messages = messages
            self.toolContext = toolContext
        }
    }

    private var values: [Call] = []

    func record(_ context: AIToolApprovalContext) {
        values.append(Call(
            toolCallID: context.toolCall.id,
            arguments: context.arguments,
            messages: context.request.messages,
            toolContext: context.toolContext
        ))
    }

    func calls() -> [Call] {
        values
    }
}

actor ToolDefinedApprovalCapture {
    struct Call: Equatable, Sendable {
        var input: JSONValue
        var toolCallID: String
        var messages: [AIMessage]
        var context: JSONValue?
    }

    private var values: [Call] = []

    func record(input: JSONValue, context: AIToolNeedsApprovalContext) {
        values.append(Call(
            input: input,
            toolCallID: context.toolCallID,
            messages: context.messages,
            context: context.context
        ))
    }

    func calls() -> [Call] {
        values
    }
}

actor StopConditionCapture {
    struct Call: Sendable {
        var number: Int
        var stepCount: Int
        var toolCallIDs: [String]
        var toolResultIDs: [String]
    }

    private var calls: [Call] = []

    func record(number: Int, context: AIStopConditionContext) {
        let lastStep = context.steps.last
        calls.append(Call(
            number: number,
            stepCount: context.steps.count,
            toolCallIDs: lastStep?.toolCalls.map(\.id) ?? [],
            toolResultIDs: lastStep?.toolResults.map(\.toolCallID) ?? []
        ))
    }

    func numbers() -> [Int] {
        calls.map(\.number)
    }

    func stepCounts() -> [Int] {
        calls.map(\.stepCount)
    }

    func toolCallIDs() -> [[String]] {
        calls.map(\.toolCallIDs)
    }

    func toolResultIDs() -> [[String]] {
        calls.map(\.toolResultIDs)
    }
}

struct GenerateToolInputAvailableEvent: Equatable, Sendable {
    var toolCallID: String
    var input: JSONValue
    var messages: [AIMessage]
    var abortSignalMatches: Bool
}

actor GenerateToolInputAvailableRecorder {
    private var recordedEvents: [GenerateToolInputAvailableEvent] = []

    func record(toolCallID: String, input: JSONValue, messages: [AIMessage], abortSignalMatches: Bool) {
        recordedEvents.append(GenerateToolInputAvailableEvent(
            toolCallID: toolCallID,
            input: input,
            messages: messages,
            abortSignalMatches: abortSignalMatches
        ))
    }

    func events() -> [GenerateToolInputAvailableEvent] {
        recordedEvents
    }
}

final class ConfiguredGenerateTextLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var results: [TextGenerationResult]
    private var streamSequences: [[LanguageStreamPart]]

    init(
        providerID: String,
        modelID: String,
        results: [TextGenerationResult],
        streamSequences: [[LanguageStreamPart]] = [[]]
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.results = results
        self.streamSequences = streamSequences
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamSequences.count > 1 ? streamSequences.removeFirst() : streamSequences[0]
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

struct GenerateTextLifecycleTelemetry: Telemetry.Integration {
    var log: ExecutionWrapperLog

    func record(_ event: Telemetry.Event) async {
        switch event.operationID {
        case "ai.generateText.step":
            await log.append("event:\(event.kind):\(event.operationID):\(event.input?["stepNumber"]?.intValue ?? event.output?["stepNumber"]?.intValue ?? -1)")
        case "ai.generateText.tool":
            await log.append("event:\(event.kind):\(event.operationID):\(event.input?["stepNumber"]?.intValue ?? event.output?["stepNumber"]?.intValue ?? -1)")
        default:
            await log.append("event:\(event.kind):\(event.operationID)")
        }
    }

    func executeLanguageModelCall<Output: Sendable>(_ context: Telemetry.LanguageModelCallContext<Output>) async throws -> Output {
        await log.append("language-start:\(context.operationID):\(context.modelID ?? "unknown")")
        let result = try await context.execute()
        await log.append("language-end:\(context.operationID)")
        return result
    }

    func executeTool<Output: Sendable>(_ context: Telemetry.ToolExecutionContext<Output>) async throws -> Output {
        await log.append("tool-start:\(context.toolCallID):\(context.toolName)")
        let result = try await context.execute()
        await log.append("tool-end:\(context.toolCallID):\(context.toolName)")
        return result
    }
}
