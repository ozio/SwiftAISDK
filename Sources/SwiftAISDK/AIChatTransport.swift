import Foundation

public enum AIChatTransportTrigger: String, Equatable, Hashable, Sendable {
    case submitMessage = "submit-message"
    case regenerateMessage = "regenerate-message"
}

public struct AIChatTransportRequest: Sendable {
    public var chatID: String
    public var trigger: AIChatTransportTrigger
    public var messageID: String?
    public var responseMessageID: String?
    public var messages: [AIUIMessage]
    public var abortSignal: AIAbortSignal?
    public var headers: [String: String]
    public var body: [String: JSONValue]
    public var metadata: JSONValue?

    public init(
        chatID: String,
        trigger: AIChatTransportTrigger = .submitMessage,
        messageID: String? = nil,
        responseMessageID: String? = nil,
        messages: [AIUIMessage],
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        body: [String: JSONValue] = [:],
        metadata: JSONValue? = nil
    ) {
        self.chatID = chatID
        self.trigger = trigger
        self.messageID = messageID
        self.responseMessageID = responseMessageID
        self.messages = messages
        self.abortSignal = abortSignal
        self.headers = headers
        self.body = body
        self.metadata = metadata
    }
}

public protocol AIChatTransport: Sendable {
    func sendMessages(_ request: AIChatTransportRequest) throws -> AsyncThrowingStream<AIUIMessage, Error>
    func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<AIUIMessage, Error>?
}

public extension AIChatTransport {
    func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<AIUIMessage, Error>? {
        nil
    }
}

public struct AIChatRequestOptions: Sendable {
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

    public init(
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
        headers: [String: String] = [:]
    ) {
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
    }

    public func languageModelRequest(
        messages: [AIMessage],
        abortSignal: AIAbortSignal? = nil,
        headers additionalHeaders: [String: String] = [:]
    ) -> LanguageModelRequest {
        LanguageModelRequest(
            messages: messages,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            maxOutputTokens: maxOutputTokens,
            stopSequences: stopSequences,
            responseFormat: responseFormat,
            reasoning: reasoning,
            tools: tools,
            toolChoice: toolChoice,
            includeRawChunks: includeRawChunks,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers.merging(additionalHeaders) { _, new in new },
            abortSignal: abortSignal
        )
    }
}

public struct DirectAIChatTransport: AIChatTransport {
    public var model: any LanguageModel
    public var executableTools: [AITool]
    public var maxSteps: Int
    public var stopWhen: [AIStopCondition]
    public var prepareStep: AIPrepareStep?
    public var toolApproval: AIToolApproval?
    public var requestOptions: AIChatRequestOptions
    public var timeoutNanoseconds: UInt64?
    public var retryPolicy: AIRetryPolicy
    public var telemetry: AITelemetryOptions?
    public var sendReasoning: Bool
    public var sendSources: Bool
    public var sendFinish: Bool
    public var generateMessageID: @Sendable () -> String

    public init(
        model: any LanguageModel,
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        requestOptions: AIChatRequestOptions = AIChatRequestOptions(),
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        sendReasoning: Bool = true,
        sendSources: Bool = false,
        sendFinish: Bool = true,
        generateMessageID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.model = model
        self.executableTools = executableTools
        self.maxSteps = maxSteps
        self.stopWhen = stopWhen
        self.prepareStep = prepareStep
        self.toolApproval = toolApproval
        self.requestOptions = requestOptions
        self.timeoutNanoseconds = timeoutNanoseconds
        self.retryPolicy = retryPolicy
        self.telemetry = telemetry
        self.sendReasoning = sendReasoning
        self.sendSources = sendSources
        self.sendFinish = sendFinish
        self.generateMessageID = generateMessageID
    }

    public func sendMessages(_ request: AIChatTransportRequest) throws -> AsyncThrowingStream<AIUIMessage, Error> {
        let modelMessages = try convertToModelMessages(request.messages)
        let languageRequest = requestOptions.languageModelRequest(
            messages: modelMessages,
            abortSignal: request.abortSignal,
            headers: request.headers
        )
        let languageStream: AsyncThrowingStream<LanguageStreamPart, Error>
        if executableTools.isEmpty && prepareStep == nil {
            languageStream = AI.streamText(
                model: model,
                request: languageRequest,
                timeoutNanoseconds: timeoutNanoseconds,
                retryPolicy: retryPolicy,
                telemetry: telemetry
            )
        } else {
            languageStream = AI.streamText(
                model: model,
                request: languageRequest,
                executableTools: executableTools,
                maxSteps: maxSteps,
                stopWhen: stopWhen,
                prepareStep: prepareStep,
                toolApproval: toolApproval,
                timeoutNanoseconds: timeoutNanoseconds,
                retryPolicy: retryPolicy,
                telemetry: telemetry
            )
        }

        return AIUIMessageStreamReducer.snapshots(
            from: filteredLanguageStream(languageStream),
            messageID: request.responseMessageID ?? generateMessageID()
        )
    }

    public func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<AIUIMessage, Error>? {
        nil
    }

    private func filteredLanguageStream(
        _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await part in stream {
                        guard shouldSend(part) else { continue }
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func shouldSend(_ part: LanguageStreamPart) -> Bool {
        switch part {
        case .reasoningStart, .reasoningDelta, .reasoningDeltaPart, .reasoningEnd, .reasoningFile:
            return sendReasoning
        case .source:
            return sendSources
        case .finish, .finishMetadata:
            return sendFinish
        default:
            return true
        }
    }
}
