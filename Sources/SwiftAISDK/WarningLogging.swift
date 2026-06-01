import Foundation

public struct AIWarningLogEvent: Equatable, Sendable {
    public var warnings: [AIWarning]
    public var providerID: String?
    public var modelID: String?

    public init(warnings: [AIWarning], providerID: String? = nil, modelID: String? = nil) {
        self.warnings = warnings
        self.providerID = providerID
        self.modelID = modelID
    }
}

public protocol AIWarningLogger: Sendable {
    func logWarnings(_ event: AIWarningLogEvent) async
}

public struct AIConsoleWarningLogger: AIWarningLogger {
    public init() {}

    public func logWarnings(_ event: AIWarningLogEvent) async {
        for warning in event.warnings {
            let message = AIWarningLogging.formattedMessage(for: warning, providerID: event.providerID, modelID: event.modelID) + "\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}

public enum AIWarningLogging {
    @TaskLocal private static var scopedState: AIWarningLoggingScopedState?

    private static let registry = AIWarningLoggingRegistry()

    public static func useDefaultLogger() {
        registry.useDefaultLogger()
    }

    public static func useLogger(_ logger: any AIWarningLogger) {
        registry.useLogger(logger)
    }

    public static func disable() {
        registry.disable()
    }

    public static func withLogger<Result>(
        _ logger: any AIWarningLogger,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await $scopedState.withValue(.custom(logger)) {
            try await operation()
        }
    }

    public static func withLoggingDisabled<Result>(
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await $scopedState.withValue(.disabled) {
            try await operation()
        }
    }

    public static func formattedMessage(for warning: AIWarning, providerID: String? = nil, modelID: String? = nil) -> String {
        let scope = providerID.flatMap { provider in
            modelID.map { model in " (\(provider) / \(model))" }
        } ?? ""
        let prefix = "AI SDK Warning\(scope):"

        switch warning.type {
        case "unsupported":
            if let feature = warning.feature {
                return "\(prefix) The feature \"\(feature)\" is not supported.\(warning.message.map { " \($0)" } ?? "")"
            }
            return "\(prefix) The requested feature is not supported.\(warning.message.map { " \($0)" } ?? "")"
        case "compatibility":
            if let feature = warning.feature {
                return "\(prefix) The feature \"\(feature)\" is used in a compatibility mode.\(warning.message.map { " \($0)" } ?? "")"
            }
            return "\(prefix) A feature is used in a compatibility mode.\(warning.message.map { " \($0)" } ?? "")"
        case "deprecated":
            let setting = warning.setting.map { "\"\($0)\"" } ?? "a setting"
            return "\(prefix) Deprecated: \(setting). \(warning.message ?? "")"
        case "other":
            return "\(prefix) \(warning.message ?? "A provider warning was returned.")"
        default:
            return "\(prefix) \(warning.type)\(warning.message.map { ": \($0)" } ?? "")"
        }
    }

    static func logWarnings(_ warnings: [AIWarning], providerID: String?, modelID: String?) async {
        guard !warnings.isEmpty else { return }
        let event = AIWarningLogEvent(warnings: warnings, providerID: providerID, modelID: modelID)
        switch scopedState {
        case let .custom(logger):
            await logger.logWarnings(event)
        case .disabled:
            return
        case nil:
            await registry.logWarnings(event)
        }
    }

    static func resetForTesting() {
        registry.resetForTesting()
    }
}

private enum AIWarningLoggingScopedState: Sendable {
    case custom(any AIWarningLogger)
    case disabled
}

private final class AIWarningLoggingRegistry: @unchecked Sendable {
    private enum State {
        case defaultLogger
        case custom(any AIWarningLogger)
        case disabled
    }

    private let lock = NSLock()
    private var state: State = .defaultLogger

    func useDefaultLogger() {
        lock.lock()
        state = .defaultLogger
        lock.unlock()
    }

    func useLogger(_ logger: any AIWarningLogger) {
        lock.lock()
        state = .custom(logger)
        lock.unlock()
    }

    func disable() {
        lock.lock()
        state = .disabled
        lock.unlock()
    }

    func logWarnings(_ event: AIWarningLogEvent) async {
        switch currentState() {
        case .defaultLogger:
            await AIConsoleWarningLogger().logWarnings(event)
        case let .custom(logger):
            await logger.logWarnings(event)
        case .disabled:
            return
        }
    }

    func resetForTesting() {
        useDefaultLogger()
    }

    private func currentState() -> State {
        lock.lock()
        let current = state
        lock.unlock()
        return current
    }
}
