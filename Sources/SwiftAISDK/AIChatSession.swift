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

@MainActor
public final class AIChatSession: ObservableObject {
    @Published public private(set) var messages: [AIUIMessage]
    @Published public private(set) var status: AIChatSessionStatus
    @Published public private(set) var error: Error?

    public let chatID: String
    public var transport: any AIChatTransport
    public var generateMessageID: @Sendable () -> String

    private var currentTask: Task<Void, Never>?
    private var currentAbortController: AIAbortController?
    private var activeRunID: UUID?

    public init(
        chatID: String = UUID().uuidString,
        transport: any AIChatTransport,
        messages: [AIUIMessage] = [],
        generateMessageID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.chatID = chatID
        self.transport = transport
        self.messages = messages
        self.status = .ready
        self.error = nil
        self.generateMessageID = generateMessageID
    }

    public var isRunning: Bool {
        status == .submitted || status == .streaming
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

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let stream = try await transport.reconnectToStream(AIChatReconnectRequest(
                    chatID: chatID,
                    headers: options.headers,
                    body: options.body,
                    metadata: options.metadata
                )) else {
                    finish(runID: runID, error: nil)
                    return
                }
                guard activeRunID == runID else { return }
                status = .submitted
                await consume(stream, runID: runID)
            } catch {
                finish(runID: runID, error: error)
            }
        }
        currentTask = task
        return task
    }

    public func stop(reason: String? = "stopped") {
        currentAbortController?.abort(reason: reason)
        currentTask?.cancel()
        currentAbortController = nil
        currentTask = nil
        activeRunID = nil
        if isRunning {
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
        metadata: [String: JSONValue] = [:]
    ) {
        addToolOutput(result, id: id, metadata: metadata)
    }

    public func addToolOutput(
        _ result: AIToolResult,
        id: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        messages.append(AIUIMessage(
            id: id ?? generateMessageID(),
            role: .tool,
            parts: [.toolResult(result)],
            metadata: metadata
        ))
    }

    public func addToolApprovalResponse(
        _ response: AIToolApprovalResponse,
        id: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        messages.append(AIUIMessage(
            id: id ?? generateMessageID(),
            role: .tool,
            parts: [.toolApprovalResponse(response)],
            metadata: metadata
        ))
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
                finish(runID: runID, error: error)
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
            finish(runID: runID, error: nil)
        } catch is CancellationError {
            finish(runID: runID, error: nil)
        } catch let error as AIAbortError {
            if Task.isCancelled {
                finish(runID: runID, error: nil)
            } else {
                finish(runID: runID, error: error)
            }
        } catch {
            finish(runID: runID, error: error)
        }
    }

    private func finish(runID: UUID, error: Error?) {
        guard activeRunID == runID else { return }
        currentTask = nil
        currentAbortController = nil
        activeRunID = nil
        if let error {
            self.error = error
            status = .error
        } else {
            status = .ready
        }
    }

    private func upsertMessage(_ message: AIUIMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func failStart(_ error: Error) -> Task<Void, Never> {
        self.error = error
        status = .error
        return Task {}
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
