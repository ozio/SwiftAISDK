import Foundation

public final class AISerialJobExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    public init() {}

    public func run(_ job: @escaping @Sendable () async throws -> Void) -> Task<Void, Error> {
        lock.lock()
        let previous = tail
        let task = Task {
            await previous?.value
            try await job()
        }
        tail = Task {
            _ = try? await task.value
            await Task.yield()
        }
        lock.unlock()
        return task
    }
}
