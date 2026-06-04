import Foundation
import Combine

public enum AIChatSessionStatus: String, Equatable, Hashable, Sendable {
    case ready
    case submitted
    case streaming
    case error
}

public struct AIChatSessionRequestOptions: Sendable {
    public var headers: [String: String]
    public var body: [String: JSONValue]
    public var metadata: JSONValue?

    public init(
        headers: [String: String] = [:],
        body: [String: JSONValue] = [:],
        metadata: JSONValue? = nil
    ) {
        self.headers = headers
        self.body = body
        self.metadata = metadata
    }
}

public struct AIChatSessionFinishEvent: Sendable {
    public var message: AIUIMessage?
    public var messages: [AIUIMessage]
    public var isAbort: Bool
    public var isDisconnect: Bool
    public var isError: Bool
    public var finishReason: String?

    public init(
        message: AIUIMessage?,
        messages: [AIUIMessage],
        isAbort: Bool,
        isDisconnect: Bool,
        isError: Bool,
        finishReason: String? = nil
    ) {
        self.message = message
        self.messages = messages
        self.isAbort = isAbort
        self.isDisconnect = isDisconnect
        self.isError = isError
        self.finishReason = finishReason
    }
}

@MainActor
public final class AIChatSession: ObservableObject {
    @Published public private(set) var messages: [AIUIMessage]
    @Published public private(set) var status: AIChatSessionStatus
    @Published public private(set) var error: Error?

    public let chatID: String
    public var transport: any AIChatTransport
    public var generateMessageID: @Sendable () -> String
    public var onError: (@MainActor @Sendable (Error) -> Void)?
    public var onFinish: (@MainActor @Sendable (AIChatSessionFinishEvent) -> Void)?
    public var sendAutomaticallyWhen: (@MainActor @Sendable ([AIUIMessage]) -> Bool)?

    private var currentTask: Task<Void, Never>?
    private var currentAbortController: AIAbortController?
    private var activeRunID: UUID?
    private var activeResponseMessageID: String?
    private var activeRequestOptions = AIChatSessionRequestOptions()

    public init(
        chatID: String = UUID().uuidString,
        transport: any AIChatTransport,
        messages: [AIUIMessage] = [],
        generateMessageID: @escaping @Sendable () -> String = { UUID().uuidString },
        onError: (@MainActor @Sendable (Error) -> Void)? = nil,
        onFinish: (@MainActor @Sendable (AIChatSessionFinishEvent) -> Void)? = nil,
        sendAutomaticallyWhen: (@MainActor @Sendable ([AIUIMessage]) -> Bool)? = nil
    ) {
        self.chatID = chatID
        self.transport = transport
        self.messages = messages
        self.status = .ready
        self.error = nil
        self.generateMessageID = generateMessageID
        self.onError = onError
        self.onFinish = onFinish
        self.sendAutomaticallyWhen = sendAutomaticallyWhen
    }

    public var isRunning: Bool {
        status == .submitted || status == .streaming
    }

    @discardableResult
    public func sendMessage(
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) -> Task<Void, Never> {
        stop()
        guard let lastMessageID = messages.last?.id else {
            return failStart(AIError.invalidArgument(
                argument: "messages",
                message: "At least one message is required to submit the current transcript."
            ))
        }

        let responseID = generateMessageID()
        messages.append(.assistant(id: responseID))
        return startStream(
            trigger: .submitMessage,
            messageID: lastMessageID,
            responseMessageID: responseID,
            requestMessages: Array(messages.dropLast()),
            options: options
        )
    }

    @discardableResult
    public func sendMessage(
        _ text: String,
        id: String? = nil,
        metadata: [String: JSONValue] = [:],
        replacingMessageID: String? = nil,
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) -> Task<Void, Never> {
        sendMessage(
            .user(text, id: id ?? replacingMessageID ?? generateMessageID(), metadata: metadata),
            replacingMessageID: replacingMessageID,
            options: options
        )
    }

