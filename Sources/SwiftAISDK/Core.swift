import Foundation

public enum AIError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingAPIKey(provider: String, environmentVariables: [String])
    case unsupportedModel(provider: String, capability: ModelCapability, modelID: String)
    case invalidArgument(argument: String, message: String)
    case invalidResponse(provider: String, message: String)
    case httpStatus(provider: String, statusCode: Int, body: String)
    case httpStatusWithHeaders(provider: String, statusCode: Int, body: String, headers: [String: String])
    case invalidURL(String)
    case timeout(durationNanoseconds: UInt64)

    public var description: String {
        switch self {
        case let .missingAPIKey(provider, variables):
            return "\(provider) API key is missing. Pass it in ProviderSettings or set one of: \(variables.joined(separator: ", "))."
        case let .unsupportedModel(provider, capability, modelID):
            return "\(provider) does not provide \(capability.rawValue) model '\(modelID)'."
        case let .invalidArgument(argument, message):
            return "Invalid \(argument): \(message)"
        case let .invalidResponse(provider, message):
            return "\(provider) returned an invalid response: \(message)"
        case let .httpStatus(provider, statusCode, body):
            return "\(provider) request failed with HTTP \(statusCode): \(body)"
        case let .httpStatusWithHeaders(provider, statusCode, body, _):
            return "\(provider) request failed with HTTP \(statusCode): \(body)"
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case let .timeout(durationNanoseconds):
            return "AI call timed out after \(durationNanoseconds) nanoseconds."
        }
    }
}

public enum AIRetryErrorReason: String, Sendable {
    case maxRetriesExceeded
    case errorNotRetryable
    case cancelled
}

public struct AIRetryError: Error, CustomStringConvertible, Sendable {
    public var reason: AIRetryErrorReason
    public var attempts: Int
    public var errors: [String]

    public init(reason: AIRetryErrorReason, attempts: Int, errors: [String]) {
        self.reason = reason
        self.attempts = attempts
        self.errors = errors
    }

    public var description: String {
        let lastError = errors.last ?? "unknown error"
        switch reason {
        case .maxRetriesExceeded:
            return "Failed after \(attempts) attempt(s). Last error: \(lastError)"
        case .errorNotRetryable:
            return "Failed with non-retryable error after \(attempts) attempt(s): \(lastError)"
        case .cancelled:
            return "Retry operation was cancelled after \(attempts) attempt(s)."
        }
    }
}

public struct AIRetryPolicy: Equatable, Sendable {
    public var maxRetries: Int
    public var initialDelayNanoseconds: UInt64
    public var backoffFactor: Double
    public var maxDelayNanoseconds: UInt64
    public var timeoutNanoseconds: UInt64?

    public init(
        maxRetries: Int = 2,
        initialDelayNanoseconds: UInt64 = 2_000_000_000,
        backoffFactor: Double = 2,
        maxDelayNanoseconds: UInt64 = 60_000_000_000,
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.maxRetries = maxRetries
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.backoffFactor = backoffFactor
        self.maxDelayNanoseconds = maxDelayNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public static let `default` = AIRetryPolicy()
    public static let none = AIRetryPolicy(maxRetries: 0, initialDelayNanoseconds: 0)
}

public enum ModelCapability: String, Hashable, Codable, CaseIterable, Sendable {
    case language
    case completion
    case embedding
    case image
    case transcription
    case speech
    case video
    case reranking
}

public enum MessageRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public enum AIContentPart: Equatable, Hashable, Sendable {
    case text(String)
    case imageURL(String)
    case data(mimeType: String, data: Data)
    case file(mimeType: String, data: Data, filename: String? = nil)
    case toolCall(AIToolCall)
    case toolResult(AIToolResult)
    case toolApprovalRequest(AIToolApprovalRequest)
    case toolApprovalResponse(AIToolApprovalResponse)

    public var text: String? {
        if case let .text(value) = self { value } else { nil }
    }

    public var filePayload: (mimeType: String, data: Data, filename: String?)? {
        switch self {
        case let .data(mimeType, data):
            return (mimeType, data, nil)
        case let .file(mimeType, data, filename):
            return (mimeType, data, filename)
        case .text, .imageURL, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return nil
        }
    }
}

public struct AIMessage: Equatable, Hashable, Sendable {
    public var role: MessageRole
    public var content: [AIContentPart]

    public init(role: MessageRole, content: [AIContentPart]) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)])
    }

    public static func assistant(
        text: String = "",
        toolCalls: [AIToolCall],
        toolApprovalRequests: [AIToolApprovalRequest] = []
    ) -> AIMessage {
        AIMessage(
            role: .assistant,
            content: (text.isEmpty ? [] : [.text(text)])
                + toolCalls.map(AIContentPart.toolCall)
                + toolApprovalRequests.map(AIContentPart.toolApprovalRequest)
        )
    }

    public static func toolResult(_ result: AIToolResult) -> AIMessage {
        AIMessage(role: .tool, content: [.toolResult(result)])
    }

    public static func toolResponses(
        approvalResponses: [AIToolApprovalResponse] = [],
        toolResults: [AIToolResult] = []
    ) -> AIMessage {
        AIMessage(
            role: .tool,
            content: approvalResponses.map(AIContentPart.toolApprovalResponse)
                + toolResults.map(AIContentPart.toolResult)
        )
    }

    public var combinedText: String {
        content.compactMap(\.text).joined(separator: "\n")
    }
}

