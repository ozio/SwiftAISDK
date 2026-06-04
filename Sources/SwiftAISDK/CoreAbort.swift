import Foundation

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