    @discardableResult
    public func sendMessage(
        _ message: AIUIMessage,
        replacingMessageID: String? = nil,
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) -> Task<Void, Never> {
        stop()
        let userMessage: AIUIMessage
        if let replacingMessageID {
            guard let index = messages.firstIndex(where: { $0.id == replacingMessageID }) else {
                return failStart(AIError.invalidArgument(
                    argument: "replacingMessageID",
                    message: "Message '\(replacingMessageID)' was not found."
                ))
            }
            guard messages[index].role == .user else {
                return failStart(AIError.invalidArgument(
                    argument: "replacingMessageID",
                    message: "Message '\(replacingMessageID)' is not a user message."
                ))
            }
            userMessage = AIUIMessage(
                id: replacingMessageID,
                role: message.role,
                parts: message.parts,
                metadata: message.metadata
            )
            messages.removeSubrange(index..<messages.endIndex)
            messages.append(userMessage)
        } else {
            userMessage = message
            messages.append(message)
        }

        let responseID = generateMessageID()
        messages.append(.assistant(id: responseID))
        let requestMessages = messages.filter { $0.id != responseID }
        return startStream(
            trigger: .submitMessage,
            messageID: replacingMessageID,
            responseMessageID: responseID,
            requestMessages: requestMessages,
            options: options
        )
    }

    @discardableResult
    public func regenerate(
        messageID: String? = nil,
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) -> Task<Void, Never> {
        stop()
        guard let target = regenerationTarget(messageID: messageID) else {
            return failStart(AIError.invalidArgument(
                argument: "messageID",
                message: "No assistant message is available to regenerate."
            ))
        }

        let requestEndIndex = target.role == .assistant ? target.index : messages.index(after: target.index)
        messages.removeSubrange(requestEndIndex..<messages.endIndex)
        let responseID = generateMessageID()
        messages.append(.assistant(id: responseID))
        return startStream(
            trigger: .regenerateMessage,
            messageID: target.id,
            responseMessageID: responseID,
            requestMessages: Array(messages.dropLast()),
            options: options
        )
    }