public struct LanguageModelRequest: Sendable {
    public var messages: [AIMessage]
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var seed: Int?
    public var maxOutputTokens: Int?
    public var stopSequences: [String]
    public var responseFormat: AIResponseFormat?
    public var reasoning: String?
    public var tools: [String: JSONValue]
    public var toolChoice: JSONValue?
    public var includeRawChunks: Bool
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        messages: [AIMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        responseFormat: AIResponseFormat? = nil,
        reasoning: String? = nil,
        tools: [String: JSONValue] = [:],
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.tools = tools
        self.toolChoice = toolChoice
        self.includeRawChunks = includeRawChunks
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public enum AIResponseFormat: Equatable, Hashable, Sendable {
    case text
    case json(schema: JSONValue? = nil, name: String? = nil, description: String? = nil)
}

public struct AIAbortError: Error, Equatable, Sendable, CustomStringConvertible {
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }

    public var description: String {
        if let reason, !reason.isEmpty {
            return "Operation aborted: \(reason)"
        }
        return "Operation aborted."
    }
}

public final class AIAbortController: @unchecked Sendable {
    public let signal: AIAbortSignal

    public init() {
        self.signal = AIAbortSignal()
    }

    public func abort(reason: String? = nil) {
        signal.abort(reason: reason)
    }
}

public final class AIAbortSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    private var abortReason: String?
    private var handlers: [UUID: @Sendable (String?) -> Void] = [:]
    private var continuations: [UUID: CheckedContinuation<String?, Never>] = [:]

    public var isAborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return aborted
    }

    public var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return abortReason
    }

    public func throwIfAborted() throws {
        if isAborted {
            throw AIAbortError(reason: reason)
        }
    }

    @discardableResult
    public func addAbortHandler(_ handler: @escaping @Sendable (String?) -> Void) -> AIAbortHandlerRegistration {
        lock.lock()
        if aborted {
            let reason = abortReason
            lock.unlock()
            handler(reason)
            return AIAbortHandlerRegistration {}
        }
        let id = UUID()
        handlers[id] = handler
        lock.unlock()

        return AIAbortHandlerRegistration { [weak self] in
            self?.removeHandler(id)
        }
    }

    public func waitUntilAborted() async -> String? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if aborted {
                let reason = abortReason
                lock.unlock()
                continuation.resume(returning: reason)
                return
            }
            let id = UUID()
            continuations[id] = continuation
            lock.unlock()
        }
    }

    fileprivate func abort(reason: String?) {
        lock.lock()
        guard !aborted else {
            lock.unlock()
            return
        }
        aborted = true
        abortReason = reason
        let handlers = Array(handlers.values)
        self.handlers.removeAll()
        let continuations = Array(continuations.values)
        self.continuations.removeAll()
        lock.unlock()

        for continuation in continuations {
            continuation.resume(returning: reason)
        }
        for handler in handlers {
            handler(reason)
        }
    }

    private func removeHandler(_ id: UUID) {
        lock.lock()
        handlers[id] = nil
        lock.unlock()
    }
}

public final class AIAbortHandlerRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    fileprivate init(_ onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let onCancel = self.onCancel
        self.onCancel = nil
        lock.unlock()
        onCancel?()
    }

    deinit {
        cancel()
    }
}

private final class AIAbortableSleepState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var registration: AIAbortHandlerRegistration?
    private var task: Task<Void, Never>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func setRegistration(_ registration: AIAbortHandlerRegistration) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            registration.cancel()
            return
        }
        self.registration = registration
        lock.unlock()
    }

    func setTask(_ task: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func resume() {
        complete(.success(()))
    }

    func resume(throwing error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let registration = self.registration
        self.registration = nil
        let task = self.task
        self.task = nil
        lock.unlock()

        registration?.cancel()
        task?.cancel()
        continuation.resume(with: result)
    }
}

func sleepWithAbortSignal(nanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws {
    guard let abortSignal else {
        try await Task.sleep(nanoseconds: nanoseconds)
        return
    }
    try abortSignal.throwIfAborted()
    try await withCheckedThrowingContinuation { continuation in
        let state = AIAbortableSleepState(continuation: continuation)
        let registration = abortSignal.addAbortHandler { reason in
            state.resume(throwing: AIAbortError(reason: reason))
        }
        state.setRegistration(registration)
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                state.resume()
            } catch {
                state.resume(throwing: error)
            }
        }
        state.setTask(task)
    }
}

public struct AIJSONInstruction: Equatable, Hashable, Sendable {
    public var isEnabled: Bool
    public var schemaPrefix: String?
    public var schemaSuffix: String?

    public init(
        isEnabled: Bool = true,
        schemaPrefix: String? = nil,
        schemaSuffix: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.schemaPrefix = schemaPrefix
        self.schemaSuffix = schemaSuffix
    }

    public static let automatic = AIJSONInstruction()
    public static let disabled = AIJSONInstruction(isEnabled: false)
}

public protocol AIObjectSchema: Sendable {
    associatedtype Output: Decodable & Sendable

