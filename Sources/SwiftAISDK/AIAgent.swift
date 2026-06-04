import Foundation

public struct AIAgentCallOptions: Sendable {
    public var requestOptions: AIChatRequestOptions
    public var abortSignal: AIAbortSignal?
    public var timeoutNanoseconds: UInt64?
    public var retryPolicy: AIRetryPolicy?
    public var telemetry: AITelemetryOptions?

    public init(
        requestOptions: AIChatRequestOptions = AIChatRequestOptions(),
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy? = nil,
        telemetry: AITelemetryOptions? = nil
    ) {
        self.requestOptions = requestOptions
        self.abortSignal = abortSignal
        self.timeoutNanoseconds = timeoutNanoseconds
        self.retryPolicy = retryPolicy
        self.telemetry = telemetry
    }
}

public protocol AIAgent: Sendable {
    var version: String { get }
    var id: String? { get }
    var executableTools: [AITool] { get }

    func generate(prompt: String, options: AIAgentCallOptions) async throws -> TextGenerationResult
    func generate(messages: [AIMessage], options: AIAgentCallOptions) async throws -> TextGenerationResult
    func stream(prompt: String, options: AIAgentCallOptions) -> AsyncThrowingStream<LanguageStreamPart, Error>
    func stream(messages: [AIMessage], options: AIAgentCallOptions) -> AsyncThrowingStream<LanguageStreamPart, Error>
}

public extension AIAgent {
    var version: String { "agent-v1" }

    func generate(prompt: String) async throws -> TextGenerationResult {
        try await generate(prompt: prompt, options: AIAgentCallOptions())
    }

    func generate(messages: [AIMessage]) async throws -> TextGenerationResult {
        try await generate(messages: messages, options: AIAgentCallOptions())
    }

    func stream(prompt: String) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        stream(prompt: prompt, options: AIAgentCallOptions())
    }

    func stream(messages: [AIMessage]) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        stream(messages: messages, options: AIAgentCallOptions())
    }
}

public struct AIToolLoopAgent: AIAgent {
    public var id: String?
    public var model: any LanguageModel
    public var instructions: String?
    public var executableTools: [AITool]
    public var maxSteps: Int
    public var stopWhen: [AIStopCondition]
    public var prepareStep: AIPrepareStep?
    public var toolApproval: AIToolApproval?
    public var requestOptions: AIChatRequestOptions
    public var retryPolicy: AIRetryPolicy
    public var telemetry: AITelemetryOptions?

    public init(
        id: String? = nil,
        model: any LanguageModel,
        instructions: String? = nil,
        executableTools: [AITool] = [],
        maxSteps: Int = 20,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        requestOptions: AIChatRequestOptions = AIChatRequestOptions(),
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) {
        self.id = id
        self.model = model
        self.instructions = instructions
        self.executableTools = executableTools
        self.maxSteps = maxSteps
        self.stopWhen = stopWhen
        self.prepareStep = prepareStep
        self.toolApproval = toolApproval
        self.requestOptions = requestOptions
        self.retryPolicy = retryPolicy
        self.telemetry = telemetry
    }

    public func generate(prompt: String, options: AIAgentCallOptions = AIAgentCallOptions()) async throws -> TextGenerationResult {
        try await generate(messages: [.user(prompt)], options: options)
    }

    public func generate(messages: [AIMessage], options: AIAgentCallOptions = AIAgentCallOptions()) async throws -> TextGenerationResult {
        try await AI.generateText(
            model: model,
            request: request(messages: messages, options: options),
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            retryPolicy: options.retryPolicy ?? retryPolicy,
            telemetry: options.telemetry ?? telemetry
        )
    }

    public func stream(prompt: String, options: AIAgentCallOptions = AIAgentCallOptions()) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        stream(messages: [.user(prompt)], options: options)
    }

    public func stream(messages: [AIMessage], options: AIAgentCallOptions = AIAgentCallOptions()) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AI.streamText(
            model: model,
            request: request(messages: messages, options: options),
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            timeoutNanoseconds: options.timeoutNanoseconds,
            retryPolicy: options.retryPolicy ?? retryPolicy,
            telemetry: options.telemetry ?? telemetry
        )
    }

    private func request(messages: [AIMessage], options: AIAgentCallOptions) -> LanguageModelRequest {
        let effectiveOptions = mergedRequestOptions(options.requestOptions)
        var requestMessages = messages
        if let instructions, !instructions.isEmpty {
            requestMessages.insert(.system(instructions), at: 0)
        }
        return effectiveOptions.languageModelRequest(
            messages: requestMessages,
            abortSignal: options.abortSignal
        )
    }

    private func mergedRequestOptions(_ options: AIChatRequestOptions) -> AIChatRequestOptions {
        var merged = requestOptions
        merged.temperature = options.temperature ?? merged.temperature
        merged.topP = options.topP ?? merged.topP
        merged.topK = options.topK ?? merged.topK
        merged.presencePenalty = options.presencePenalty ?? merged.presencePenalty
        merged.frequencyPenalty = options.frequencyPenalty ?? merged.frequencyPenalty
        merged.seed = options.seed ?? merged.seed
        merged.maxOutputTokens = options.maxOutputTokens ?? merged.maxOutputTokens
        if !options.stopSequences.isEmpty { merged.stopSequences = options.stopSequences }
        merged.responseFormat = options.responseFormat ?? merged.responseFormat
        merged.reasoning = options.reasoning ?? merged.reasoning
        if !options.tools.isEmpty { merged.tools.merge(options.tools) { _, new in new } }
        merged.toolChoice = options.toolChoice ?? merged.toolChoice
        merged.includeRawChunks = options.includeRawChunks || merged.includeRawChunks
        if !options.providerOptions.isEmpty { merged.providerOptions.merge(options.providerOptions) { _, new in new } }
        if !options.extraBody.isEmpty { merged.extraBody.merge(options.extraBody) { _, new in new } }
        if !options.headers.isEmpty { merged.headers.merge(options.headers) { _, new in new } }
        return merged
    }
}

public func createAgentUIStream(
    agent: any AIAgent,
    uiMessages: [AIUIMessage],
    options: AIAgentCallOptions = AIAgentCallOptions(),
    messageID: String = UUID().uuidString
) throws -> AsyncThrowingStream<AIUIMessage, Error> {
    let validatedMessages = try validateUIMessages(uiMessages)
    let modelMessages = try convertToModelMessages(validatedMessages)
    return AIUIMessageStreamReducer.snapshots(
        from: agent.stream(messages: modelMessages, options: options),
        messageID: messageID
    )
}