    @discardableResult
    public func resumeStream(
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) -> Task<Void, Never> {
        stop()
        let runID = UUID()
        activeRunID = runID
        error = nil
        activeRequestOptions = options

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let stream = try await transport.reconnectToStream(AIChatReconnectRequest(
                    chatID: chatID,
                    headers: options.headers,
                    body: options.body,
                    metadata: options.metadata
                )) else {
                    clearRunWithoutFinish(runID: runID)
                    return
                }
                guard activeRunID == runID else { return }
                status = .submitted
                await consume(stream, runID: runID)
            } catch {
                finish(runID: runID, error: error, isAbort: false)
            }
        }
        currentTask = task
        return task
    }

    public func stop(reason: String? = "stopped") {
        let stoppedRunID = activeRunID
        currentAbortController?.abort(reason: reason)
        currentTask?.cancel()
        if let stoppedRunID, isRunning {
            finish(runID: stoppedRunID, error: nil, isAbort: true)
        } else {
            currentAbortController = nil
            currentTask = nil
            activeRunID = nil
            activeResponseMessageID = nil
            status = .ready
        }
    }

    public func setMessages(_ messages: [AIUIMessage]) {
        self.messages = messages
    }

    public func clearError() {
        error = nil
        if status == .error {
            status = .ready
        }
    }

    public func addToolResult(
        _ result: AIToolResult,
        id: String? = nil,
        metadata: [String: JSONValue] = [:],
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) {
        addToolOutput(result, id: id, metadata: metadata, options: options)
    }

    public func addToolOutput(
        _ result: AIToolResult,
        id: String? = nil,
        metadata: [String: JSONValue] = [:],
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) {
        messages.append(AIUIMessage(
            id: id ?? generateMessageID(),
            role: .tool,
            parts: [.toolResult(result)],
            metadata: metadata
        ))
        triggerAutomaticSendIfNeeded(options: options)
    }

    public func addToolApprovalResponse(
        _ response: AIToolApprovalResponse,
        id: String? = nil,
        metadata: [String: JSONValue] = [:],
        options: AIChatSessionRequestOptions = AIChatSessionRequestOptions()
    ) {
        messages.append(AIUIMessage(
            id: id ?? generateMessageID(),
            role: .tool,
            parts: [.toolApprovalResponse(response)],
            metadata: metadata
        ))
        triggerAutomaticSendIfNeeded(options: options)
    }

    private func startStream(
        trigger: AIChatTransportTrigger,
        messageID: String?,
        responseMessageID: String,
        requestMessages: [AIUIMessage],
        options: AIChatSessionRequestOptions
    ) -> Task<Void, Never> {
        let runID = UUID()
        let controller = AIAbortController()
        activeRunID = runID
        activeResponseMessageID = responseMessageID
        activeRequestOptions = options
        currentAbortController = controller
        status = .submitted
        error = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try transport.sendMessages(AIChatTransportRequest(
                    chatID: chatID,
                    trigger: trigger,
                    messageID: messageID,
                    responseMessageID: responseMessageID,
                    messages: requestMessages,
                    abortSignal: controller.signal,
                    headers: options.headers,
                    body: options.body,
                    metadata: options.metadata
                ))
                await consume(stream, runID: runID)
            } catch {
                finish(runID: runID, error: error, isAbort: false)
            }
        }
        currentTask = task
        return task
    }

    private func consume(_ stream: AsyncThrowingStream<AIUIMessage, Error>, runID: UUID) async {
        do {
            for try await snapshot in stream {
                guard activeRunID == runID else { return }
                upsertMessage(snapshot)
                status = .streaming
            }
            finish(runID: runID, error: nil, isAbort: false)
        } catch is CancellationError {
            finish(runID: runID, error: nil, isAbort: true)
        } catch let error as AIAbortError {
            finish(runID: runID, error: Task.isCancelled ? nil : error, isAbort: true)
        } catch {
            finish(runID: runID, error: error, isAbort: false)
        }
    }

    private func finish(runID: UUID, error: Error?, isAbort: Bool) {
        guard activeRunID == runID else { return }
        let finishedMessage = activeResponseMessageID.flatMap { id in
            messages.first { $0.id == id }
        } ?? messages.last
        let finishReason = finishedMessage?.metadata["finishReason"]?.stringValue
        let isDisconnect = error.map(isDisconnectError) ?? false
        let isError = error != nil

        currentTask = nil
        currentAbortController = nil
        activeRunID = nil
        activeResponseMessageID = nil
        if let error {
            self.error = error
            onError?(error)
            status = .error
        } else {
            status = .ready
        }
        onFinish?(AIChatSessionFinishEvent(
            message: finishedMessage,
            messages: messages,
            isAbort: isAbort,
            isDisconnect: isDisconnect,
            isError: isError,
            finishReason: finishReason
        ))
        if !isAbort && !isError {
            triggerAutomaticSendIfNeeded(options: activeRequestOptions)
        }
    }

    private func upsertMessage(_ message: AIUIMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func clearRunWithoutFinish(runID: UUID) {
        guard activeRunID == runID else { return }
        currentTask = nil
        currentAbortController = nil
        activeRunID = nil
        activeResponseMessageID = nil
        status = .ready
    }

    private func failStart(_ error: Error) -> Task<Void, Never> {
        self.error = error
        onError?(error)
        status = .error
        return Task {}
    }

    private func triggerAutomaticSendIfNeeded(options: AIChatSessionRequestOptions) {
        guard !isRunning, sendAutomaticallyWhen?(messages) == true else { return }
        guard let lastMessageID = messages.last?.id else { return }
        let responseID = generateMessageID()
        messages.append(.assistant(id: responseID))
        _ = startStream(
            trigger: .submitMessage,
            messageID: lastMessageID,
            responseMessageID: responseID,
            requestMessages: Array(messages.dropLast()),
            options: options
        )
    }

    private func isDisconnectError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        let description = String(describing: error).lowercased()
        return description.contains("network") || description.contains("connection")
    }

    private func regenerationTarget(messageID: String?) -> (id: String, index: Array<AIUIMessage>.Index, role: MessageRole)? {
        if let messageID {
            guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
                return nil
            }
            return (messageID, index, messages[index].role)
        }

        guard let index = messages.indices.last(where: { messages[$0].role == .assistant || messages[$0].role == .user }) else {
            return nil
        }
        return (messages[index].id, index, messages[index].role)
    }
}