    var jsonSchema: JSONValue { get }
    var name: String? { get }
    var description: String? { get }
}

public extension AIObjectSchema {
    var name: String? { nil }
    var description: String? { nil }
}

public struct AIJSONSchema<Output: Decodable & Sendable>: AIObjectSchema {
    public var jsonSchema: JSONValue
    public var name: String?
    public var description: String?

    public init(
        _ jsonSchema: JSONValue,
        name: String? = nil,
        description: String? = nil,
        as type: Output.Type = Output.self
    ) {
        self.jsonSchema = jsonSchema
        self.name = name
        self.description = description
    }
}

public struct TextGenerationResult: Sendable {
    public var text: String
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var toolCalls: [AIToolCall]
    public var toolResults: [AIToolResult]
    public var toolApprovalRequests: [AIToolApprovalRequest]
    public var toolApprovalResponses: [AIToolApprovalResponse]
    public var steps: [AIToolStep]
    public var sources: [AISource]
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var responseMetadata: AIResponseMetadata

    public init(
        text: String,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        toolCalls: [AIToolCall] = [],
        toolResults: [AIToolResult] = [],
        toolApprovalRequests: [AIToolApprovalRequest] = [],
        toolApprovalResponses: [AIToolApprovalResponse] = [],
        steps: [AIToolStep] = [],
        sources: [AISource] = [],
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.toolApprovalRequests = toolApprovalRequests
        self.toolApprovalResponses = toolApprovalResponses
        self.steps = steps
        self.sources = sources
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
        self.warnings = warnings
        self.responseMetadata = responseMetadata
    }
}

public struct ObjectGenerationResult<Object: Sendable>: Sendable {
    public var object: Object
    public var text: String
    public var rawObject: JSONValue
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata
    public var textResult: TextGenerationResult

    public init(
        object: Object,
        text: String,
        rawObject: JSONValue,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        textResult: TextGenerationResult
    ) {
        self.object = object
        self.text = text
        self.rawObject = rawObject
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
        self.textResult = textResult
    }
}

public struct AIObjectGenerationCallbacks<Output: Sendable>: Sendable {
    public var onStart: (@Sendable (AIObjectGenerationStartEvent) async -> Void)?
    public var onStepStart: (@Sendable (AIObjectGenerationStepStartEvent) async -> Void)?
    public var onStepFinish: (@Sendable (AIObjectGenerationStepFinishEvent) async -> Void)?
    public var onFinish: (@Sendable (AIObjectGenerationFinishEvent<Output>) async -> Void)?
    public var onError: (@Sendable (AIObjectGenerationErrorEvent) async -> Void)?

    public init(
        onStart: (@Sendable (AIObjectGenerationStartEvent) async -> Void)? = nil,
        onStepStart: (@Sendable (AIObjectGenerationStepStartEvent) async -> Void)? = nil,
        onStepFinish: (@Sendable (AIObjectGenerationStepFinishEvent) async -> Void)? = nil,
        onFinish: (@Sendable (AIObjectGenerationFinishEvent<Output>) async -> Void)? = nil,
        onError: (@Sendable (AIObjectGenerationErrorEvent) async -> Void)? = nil
    ) {
        self.onStart = onStart
        self.onStepStart = onStepStart
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.onError = onError
    }
}

public struct AIObjectGenerationStartEvent: Sendable {
    public var callID: String
    public var operationID: String
    public var providerID: String
    public var modelID: String?
    public var outputKind: String
    public var request: LanguageModelRequest
    public var schema: JSONValue?
    public var schemaName: String?
    public var schemaDescription: String?
    public var maxRetries: Int

    public init(
        callID: String,
        operationID: String,
        providerID: String,
        modelID: String?,
        outputKind: String,
        request: LanguageModelRequest,
        schema: JSONValue?,
        schemaName: String?,
        schemaDescription: String?,
        maxRetries: Int
    ) {
        self.callID = callID
        self.operationID = operationID
        self.providerID = providerID
        self.modelID = modelID
        self.outputKind = outputKind
        self.request = request
        self.schema = schema
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
        self.maxRetries = maxRetries
    }
}

public struct AIObjectGenerationStepStartEvent: Sendable {
    public var callID: String
    public var stepNumber: Int
    public var providerID: String
    public var modelID: String?
    public var request: LanguageModelRequest

    public init(callID: String, stepNumber: Int, providerID: String, modelID: String?, request: LanguageModelRequest) {
        self.callID = callID
        self.stepNumber = stepNumber
        self.providerID = providerID
        self.modelID = modelID
        self.request = request
    }
}

