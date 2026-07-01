import Foundation

public struct AIToolStep: Sendable {
    public var index: Int
    public var content: [AIResultContentPart]
    public var text: String
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var files: [AIStreamFile]
    public var toolCalls: [AIToolCall]
    public var toolResults: [AIToolResult]
    public var toolApprovalRequests: [AIToolApprovalRequest]
    public var toolApprovalResponses: [AIToolApprovalResponse]
    public var sources: [AISource]
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata

    public init(
        index: Int,
        content: [AIResultContentPart] = [],
        text: String,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        files: [AIStreamFile] = [],
        toolCalls: [AIToolCall] = [],
        toolResults: [AIToolResult] = [],
        toolApprovalRequests: [AIToolApprovalRequest] = [],
        toolApprovalResponses: [AIToolApprovalResponse] = [],
        sources: [AISource] = [],
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.index = index
        self.content = content
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.files = files
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.toolApprovalRequests = toolApprovalRequests
        self.toolApprovalResponses = toolApprovalResponses
        self.sources = sources
        self.warnings = warnings
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
    public var providerExecuted: Bool
    public var providerMetadata: [String: JSONValue]

    public init(
        toolCallID: String,
        toolName: String,
        result: JSONValue,
        modelOutput: JSONValue? = nil,
        isError: Bool = false,
        preliminary: Bool = false,
        dynamic: Bool = false,
        providerExecuted: Bool = false,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.result = result
        self.modelOutput = modelOutput
        self.isError = isError
        self.preliminary = preliminary
        self.dynamic = dynamic
        self.providerExecuted = providerExecuted
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
    public var toolContext: JSONValue?

    public init(
        toolCall: AIToolCall,
        arguments: JSONValue,
        tool: AITool,
        request: LanguageModelRequest,
        toolContext: JSONValue? = nil
    ) {
        self.toolCall = toolCall
        self.arguments = arguments
        self.tool = tool
        self.request = request
        self.toolContext = toolContext
    }
}

public typealias AIToolApproval = @Sendable (AIToolApprovalContext) async throws -> AIToolApprovalStatus?

public struct AIToolNeedsApprovalContext: Sendable {
    public var toolCallID: String
    public var messages: [AIMessage]
    public var context: JSONValue?

    public init(toolCallID: String, messages: [AIMessage], context: JSONValue? = nil) {
        self.toolCallID = toolCallID
        self.messages = messages
        self.context = context
    }
}

public typealias AIToolNeedsApproval = @Sendable (JSONValue, AIToolNeedsApprovalContext) async throws -> Bool

public struct AIToolInputStartContext: Sendable {
    public var toolCallID: String
    public var messages: [AIMessage]
    public var abortSignal: AIAbortSignal?
    public var toolContext: JSONValue?

    public init(
        toolCallID: String,
        messages: [AIMessage] = [],
        abortSignal: AIAbortSignal? = nil,
        toolContext: JSONValue? = nil
    ) {
        self.toolCallID = toolCallID
        self.messages = messages
        self.abortSignal = abortSignal
        self.toolContext = toolContext
    }
}

public struct AIToolInputDeltaContext: Sendable {
    public var toolCallID: String
    public var inputTextDelta: String
    public var messages: [AIMessage]
    public var abortSignal: AIAbortSignal?
    public var toolContext: JSONValue?

    public init(
        toolCallID: String,
        inputTextDelta: String,
        messages: [AIMessage] = [],
        abortSignal: AIAbortSignal? = nil,
        toolContext: JSONValue? = nil
    ) {
        self.toolCallID = toolCallID
        self.inputTextDelta = inputTextDelta
        self.messages = messages
        self.abortSignal = abortSignal
        self.toolContext = toolContext
    }
}

public struct AIToolInputAvailableContext: Sendable {
    public var toolCallID: String
    public var input: JSONValue
    public var messages: [AIMessage]
    public var abortSignal: AIAbortSignal?
    public var toolContext: JSONValue?

    public init(
        toolCallID: String,
        input: JSONValue,
        messages: [AIMessage] = [],
        abortSignal: AIAbortSignal? = nil,
        toolContext: JSONValue? = nil
    ) {
        self.toolCallID = toolCallID
        self.input = input
        self.messages = messages
        self.abortSignal = abortSignal
        self.toolContext = toolContext
    }
}

public typealias AIToolInputStartCallback = @Sendable (AIToolInputStartContext) async -> Void
public typealias AIToolInputDeltaCallback = @Sendable (AIToolInputDeltaContext) async -> Void
public typealias AIToolInputAvailableCallback = @Sendable (AIToolInputAvailableContext) async -> Void

public struct AIToolCallRepairContext: @unchecked Sendable {
    public var toolCall: AIToolCall
    public var toolsByName: [String: AITool]
    public var request: LanguageModelRequest?
    public var error: any Error

    public init(
        toolCall: AIToolCall,
        toolsByName: [String: AITool],
        request: LanguageModelRequest? = nil,
        error: any Error
    ) {
        self.toolCall = toolCall
        self.toolsByName = toolsByName
        self.request = request
        self.error = error
    }

    public func inputSchema(for toolName: String) throws -> JSONValue {
        guard let tool = toolsByName[toolName] else {
            throw AINoSuchToolError(toolName: toolName, availableToolNames: Array(toolsByName.keys))
        }
        return tool.parameters
    }
}

public typealias AIToolCallRepair = @Sendable (AIToolCallRepairContext) async throws -> AIToolCall?

public struct AIToolExecutionContext: Sendable {
    public var toolCallID: String?
    public var messages: [AIMessage]
    public var abortSignal: AIAbortSignal?
    public var metadata: [String: JSONValue]
    public var toolContext: JSONValue?

    public init(
        toolCallID: String? = nil,
        messages: [AIMessage] = [],
        abortSignal: AIAbortSignal? = nil,
        metadata: [String: JSONValue] = [:],
        toolContext: JSONValue? = nil
    ) {
        self.toolCallID = toolCallID
        self.messages = messages
        self.abortSignal = abortSignal
        self.metadata = metadata
        self.toolContext = toolContext
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
    public var providerOptions: [String: JSONValue]
    public var strict: Bool?
    public var inputExamples: [JSONValue]
    public var contextSchema: JSONValue?
    public var needsApproval: AIToolNeedsApproval?
    public var onInputStart: AIToolInputStartCallback?
    public var onInputDelta: AIToolInputDeltaCallback?
    public var onInputAvailable: AIToolInputAvailableCallback?
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
        providerOptions: [String: JSONValue] = [:],
        strict: Bool? = nil,
        inputExamples: [JSONValue] = [],
        contextSchema: JSONValue? = nil,
        needsApproval: AIToolNeedsApproval? = nil,
        onInputStart: AIToolInputStartCallback? = nil,
        onInputDelta: AIToolInputDeltaCallback? = nil,
        onInputAvailable: AIToolInputAvailableCallback? = nil,
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
        self.providerOptions = providerOptions
        self.strict = strict
        self.inputExamples = inputExamples
        self.contextSchema = contextSchema
        self.needsApproval = needsApproval
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
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
        providerOptions: [String: JSONValue] = [:],
        strict: Bool? = nil,
        inputExamples: [JSONValue] = [],
        contextSchema: JSONValue? = nil,
        needsApproval: AIToolNeedsApproval? = nil,
        onInputStart: AIToolInputStartCallback? = nil,
        onInputDelta: AIToolInputDeltaCallback? = nil,
        onInputAvailable: AIToolInputAvailableCallback? = nil,
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
            providerOptions: providerOptions,
            strict: strict,
            inputExamples: inputExamples,
            contextSchema: contextSchema,
            needsApproval: needsApproval,
            onInputStart: onInputStart,
            onInputDelta: onInputDelta,
            onInputAvailable: onInputAvailable,
            refineArguments: refineArguments,
            toModelOutput: toModelOutput,
            executeWithContext: executeWithContext,
            execute: execute
        )
    }

    public var schema: JSONValue {
        var object = parameters.objectValue ?? ["type": .string("object")]
        if let description {
            object["description"] = .string(description)
        }
        if !providerOptions.isEmpty {
            object["providerOptions"] = .object(providerOptions)
        }
        if let strict {
            object["strict"] = .bool(strict)
        }
        if !inputExamples.isEmpty {
            object["inputExamples"] = .array(inputExamples)
        }
        return .object(object)
    }
}

public struct AIStreamFile: Equatable, Hashable, Sendable {
    public var id: String?
    public var mediaType: String
    public var data: Data?
    public var url: String?
    public var filename: String?
    public var providerReference: AIProviderReference?
    public var providerMetadata: [String: JSONValue]
    public var rawValue: JSONValue?

    public init(
        id: String? = nil,
        mediaType: String,
        data: Data? = nil,
        url: String? = nil,
        filename: String? = nil,
        providerReference: AIProviderReference? = nil,
        providerMetadata: [String: JSONValue] = [:],
        rawValue: JSONValue? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.data = data
        self.url = url
        self.filename = filename
        self.providerReference = providerReference
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