public struct AIObjectGenerationStepFinishEvent: Sendable {
    public var callID: String
    public var stepNumber: Int
    public var providerID: String
    public var modelID: String?
    public var text: String
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        callID: String,
        stepNumber: Int,
        providerID: String,
        modelID: String?,
        text: String,
        reasoning: String,
        finishReason: String?,
        usage: TokenUsage?,
        warnings: [AIWarning],
        providerMetadata: [String: JSONValue],
        responseMetadata: AIResponseMetadata
    ) {
        self.callID = callID
        self.stepNumber = stepNumber
        self.providerID = providerID
        self.modelID = modelID
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct AIObjectGenerationFinishEvent<Output: Sendable>: Sendable {
    public var callID: String
    public var object: Output
    public var text: String
    public var rawObject: JSONValue
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        callID: String,
        object: Output,
        text: String,
        rawObject: JSONValue,
        reasoning: String,
        finishReason: String?,
        usage: TokenUsage?,
        warnings: [AIWarning],
        providerMetadata: [String: JSONValue],
        responseMetadata: AIResponseMetadata
    ) {
        self.callID = callID
        self.object = object
        self.text = text
        self.rawObject = rawObject
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct AIObjectGenerationErrorEvent: Sendable {
    public var callID: String
    public var providerID: String
    public var modelID: String?
    public var text: String
    public var errorDescription: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        callID: String,
        providerID: String,
        modelID: String?,
        text: String,
        errorDescription: String,
        finishReason: String?,
        usage: TokenUsage?,
        warnings: [AIWarning],
        providerMetadata: [String: JSONValue],
        responseMetadata: AIResponseMetadata
    ) {
        self.callID = callID
        self.providerID = providerID
        self.modelID = modelID
        self.text = text
        self.errorDescription = errorDescription
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
    }
}

public enum ObjectStreamPart<Object: Sendable>: Sendable {
    case textDelta(String)
    case partialObject(JSONValue)
    case partial(Object)
    case object(ObjectGenerationResult<Object>)
    case warning(AIWarning)
    case source(AISource)
    case metadata([String: JSONValue])
    case responseMetadata(AIResponseMetadata)
    case raw(LanguageStreamPart)
    case finish(reason: String?, usage: TokenUsage?)
}

public struct AIObjectRepairContext: Sendable {
    public var text: String
    public var errorMessage: String

    public init(text: String, errorMessage: String) {
        self.text = text
        self.errorMessage = errorMessage
    }
}

public enum AIObjectGenerationFailureKind: String, Equatable, Sendable {
    case noJSON
    case schemaValidation
    case decoding
    case repairFailed
}

public enum AIObjectOutputStrategy: String, Equatable, Sendable {
    case object
    case array
    case enumeration
    case json
}

public struct AIObjectGenerationError: Error, Equatable, CustomStringConvertible, Sendable {
    public var provider: String
    public var strategy: AIObjectOutputStrategy
    public var kind: AIObjectGenerationFailureKind
    public var message: String
    public var path: String?
    public var text: String
    public var repairAttempted: Bool

    public init(
        provider: String,
        strategy: AIObjectOutputStrategy,
        kind: AIObjectGenerationFailureKind,
        message: String,
        path: String? = nil,
        text: String,
        repairAttempted: Bool = false
    ) {
        self.provider = provider
        self.strategy = strategy
        self.kind = kind
        self.message = message
        self.path = path
        self.text = text
        self.repairAttempted = repairAttempted
    }

    public var description: String {
        let pathSuffix = path.map { " at \($0)" } ?? ""
        let repairSuffix = repairAttempted ? " after repair" : ""
        return "\(provider) did not generate a valid \(strategy.rawValue)\(repairSuffix): \(kind.rawValue)\(pathSuffix): \(message)"
    }
}

public struct AIToolStep: Sendable {
    public var index: Int
    public var text: String
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var toolCalls: [AIToolCall]
    public var toolResults: [AIToolResult]
    public var toolApprovalRequests: [AIToolApprovalRequest]
    public var toolApprovalResponses: [AIToolApprovalResponse]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        index: Int,
        text: String,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        toolCalls: [AIToolCall] = [],
        toolResults: [AIToolResult] = [],
        toolApprovalRequests: [AIToolApprovalRequest] = [],
        toolApprovalResponses: [AIToolApprovalResponse] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.index = index
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.toolApprovalRequests = toolApprovalRequests
        self.toolApprovalResponses = toolApprovalResponses
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct AIStopConditionContext: Sendable {
    public var steps: [AIToolStep]

    public init(steps: [AIToolStep]) {
        self.steps = steps
    }
}

public struct AIStopCondition: Sendable {
    public var evaluate: @Sendable (AIStopConditionContext) async throws -> Bool

    public init(_ evaluate: @escaping @Sendable (AIStopConditionContext) async throws -> Bool) {
        self.evaluate = evaluate
    }

    public static func isStepCount(_ stepCount: Int) -> AIStopCondition {
        AIStopCondition { context in
            context.steps.count == stepCount
        }
    }

    public static func isLoopFinished() -> AIStopCondition {
        AIStopCondition { _ in false }
    }

    public static func hasToolCall(_ toolNames: String...) -> AIStopCondition {
        AIStopCondition { context in
            guard let lastStep = context.steps.last else { return false }
            return lastStep.toolCalls.contains { toolNames.contains($0.name) }
        }
    }
}

public struct AIPrepareStepContext: Sendable {
    public var model: any LanguageModel
    public var stepNumber: Int
    public var steps: [AIToolStep]
    public var request: LanguageModelRequest
    public var initialRequest: LanguageModelRequest
    public var responseMessages: [AIMessage]

    public init(
        model: any LanguageModel,
        stepNumber: Int,
        steps: [AIToolStep],
        request: LanguageModelRequest,
        initialRequest: LanguageModelRequest,
        responseMessages: [AIMessage]
    ) {
        self.model = model
        self.stepNumber = stepNumber
        self.steps = steps
        self.request = request
        self.initialRequest = initialRequest
        self.responseMessages = responseMessages
    }
}

public struct AIPrepareStepResult: Sendable {
    public var model: (any LanguageModel)?
    public var request: LanguageModelRequest?
    public var executableTools: [AITool]?

    public init(
        model: (any LanguageModel)? = nil,
        request: LanguageModelRequest? = nil,
        executableTools: [AITool]? = nil
    ) {
        self.model = model
        self.request = request
        self.executableTools = executableTools
    }
}

public typealias AIPrepareStep = @Sendable (AIPrepareStepContext) async throws -> AIPrepareStepResult?

public struct AISource: Equatable, Hashable, Sendable {
    public var id: String
    public var sourceType: String
    public var url: String?
    public var title: String?
    public var mediaType: String?
    public var filename: String?
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue?

    public init(
        id: String,
        sourceType: String,
        url: String? = nil,
        title: String? = nil,
        mediaType: String? = nil,
        filename: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.url = url
        self.title = title
        self.mediaType = mediaType
        self.filename = filename
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
    }
}

public struct AIToolCall: Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String
    public var providerExecuted: Bool
    public var dynamic: Bool
    public var title: String?
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue?

    public init(
        id: String,
        name: String,
        arguments: String,
        providerExecuted: Bool = false,
        dynamic: Bool = false,
        title: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.providerExecuted = providerExecuted
        self.dynamic = dynamic
        self.title = title
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
    }
}

public struct AIToolResult: Equatable, Hashable, Sendable {
    public var toolCallID: String
    public var toolName: String
    public var result: JSONValue
    public var modelOutput: JSONValue?
    public var isError: Bool
    public var preliminary: Bool
    public var dynamic: Bool
    public var providerMetadata: [String: JSONValue]

    public init(
        toolCallID: String,
        toolName: String,
        result: JSONValue,
        modelOutput: JSONValue? = nil,
        isError: Bool = false,
        preliminary: Bool = false,
        dynamic: Bool = false,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.result = result
        self.modelOutput = modelOutput
        self.isError = isError
        self.preliminary = preliminary
        self.dynamic = dynamic
        self.providerMetadata = providerMetadata
    }
}

public struct AIToolApprovalRequest: Equatable, Hashable, Sendable {
    public var id: String
    public var toolCallID: String?
    public var toolName: String
    public var arguments: String
    public var isAutomatic: Bool
    public var providerMetadata: [String: JSONValue]

    public init(
        id: String,
        toolName: String,
        arguments: String,
        toolCallID: String? = nil,
        isAutomatic: Bool = false,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.arguments = arguments
        self.isAutomatic = isAutomatic
        self.providerMetadata = providerMetadata
    }
}

public struct AIToolApprovalResponse: Equatable, Hashable, Sendable {
    public var id: String
    public var approved: Bool
    public var reason: String?
    public var providerExecuted: Bool
    public var providerMetadata: [String: JSONValue]

    public init(
        id: String,
        approved: Bool,
        reason: String? = nil,
        providerExecuted: Bool = false,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.approved = approved
        self.reason = reason
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
    }
}

public enum AIToolApprovalStatus: Equatable, Hashable, Sendable {
    case notApplicable
    case approved(reason: String? = nil)
    case denied(reason: String? = nil)
    case userApproval
}

public struct AIToolApprovalContext: Sendable {
    public var toolCall: AIToolCall
    public var arguments: JSONValue
    public var tool: AITool
    public var request: LanguageModelRequest

    public init(toolCall: AIToolCall, arguments: JSONValue, tool: AITool, request: LanguageModelRequest) {
        self.toolCall = toolCall
        self.arguments = arguments
        self.tool = tool
        self.request = request
    }
}

public typealias AIToolApproval = @Sendable (AIToolApprovalContext) async throws -> AIToolApprovalStatus?

public struct AIToolExecutionContext: Sendable {
    public var toolCallID: String?
    public var messages: [AIMessage]
    public var abortSignal: AIAbortSignal?
    public var metadata: [String: JSONValue]

    public init(
        toolCallID: String? = nil,
        messages: [AIMessage] = [],
        abortSignal: AIAbortSignal? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.toolCallID = toolCallID
        self.messages = messages
        self.abortSignal = abortSignal
        self.metadata = metadata
    }
}

public struct AIToolModelOutputContext: Sendable {
    public var toolCallID: String
    public var input: JSONValue
    public var output: JSONValue

    public init(toolCallID: String, input: JSONValue, output: JSONValue) {
        self.toolCallID = toolCallID
        self.input = input
        self.output = output
    }
}

public struct AITool: Sendable {
    public var name: String
    public var description: String?
    public var parameters: JSONValue
    public var dynamic: Bool
    public var providerMetadata: [String: JSONValue]
    public var refineArguments: (@Sendable (JSONValue) async throws -> JSONValue)?
    public var execute: @Sendable (JSONValue) async throws -> JSONValue
    public var executeWithContext: @Sendable (JSONValue, AIToolExecutionContext) async throws -> JSONValue
    public var toModelOutput: (@Sendable (AIToolModelOutputContext) async throws -> JSONValue)?

    public init(
        name: String,
        description: String? = nil,
        parameters: JSONValue,
        dynamic: Bool = false,
        providerMetadata: [String: JSONValue] = [:],
        refineArguments: (@Sendable (JSONValue) async throws -> JSONValue)? = nil,
        toModelOutput: (@Sendable (AIToolModelOutputContext) async throws -> JSONValue)? = nil,
        executeWithContext: (@Sendable (JSONValue, AIToolExecutionContext) async throws -> JSONValue)? = nil,
        execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.dynamic = dynamic
        self.providerMetadata = providerMetadata
        self.refineArguments = refineArguments
        self.toModelOutput = toModelOutput
        self.execute = execute
        self.executeWithContext = executeWithContext ?? { arguments, _ in
            try await execute(arguments)
        }
    }

    public static func dynamic(
        name: String,
        description: String? = nil,
        parameters: JSONValue,
        providerMetadata: [String: JSONValue] = [:],
        refineArguments: (@Sendable (JSONValue) async throws -> JSONValue)? = nil,
        toModelOutput: (@Sendable (AIToolModelOutputContext) async throws -> JSONValue)? = nil,
        executeWithContext: (@Sendable (JSONValue, AIToolExecutionContext) async throws -> JSONValue)? = nil,
        execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) -> AITool {
        AITool(
            name: name,
            description: description,
            parameters: parameters,
            dynamic: true,
            providerMetadata: providerMetadata,
            refineArguments: refineArguments,
            toModelOutput: toModelOutput,
            executeWithContext: executeWithContext,
            execute: execute
        )
    }

    public var schema: JSONValue {
        guard let description else { return parameters }
        var object = parameters.objectValue ?? ["type": .string("object")]
        object["description"] = .string(description)
        return .object(object)
    }
}

public struct AIStreamFile: Equatable, Hashable, Sendable {
    public var id: String?
    public var mediaType: String
    public var data: Data?
    public var url: String?
    public var filename: String?
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue?

    public init(
        id: String? = nil,
        mediaType: String,
        data: Data? = nil,
        url: String? = nil,
        filename: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.data = data
        self.url = url
        self.filename = filename
        self.providerMetadata = providerMetadata
        self.rawValue = rawValue
    }
}

public struct AIResponseMetadata: Equatable, Hashable, Sendable {
    public var id: String?
    public var timestamp: Date?
    public var modelID: String?
    public var headers: [String: String]
    public var body: JSONValue?

    public init(id: String? = nil, timestamp: Date? = nil, modelID: String? = nil, headers: [String: String] = [:], body: JSONValue? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.modelID = modelID
        self.headers = headers
        self.body = body
    }
}

public struct AIRequestMetadata: Equatable, Hashable, Sendable {
    public var body: JSONValue?
    public var headers: [String: String]

    public init(body: JSONValue? = nil, headers: [String: String] = [:]) {
        self.body = body
        self.headers = headers
    }
}

public enum LanguageStreamPart: Equatable, Sendable {
    case streamStart(warnings: [AIWarning])
    case textStart(id: String, providerMetadata: [String: JSONValue] = [:])
    case textDelta(String)
    case textDeltaPart(id: String, delta: String, providerMetadata: [String: JSONValue] = [:])
    case textEnd(id: String, providerMetadata: [String: JSONValue] = [:])
    case reasoningStart(id: String, providerMetadata: [String: JSONValue] = [:])
    case reasoningDelta(String)
    case reasoningDeltaPart(id: String, delta: String, providerMetadata: [String: JSONValue] = [:])
    case reasoningEnd(id: String, providerMetadata: [String: JSONValue] = [:])
    case toolInputStart(id: String, name: String, providerExecuted: Bool = false, dynamic: Bool = false, title: String? = nil, providerMetadata: [String: JSONValue] = [:])
    case toolInputDelta(id: String, delta: String, providerMetadata: [String: JSONValue] = [:])
    case toolInputEnd(id: String, providerMetadata: [String: JSONValue] = [:])
    case toolCallDelta(id: String?, name: String?, argumentsDelta: String, index: Int?)
    case toolCall(AIToolCall)
    case toolResult(AIToolResult)
    case toolApprovalRequest(AIToolApprovalRequest)
    case toolApprovalResponse(AIToolApprovalResponse)
    case file(AIStreamFile)
    case reasoningFile(AIStreamFile)
    case custom(JSONValue, providerMetadata: [String: JSONValue] = [:])
    case source(AISource)
    case metadata([String: JSONValue])
    case responseMetadata(AIResponseMetadata)
    case raw(JSONValue)
    case error(message: String, rawValue: JSONValue? = nil)
    case finish(reason: String?, usage: TokenUsage?)
    case finishMetadata(reason: String?, usage: TokenUsage?, providerMetadata: [String: JSONValue])
}

public struct EmbeddingRequest: Sendable {
    public var values: [String]
    public var dimensions: Int?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        values: [String],
        dimensions: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.values = values
        self.dimensions = dimensions
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct EmbeddingResult: Sendable {
    public var embeddings: [[Double]]
    public var usage: TokenUsage?
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        embeddings: [[Double]],
        usage: TokenUsage? = nil,
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.embeddings = embeddings
        self.usage = usage
        self.rawValue = rawValue
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct ImageGenerationRequest: Sendable {
    public var prompt: String
    public var size: String?
    public var aspectRatio: String?
    public var seed: Int?
    public var count: Int?
    public var files: [ImageInputFile]
    public var mask: ImageInputFile?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        prompt: String,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        count: Int? = nil,
        files: [ImageInputFile] = [],
        mask: ImageInputFile? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.prompt = prompt
        self.size = size
        self.aspectRatio = aspectRatio
        self.seed = seed
        self.count = count
        self.files = files
        self.mask = mask
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct ImageInputFile: Sendable, Equatable {
    public var data: Data?
    public var url: String?
    public var mediaType: String?
    public var fileName: String?

    public init(data: Data, mediaType: String, fileName: String? = nil) {
        self.data = data
        self.url = nil
        self.mediaType = mediaType
        self.fileName = fileName
    }

    public init(url: String, mediaType: String? = nil, fileName: String? = nil) {
        self.data = nil
        self.url = url
        self.mediaType = mediaType
        self.fileName = fileName
    }
}

public struct ImageGenerationResult: Sendable {
    public var urls: [String]
    public var base64Images: [String]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var usage: TokenUsage?
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        urls: [String],
        base64Images: [String] = [],
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        usage: TokenUsage? = nil,
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.urls = urls
        self.base64Images = base64Images
        self.rawValue = rawValue
        self.warnings = warnings
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct AudioTranscriptionRequest: Sendable {
    public var audio: Data
    public var fileName: String
    public var mimeType: String
    public var language: String?
    public var prompt: String?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        audio: Data,
        fileName: String = "audio.wav",
        mimeType: String = "audio/wav",
        language: String? = nil,
        prompt: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.audio = audio
        self.fileName = fileName
        self.mimeType = mimeType
        self.language = language
        self.prompt = prompt
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var rawValue: JSONValue
    public var segments: [TranscriptionSegment]
    public var language: String?
    public var durationInSeconds: Double?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        text: String,
        rawValue: JSONValue,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.text = text
        self.rawValue = rawValue
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct TranscriptionSegment: Equatable, Sendable {
    public var text: String
    public var startSecond: Double
    public var endSecond: Double

    public init(text: String, startSecond: Double, endSecond: Double) {
        self.text = text
        self.startSecond = startSecond
        self.endSecond = endSecond
    }
}

public struct SpeechRequest: Sendable {
    public var text: String
    public var voice: String?
    public var format: String?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        text: String,
        voice: String? = nil,
        format: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.text = text
        self.voice = voice
        self.format = format
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct SpeechResult: Sendable {
    public var audio: Data
    public var contentType: String?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        audio: Data,
        contentType: String? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.audio = audio
        self.contentType = contentType
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct VideoGenerationRequest: Sendable {
    public var prompt: String
    public var aspectRatio: String?
    public var durationSeconds: Double?
    public var image: ImageInputFile?
    public var resolution: String?
    public var fps: Double?
    public var seed: Int?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        prompt: String,
        aspectRatio: String? = nil,
        durationSeconds: Double? = nil,
        image: ImageInputFile? = nil,
        resolution: String? = nil,
        fps: Double? = nil,
        seed: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.durationSeconds = durationSeconds
        self.image = image
        self.resolution = resolution
        self.fps = fps
        self.seed = seed
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct VideoGenerationResult: Sendable {
    public var urls: [String]
    public var operationID: String?
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        urls: [String],
        operationID: String? = nil,
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.urls = urls
        self.operationID = operationID
        self.rawValue = rawValue
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct RerankingRequest: Sendable {
    public var query: String
    public var documents: [String]
    public var documentObjects: [[String: JSONValue]]?
    public var topK: Int?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        query: String,
        documents: [String],
        topK: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.query = query
        self.documents = documents
        self.documentObjects = nil
        self.topK = topK
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }

    public init(
        query: String,
        documents: [[String: JSONValue]],
        topK: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.query = query
        self.documents = []
        self.documentObjects = documents
        self.topK = topK
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }

    var documentsJSON: [JSONValue] {
        if let documentObjects {
            return documentObjects.map(JSONValue.object)
        }
        return documents.map(JSONValue.string)
    }
}

public struct RerankingResult: Sendable {
    public var results: [RerankedDocument]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        results: [RerankedDocument],
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.results = results
        self.rawValue = rawValue
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct RerankedDocument: Equatable, Sendable {
    public var index: Int
    public var score: Double
    public var document: String?

    public init(index: Int, score: Double, document: String? = nil) {
        self.index = index
        self.score = score
        self.document = document
    }
}

public struct FileUploadRequest: Sendable {
    public var data: Data
    public var mediaType: String
    public var filename: String?
    public var purpose: String?
    public var displayName: String?
    public var pollIntervalNanoseconds: UInt64
    public var pollTimeoutNanoseconds: UInt64
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        data: Data,
        mediaType: String,
        filename: String? = nil,
        purpose: String? = nil,
        displayName: String? = nil,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        pollTimeoutNanoseconds: UInt64 = 300_000_000_000,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.purpose = purpose
        self.displayName = displayName
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.pollTimeoutNanoseconds = pollTimeoutNanoseconds
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct FileUploadResult: Sendable {
    public var providerReference: [String: String]
    public var filename: String?
    public var mediaType: String?
    public var metadata: [String: JSONValue]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        providerReference: [String: String],
        filename: String? = nil,
        mediaType: String? = nil,
        metadata: [String: JSONValue] = [:],
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.providerReference = providerReference
        self.filename = filename
        self.mediaType = mediaType
        self.metadata = metadata
        self.rawValue = rawValue
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct SkillUploadFile: Equatable, Sendable {
    public var path: String
    public var data: Data
    public var mediaType: String

    public init(path: String, data: Data, mediaType: String = "application/octet-stream") {
        self.path = path
        self.data = data
        self.mediaType = mediaType
    }
}

public struct SkillUploadRequest: Sendable {
    public var files: [SkillUploadFile]
    public var displayTitle: String?
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(files: [SkillUploadFile], displayTitle: String? = nil, headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil) {
        self.files = files
        self.displayTitle = displayTitle
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct AIWarning: Equatable, Sendable {
    public var type: String
    public var feature: String?
    public var setting: String?
    public var message: String?

    public init(type: String, feature: String? = nil, setting: String? = nil, message: String? = nil) {
        self.type = type
        self.feature = feature
        self.setting = setting
        self.message = message
    }
}

public struct SkillUploadResult: Sendable {
    public var providerReference: [String: String]
    public var displayTitle: String?
    public var name: String?
    public var description: String?
    public var latestVersion: String?
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata
    public var warnings: [AIWarning]
    public var rawValue: JSONValue

    public init(
        providerReference: [String: String],
        displayTitle: String? = nil,
        name: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        warnings: [AIWarning] = [],
        rawValue: JSONValue
    ) {
        self.providerReference = providerReference
        self.displayTitle = displayTitle
        self.name = name
        self.description = description
        self.latestVersion = latestVersion
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
        self.warnings = warnings
        self.rawValue = rawValue
    }
}

public struct TokenUsage: Equatable, Codable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var inputTokensNoCache: Int?
    public var inputTokensCacheRead: Int?
    public var inputTokensCacheWrite: Int?
    public var outputTextTokens: Int?
    public var outputReasoningTokens: Int?
    public var rawValue: JSONValue?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        inputTokensNoCache: Int? = nil,
        inputTokensCacheRead: Int? = nil,
        inputTokensCacheWrite: Int? = nil,
        outputTextTokens: Int? = nil,
        outputReasoningTokens: Int? = nil,
        rawValue: JSONValue? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputTokensNoCache = inputTokensNoCache
        self.inputTokensCacheRead = inputTokensCacheRead
        self.inputTokensCacheWrite = inputTokensCacheWrite
        self.outputTextTokens = outputTextTokens
        self.outputReasoningTokens = outputReasoningTokens
        self.rawValue = rawValue
    }
}

public protocol LanguageModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult
    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error>
}

public extension LanguageModel {
    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await generate(request)
                    if !result.text.isEmpty {
                        continuation.yield(.textDelta(result.text))
                    }
                    for toolCall in result.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }
                    continuation.yield(.finish(reason: result.finishReason, usage: result.usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public protocol EmbeddingModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult
}

public protocol ImageModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult
}

public protocol TranscriptionModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult
}

public protocol SpeechModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func speak(_ request: SpeechRequest) async throws -> SpeechResult
}

public protocol VideoModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult
}

public protocol RerankingModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func rerank(_ request: RerankingRequest) async throws -> RerankingResult
}

public protocol AIFileClient: Sendable {
    var providerID: String { get }
    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult
}

public protocol AISkillsClient: Sendable {
    var providerID: String { get }
    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult
}

public protocol AIProvider: Sendable {
    var providerID: String { get }
    var supportedCapabilities: Set<ModelCapability> { get }
    func languageModel(_ modelID: String) throws -> any LanguageModel
    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel
    func imageModel(_ modelID: String) throws -> any ImageModel
    func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel
    func speechModel(_ modelID: String) throws -> any SpeechModel
    func videoModel(_ modelID: String) throws -> any VideoModel
    func rerankingModel(_ modelID: String) throws -> any RerankingModel
}

public protocol AIFileProvider: AIProvider {
    func files() throws -> any AIFileClient
}

public protocol AISkillsProvider: AIProvider {
    func skills() throws -> any AISkillsClient
}

public extension AIProvider {
    func callAsFunction(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    func chat(_ modelID: String) throws -> any LanguageModel {
        try languageModel(modelID)
    }

    func embedding(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func textEmbeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func textEmbedding(_ modelID: String) throws -> any EmbeddingModel {
        try embeddingModel(modelID)
    }

    func image(_ modelID: String) throws -> any ImageModel {
        try imageModel(modelID)
    }

    func transcription(_ modelID: String) throws -> any TranscriptionModel {
        try transcriptionModel(modelID)
    }

    func speech(_ modelID: String) throws -> any SpeechModel {
        try speechModel(modelID)
    }

    func video(_ modelID: String) throws -> any VideoModel {
        try videoModel(modelID)
    }

    func reranking(_ modelID: String) throws -> any RerankingModel {
        try rerankingModel(modelID)
    }
}
